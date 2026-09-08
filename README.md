# Goldesel

A MetaTrader 5 Expert Advisor for **XAUUSD** (and the same code path on majors such as EURUSD). Survival-first position sizing. One simple trend-pullback setup. Not a compounding product, not an investment advisor, not a managed account.

## DISCLAIMER — READ BEFORE ANYTHING ELSE

**This software cannot be guaranteed profitable. Past backtests, forward tests, or live results do not predict future results.**

Goldesel is a piece of local trading **software**, not a financial product, not an investment advisor, not a managed account, and not a regulated offering. It places market orders according to mechanical rules. Those rules can and will lose money.

**You can lose the entire deposit**, including on a $10 account, a $20 account, and a large account. High leverage (1:500 or higher) does not create edge; it only increases how fast a wrong position consumes margin. Stops can gap. Spreads can explode. Brokers can requote, reject, or widen stops-level. Gold (XAUUSD) is especially hostile to small accounts because a 0.01 lot stop of a few dollars can be a double-digit percentage of a $10–20 balance.

- Do not deposit money you cannot afford to lose.
- Do not interpret “designed for small accounts” as “safe for small accounts.”
- Do not interpret a green Strategy Tester report as a forecast.
- The author and contributors provide **no warranty of merchantability or fitness for a particular purpose** (see `LICENSE`).

**Forbidden (will not be implemented, not even as optional inputs):** martingale, grid-without-hard-caps, recovery averaging / “add to losers,” martingale-like lot multipliers after a loss, and any always-in-the-market / no-stop pattern. Those are the usual ways small high-leverage accounts die.

The product goal is **survival-first position sizing with a simple, testable edge** — not marketing claims, and not a compounding promise.

## What it is

- One position per chart symbol, isolated by magic number.
- Higher-timeframe EMA trend (H1 21/55) + M15 pullback continuation.
- Stop = 1.5 × ATR beyond the farther of the signal-bar extreme and the fast EMA, then pushed to broker stops/freeze/spread floors vs **Bid (long) / Ask (short)**.
- Take profit = 2.0 × risk (R). Optional bundled break-even at +1.0R and chandelier trail at +1.5R.
- Lot size from **percent of equity vs the real stop in account currency**, after a 10% commission reserve, with a hard **1% of equity** cap that includes spread + slippage extra.
- **Refuses** the trade when broker min lot would exceed that cap. It will **not** “just buy 0.01.”
- Drawdown: 5% from peak → half risk; 10% → halt new entries. Daily 2% and weekly 5% loss **latches** until the next period.
- Profit-lock **ratchets down** at +50% / +100% growth from initial balance. Risk never increases after a loss.
- Friday flatten from `SymbolInfoSessionTrade` (21:00 fallback). Attempted even if the terminal is disconnected (send will fail; it logs loudly).

## What it is not

- Not a promise of passive income.
- Not a $20 → riches machine. See **Minimum viable balance** below.
- Not a multi-symbol dashboard, news bot, martingale, or grid.
- Not validated on your broker until **you** run the tester and a demo.

## Who it is for

People who accept losses, can demo-test on their own broker, and understand that a $10–20 standard gold account is usually **below** the minimum viable balance for a 0.01 lot ATR stop.

## Operational rule

**One attached Goldesel instance per account** unless you explicitly accept additive risk. On netting accounts, **one EA per symbol** — a second expert on the same symbol can reverse the net position and steal `POSITION_MAGIC`. Two charts (e.g. gold + EURUSD) is up to 2% simultaneous risk; that is not the default.

## $20 will not trade (and that is correct)

Worked examples at 1% cap with a 10% commission reserve, typical contract specs (live code uses `OrderCalcProfit` / tick fields, never these constants):

| Account | Symbol | Stop | Min lot | Money at min lot | Result |
|---|---|---|---|---|---|
| **$20** | XAUUSD | $4.00 ATR | 0.01 | **$4.00** | **`SKIP_MINLOT_RISK`** (cap allows $0.18) |
| **$20** | EURUSD | 20 pips | 0.01 | **$2.00** | **`SKIP_MINLOT_RISK`** |
| $2,000 | XAUUSD | $4.00 ATR | 0.01 step | $8.00 on 0.02 lot | Trades; `risk_pct_actual` ≈ 0.44% |

Taking 0.01 gold anyway on $20 would risk ~20% of equity on a normal stop. Goldesel refuses. Chart comment: `last=SKIP_MINLOT_RISK mvb≈444 eq=20`.

A **cent / nano-lot** account uses the same formula. There is no secret “tiny account mode” that over-risks.

## Minimum viable balance

