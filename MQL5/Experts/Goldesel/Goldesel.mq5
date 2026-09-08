#property copyright   "Goldesel contributors"
#property version     "1.0.0"
#property description "Survival-first XAUUSD/FX Expert Advisor. Not financial advice. You can lose the entire deposit."

#include <Goldesel/Config.mqh>

input group "=== Core ==="
input long             InpMagic              = 20260908;    // Magic number
input double           InpRiskPercent        = 0.5;         // Risk per trade, % of equity

input group "=== Strategy ==="
input ENUM_TIMEFRAMES  InpSignalTF           = PERIOD_M15;  // Signal timeframe
input ENUM_TIMEFRAMES  InpBiasTF             = PERIOD_H1;   // Bias timeframe
input int              InpFastEMA            = 21;          // Fast EMA period
input int              InpSlowEMA            = 55;          // Slow EMA period
input int              InpATRPeriod          = 14;          // ATR period
input double           InpSLATRMult          = 1.5;         // SL = this × ATR beyond extreme/EMA
input double           InpTPRMultiple        = 2.0;         // Take profit in R (reward:risk)
input bool             InpUseTrail           = true;        // BE at 1R AND chandelier at 1.5R (bundled)

input group "=== Filters ==="
input bool             InpUseSessions        = true;        // Limit to session hours (server live / GMT in tester)
input int              InpSessionStartHour   = 7;           // Session start hour, inclusive (wrap OK)
input int              InpSessionEndHour     = 20;          // Session end hour, exclusive
input double           InpMaxSpreadATRFrac   = 0.15;        // Skip if spread > this × ATR

input group "=== Safety ==="
input double           InpDailyLossPercent   = 2.0;         // Latch halt: daily loss % of day-start equity
input double           InpWeeklyLossPercent  = 5.0;         // Latch halt: weekly loss % of week-start equity
input int              InpMaxSlippagePoints  = 30;          // Slippage cap in TICKS (tick_size), not SYMBOL_POINT
input bool             InpFridayFlatten      = true;        // Close our positions before Friday session end

#include <Goldesel/Util.mqh>
#include <Goldesel/State.mqh>
#include <Goldesel/Trade.mqh>
#include <Goldesel/Signal.mqh>
#include <Goldesel/Filters.mqh>
#include <Goldesel/Risk.mqh>
#include <Goldesel/Log.mqh>

bool ValidateInputs()
{
   if(InpMagic <= 0)
   {
      Print("Goldesel: InpMagic must be > 0");
      return false;
   }
   if(InpRiskPercent < 0.05 || InpRiskPercent > kMaxRiskPercent)
   {
      Print("Goldesel: InpRiskPercent must be in [0.05, ", DoubleToString(kMaxRiskPercent, 1), "]");
      return false;
   }
   if(InpFastEMA < 2 || InpFastEMA >= InpSlowEMA)
   {
      Print("Goldesel: InpFastEMA must be >= 2 and < InpSlowEMA");
      return false;
   }
   if(InpSlowEMA < 3 || InpSlowEMA > 500)
   {
      Print("Goldesel: InpSlowEMA must be in [3, 500]");
      return false;
   }
   if(InpATRPeriod < 2 || InpATRPeriod > 100)
   {
      Print("Goldesel: InpATRPeriod must be in [2, 100]");
      return false;
   }
   if(InpSLATRMult < 0.5 || InpSLATRMult > 5.0)
   {
      Print("Goldesel: InpSLATRMult must be in [0.5, 5.0]");
      return false;
   }
   if(InpTPRMultiple < 0.5 || InpTPRMultiple > 10.0)
   {
      Print("Goldesel: InpTPRMultiple must be in [0.5, 10.0]");
      return false;
   }
   if(InpSessionStartHour < 0 || InpSessionStartHour > 23 ||
      InpSessionEndHour < 0 || InpSessionEndHour > 23 ||
      InpSessionStartHour == InpSessionEndHour)
   {
      Print("Goldesel: session hours must be 0..23 and start != end (wrap is OK)");
      return false;
   }
   if(InpMaxSpreadATRFrac < 0.01 || InpMaxSpreadATRFrac > 2.0)
   {
      Print("Goldesel: InpMaxSpreadATRFrac must be in [0.01, 2.0]");
      return false;
   }
   if(InpDailyLossPercent <= 0.0 || InpDailyLossPercent > 50.0 ||
      InpWeeklyLossPercent <= 0.0 || InpWeeklyLossPercent > 50.0 ||
      InpWeeklyLossPercent < InpDailyLossPercent)
   {
      Print("Goldesel: daily/weekly halt percents invalid (weekly >= daily, both in (0, 50])");
      return false;
   }
   if(InpMaxSlippagePoints < 0 || InpMaxSlippagePoints > 10000)
   {
      Print("Goldesel: InpMaxSlippagePoints must be in [0, 10000]");
      return false;
   }
   return true;
}

