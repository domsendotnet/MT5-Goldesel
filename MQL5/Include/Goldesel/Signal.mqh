#ifndef GOLDESEL_SIGNAL_MQH
#define GOLDESEL_SIGNAL_MQH

int      g_hFastBias = INVALID_HANDLE;
int      g_hSlowBias = INVALID_HANDLE;
int      g_hFastSig  = INVALID_HANDLE;
int      g_hATR      = INVALID_HANDLE;
double   g_fast_bias[3];
double   g_slow_bias[3];
double   g_fast_sig[3];
double   g_atr[3];
MqlRates g_bias_rates[];
MqlRates g_sig_rates[];
datetime g_last_signal_bar = 0;
int      g_need_bias       = 0;
int      g_need_signal     = 0;

ENUM_TIMEFRAMES GeResolveTF(const ENUM_TIMEFRAMES tf)
{
   if(tf == PERIOD_CURRENT)
      return (ENUM_TIMEFRAMES)_Period;
   return tf;
}

bool SignalInit()
{
   const ENUM_TIMEFRAMES bias_tf = GeResolveTF(InpBiasTF);
   const ENUM_TIMEFRAMES sig_tf  = GeResolveTF(InpSignalTF);

   g_hFastBias = iMA(_Symbol, bias_tf, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_hSlowBias = iMA(_Symbol, bias_tf, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_hFastSig  = iMA(_Symbol, sig_tf,  InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_hATR      = iATR(_Symbol, sig_tf, InpATRPeriod);

   if(g_hFastBias == INVALID_HANDLE || g_hSlowBias == INVALID_HANDLE ||
      g_hFastSig  == INVALID_HANDLE || g_hATR      == INVALID_HANDLE)
   {
      Print("Goldesel: indicator handle failed");
      return false;
   }

   g_need_bias   = InpSlowEMA + 5;
   g_need_signal = MathMax(InpFastEMA, MathMax(InpATRPeriod, kPullbackBars)) + 5;

   MqlRates tmp[];
   CopyRates(_Symbol, bias_tf, 0, g_need_bias, tmp);
   CopyRates(_Symbol, sig_tf,  0, g_need_signal, tmp);

   g_last_signal_bar = iTime(_Symbol, sig_tf, 0);
   ArraySetAsSeries(g_fast_bias, true);
   ArraySetAsSeries(g_slow_bias, true);
   ArraySetAsSeries(g_fast_sig,  true);
   ArraySetAsSeries(g_atr,       true);
   ArraySetAsSeries(g_bias_rates, true);
   ArraySetAsSeries(g_sig_rates,  true);
   return true;
}

void SignalRelease()
{
   if(g_hFastBias != INVALID_HANDLE) IndicatorRelease(g_hFastBias);
   if(g_hSlowBias != INVALID_HANDLE) IndicatorRelease(g_hSlowBias);
   if(g_hFastSig  != INVALID_HANDLE) IndicatorRelease(g_hFastSig);
   if(g_hATR      != INVALID_HANDLE) IndicatorRelease(g_hATR);
   g_hFastBias = g_hSlowBias = g_hFastSig = g_hATR = INVALID_HANDLE;
}

bool SignalReady()
{
   if(BarsCalculated(g_hFastBias) < g_need_bias)   return false;
   if(BarsCalculated(g_hSlowBias) < g_need_bias)   return false;
   if(BarsCalculated(g_hFastSig)  < g_need_signal) return false;
   if(BarsCalculated(g_hATR)      < g_need_signal) return false;
   return true;
}

bool SignalNewBar()
{
   const datetime t = iTime(_Symbol, GeResolveTF(InpSignalTF), 0);
   if(t == 0)
      return false;
   if(t == g_last_signal_bar)
      return false;
   g_last_signal_bar = t;
   return true;
}

bool SignalCopyBuffers()
{
   if(CopyBuffer(g_hFastBias, 0, 0, 3, g_fast_bias) < 3) return false;
   if(CopyBuffer(g_hSlowBias, 0, 0, 3, g_slow_bias) < 3) return false;
   if(CopyBuffer(g_hFastSig,  0, 0, 3, g_fast_sig)  < 3) return false;
   if(CopyBuffer(g_hATR,      0, 0, 3, g_atr)       < 3) return false;

   const ENUM_TIMEFRAMES bias_tf = GeResolveTF(InpBiasTF);
   const ENUM_TIMEFRAMES sig_tf  = GeResolveTF(InpSignalTF);
   if(CopyRates(_Symbol, bias_tf, 0, 3, g_bias_rates) < 3)
      return false;
   if(CopyRates(_Symbol, sig_tf, 0, kPullbackBars + 2, g_sig_rates) < kPullbackBars + 2)
      return false;
   return true;
}

double SignalAtr()
{
   if(ArraySize(g_atr) < 2)
      return 0.0;
   return g_atr[1];
}

bool SignalCopyAtrTrail(double &atr)
{
   atr = 0.0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_hATR, 0, 1, 1, buf) < 1)
      return false;
   atr = buf[0];
   return (atr > 0.0);
}

void SignalSLTP(const GeSetup &setup, const double entry, const double spread_price,
                double &sl, double &tp)
{
   const double atr = setup.atr;
   if(setup.dir == GE_DIR_LONG)
   {
      const double sl_from_extreme = setup.bar1_low     - InpSLATRMult * atr;
      const double sl_from_ema     = setup.ema_fast_sig - InpSLATRMult * atr;
      sl = MathMin(sl_from_extreme, sl_from_ema);
   }
   else
   {
      const double sl_from_extreme = setup.bar1_high    + InpSLATRMult * atr;
      const double sl_from_ema     = setup.ema_fast_sig + InpSLATRMult * atr;
      sl = MathMax(sl_from_extreme, sl_from_ema);
   }
   const double r = MathAbs(entry - sl);
   tp = (setup.dir == GE_DIR_LONG) ? entry + InpTPRMultiple * r
                                   : entry - InpTPRMultiple * r;
   if(spread_price < 0.0)
      sl = sl;
}

bool SignalEvaluate(GeSetup &out, ENUM_GE_SKIP &why)
{
   ZeroMemory(out);
   out.dir = GE_DIR_NONE;
   why = SKIP_NONE;

   const double atr = g_atr[1];
   if(atr <= 0.0)
   {
      why = SKIP_ATR;
      return false;
   }

   const double ema_fast_bias = g_fast_bias[1];
   const double ema_slow_bias = g_slow_bias[1];
   const double close_bias    = g_bias_rates[1].close;
   const bool bias_long  = (ema_fast_bias > ema_slow_bias) && (close_bias > ema_slow_bias);
   const bool bias_short = (ema_fast_bias < ema_slow_bias) && (close_bias < ema_slow_bias);
   if(!bias_long && !bias_short)
   {
      why = SKIP_NO_BIAS;
      return false;
   }

   const double ema = g_fast_sig[1];
   const double close1 = g_sig_rates[1].close;
   const double open1  = g_sig_rates[1].open;

   bool long_ok  = false;
   bool short_ok = false;

   if(bias_long)
   {
      bool touch = false;
      for(int i = 1; i <= kPullbackBars; ++i)
      {
         if(g_sig_rates[i].low <= ema + kEntryATRFrac * atr)
         {
            touch = true;
            break;
         }
      }
      const bool reclaim = (close1 > ema) && (close1 > open1);
      if(touch && reclaim)
      {
         if((close1 - ema) > kMaxChaseATR * atr)
         {
            why = SKIP_CHASE;
            return false;
         }
         long_ok = true;
      }
      else
      {
         why = SKIP_NO_PULLBACK;
      }
   }

   if(bias_short)
   {
      bool touch = false;
      for(int i = 1; i <= kPullbackBars; ++i)
      {
         if(g_sig_rates[i].high >= ema - kEntryATRFrac * atr)
         {
            touch = true;
            break;
         }
      }
      const bool reclaim = (close1 < ema) && (close1 < open1);
      if(touch && reclaim)
      {
         if((ema - close1) > kMaxChaseATR * atr)
         {
            why = SKIP_CHASE;
            return false;
         }
         short_ok = true;
      }
      else if(!long_ok)
      {
         why = SKIP_NO_PULLBACK;
      }
   }

   if(long_ok && short_ok)
   {
      why = SKIP_AMBIGUOUS;
      return false;
   }
   if(!long_ok && !short_ok)
   {
      if(why == SKIP_NONE)
         why = SKIP_NO_PULLBACK;
      return false;
   }

   out.dir          = long_ok ? GE_DIR_LONG : GE_DIR_SHORT;
   out.ema_fast_sig = ema;
   out.atr          = atr;
   out.bar1_low     = g_sig_rates[1].low;
   out.bar1_high    = g_sig_rates[1].high;
   out.bar1_close   = close1;
   out.bar1_time    = g_sig_rates[1].time;
   why              = SKIP_NONE;
   return true;
}

#endif
