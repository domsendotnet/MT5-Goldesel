#ifndef GOLDESEL_STATE_MQH
#define GOLDESEL_STATE_MQH

struct GeEquityState
{
   double equity;
   double balance;
   double last_balance;
   double deal_pnl_accum;
   double peak;
   double initial_balance;
   double day_equity;
   double week_equity;
   int    day_key;
   int    week_key;
   bool   day_halted;
   bool   week_halted;
   double lock_mult;
   double init_sl;
   double init_r;
   bool   flatten_fail;
   bool   seeded;
   ulong  last_deal_ticket;
};

GeEquityState g_state;

void StateCatchUpDealCursor();
void StateHarvestDeals();

string StateGvPrefix()
{
   const long magic = InpMagic;
   long login = (long)AccountInfoInteger(ACCOUNT_LOGIN);
   string prefix = "GE_" + IntegerToString(magic) + "_" + IntegerToString(login) + "_";
   if(StringLen(prefix) + 6 > 63)
   {
      login = login % 10000000000;
      prefix = "GE_" + IntegerToString(magic) + "_" + IntegerToString(login) + "_";
      static bool warned = false;
      if(!warned)
      {
         Print("Goldesel: login truncated for GV name length");
         warned = true;
      }
   }
   return prefix;
}

bool StateGvGet(const string key, double &out)
{
   if(!GlobalVariableCheck(key))
      return false;
   out = GlobalVariableGet(key);
   return true;
}

void StateGvSet(const string key, const double v)
{
   GlobalVariableSet(key, v);
}

void StatePersistLive()
{
   if(GeIsTester() || GeIsOptimizing())
      return;
   const string p = StateGvPrefix();
   StateGvSet(p + "peak",   g_state.peak);
   StateGvSet(p + "init",   g_state.initial_balance);
   StateGvSet(p + "bal",    g_state.last_balance);
   StateGvSet(p + "lock",   g_state.lock_mult);
   StateGvSet(p + "dayeq",  g_state.day_equity);
   StateGvSet(p + "day",    (double)g_state.day_key);
   StateGvSet(p + "dayh",   g_state.day_halted ? 1.0 : 0.0);
   StateGvSet(p + "weekeq", g_state.week_equity);
   StateGvSet(p + "week",   (double)g_state.week_key);
   StateGvSet(p + "weekh",  g_state.week_halted ? 1.0 : 0.0);
   StateGvSet(p + "initsl", g_state.init_sl);
   StateGvSet(p + "initr",  g_state.init_r);
   StateGvSet(p + "deal",   (double)g_state.last_deal_ticket);
}

void StateSeedFromAccount()
{
   g_state.equity          = AccountInfoDouble(ACCOUNT_EQUITY);
   g_state.balance         = AccountInfoDouble(ACCOUNT_BALANCE);
   g_state.last_balance    = g_state.balance;
   g_state.deal_pnl_accum  = 0.0;
   g_state.peak            = g_state.equity;
   g_state.initial_balance = (g_state.balance > 0.0) ? g_state.balance : g_state.equity;
   if(g_state.initial_balance <= 0.0)
      g_state.initial_balance = 1e-6;
   g_state.day_equity      = g_state.equity;
   g_state.week_equity     = g_state.equity;
   g_state.day_key         = GeDayKey(TimeTradeServer());
   g_state.week_key        = GeWeekKey(TimeTradeServer());
   g_state.day_halted      = false;
   g_state.week_halted     = false;
   g_state.lock_mult       = 1.0;
   g_state.init_sl           = 0.0;
   g_state.init_r            = 0.0;
   g_state.flatten_fail      = false;
   g_state.seeded            = true;
   g_state.last_deal_ticket  = 0;
   StateCatchUpDealCursor();
}

bool StateLoad()
{
   ZeroMemory(g_state);
   if(GeIsTester() || GeIsOptimizing())
   {
      StateSeedFromAccount();
      return true;
   }

   const string p = StateGvPrefix();
   double init = 0.0;
   if(!StateGvGet(p + "init", init) || init <= 0.0)
   {
      StateSeedFromAccount();
      StatePersistLive();
      return true;
   }

   g_state.equity          = AccountInfoDouble(ACCOUNT_EQUITY);
   g_state.balance         = AccountInfoDouble(ACCOUNT_BALANCE);
   g_state.initial_balance = init;
   StateGvGet(p + "peak",   g_state.peak);
   StateGvGet(p + "bal",    g_state.last_balance);
   StateGvGet(p + "lock",   g_state.lock_mult);
   StateGvGet(p + "dayeq",  g_state.day_equity);
   double tmp = 0.0;
   if(StateGvGet(p + "day", tmp))   g_state.day_key  = (int)tmp;
   if(StateGvGet(p + "dayh", tmp))  g_state.day_halted = (tmp != 0.0);
   StateGvGet(p + "weekeq", g_state.week_equity);
   if(StateGvGet(p + "week", tmp))  g_state.week_key = (int)tmp;
   if(StateGvGet(p + "weekh", tmp)) g_state.week_halted = (tmp != 0.0);
   StateGvGet(p + "initsl", g_state.init_sl);
   StateGvGet(p + "initr",  g_state.init_r);
   g_state.deal_pnl_accum   = 0.0;
   g_state.flatten_fail     = false;
   g_state.last_deal_ticket = 0;
   if(StateGvGet(p + "deal", tmp) && tmp > 0.0)
      g_state.last_deal_ticket = (ulong)tmp;
   if(g_state.peak <= 0.0)
      g_state.peak = g_state.equity;
   if(g_state.lock_mult <= 0.0)
      g_state.lock_mult = 1.0;
   if(g_state.last_balance <= 0.0)
      g_state.last_balance = g_state.balance;
   if(g_state.day_equity <= 0.0)
      g_state.day_equity = g_state.equity;
   if(g_state.week_equity <= 0.0)
      g_state.week_equity = g_state.equity;
   g_state.seeded = true;
   if(g_state.last_deal_ticket == 0)
      StateCatchUpDealCursor();
   return true;
}