void PrintInitDump()
{
   bool friday_fallback = false;
   const datetime friday_close = FiltersFridayCloseDatetime(TimeTradeServer(), friday_fallback);
   const long trade_mode = AccountInfoInteger(ACCOUNT_TRADE_MODE);
   string acct_mode = "unknown";
   if(trade_mode == ACCOUNT_TRADE_MODE_DEMO)    acct_mode = "DEMO";
   if(trade_mode == ACCOUNT_TRADE_MODE_CONTEST) acct_mode = "CONTEST";
   if(trade_mode == ACCOUNT_TRADE_MODE_REAL)    acct_mode = "REAL";
   const long mm = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   const string hedge = (mm == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) ? "HEDGING" : "NETTING";
   const long exe = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_EXEMODE);
   const long fill_flags = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   const long sym_mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);

   Print("Goldesel: v", GOLDESEL_VERSION,
         " symbol=", _Symbol,
         " magic=", IntegerToString(InpMagic),
         " account=", IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)),
         " mode=", acct_mode,
         " margin=", hedge);
   Print("Goldesel: SYMBOL_TRADE_MODE=", IntegerToString(sym_mode),
         " digits=", IntegerToString(GeDigits()),
         " point=", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_POINT), 8),
         " tick_size=", DoubleToString(GeTickSize(), 8));
   Print("Goldesel: tick_value=", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), 6),
         " tick_value_loss=", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS), 6),
         " tick_value_profit=", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT), 6));
   Print("Goldesel: volume min/step/max=",
         DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), 4), "/",
         DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), 4), "/",
         DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), 4));
   Print("Goldesel: filling_flags=", IntegerToString(fill_flags),
         " exemode=", GeExeModeName((ENUM_SYMBOL_TRADE_EXECUTION)exe),
         " chosen=", GeFillingName(g_trade.Filling()),
         " market_exe=", (g_trade.MarketExecution() ? "yes" : "no"));
   Print("Goldesel: deviation_price=", DoubleToString(GeDeviationPrice(), GeDigits()),
         " deviation_points=", IntegerToString(GeDeviationPoints()));
   Print("Goldesel: Friday close=", TimeToString(friday_close, TIME_DATE | TIME_MINUTES),
         " source=", (friday_fallback ? "fallback-21:00" : "SymbolInfoSessionTrade"));
   Print("Goldesel: tester=", (GeIsTester() ? "yes" : "no"),
         " optimizing=", (GeIsOptimizing() ? "yes" : "no"),
         " visual=", (GeIsVisual() ? "yes" : "no"));
   Print("Goldesel: DISCLAIMER — this software is not guaranteed profitable. You can lose the entire deposit.");
}

int OnInit()
{
   if(!ValidateInputs())
      return INIT_FAILED;
   if(!SymbolSelect(_Symbol, true))
   {
      Print("Goldesel: SymbolSelect failed");
      return INIT_FAILED;
   }
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
   {
      Print("Goldesel: symbol trade mode DISABLED");
      return INIT_FAILED;
   }
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_CLOSEONLY)
      Print("Goldesel: symbol is CLOSEONLY — entries will skip");
   if(!FiltersAlgoOk())
      Print("Goldesel: algo trading currently off — enable AutoTrading");

   if(!g_trade.Init())
      return INIT_FAILED;

   if(g_trade.CountOtherMagicOnSymbol() > 0)
   {
      Print("Goldesel: another position on this symbol with a different magic. One instance per account is the default; risk is additive.");
      if(!GeIsTester())
         Alert("Goldesel: another position on this symbol with a different magic. One instance per account is the default; risk is additive.");
   }

   if(!SignalInit())
      return INIT_FAILED;
   if(!StateLoad())
      return INIT_FAILED;
   LogInit();
   PrintInitDump();
   g_ready = false;
   g_last_skip = SKIP_NOT_READY;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   SignalRelease();
   LogDeinit();
}

