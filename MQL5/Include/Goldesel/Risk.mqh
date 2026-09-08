#ifndef GOLDESEL_RISK_MQH
#define GOLDESEL_RISK_MQH

double RiskDrawdownPct(const GeEquityState &st)
{
   if(st.peak <= 0.0)
      return 0.0;
   return 100.0 * (st.peak - st.equity) / st.peak;
}

double RiskEffectivePercent(const GeEquityState &st)
{
   double base = InpRiskPercent;
   double lock_mult = st.lock_mult;
   if(lock_mult <= 0.0)
      lock_mult = 1.0;
   double dd_mult = 1.0;
   const double dd = RiskDrawdownPct(st);
   if(dd >= kReduceDrawdownPct)
      dd_mult = kDrawdownRiskScale;
   double effective = base * lock_mult * dd_mult;
   if(effective > kMaxRiskPercent)
      effective = kMaxRiskPercent;
   return effective;
}

bool RiskAllowNewTrade(const GeEquityState &st, ENUM_GE_SKIP &why)
{
   if(RiskDrawdownPct(st) >= kHaltDrawdownPct)
   {
      why = SKIP_DD_HALT;
      return false;
   }
   if(st.day_halted)
   {
      why = SKIP_DAILY_HALT;
      return false;
   }
   if(st.week_halted)
   {
      why = SKIP_WEEKLY_HALT;
      return false;
   }
   if(st.flatten_fail)
   {
      why = SKIP_FLATTEN_FAIL;
      return false;
   }
   why = SKIP_NONE;
   return true;
}

double RiskEstimateMVB(const double money_per_min_lot)
{
   if(money_per_min_lot <= 0.0)
      return 0.0;
   const double denom = (kMaxRiskPercent / 100.0) * (1.0 - kCommissionHaircut);
   if(denom <= 0.0)
      return 0.0;
   return money_per_min_lot / denom;
}

bool RiskMoneyPerLot(const ENUM_GE_DIR dir, const double entry, const double sl, double &money_per_lot)
{
   money_per_lot = 0.0;
   const double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   const double vref = MathMax(vmin, MathMin(1.0, vmax));
   if(vref <= 0.0)
      return false;

   const ENUM_ORDER_TYPE ot = (dir == GE_DIR_LONG) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double profit_ref = 0.0;
   const bool oc_ok = OrderCalcProfit(ot, _Symbol, vref, entry, sl, profit_ref);

   if(oc_ok && profit_ref != 0.0)
   {
      money_per_lot = MathAbs(profit_ref) / vref;
   }
   else
   {
      const double tick_size = GeTickSize();
      double tick_val = (dir == GE_DIR_LONG)
         ? SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS)
         : SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT);
      if(tick_val <= 0.0)
         tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tick_size <= 0.0 || tick_val <= 0.0)
         return false;
      money_per_lot = MathAbs(entry - sl) / tick_size * tick_val;
   }
   return (money_per_lot > 0.0);
}

bool RiskComputeLot(const ENUM_GE_DIR dir, const double entry, const double sl, const double tp, GeLotResult &out)
{
   ZeroMemory(out);
   out.ok   = false;
   out.sl   = sl;
   out.tp   = tp;
   out.skip = SKIP_NONE;

   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   const double risk_pct = RiskEffectivePercent(g_state);
   if(risk_pct <= 0.0 || equity <= 0.0)
   {
      out.skip = SKIP_RISK_ZERO;
      return false;
   }

   const double risk_money_gross = equity * risk_pct / 100.0;
   const double risk_money       = risk_money_gross * (1.0 - kCommissionHaircut);
   out.risk_money_planned = risk_money;
   out.risk_pct_planned   = risk_pct;
   if(risk_money <= 0.0)
   {
      out.skip = SKIP_RISK_ZERO;
      return false;
   }

   double money_per_lot = 0.0;
   if(!RiskMoneyPerLot(dir, entry, sl, money_per_lot))
   {
      out.skip = SKIP_TICK_VALUE;
      return false;
   }

   const double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double vmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   const double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double raw_lot = risk_money / money_per_lot;
   double lot     = GeFloorToStep(raw_lot, vstep);

   if(lot < vmin)
   {
      const double money_at_min = money_per_lot * vmin;
      const double max_money    = equity * kMaxRiskPercent / 100.0 * (1.0 - kCommissionHaircut);
      if(money_at_min > max_money + 1e-6)
      {
         out.skip = SKIP_MINLOT_RISK;
         out.lot  = 0.0;
         return false;
      }
      lot = vmin;
   }

   if(lot > vmax)
      lot = vmax;

   if(lot <= 0.0)
   {
      out.skip = SKIP_MINLOT_RISK;
      return false;
   }

   const double actual_sl_money  = lot * money_per_lot;
   const double actual_with_comm = actual_sl_money / (1.0 - kCommissionHaircut);
   if(actual_with_comm > equity * kMaxRiskPercent / 100.0 + 1e-6)
   {
      out.skip = SKIP_MAX_RISK;
      return false;
   }

   const ENUM_ORDER_TYPE ot = (dir == GE_DIR_LONG) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double margin = 0.0;
   if(!OrderCalcMargin(ot, _Symbol, lot, entry, margin) || margin <= 0.0)
   {
      out.skip = SKIP_MARGIN;
      return false;
   }
   const double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(margin > free * kMarginFreeBuffer)
   {
      out.skip = SKIP_MARGIN;
      return false;
   }

   const double spread_price    = GeSpreadPrice();
   const double deviation_price = GeDeviationPrice();
   const double extra           = spread_price + deviation_price;
   const double dist            = MathAbs(entry - sl);
   if(dist <= 0.0)
   {
      out.skip = SKIP_STOPS_LEVEL;
      return false;
   }
   const double eff_sl_money  = lot * money_per_lot / dist * (dist + extra);
   const double eff_with_comm = eff_sl_money / (1.0 - kCommissionHaircut);
   const double cap_money     = equity * kMaxRiskPercent / 100.0;
   const double tight_money   = kSlippageRiskMult * risk_money_gross;

   if(eff_with_comm > cap_money + 1e-6)
   {
      out.skip = SKIP_MAX_RISK;
      return false;
   }
   if(eff_sl_money > tight_money + 1e-6)
   {
      out.skip = SKIP_SLIPPAGE_RISK;
      return false;
   }

   out.ok                 = true;
   out.lot                = NormalizeDouble(lot, GeVolumeDigits(vstep));
   out.risk_money_actual  = actual_sl_money;
   out.risk_money_capped  = actual_with_comm;
   out.risk_pct_actual    = 100.0 * actual_with_comm / equity;
   out.risk_pct_efffill   = 100.0 * eff_with_comm / equity;
   out.skip               = SKIP_NONE;
   return true;
}

