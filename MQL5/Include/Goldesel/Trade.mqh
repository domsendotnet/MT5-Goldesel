#ifndef GOLDESEL_TRADE_MQH
#define GOLDESEL_TRADE_MQH

#include <Trade/Trade.mqh>

ENUM_ORDER_TYPE_FILLING GeDetectFilling(bool &market_exe, bool &ok)
{
   ok = false;
   market_exe = false;
   const long flags = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   const ENUM_SYMBOL_TRADE_EXECUTION exe =
      (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_EXEMODE);
   market_exe = (exe == SYMBOL_TRADE_EXECUTION_MARKET);

   const bool allow_fok    = ((flags & SYMBOL_FILLING_FOK) != 0);
   const bool allow_ioc    = ((flags & SYMBOL_FILLING_IOC) != 0);
   bool       allow_return = !market_exe;
   if(market_exe)
      allow_return = false;

   ENUM_ORDER_TYPE_FILLING pick = ORDER_FILLING_FOK;
   if(allow_fok)
      pick = ORDER_FILLING_FOK;
   else if(allow_ioc)
      pick = ORDER_FILLING_IOC;
   else if(allow_return)
      pick = ORDER_FILLING_RETURN;
   else if(market_exe && flags == 0)
   {
      pick = ORDER_FILLING_FOK;
      Print("Goldesel: flags=0 Market Execution; will fallback FOK↔IOC per order");
   }
   else
   {
      ok = false;
      return pick;
   }
   ok = true;
   return pick;
}

bool GeNormalizeStops(const double entry, const ENUM_GE_DIR dir, double &sl, double &tp, ENUM_GE_SKIP &why)
{
   why = SKIP_NONE;
   const double tick   = GeTickSize();
   const int    stops  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const int    freeze = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   const double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double spread = ask - bid;
   const bool   is_long = (dir == GE_DIR_LONG);
   const double ref     = is_long ? bid : ask;

   double min_dist = kSpreadFloorMult * MathMax(spread, 0.0);
   if(tick > 0.0)
   {
      min_dist = MathMax(min_dist, (double)(stops  + 1) * tick);
      min_dist = MathMax(min_dist, (double)(freeze + 1) * tick);
   }

   if(is_long)
   {
      if(ref - sl < min_dist)
         sl = ref - min_dist;
      if(sl >= ref)
      {
         why = SKIP_STOPS_LEVEL;
         return false;
      }
   }
   else
   {
      if(sl - ref < min_dist)
         sl = ref + min_dist;
      if(sl <= ref)
      {
         why = SKIP_STOPS_LEVEL;
         return false;
      }
   }

   const int digits = GeDigits();
   sl = NormalizeDouble(sl, digits);

   const double r = MathAbs(entry - sl);
   if(r <= 0.0)
   {
      why = SKIP_STOPS_LEVEL;
      return false;
   }
   tp = is_long ? entry + InpTPRMultiple * r
                : entry - InpTPRMultiple * r;
   tp = NormalizeDouble(tp, digits);

   if(is_long && (tp - bid < min_dist))
   {
      why = SKIP_TP_LEVEL;
      return false;
   }
   if(!is_long && (ask - tp < min_dist))
   {
      why = SKIP_TP_LEVEL;
      return false;
   }
   return true;
}

class GoldeselTrade
{
private:
   CTrade                   m_trade;
   ENUM_ORDER_TYPE_FILLING  m_filling;
   bool                     m_market_exe;
   bool                     m_filling_ok;
   bool                     m_allow_fok;
   bool                     m_allow_ioc;

   bool SwitchFillingOnInvalid()
   {
      if(m_filling == ORDER_FILLING_FOK && (m_allow_ioc || (m_market_exe && !m_allow_fok && !m_allow_ioc)))
      {
         m_filling = ORDER_FILLING_IOC;
         m_trade.SetTypeFilling(m_filling);
         return true;
      }
      if(m_filling == ORDER_FILLING_IOC && (m_allow_fok || (m_market_exe && !m_allow_fok && !m_allow_ioc)))
      {
         m_filling = ORDER_FILLING_FOK;
         m_trade.SetTypeFilling(m_filling);
         return true;
      }
      return false;
   }

   bool SendMarket(const ENUM_GE_DIR dir, const double lot, const double sl, const double tp, const string comment)
   {
      const string sym = _Symbol;
      bool sent = false;
      if(dir == GE_DIR_LONG)
         sent = m_trade.Buy(lot, sym, 0.0, sl, tp, comment);
      else
         sent = m_trade.Sell(lot, sym, 0.0, sl, tp, comment);
      return sent;
   }

public:
   GoldeselTrade() : m_filling(ORDER_FILLING_FOK), m_market_exe(false), m_filling_ok(false),
                     m_allow_fok(false), m_allow_ioc(false) {}

