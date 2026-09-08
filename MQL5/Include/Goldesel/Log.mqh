#ifndef GOLDESEL_LOG_MQH
#define GOLDESEL_LOG_MQH

int      g_csv            = INVALID_HANDLE;
datetime g_last_comment   = 0;
datetime g_last_hist_print = 0;
datetime g_last_flat_print = 0;

void LogInit()
{
   g_csv = INVALID_HANDLE;
   if(GeIsOptimizing())
      return;
   const long login = (long)AccountInfoInteger(ACCOUNT_LOGIN);
   const string name = "Goldesel_" + IntegerToString(InpMagic) + "_" + IntegerToString(login) + ".csv";
   g_csv = FileOpen(name, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ);
   if(g_csv == INVALID_HANDLE)
   {
      Print("Goldesel: CSV FileOpen failed err=", IntegerToString(GetLastError()));
      return;
   }
   if(FileSize(g_csv) == 0)
      FileWrite(g_csv,
                "time_server","event","symbol","side","lot","price","sl","tp","r",
                "equity","peak","dd_pct","risk_pct","skip","ticket","comment");
   else
      FileSeek(g_csv, 0, SEEK_END);
}

void LogDeinit()
{
   if(g_csv != INVALID_HANDLE)
   {
      FileClose(g_csv);
      g_csv = INVALID_HANDLE;
   }
   Comment("");
}

void LogEvent(string event, ENUM_GE_SKIP skip, ENUM_GE_DIR dir,
              double lot, double sl, double tp, double r, string extra)
{
   const string line_prefix = "Goldesel: ";
   if(event == "SKIP" && (skip == SKIP_NO_PULLBACK || skip == SKIP_NO_BIAS || skip == SKIP_SESSION))
      ; // journal: once-per-bar is already enforced by new-bar path; still CSV
   else if(event != "")
      Print(line_prefix, event, " ", GeSkipName(skip), " ", GeDirName(dir),
            " lot=", DoubleToString(lot, 4),
            " sl=", DoubleToString(sl, GeDigits()),
            " tp=", DoubleToString(tp, GeDigits()),
            " r=", DoubleToString(r, GeDigits()),
            " ", extra);

   if(g_csv == INVALID_HANDLE || GeIsOptimizing())
      return;

   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   FileWrite(g_csv,
             TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS),
             event,
             _Symbol,
             GeDirName(dir),
             DoubleToString(lot, 8),
             DoubleToString(bid, GeDigits()),
             DoubleToString(sl, GeDigits()),
             DoubleToString(tp, GeDigits()),
             DoubleToString(r, GeDigits()),
             DoubleToString(g_state.equity, 2),
             DoubleToString(g_state.peak, 2),
             DoubleToString(RiskDrawdownPct(g_state), 2),
             DoubleToString(RiskEffectivePercent(g_state), 4),
             GeSkipName(skip),
             extra,
             extra);
   FileFlush(g_csv);
}

void LogError(string where, uint retcode, int last_err)
{
   Print("Goldesel ", where, " FAIL ret=", IntegerToString((int)retcode),
         " (", GeRetcodeText(retcode), ") last=", IntegerToString(last_err),
         " (", GeLastErrorText(last_err), ")");
   LogEvent("ERROR", SKIP_SEND_FAIL, GE_DIR_NONE, 0, 0, 0, 0,
            where + " ret=" + IntegerToString((int)retcode));
}

void LogWaitingHistory()
{
   const datetime now = TimeCurrent();
   if(now - g_last_hist_print < kHistoryPrintSec)
      return;
   g_last_hist_print = now;
   Print("Goldesel: waiting for history");
}

void LogFlattenBlocked()
{
   const datetime now = TimeCurrent();
   if(now - g_last_flat_print < kFlattenLogSec)
      return;
   g_last_flat_print = now;
   g_last_skip = SKIP_FLATTEN_BLOCKED_DISCONNECTED;
   Print("Goldesel: FLATTEN_BLOCKED_DISCONNECTED");
   LogEvent("FLATTEN_BLOCKED_DISCONNECTED", SKIP_FLATTEN_BLOCKED_DISCONNECTED,
            GE_DIR_NONE, 0, 0, 0, 0, "");
}