bool RecoverInitR(const ulong ticket, double &r)
{
   r = 0.0;
   if(g_state.init_r > 0.0)
   {
      r = g_state.init_r;
      return true;
   }
   if(!PositionSelectByTicket(ticket))
      return false;
   const string cmt = PositionGetString(POSITION_COMMENT);
   string parts[];
   const ushort sep = StringGetCharacter("|", 0);
   const int n = StringSplit(cmt, sep, parts);
   if(n >= 3)
   {
      r = StringToDouble(parts[2]);
      if(r > 0.0)
      {
         g_state.init_r = r;
         return true;
      }
   }
   const double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   const double sl    = PositionGetDouble(POSITION_SL);
   const long   type  = PositionGetInteger(POSITION_TYPE);
   const bool   is_long = (type == POSITION_TYPE_BUY);
   if(sl <= 0.0)
      return false;
   const bool sl_on_loss_side = is_long ? (sl < entry) : (sl > entry);
   if(sl_on_loss_side)
   {
      r = MathAbs(entry - sl);
      if(r > 0.0)
      {
         g_state.init_r = r;
         return true;
      }
   }
   static bool logged_missing = false;
   if(!logged_missing)
   {
      Print("Goldesel: init_r missing after BE");
      logged_missing = true;
   }
   return false;
}

double MinStopDistance()
{
   const double tick   = GeTickSize();
   const int    stops  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const int    freeze = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   const double spread = GeSpreadPrice();
   double min_dist = kSpreadFloorMult * spread;
   if(tick > 0.0)
   {
      min_dist = MathMax(min_dist, (double)(stops  + 1) * tick);
      min_dist = MathMax(min_dist, (double)(freeze + 1) * tick);
   }
   return min_dist;
}

bool ChandelierSL(const ulong ticket, const bool is_long, const double atr, double &trail_sl)
{
   trail_sl = 0.0;
   if(!PositionSelectByTicket(ticket))
      return false;
   const datetime pos_time = (datetime)PositionGetInteger(POSITION_TIME);
   const double   open_px  = PositionGetDouble(POSITION_PRICE_OPEN);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   const int copied = CopyRates(_Symbol, GeResolveTF(InpSignalTF), 0, kChandelierMaxBars, rates);
   if(copied <= 0)
      return false;
   const datetime bar0 = iTime(_Symbol, GeResolveTF(InpSignalTF), 0);
   double extreme = is_long ? -DBL_MAX : DBL_MAX;
   int used = 0;
   for(int i = 0; i < copied; ++i)
   {
      if(rates[i].time < pos_time)
         continue;
      if(rates[i].time >= bar0)
         continue;
      if(is_long)
         extreme = MathMax(extreme, rates[i].close);
      else
         extreme = MathMin(extreme, rates[i].close);
      used++;
   }
   if(used == 0)
      extreme = open_px;
   trail_sl = is_long ? (extreme - kTrailATRMult * atr)
                      : (extreme + kTrailATRMult * atr);
   return true;
}

