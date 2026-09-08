#ifndef GOLDESEL_UTIL_MQH
#define GOLDESEL_UTIL_MQH

bool GeIsTester()
{
   return (bool)MQLInfoInteger(MQL_TESTER);
}

bool GeIsOptimizing()
{
   return (bool)MQLInfoInteger(MQL_OPTIMIZATION);
}

bool GeIsVisual()
{
   return (bool)MQLInfoInteger(MQL_VISUAL_MODE);
}

bool GeTimeToStruct(const datetime t, MqlDateTime &dt)
{
   return TimeToStruct(t, dt);
}

int GeDayKey(const datetime t)
{
   MqlDateTime dt;
   if(!GeTimeToStruct(t, dt))
      return 0;
   return dt.year * 10000 + dt.mon * 100 + dt.day;
}

int GeWeekKey(const datetime t)
{
   MqlDateTime dt;
   if(!GeTimeToStruct(t, dt))
      return 0;
   const int dow = dt.day_of_week;
   const int days_since_monday = (dow == 0) ? 6 : (dow - 1);
   const datetime monday = t - (datetime)days_since_monday * 86400;
   MqlDateTime m;
   if(!GeTimeToStruct(monday, m))
      return 0;
   return m.year * 10000 + m.mon * 100 + m.day;
}

double GeFloorToStep(const double vol, const double step)
{
   if(step <= 0.0)
      return vol;
   return MathFloor(vol / step + 1e-12) * step;
}

int GeVolumeDigits(const double step)
{
   int d = 0;
   double s = step;
   while(s < 1.0 - 1e-12 && d < 8)
   {
      s *= 10.0;
      ++d;
   }
   return d;
}

double GeSpreadPrice()
{
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double sp  = ask - bid;
   return (sp > 0.0) ? sp : 0.0;
}

double GeDeviationPrice()
{
   const double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   const double from_ticks = (tick > 0.0) ? (double)InpMaxSlippagePoints * tick : 0.0;
   const double from_spread = kDeviationSpreadMult * GeSpreadPrice();
   return MathMax(from_ticks, from_spread);
}

int GeDeviationPoints()
{
   const double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return InpMaxSlippagePoints;
   const int pts = (int)MathRound(GeDeviationPrice() / point);
   return (pts < 0) ? 0 : pts;
}

int GeDigits()
{
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
}

double GeTickSize()
{
   double t = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(t <= 0.0)
      t = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   return t;
}

string GeFillingName(const ENUM_ORDER_TYPE_FILLING f)
{
   switch(f)
   {
      case ORDER_FILLING_FOK:    return "FOK";
      case ORDER_FILLING_IOC:    return "IOC";
      case ORDER_FILLING_RETURN: return "RETURN";
   }
   return "UNKNOWN";
}

string GeExeModeName(const ENUM_SYMBOL_TRADE_EXECUTION exe)
{
   switch(exe)
   {
      case SYMBOL_TRADE_EXECUTION_REQUEST:  return "REQUEST";
      case SYMBOL_TRADE_EXECUTION_INSTANT:  return "INSTANT";
      case SYMBOL_TRADE_EXECUTION_MARKET:   return "MARKET";
      case SYMBOL_TRADE_EXECUTION_EXCHANGE: return "EXCHANGE";
   }
   return "UNKNOWN";
}

string GeRetcodeText(const uint ret)
{
   switch(ret)
   {
      case TRADE_RETCODE_REQUOTE:            return "requote";
      case TRADE_RETCODE_REJECT:             return "reject";
      case TRADE_RETCODE_CANCEL:             return "cancel";
      case TRADE_RETCODE_PLACED:             return "placed";
      case TRADE_RETCODE_DONE:               return "done";
      case TRADE_RETCODE_DONE_PARTIAL:       return "done_partial";
      case TRADE_RETCODE_ERROR:              return "error";
      case TRADE_RETCODE_TIMEOUT:            return "timeout";
      case TRADE_RETCODE_INVALID:            return "invalid";
      case TRADE_RETCODE_INVALID_VOLUME:     return "invalid_volume";
      case TRADE_RETCODE_INVALID_PRICE:      return "invalid_price";
      case TRADE_RETCODE_INVALID_STOPS:      return "invalid_stops";
      case TRADE_RETCODE_TRADE_DISABLED:     return "trade_disabled";
      case TRADE_RETCODE_MARKET_CLOSED:      return "market_closed";
      case TRADE_RETCODE_NO_MONEY:           return "no_money";
      case TRADE_RETCODE_PRICE_CHANGED:      return "price_changed";
      case TRADE_RETCODE_PRICE_OFF:          return "price_off";
      case TRADE_RETCODE_INVALID_EXPIRATION: return "invalid_expiration";
      case TRADE_RETCODE_ORDER_CHANGED:      return "order_changed";
      case TRADE_RETCODE_TOO_MANY_REQUESTS:  return "too_many_requests";
      case TRADE_RETCODE_NO_CHANGES:         return "no_changes";
      case TRADE_RETCODE_SERVER_DISABLES_AT: return "server_disables_at";
      case TRADE_RETCODE_CLIENT_DISABLES_AT: return "client_disables_at";
      case TRADE_RETCODE_LOCKED:             return "locked";
      case TRADE_RETCODE_FROZEN:             return "frozen";
      case TRADE_RETCODE_INVALID_FILL:       return "invalid_fill";
      case TRADE_RETCODE_CONNECTION:         return "connection";
      case TRADE_RETCODE_ONLY_REAL:          return "only_real";
      case TRADE_RETCODE_LIMIT_ORDERS:       return "limit_orders";
      case TRADE_RETCODE_LIMIT_VOLUME:       return "limit_volume";
      case TRADE_RETCODE_INVALID_ORDER:      return "invalid_order";
      case TRADE_RETCODE_POSITION_CLOSED:    return "position_closed";
   }
   return IntegerToString((int)ret);
}

string GeLastErrorText(const int err)
{
   switch(err)
   {
      case 0:    return "ok";
      case 4752: return "trade_disabled";
      case 4753: return "market_closed";
      case 4754: return "no_money";
      case 4756: return "trade_timeout";
      case 10004: return "requote";
      case 10006: return "reject";
      case 10015: return "invalid_stops";
      case 10016: return "invalid_fill";
      case 10018: return "market_closed";
      case 10019: return "no_money";
      case 10020: return "price_changed";
      case 10021: return "price_off";
      case 10030: return "invalid_fill";
   }
   return IntegerToString(err);
}

string GeDirName(const ENUM_GE_DIR d)
{
   if(d == GE_DIR_LONG)  return "LONG";
   if(d == GE_DIR_SHORT) return "SHORT";
   return "NONE";
}

void GeSleepRetry()
{
   if(!GeIsTester())
      Sleep(100);
}

#endif
