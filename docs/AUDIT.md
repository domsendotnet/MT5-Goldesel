# Goldesel implementation audit vs DESIGN.md v1.2

## Summary

The Expert Advisor matches the survival-first spec on the blow-up patterns that matter most: no martingale/grid/recovery, ticket+magic close only, `InpRiskPercent > 1.0` fails init, lot is floored never rounded up, min-lot refuse includes the 10% commission haircut, 1.25× slippage is tightness only, the hard 1% cap includes slip + haircut, OnTick flattens before the disconnected return, Friday close comes from `SymbolInfoSessionTrade` with 21:00 fallback and leftover `pos_time < friday_close` keeps flattening, filling uses FOK/IOC bits plus EXEMODE and never RETURN on Market Execution, stops are vs Bid (long) / Ask (short), there are exactly 18 inputs, daily/weekly halts latch and `lock_mult` only ratchets down, RSI is absent, `FileOpen`/`iMA` are init-only, tester flags go through `MQLInfoInteger` via `GeIsTester`/`GeIsOptimizing`, and the README carries the disclaimer, $20-will-not-trade table, and tester-GMT vs live-server clock.

Post-audit fixes (v1.0.0): requote retries re-run `GeNormalizeStops` + `RiskComputeLot` in `OnTick`; close path FOK↔IOC on `INVALID_FILL`; deal cursor persisted in GV `deal` so offline PnL is harvested on reattach; MVB cached on skip (no `OrderCalcProfit` on the cheap path); `FLATTEN_FAIL` journal throttled to 10s.

Checklist (must-verify):

| # | Check | Result |
|---|---|---|
| 1 | No martingale/grid/recovery/`lot*=` on loss | pass — sizing only in `RiskComputeLot` |
| 2 | No `PositionClose(symbol)` — ticket + magic only | pass |
| 3 | No bare `MQL_TESTER` / `MQL_OPTIMIZATION` booleans | pass |
| 4 | No `SYMBOL_FILLING_RETURN` identifier | pass |
| 5 | No `TimeDayOfWeek` | pass |
| 6 | `InpRiskPercent > 1.0` → `INIT_FAILED` | pass |
| 7 | Lot floor never round-up; min-lot refuse vs 1% with 10% haircut | pass |
| 8 | 1.25× tightness only; hard 1% includes slip + haircut | pass |
| 9 | Flatten/`ManagePosition` before disconnected early-return | pass |
| 10 | Friday session-API close, 21:00 fallback, leftover flatten | pass |
| 11 | FOK/IOC + EXEMODE; never RETURN on Market Execution | pass on open; close path incomplete (Issue 2) |
| 12 | Stops vs Bid (long) / Ask (short) | pass |
| 13 | Exactly 18 inputs | pass |
| 14 | Daily/weekly halt latched; `lock_mult` ratchet down only | pass |
| 15 | Cash-flow = Δbalance − our-magic deal PnL; StateOnTick order | pass while attached; restart hole (Issue 3) |
| 16 | README disclaimer + $20 examples + tester GMT vs live server | pass |
| 17 | Cheap tick path: no `FileOpen` on tick, no `iMA` in loops | pass (`FileOpen` in `LogInit` only; `iMA`/`iATR` in `SignalInit` only) |
| 18 | RSI absent | pass |

## Issues

### Issue 1 -- Severity: bug
- File: MQL5/Include/Goldesel/Trade.mqh:213
- Description: On `TRADE_RETCODE_REQUOTE` / `PRICE_CHANGED` / `PRICE_OFF`, `GoldeselTrade::Open` resends the original `lot`/`sl`/`tp` after `Sleep(100)` without refreshing Bid/Ask, re-running `GeNormalizeStops`, or re-running `RiskComputeLot`. DESIGN.md (retries) requires those gates on each extra send and abort if they fail. `Buy`/`Sell` is sent with price `0.0`, so the fill can move while SL stays put. On Instant-execution gold a requote that walks away from SL widens R at the same lot and can pierce `kMaxRiskPercent` (shipping S3). `Trade.mqh` is included before `Risk.mqh`, so the retry loop cannot call `RiskComputeLot` where it lives today.
- Suggestion: Hoist requote retries to `OnTick` (or otherwise call back into risk): refresh Ask/Bid, `GeNormalizeStops`, `RiskComputeLot`, abort on `SKIP_MAX_RISK` / `SKIP_SLIPPAGE_RISK` / stops-level; only then `Open` once. Keep `Open` as a single send plus the FOK↔IOC `INVALID_FILL` switch.
- Status: addressed — requote retries live in `OnTick`; `Open` is a single send plus FOK↔IOC.