void ManagePosition()
{
   const datetime now = TimeTradeServer();
   const bool in_flat = FiltersInFridayFlattenWindow(now);
   const int  our     = g_trade.CountOurPositions();

   if(InpFridayFlatten && (in_flat || (our > 0 && g_state.flatten_fail)))
   {
      if(!TerminalInfoInteger(TERMINAL_CONNECTED) && !GeIsTester())
      {
         if(our > 0)
         {
            g_state.flatten_fail = true;
            LogFlattenBlocked();
         }
         return;
      }
      if(our > 0)
      {
         const bool closed = g_trade.CloseAllOurPositions("friday");
         if(g_trade.CountOurPositions() > 0)
         {
            g_state.flatten_fail = true;
            g_last_skip = SKIP_FLATTEN_FAIL;
            LogFlattenFail();
         }
         else
         {
            g_state.flatten_fail = false;
            StateClearPositionRisk();
            LogEvent("FLATTEN", SKIP_NONE, GE_DIR_NONE, 0, 0, 0, 0, closed ? "ok" : "ok-partial");
         }
      }
      else
         g_state.flatten_fail = false;
      return;
   }

   if(!InpUseTrail)
      return;
   ulong ticket = 0;
   if(!g_trade.SelectOurPosition(ticket))
      return;
   if(!PositionSelectByTicket(ticket))
      return;

   double r = 0.0;
   if(!RecoverInitR(ticket, r) || r <= 0.0)
      return;

   double atr = 0.0;
   if(!SignalCopyAtrTrail(atr))
      return;

   const bool   is_long = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   const double entry   = PositionGetDouble(POSITION_PRICE_OPEN);
   const double sl_now  = PositionGetDouble(POSITION_SL);
   const double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double spread  = GeSpreadPrice();
   const double fav     = is_long ? bid : ask;
   const double mfe     = is_long ? (fav - entry) : (entry - fav);
   const double min_dist = MinStopDistance();
   const double ref      = is_long ? bid : ask;
   const int    digits   = GeDigits();

   double candidate = sl_now;
   bool   have      = (sl_now > 0.0);

   if(mfe >= kBE_R * r)
   {
      const double be_sl = is_long ? (entry + spread) : (entry - spread);
      if(is_long)
      {
         if(!have || be_sl > candidate)
         {
            if(ref - be_sl >= min_dist)
            {
               candidate = be_sl;
               have = true;
            }
         }
      }
      else
      {
         if(!have || be_sl < candidate)
         {
            if(be_sl - ref >= min_dist)
            {
               candidate = be_sl;
               have = true;
            }
         }
      }
   }

   if(mfe >= kTrailStartR * r)
   {
      double trail_sl = 0.0;
      if(ChandelierSL(ticket, is_long, atr, trail_sl))
      {
         if(is_long)
         {
            if(ref - trail_sl < min_dist || trail_sl >= ref)
               trail_sl = 0.0;
            else if(!have || trail_sl > candidate)
            {
               candidate = trail_sl;
               have = true;
            }
         }
         else
         {
            if(trail_sl - ref < min_dist || trail_sl <= ref)
               trail_sl = 0.0;
            else if(!have || trail_sl < candidate)
            {
               candidate = trail_sl;
               have = true;
            }
         }
      }
   }

   if(!have)
      return;
   candidate = NormalizeDouble(candidate, digits);
   const double sl_cmp = NormalizeDouble(sl_now, digits);
   const bool tighter = is_long ? (candidate > sl_cmp + 1e-12) : (candidate < sl_cmp - 1e-12 || sl_now <= 0.0);
   if(!tighter)
      return;

   const int freeze = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   if(freeze > 0)
   {
      const double freeze_dist = (double)(freeze + 1) * GeTickSize();
      if(MathAbs(ref - sl_now) < freeze_dist)
      {
         g_last_skip = SKIP_FREEZE;
         return;
      }
   }

   const bool was_be = (mfe >= kBE_R * r && mfe < kTrailStartR * r);
   if(g_trade.ModifySL(ticket, candidate))
      LogEvent(was_be ? "MODIFY_BE" : "MODIFY_TRAIL", SKIP_NONE,
               is_long ? GE_DIR_LONG : GE_DIR_SHORT,
               PositionGetDouble(POSITION_VOLUME), candidate,
               PositionGetDouble(POSITION_TP), r, "");
}

