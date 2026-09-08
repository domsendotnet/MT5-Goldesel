#ifndef GOLDESEL_CONFIG_MQH
#define GOLDESEL_CONFIG_MQH

#define GOLDESEL_VERSION          "1.0.0"
#define GOLDESEL_USE_PROFIT_LOCK  1

#define kPullbackBars                  5
#define kEntryATRFrac                  0.25
#define kMaxChaseATR                   1.00
#define kBE_R                          1.0
#define kTrailStartR                   1.5
#define kTrailATRMult                  1.0
#define kSpreadFloorMult               2.0
#define kFridayCloseHourFallback       21
#define kFridayCloseMinuteFallback     0
#define kMinutesBeforeFridayClose      30
#define kMaxRiskPercent                1.0
#define kReduceDrawdownPct             5.0
#define kHaltDrawdownPct               10.0
#define kDrawdownRiskScale             0.5
#define kSlippageRiskMult              1.25
#define kMarginFreeBuffer              0.80
#define kCommissionHaircut             0.10
#define kCashFlowEps                   0.01
#define kDeviationSpreadMult           1.0
#define kRetryMax                      2
#define kCommentThrottleSec            1
#define kHistoryPrintSec               10
#define kFlattenLogSec                 10
#define kChandelierMaxBars             500

enum ENUM_GE_SKIP
{
   SKIP_NONE = 0,
   SKIP_NOT_READY,
   SKIP_DISCONNECTED,
   SKIP_NO_ALGO,
   SKIP_CLOSEONLY,
   SKIP_IN_POSITION,
   SKIP_SESSION,
   SKIP_SPREAD,
   SKIP_DAILY_HALT,
   SKIP_WEEKLY_HALT,
   SKIP_DD_HALT,
   SKIP_FRIDAY_FLAT,
   SKIP_FLATTEN_FAIL,
   SKIP_FLATTEN_BLOCKED_DISCONNECTED,
   SKIP_NO_BIAS,
   SKIP_NO_PULLBACK,
   SKIP_CHASE,
   SKIP_AMBIGUOUS,
   SKIP_ATR,
   SKIP_MINLOT_RISK,
   SKIP_MAX_RISK,
   SKIP_MARGIN,
   SKIP_SLIPPAGE_RISK,
   SKIP_STOPS_LEVEL,
   SKIP_TP_LEVEL,
   SKIP_TICK_VALUE,
   SKIP_FREEZE,
   SKIP_SEND_FAIL,
   SKIP_RISK_ZERO
};

enum ENUM_GE_DIR
{
   GE_DIR_NONE  = 0,
   GE_DIR_LONG  = 1,
   GE_DIR_SHORT = -1
};

struct GeSetup
{
   ENUM_GE_DIR dir;
   double      ema_fast_sig;
   double      atr;
   double      bar1_low;
   double      bar1_high;
   double      bar1_close;
   datetime    bar1_time;
};

struct GeLotResult
{
   bool         ok;
   double       lot;
   double       risk_money_planned;
   double       risk_money_actual;
   double       risk_money_capped;
   double       sl;
   double       tp;
   double       risk_pct_planned;
   double       risk_pct_actual;
   double       risk_pct_efffill;
   ENUM_GE_SKIP skip;
};

ENUM_GE_SKIP g_last_skip = SKIP_NONE;
bool         g_ready     = false;
double       g_last_mvb  = 0.0;

void LogEvent(string event, ENUM_GE_SKIP skip, ENUM_GE_DIR dir,
              double lot, double sl, double tp, double r, string extra);
void LogError(string where, uint retcode, int last_err);

string GeSkipName(const ENUM_GE_SKIP s)
{
   switch(s)
   {
      case SKIP_NONE:                           return "SKIP_NONE";
      case SKIP_NOT_READY:                      return "SKIP_NOT_READY";
      case SKIP_DISCONNECTED:                   return "SKIP_DISCONNECTED";
      case SKIP_NO_ALGO:                        return "SKIP_NO_ALGO";
      case SKIP_CLOSEONLY:                      return "SKIP_CLOSEONLY";
      case SKIP_IN_POSITION:                    return "SKIP_IN_POSITION";
      case SKIP_SESSION:                        return "SKIP_SESSION";
      case SKIP_SPREAD:                         return "SKIP_SPREAD";
      case SKIP_DAILY_HALT:                     return "SKIP_DAILY_HALT";
      case SKIP_WEEKLY_HALT:                    return "SKIP_WEEKLY_HALT";
      case SKIP_DD_HALT:                        return "SKIP_DD_HALT";
      case SKIP_FRIDAY_FLAT:                    return "SKIP_FRIDAY_FLAT";
      case SKIP_FLATTEN_FAIL:                   return "SKIP_FLATTEN_FAIL";
      case SKIP_FLATTEN_BLOCKED_DISCONNECTED:   return "SKIP_FLATTEN_BLOCKED_DISCONNECTED";
      case SKIP_NO_BIAS:                        return "SKIP_NO_BIAS";
      case SKIP_NO_PULLBACK:                    return "SKIP_NO_PULLBACK";
      case SKIP_CHASE:                          return "SKIP_CHASE";
      case SKIP_AMBIGUOUS:                      return "SKIP_AMBIGUOUS";
      case SKIP_ATR:                            return "SKIP_ATR";
      case SKIP_MINLOT_RISK:                    return "SKIP_MINLOT_RISK";
      case SKIP_MAX_RISK:                       return "SKIP_MAX_RISK";
      case SKIP_MARGIN:                         return "SKIP_MARGIN";
      case SKIP_SLIPPAGE_RISK:                  return "SKIP_SLIPPAGE_RISK";
      case SKIP_STOPS_LEVEL:                    return "SKIP_STOPS_LEVEL";
      case SKIP_TP_LEVEL:                       return "SKIP_TP_LEVEL";
      case SKIP_TICK_VALUE:                     return "SKIP_TICK_VALUE";
      case SKIP_FREEZE:                         return "SKIP_FREEZE";
      case SKIP_SEND_FAIL:                      return "SKIP_SEND_FAIL";
      case SKIP_RISK_ZERO:                      return "SKIP_RISK_ZERO";
   }
   return "SKIP_UNKNOWN";
}

#endif