### Issue 2 -- Severity: bug
- File: MQL5/Include/Goldesel/Trade.mqh:254
- Description: `CloseTicket` retries frozen/requote/price-changed/price-off only. It never switches FOK↔IOC on `TRADE_RETCODE_INVALID_FILL`. `Open` does that fallback; flatten uses `CloseAllOurPositions` → `PositionClose(ticket)` with the filling mode chosen at init. DESIGN.md K16/K20/K40: Friday flatten is the weekend-gap control and filling fallback is per-order, not once per init. On gold Market Execution, FOK close of the full volume can return `INVALID_FILL`; without an IOC retry the close fails, `flatten_fail` sticks, and the position can gap over the weekend.
- Suggestion: On close `INVALID_FILL`, reuse `SwitchFillingOnInvalid`, resend this ticket, remember the working mode. Never fall back to `ORDER_FILLING_RETURN` when `m_market_exe`. Throttle `FLATTEN_FAIL` logs (see Issue 5) so a closed market does not journal every tick.
- Status: addressed — `CloseTicket` switches FOK↔IOC on `INVALID_FILL`.

### Issue 3 -- Severity: bug
- File: MQL5/Include/Goldesel/State.mqh:154
- Description: Live `StateLoad` sets `last_deal_ticket = 0` then `StateCatchUpDealCursor()` walks history and advances the cursor to the latest deal **without** adding `DEAL_PROFIT+COMMISSION+SWAP`. `last_deal_ticket` is not a GV. First `StateOnTick` after reattach then sees `d_bal = current_balance - gv_bal` (includes our closed PnL while the EA was down) and `StateHarvestDeals` skips those tickets, so `cash_delta ≈ trade PnL`. K32 says cash-flow is `Δbalance − our-magic deal PnL` and a 2R win is not a deposit. Effect: a TP while the EA is recompiling/restarting raises `initial_balance` (profit-lock never sees the growth) and a loss is applied as a withdrawal (`day_equity`/`peak` drop with equity, daily/weekly latch and DD halt do not fire). That is the revenge-trade hole K9/K32 exist to close. While the EA stays attached, `OnTradeTransaction` plus harvest-on-balance-change is correct and the TwoRCloseIsNotDeposit order (cash-flow, then peak, then `max(peak, equity)`) holds.
- Suggestion: Persist the deal cursor (or last-deal time) next to `bal`, or on load harvest our-magic BUY/SELL deals newer than the persisted cursor and feed `StateOnDealRealized` before the first cash-flow pass. Do not skip historical tickets that are not already inside `last_balance`.
- Status: addressed — persist `GE_{magic}_{login}_deal`; reload uses that cursor and harvests newer deals. Catch-up-without-PnL only on first seed (no prior GV).

### Issue 4 -- Severity: suggestion
- File: MQL5/Include/Goldesel/Log.mqh:147
- Description: After a `SKIP_MINLOT_RISK` bar, the cheap path (`StateOnTick` + throttled `CommentUpdate` + return) still calls `RiskMoneyPerLot` → `OrderCalcProfit` once per second to paint `mvb≈`. DESIGN.md cheap-path invariant: no `CopyBuffer`, no `FileOpen`, no `OrderCalc*` unless it is a new signal bar, we are in position, or we are in the Friday flatten window. Not a sizing hole; it is extra work on the idle $20-gold path the spec wanted silent.
- Suggestion: Cache MVB on the skip event and only print the cached value from `CommentUpdate`.
- Status: addressed — `g_last_mvb` cached on `SKIP_MINLOT_RISK`; comment prints the cache.

### Issue 5 -- Severity: suggestion
- File: MQL5/Experts/Goldesel/Goldesel.mq5:314
- Description: While a flatten close fails (weekend, freeze, `INVALID_FILL`), every tick writes Journal + CSV `FLATTEN_FAIL`. Disconnected flatten is throttled to 10s (`LogFlattenBlocked`); failed send is not. DESIGN.md allows retry every tick in the window but Print is “events and errors only” with the 10s exception only for `FLATTEN_BLOCKED_DISCONNECTED`. A closed Friday book will spam the log and can stall the tester.
- Suggestion: Same 10s throttle as flatten-blocked, still retry `CloseAllOurPositions` every tick.
- Status: addressed — `LogFlattenFail()` shares the 10s throttle with flatten-blocked.