Smallest equity at which **broker min lot** against the **current stop distance**, after the commission haircut, does not exceed 1%:

```
MVB = money_at_min_lot / 0.01 / 0.90
```

Haircut MVB at 1% cap:

| Setup | Min lot | Stop | MVB |
|---|---|---|---|
| XAUUSD, $4.00 ATR stop | 0.01 | $4.00 | **~$444** |
| XAUUSD, $8.00 ATR stop | 0.01 | $8.00 | **~$889** |
| XAUUSD, $4.00, nano 0.001 | 0.001 | $4.00 | **~$44** |
| EURUSD, 20 pips | 0.01 | 20 pips | **~$222** |
| EURUSD, 30 pips | 0.01 | 30 pips | **~$333** |

If your balance is below MVB for the current ATR stop, Goldesel will not trade. That is correct behavior. Fund a cent/nano account, use a tighter-ATR symbol (EURUSD), or add capital. Do not edit `kMaxRiskPercent` to force 0.01 lots.

Stated risk % is stop-distance after a 10% commission **reserve**, not your broker’s exact round-turn.

High leverage is **margin headroom only**. It never increases lot size.

## Install

1. Open MT5 → **File → Open Data Folder**.
2. Copy `MQL5/Experts/Goldesel/` into `MQL5/Experts/`.
3. Copy `MQL5/Include/Goldesel/` into `MQL5/Include/`.
4. Copy `Sets/*.set` into `MQL5/Presets/` (or load them from this repo).
5. Restart MetaTrader / MetaEditor. Open `MQL5/Experts/Goldesel/Goldesel.mq5` and **Compile**. Zero errors expected.
6. Attach to an **XAUUSD** chart (or the broker’s gold name: `XAUUSDm`, `GOLD`, `XAUUSD.a` — the EA uses `_Symbol`). Chart period can be anything; signals are requested on M15/H1 internally.
7. Load `Sets/Goldesel-XAUUSD-Conservative.set` (or the EURUSD set on an EURUSD chart).
8. Enable **Algo Trading**.
9. Read the Journal init dump: digits, tick size, filling mode, Friday close source, deviation **price**.

Do **not** attach live until you have compiled this full build (entries and Friday flatten ship together).

## Inputs (exactly 18)

| Group | Input | Default | Notes |
|---|---|---|---|
| Core | `InpMagic` | 20260908 | Unique per instance |
| Core | `InpRiskPercent` | 0.5 | % of equity. `OnInit` **fails** if > 1.0 |
| Strategy | `InpSignalTF` | M15 | Pullback / ATR |
| Strategy | `InpBiasTF` | H1 | EMA trend |
| Strategy | `InpFastEMA` / `InpSlowEMA` | 21 / 55 | Fast must be < slow |
| Strategy | `InpATRPeriod` | 14 | |
| Strategy | `InpSLATRMult` | 1.5 | SL distance in ATR |
| Strategy | `InpTPRMultiple` | 2.0 | Reward:risk |
| Strategy | `InpUseTrail` | true | **Bundled:** break-even at 1R **and** chandelier at 1.5R. Off = fixed SL/TP only |
| Filters | `InpUseSessions` | true | |
| Filters | `InpSessionStartHour` / `EndHour` | 7 / 20 | Inclusive start, exclusive end. Overnight wrap (`start > end`) is legal |
| Filters | `InpMaxSpreadATRFrac` | 0.15 | Skip if spread > this × ATR |
| Safety | `InpDailyLossPercent` | 2.0 | **Latched** until next server day |
| Safety | `InpWeeklyLossPercent` | 5.0 | **Latched** until next Monday |
| Safety | `InpMaxSlippagePoints` | 30 gold / 10 EURUSD | **Ticks** (`tick_size`), not `SYMBOL_POINT`. Live deviation = `max(ticks × tick, 1 × spread)` |
| Safety | `InpFridayFlatten` | true | Close our positions ~30 minutes before Friday session end |

## Session hours: tester is GMT, live is broker server

**Live:** `InpSessionStartHour` / `EndHour` are **broker server time** (`TimeTradeServer()`). Not GMT, not your PC clock.

**Strategy Tester / optimization:** MetaQuotes sets `TimeTradeServer() == TimeGMT()`. A 07:00–20:00 window in the tester is **07:00–20:00 GMT**, not a GMT+2/+3 broker. The same `.set` trades a **different cash window** live vs tester. Shift hours for the tester run if you want them to match, or accept the GMT clock.

Eligibility uses the **open time of the last closed M15 bar**, not the forming bar.

