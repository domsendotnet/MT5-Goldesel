#ifndef GOLDESEL_FILTERS_MQH
#define GOLDESEL_FILTERS_MQH

bool FiltersHourInSession(const int hour)
{
   const int start = InpSessionStartHour;
   const int end   = InpSessionEndHour;
   if(start < end)
      return (hour >= start && hour < end);
   return (hour >= start || hour < end);
}

bool FiltersInSessionBarOpen(const datetime bar1_open)
{
   if(!InpUseSessions)
      return true;
   MqlDateTime dt;
   if(!GeTimeToStruct(bar1_open, dt))
      return false;
   return FiltersHourInSession(dt.hour);
}

datetime FiltersFridayCloseDatetime(const datetime now, bool &used_fallback)
{
   used_fallback = false;
   MqlDateTime dt;
   if(!GeTimeToStruct(now, dt))
   {
      used_fallback = true;
      return 0;
   }

   const int dow = dt.day_of_week;
   int days_since_friday;
   if(dow >= 5)
      days_since_friday = dow - 5;
   else
      days_since_friday = dow + 2;
   const datetime friday_date = now - (datetime)days_since_friday * 86400;

   datetime latest_to = 0;
   for(int i = 0; i < 10; ++i)
   {
      datetime ses_from = 0, ses_to = 0;
      if(!SymbolInfoSessionTrade(_Symbol, FRIDAY, (uint)i, ses_from, ses_to))
         break;
      if(ses_to > latest_to)
         latest_to = ses_to;
   }

   MqlDateTime fd;
   GeTimeToStruct(friday_date, fd);
   if(latest_to > 0)
   {
      MqlDateTime st;
      GeTimeToStruct(latest_to, st);
      fd.hour = st.hour;
      fd.min  = st.min;
      fd.sec  = st.sec;
   }
   else
   {
      used_fallback = true;
      fd.hour = kFridayCloseHourFallback;
      fd.min  = kFridayCloseMinuteFallback;
      fd.sec  = 0;
   }
   return StructToTime(fd);
}

bool FiltersInFridayFlattenWindow(const datetime t)
{
   if(!InpFridayFlatten)
      return false;

   MqlDateTime dt;
   if(!GeTimeToStruct(t, dt))
      return false;

   bool used_fallback = false;
   const datetime friday_close = FiltersFridayCloseDatetime(t, used_fallback);
   if(friday_close <= 0)
      return false;
   const datetime start = friday_close - (datetime)kMinutesBeforeFridayClose * 60;

   if(dt.day_of_week == 5 && t >= start)
      return true;

   const int our = g_trade.CountOurPositions();
   if(our <= 0 || t < friday_close)
      return false;

   ulong ticket = 0;
   if(!g_trade.SelectOurPosition(ticket) || !PositionSelectByTicket(ticket))
      return g_state.flatten_fail;
   const datetime pos_time = (datetime)PositionGetInteger(POSITION_TIME);
   return (pos_time < friday_close);
}

bool FiltersSpreadOk(const double atr, ENUM_GE_SKIP &why)
{
   if(atr <= 0.0)
   {
      why = SKIP_ATR;
      return false;
   }
   const double spread = GeSpreadPrice();
   if(spread > InpMaxSpreadATRFrac * atr)
   {
      why = SKIP_SPREAD;
      return false;
   }
   return true;
}

bool FiltersAlgoOk()
{
   return (bool)MQLInfoInteger(MQL_TRADE_ALLOWED)
       && (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)
       && (bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT)
       && (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
}

bool FiltersAllowEntry(const double atr, ENUM_GE_SKIP &why)
{
   why = SKIP_NONE;
   const long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(mode == SYMBOL_TRADE_MODE_CLOSEONLY)
   {
      why = SKIP_CLOSEONLY;
      return false;
   }
   if(!FiltersAlgoOk())
   {
      why = SKIP_NO_ALGO;
      return false;
   }
   if(g_trade.CountOurPositions() > 0)
   {
      why = SKIP_IN_POSITION;
      return false;
   }
   if(FiltersInFridayFlattenWindow(TimeTradeServer()))
   {
      why = SKIP_FRIDAY_FLAT;
      return false;
   }
   if(g_state.flatten_fail)
   {
      why = SKIP_FLATTEN_FAIL;
      return false;
   }
   if(InpUseSessions)
   {
      const datetime bar1 = iTime(_Symbol, GeResolveTF(InpSignalTF), 1);
      if(!FiltersInSessionBarOpen(bar1))
      {
         why = SKIP_SESSION;
         return false;
      }
   }
   if(!FiltersSpreadOk(atr, why))
      return false;
   return true;
}

#endif