void OnTick()
{
   StateOnTick();
   CommentUpdate();

   const bool have_pos = g_trade.CountOurPositions() > 0;
   if(have_pos || FiltersInFridayFlattenWindow(TimeTradeServer()))
      ManagePosition();

   if(!g_ready)
   {
      g_ready = SignalReady();
      if(!g_ready)
      {
         g_last_skip = SKIP_NOT_READY;
         LogWaitingHistory();
         return;
      }
   }

   if(!TerminalInfoInteger(TERMINAL_CONNECTED) && !GeIsTester())
      return;

   if(!SignalNewBar())
      return;

   if(!SignalCopyBuffers())
   {
      g_last_skip = SKIP_ATR;
      LogEvent("SKIP", SKIP_ATR, GE_DIR_NONE, 0, 0, 0, 0, "");
      return;
   }

   ENUM_GE_SKIP why = SKIP_NONE;
   if(!FiltersAllowEntry(SignalAtr(), why) || !RiskAllowNewTrade(g_state, why))
   {
      LogEvent("SKIP", why, GE_DIR_NONE, 0, 0, 0, 0, "");
      g_last_skip = why;
      return;
   }

   GeSetup setup;
   if(!SignalEvaluate(setup, why) || setup.dir == GE_DIR_NONE)
   {
      g_last_skip = why;
      LogEvent("SKIP", why, GE_DIR_NONE, 0, 0, 0, 0, "");
      return;
   }

   bool opened = false;
   GeLotResult lot;
   ZeroMemory(lot);
   double sl = 0.0, tp = 0.0, entry = 0.0;
   for(int attempt = 0; attempt <= kRetryMax; ++attempt)
   {
      entry  = (setup.dir == GE_DIR_LONG)
               ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
               : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      const double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
      SignalSLTP(setup, entry, spread, sl, tp);
      if(!GeNormalizeStops(entry, setup.dir, sl, tp, why))
      {
         LogEvent("SKIP", why, setup.dir, 0, sl, tp, 0, "");
         g_last_skip = why;
         return;
      }

      if(!RiskComputeLot(setup.dir, entry, sl, tp, lot))
      {
         if(lot.skip == SKIP_MINLOT_RISK)
         {
            double mpl = 0.0;
            if(RiskMoneyPerLot(setup.dir, entry, sl, mpl))
               g_last_mvb = RiskEstimateMVB(mpl * SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
         }
         LogEvent("SKIP", lot.skip, setup.dir, lot.lot, sl, tp, MathAbs(entry - sl), "");
         g_last_skip = lot.skip;
         return;
      }

      string cmt = "GE|" + GOLDESEL_VERSION + "|" + DoubleToString(MathAbs(entry - sl), GeDigits());
      if(StringLen(cmt) > 31)
         cmt = StringSubstr(cmt, 0, 31);
      if(g_trade.Open(setup.dir, lot.lot, sl, tp, cmt))
      {
         opened = true;
         break;
      }

      const uint rc = g_trade.LastRetcode();
      if(rc == TRADE_RETCODE_REQUOTE || rc == TRADE_RETCODE_PRICE_CHANGED || rc == TRADE_RETCODE_PRICE_OFF)
      {
         if(attempt < kRetryMax)
         {
            GeSleepRetry();
            continue;
         }
      }
      break;
   }

   if(!opened)
   {
      LogEvent("SKIP", SKIP_SEND_FAIL, setup.dir, lot.lot, sl, tp, MathAbs(entry - sl), "");
      g_last_skip = SKIP_SEND_FAIL;
      return;
   }
   StateSavePositionRisk(sl, MathAbs(entry - sl));
   LogEvent("OPEN", SKIP_NONE, setup.dir, lot.lot, sl, tp, MathAbs(entry - sl),
            "risk_pct_actual=" + DoubleToString(lot.risk_pct_actual, 4)
            + " risk_pct_efffill=" + DoubleToString(lot.risk_pct_efffill, 4));
   g_last_skip = SKIP_NONE;
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   const ulong deal = trans.deal;
   if(deal == 0)
      return;
   if(!HistoryDealSelect(deal))
      return;
   if((long)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic)
      return;
   if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
      return;

   const ENUM_DEAL_TYPE dtype = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE);
   if(dtype == DEAL_TYPE_BUY || dtype == DEAL_TYPE_SELL)
   {
      const double profit = HistoryDealGetDouble(deal, DEAL_PROFIT);
      const double comm   = HistoryDealGetDouble(deal, DEAL_COMMISSION);
      const double swap   = HistoryDealGetDouble(deal, DEAL_SWAP);
      StateOnDealRealized(deal, profit, comm, swap);

      const ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      const double vol   = HistoryDealGetDouble(deal, DEAL_VOLUME);
      const double price = HistoryDealGetDouble(deal, DEAL_PRICE);
      const ENUM_GE_DIR dir = (dtype == DEAL_TYPE_BUY) ? GE_DIR_LONG : GE_DIR_SHORT;
      if(entry == DEAL_ENTRY_IN)
      {
         if(g_state.init_sl > 0.0)
         {
            const double r = MathAbs(price - g_state.init_sl);
            if(r > 0.0)
               StateSavePositionRisk(g_state.init_sl, r);
         }
         LogEvent("FILL", SKIP_NONE, dir, vol, g_state.init_sl, 0, g_state.init_r,
                  "price=" + DoubleToString(price, GeDigits())
                  + " deal=" + IntegerToString((long)deal));
      }
      else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
      {
         LogEvent("CLOSE", SKIP_NONE, dir, vol, 0, 0, 0,
                  "pnl=" + DoubleToString(profit + comm + swap, 2)
                  + " deal=" + IntegerToString((long)deal));
         if(g_trade.CountOurPositions() == 0)
         {
            StateClearPositionRisk();
            g_state.flatten_fail = false;
         }
      }
   }
}