Set session hours so the chart comment `server=` lines up with London/NY for gold. Defaults (7–20) are a starting point, not a universal map.

Weekend gap is the one gold risk we refuse: Friday flatten. Monday–Thursday overnight holds are allowed.

## How to run Strategy Tester

1. View → Strategy Tester. Expert: `Goldesel`.
2. Symbol: `XAUUSD` (or broker gold name). Period: **M15**.
3. Dates: **2–3 years**.
4. Model: **1-minute OHLC** for iteration; final gold check **Every tick based on real ticks** if available. *1-minute OHLC understates intra-bar stop hunts on gold.*
5. Deposit: **2000 USD** for a meaningful gold test. Also run **$20** and confirm `SKIP_MINLOT_RISK` dominates — that is a **passing** risk test, not a bug.
6. Leverage: 1:500 (must **not** change lot).
7. Set contract / **commission** / swap to the broker’s real values. Default tester commission of 0 is a lie.
8. Load `Sets/Goldesel-XAUUSD-Conservative.set`.
9. **Session hours in the tester are GMT.**
10. Optimization is **not required and not recommended**.

EURUSD: deposit at haircut MVB (~$222+), 1-minute OHLC, EURUSD `.set`.

### Model quality caveats

- Tester spread is often a constant; live gold spread varies; the filter depends on that.
- Swaps on gold can dominate a slow trail.
- “Every tick” without real ticks interpolates; do not treat profit factor as truth.
- Slippage is not fully modeled; live `SKIP_SLIPPAGE_RISK` / `SKIP_MAX_RISK` may fire more.
- Stated risk % is SL-distance after a 10% commission reserve, not exact round-turn.

**There is no shipping Sharpe, win rate, or profit-factor target.** You must validate on your broker’s data.

## Chart comment

```
Goldesel v1.0.0  XAUUSDm  M15/H1  magic=20260908
eq=2015.40  bal=2000.00  peak=2100.00  dd=4.0%  risk=0.50%→0.25%
day=-0.4%  week=+1.2%  pos=FLAT  last=SKIP_SPREAD
server=2026.09.08 14:32  session=YES  spread=22pts  atr=8.40
```

`last=` uses the full skip token (`SKIP_MINLOT_RISK`, not a nickname). CSV trade log: `MQL5/Files/Goldesel_{magic}_{account}.csv` (terminal sandbox, not this git repo).

## Deposits, withdrawals, and “it stopped trading”

- **Banking profits** (withdrawal) adjusts peak and initial balance so the EA does **not** freeze in a fake 10% drawdown halt.
- **Deposits** raise initial balance so they do not fake a profit-lock.
- Closed trade PnL is **not** treated as a deposit (a 2R winner at 0.5% risk is ~1% of equity).
- To **re-arm 0.5% risk** after you have grown and locked down: Tools → Global Variables → delete `GE_{magic}_{login}_*`. Do **not** do this just because you withdrew.

Daily/weekly halts **stay on** after a bounce until the next day/week. That is anti-revenge, not a bug.

## Staged rollout

1. Compile. Zero errors.
2. Strategy Tester on XAUUSD and EURUSD as above. Inspect Journal for `SKIP_MINLOT_RISK`, halt codes, and `risk_pct_actual` ≤ 1.0.
3. **Demo 2–4 weeks** on the same broker (suffix, server time, min lot).
4. **Micro live** at MVB or higher, still 0.5% risk. One symbol, one instance.
5. Scale only after **you** accept the demo/live discrepancy. Raising `InpRiskPercent` is allowed up to 1.0, not above.

Rollback: disable AutoTrading or remove the EA. Open positions are **not** closed on remove (`OnDeinit` does not flatten). Use Friday flatten or close manually.

## FAQ

**Will this turn $10–20 into a large account?**  
Usually it will not even open a gold trade. See the $20 table. That refusal is the safety system working.

**I have 1:500 leverage. Why is lot still tiny?**  
Leverage is margin, not risk. Size comes from stop distance vs equity.

**Why did it stop after a bad day?**  
Daily halt latches at −2% of day-start equity until the next server day. Weekly at −5%. Drawdown ≥ 10% from peak also blocks entries until equity recovers inside 10% of peak.

**Gold symbol is `GOLD` / `XAUUSDpro`.**  
Attach to that chart. No code change.

**Can I run gold and EURUSD together?**  
Not the default. Risk adds. If you do, you accept up to ~2% simultaneous.

**News?**  
Out of v1. Pause algo around NFP/FOMC/CPI if you care.

## License

MIT. Source only in git — no `.ex5`. Spec: [`docs/DESIGN.md`](docs/DESIGN.md).