void LogFlattenFail()
{
   const datetime now = TimeCurrent();
   if(now - g_last_flat_print < kFlattenLogSec)
      return;
   g_last_flat_print = now;
   Print("Goldesel: FLATTEN_FAIL");
   LogEvent("FLATTEN_FAIL", SKIP_FLATTEN_FAIL, GE_DIR_NONE, 0, 0, 0, 0, "");
}

void CommentUpdate()
{
   if(GeIsOptimizing())
      return;
   const datetime now = TimeCurrent();
   if(g_last_comment == now)
      return;
   g_last_comment = now;

   const ENUM_TIMEFRAMES sig  = GeResolveTF(InpSignalTF);
   const ENUM_TIMEFRAMES bias = GeResolveTF(InpBiasTF);
   const double dd   = RiskDrawdownPct(g_state);
   const double risk = RiskEffectivePercent(g_state);
   double day_pct = 0.0, week_pct = 0.0;
   if(g_state.day_equity > 0.0)
      day_pct = 100.0 * (g_state.equity - g_state.day_equity) / g_state.day_equity;
   if(g_state.week_equity > 0.0)
      week_pct = 100.0 * (g_state.equity - g_state.week_equity) / g_state.week_equity;

   string pos = "FLAT";
   ulong ticket = 0;
   if(g_trade.SelectOurPosition(ticket) && PositionSelectByTicket(ticket))
   {
      const long type = PositionGetInteger(POSITION_TYPE);
      pos = ((type == POSITION_TYPE_BUY) ? "LONG " : "SHORT ")
          + DoubleToString(PositionGetDouble(POSITION_VOLUME),
                           GeVolumeDigits(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP)))
          + " sl=" + DoubleToString(PositionGetDouble(POSITION_SL), GeDigits())
          + " tp=" + DoubleToString(PositionGetDouble(POSITION_TP), GeDigits())
          + " R=" + DoubleToString(g_state.init_r, GeDigits());
   }

   MqlDateTime dt;
   GeTimeToStruct(TimeTradeServer(), dt);
   const bool in_sess = FiltersHourInSession(dt.hour);
   const double atr = SignalAtr();
   const int spread_pts = (int)MathRound(GeSpreadPrice() / MathMax(SymbolInfoDouble(_Symbol, SYMBOL_POINT), 1e-12));

   string extra = "";
   if(g_last_skip == SKIP_MINLOT_RISK && g_last_mvb > 0.0)
      extra = " mvb≈" + DoubleToString(g_last_mvb, 0)
            + " eq=" + DoubleToString(g_state.equity, 0);

   string text =
      "Goldesel v" + GOLDESEL_VERSION + "  " + _Symbol + "  "
      + EnumToString(sig) + "/" + EnumToString(bias)
      + "  magic=" + IntegerToString(InpMagic) + "\n"
      + "eq=" + DoubleToString(g_state.equity, 2)
      + "  bal=" + DoubleToString(g_state.balance, 2)
      + "  peak=" + DoubleToString(g_state.peak, 2)
      + "  dd=" + DoubleToString(dd, 1) + "%"
      + "  risk=" + DoubleToString(InpRiskPercent, 2) + "%→" + DoubleToString(risk, 2) + "%\n"
      + "day=" + DoubleToString(day_pct, 1) + "%  week=" + DoubleToString(week_pct, 1)
      + "%  pos=" + pos
      + "  last=" + GeSkipName(g_last_skip) + extra + "\n"
      + "server=" + TimeToString(TimeTradeServer(), TIME_DATE | TIME_MINUTES)
      + "  session=" + (in_sess ? "YES" : "NO")
      + "  spread=" + IntegerToString(spread_pts) + "pts"
      + "  atr=" + DoubleToString(atr, GeDigits());
   Comment(text);
}

#endif