void RiskSelfCheckComments_(void)
{
   // SCENARIO TwoRCloseIsNotDeposit
   //   init=2000 peak=2000 equity=2000 last_bal=2000 lock=1.0
   //   2R TP: realized=+20, balance 2020, equity 2020
   //   cash_delta = 20 - 20 = 0
   //   init stays 2000, day_equity stays 2000, peak = max(2000,2020)=2020
   //   growth = 1.0%  → lock still 1.0 (need +50%), but lock CAN engage later
   //   day_pnl = +1.0% (win counts). NOT a BALANCE_JUMP.
   //
   // SCENARIO DepositAtPeakDoesNotDDHalt
   //   init=2000 peak=2000 equity=2000 lock=1.0
   //   deposit +2000, realized=0, equity=4000
   //   step1: init=4000 day/week +=2000
   //   step2: deposit → peak unchanged 2000
   //   step3: peak = max(2000, 4000) = 4000
   //   DD=0, growth=0, lock=1.0. NOT SKIP_DD_HALT. NOT profit-lock.
   //
   // SCENARIO WithdrawDoesNotDDHalt
   //   init=2000 peak=4000 equity=4000 lock=0.50
   //   withdraw -2000, realized=0, equity=2000
   //   step1: init=0+floor → 1e-6 (lock already ratcheted 0.50; does not rise)
   //   step2: peak = max(0, 4000-2000) = 2000
   //   step3: peak = max(2000, 2000) = 2000
   //   DD=0. NOT SKIP_DD_HALT
   //
   // SCENARIO DepositDoesNotTripLock
   //   (same numbers as DepositAtPeakDoesNotDDHalt)
   //
   // SCENARIO DailyHaltLatch
   //   DayEquity=1000, InpDailyLossPercent=2
   //   Equity=979 → pnl=-2.1 → latch HALT
   //   Equity=981 → still HALT (not allow)
   //   next day_key → latch cleared, new DayEquity
   //
   // SCENARIO WeeklyHaltLatch
   //   WeekEquity=1000, InpWeeklyLossPercent=5, Equity=949 → latch
   //   Equity=960 → still HALT
   //
   // Week key fixtures:
   //   2026-09-11 Friday 23:59  → Monday 2026-09-07 → 20260907
   //   2026-09-13 Sunday 23:59  → Monday 2026-09-07 → 20260907
   //   2026-09-14 Monday 00:00  → 20260914
   //   2026-01-01 Thursday      → Monday 2025-12-29 → 20251229
   //
   // Example A: $20 XAUUSD $4 stop → SKIP_MINLOT_RISK (money_at_min $4 > $0.18)
   // Example B: $20 EURUSD 20-pip → SKIP_MINLOT_RISK (money_at_min $2 > $0.18)
   // Example C: $2000 XAUUSD $4 stop 0.5% → 0.02 lot, risk_pct_actual ≈ 0.44%
   // Example D: 1.25× must not pierce 1% — hard cap fires first
}

#endif