   bool Init()
   {
      m_filling = GeDetectFilling(m_market_exe, m_filling_ok);
      if(!m_filling_ok)
      {
         Print("Goldesel: no legal filling mode for this symbol");
         return false;
      }
      const long flags = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
      m_allow_fok = ((flags & SYMBOL_FILLING_FOK) != 0) || (m_market_exe && flags == 0);
      m_allow_ioc = ((flags & SYMBOL_FILLING_IOC) != 0) || (m_market_exe && flags == 0);

      m_trade.SetExpertMagicNumber(InpMagic);
      m_trade.SetDeviationInPoints((ulong)GeDeviationPoints());
      m_trade.SetTypeFilling(m_filling);
      m_trade.SetAsyncMode(false);
      m_trade.LogLevel(GeIsTester() ? LOG_LEVEL_ERRORS : LOG_LEVEL_ALL);
      return true;
   }

   ENUM_ORDER_TYPE_FILLING Filling() const { return m_filling; }
   bool MarketExecution() const { return m_market_exe; }
   uint LastRetcode() const { return m_trade.ResultRetcode(); }

   bool Open(const ENUM_GE_DIR dir, const double lot, const double sl, const double tp, const string comment)
   {
      if(dir == GE_DIR_NONE || lot <= 0.0)
         return false;

      bool fill_switched = false;
      for(int pass = 0; pass < 2; ++pass)
      {
         ResetLastError();
         if(SendMarket(dir, lot, sl, tp, comment))
         {
            const uint rc = m_trade.ResultRetcode();
            const double filled = m_trade.ResultVolume();
            if(rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL || rc == TRADE_RETCODE_PLACED)
            {
               if(filled <= 0.0 && rc != TRADE_RETCODE_PLACED)
               {
                  LogError("Open", rc, GetLastError());
                  return false;
               }
               if(filled > 0.0 && filled + 1e-12 < lot)
                  Print("Goldesel: IOC partial fill accepted lot=",
                        DoubleToString(filled, GeVolumeDigits(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP))),
                        " requested=", DoubleToString(lot, 8));
               return true;
            }
         }

         const uint ret = m_trade.ResultRetcode();
         LogError("Open", ret, GetLastError());

         if(ret == TRADE_RETCODE_INVALID_FILL && !fill_switched && SwitchFillingOnInvalid())
         {
            fill_switched = true;
            Print("Goldesel: INVALID_FILL, retrying with ", GeFillingName(m_filling));
            continue;
         }
         break;
      }
      return false;
   }

   bool ModifySL(const ulong ticket, const double sl)
   {
      if(!PositionSelectByTicket(ticket))
         return false;
      const double tp = PositionGetDouble(POSITION_TP);
      ResetLastError();
      if(!m_trade.PositionModify(ticket, sl, tp))
      {
         LogError("ModifySL", m_trade.ResultRetcode(), GetLastError());
         return false;
      }
      return true;
   }

   bool CloseTicket(const ulong ticket, const string reason)
   {
      ResetLastError();
      int attempts = 0;
      bool fill_switched = false;
      while(attempts <= kRetryMax)
      {
         if(m_trade.PositionClose(ticket))
         {
            Print("Goldesel: closed ticket=", IntegerToString((long)ticket), " reason=", reason);
            return true;
         }
         const uint ret = m_trade.ResultRetcode();
         LogError("CloseTicket", ret, GetLastError());
         if(ret == TRADE_RETCODE_INVALID_FILL && !fill_switched && SwitchFillingOnInvalid())
         {
            fill_switched = true;
            Print("Goldesel: close INVALID_FILL, retrying with ", GeFillingName(m_filling));
            continue;
         }
         if(ret == TRADE_RETCODE_FROZEN || ret == TRADE_RETCODE_REQUOTE ||
            ret == TRADE_RETCODE_PRICE_CHANGED || ret == TRADE_RETCODE_PRICE_OFF)
         {
            attempts++;
            if(attempts <= kRetryMax)
            {
               GeSleepRetry();
               continue;
            }
         }
         break;
      }
      return false;
   }

   bool CloseAllOurPositions(const string reason)
   {
      bool all_ok = true;
      for(int i = PositionsTotal() - 1; i >= 0; --i)
      {
         const ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
         if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            continue;
         if(!CloseTicket(ticket, reason))
            all_ok = false;
      }
      return all_ok;
   }

   int CountOurPositions()
   {
      int n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; --i)
      {
         const ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
         if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            continue;
         n++;
      }
      return n;
   }

   bool SelectOurPosition(ulong &ticket)
   {
      ticket = 0;
      for(int i = PositionsTotal() - 1; i >= 0; --i)
      {
         const ulong t = PositionGetTicket(i);
         if(t == 0)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
         if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            continue;
         ticket = t;
         return true;
      }
      return false;
   }

   int CountOtherMagicOnSymbol()
   {
      int n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; --i)
      {
         const ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
         if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            n++;
      }
      return n;
   }
};

GoldeselTrade g_trade;

#endif