void StateCatchUpDealCursor()
{
   const datetime now = TimeTradeServer();
   if(!HistorySelect(now - 14 * 86400, now + 60))
      return;
   const int total = HistoryDealsTotal();
   for(int i = 0; i < total; ++i)
   {
      const ulong ticket = HistoryDealGetTicket(i);
      if(ticket > g_state.last_deal_ticket)
         g_state.last_deal_ticket = ticket;
   }
}

void StateHarvestDeals()
{
   const datetime now = TimeTradeServer();
   if(!HistorySelect(now - 7 * 86400, now + 60))
      return;
   const int total = HistoryDealsTotal();
   for(int i = 0; i < total; ++i)
   {
      const ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0 || ticket <= g_state.last_deal_ticket)
         continue;
      if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic)
      {
         if(ticket > g_state.last_deal_ticket)
            g_state.last_deal_ticket = ticket;
         continue;
      }
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
      {
         if(ticket > g_state.last_deal_ticket)
            g_state.last_deal_ticket = ticket;
         continue;
      }
      const ENUM_DEAL_TYPE dtype = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(dtype == DEAL_TYPE_BUY || dtype == DEAL_TYPE_SELL)
      {
         g_state.deal_pnl_accum += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                                 + HistoryDealGetDouble(ticket, DEAL_COMMISSION)
                                 + HistoryDealGetDouble(ticket, DEAL_SWAP);
      }
      g_state.last_deal_ticket = ticket;
   }
}

void StateOnDealRealized(const ulong deal, const double profit, const double commission, const double swap)
{
   if(deal == 0 || deal <= g_state.last_deal_ticket)
      return;
   g_state.deal_pnl_accum += profit + commission + swap;
   g_state.last_deal_ticket = deal;
}

void StateSavePositionRisk(const double sl, const double r)
{
   g_state.init_sl = sl;
   g_state.init_r  = r;
   if(!GeIsTester() && !GeIsOptimizing())
   {
      const string p = StateGvPrefix();
      StateGvSet(p + "initsl", sl);
      StateGvSet(p + "initr",  r);
   }
}

void StateClearPositionRisk()
{
   g_state.init_sl = 0.0;
   g_state.init_r  = 0.0;
   if(!GeIsTester() && !GeIsOptimizing())
   {
      const string p = StateGvPrefix();
      StateGvSet(p + "initsl", 0.0);
      StateGvSet(p + "initr",  0.0);
   }
}

void StateUpdateLockMult()
{
#ifdef GOLDESEL_USE_PROFIT_LOCK
   if(GOLDESEL_USE_PROFIT_LOCK == 0)
      return;
#endif
   if(g_state.initial_balance <= 0.0)
      return;
   const double growth = (g_state.equity / g_state.initial_balance) - 1.0;
   double computed = 1.0;
   if(growth >= 1.00)
      computed = 0.50;
   else if(growth >= 0.50)
      computed = 0.70;
   if(computed < g_state.lock_mult)
      g_state.lock_mult = computed;
}

void StateOnTick()
{
   g_state.balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_state.equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   const double d_bal = g_state.balance - g_state.last_balance;
   if(MathAbs(d_bal) > kCashFlowEps)
   {
      StateHarvestDeals();
      const double realized = g_state.deal_pnl_accum;
      g_state.deal_pnl_accum = 0.0;
      double cash_delta = d_bal - realized;
      if(MathAbs(cash_delta) <= kCashFlowEps)
         cash_delta = 0.0;

      if(cash_delta != 0.0)
      {
         g_state.initial_balance = MathMax(1e-6, g_state.initial_balance + cash_delta);
         g_state.day_equity      = g_state.day_equity + cash_delta;
         g_state.week_equity     = g_state.week_equity + cash_delta;
         LogEvent("BALANCE_JUMP", SKIP_NONE, GE_DIR_NONE, 0, 0, 0, 0,
                  DoubleToString(cash_delta, 2));
      }

      if(cash_delta < 0.0)
         g_state.peak = MathMax(0.0, g_state.peak + cash_delta);
   }

   g_state.peak = MathMax(g_state.peak, g_state.equity);
   g_state.last_balance = g_state.balance;

   const datetime now = TimeTradeServer();
   const int day_key  = GeDayKey(now);
   const int week_key = GeWeekKey(now);
   if(day_key != g_state.day_key)
   {
      g_state.day_key    = day_key;
      g_state.day_equity = g_state.equity;
      g_state.day_halted = false;
   }
   if(week_key != g_state.week_key)
   {
      g_state.week_key    = week_key;
      g_state.week_equity = g_state.equity;
      g_state.week_halted = false;
   }

   if(g_state.day_equity > 0.0)
   {
      const double day_pnl_pct = 100.0 * (g_state.equity - g_state.day_equity) / g_state.day_equity;
      if(!g_state.day_halted && day_pnl_pct <= -InpDailyLossPercent)
         g_state.day_halted = true;
   }
   if(g_state.week_equity > 0.0)
   {
      const double week_pnl_pct = 100.0 * (g_state.equity - g_state.week_equity) / g_state.week_equity;
      if(!g_state.week_halted && week_pnl_pct <= -InpWeeklyLossPercent)
         g_state.week_halted = true;
   }

   StateUpdateLockMult();
   StatePersistLive();
}

#endif
