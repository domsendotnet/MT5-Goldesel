# Contributing to Goldesel

## Rules

- Compile in MetaEditor. Do **not** commit `*.ex5` binaries.
- Do not add martingale, grid, recovery averaging, or lot multipliers after a loss — not even as optional inputs.
- Ban bare `MQL_TESTER` / `MQL_OPTIMIZATION` as booleans. Always use `GeIsTester()` / `GeIsOptimizing()`, which wrap `MQLInfoInteger(...)`. Those enums are non-zero integers; `if(MQL_TESTER)` is constantly true.
- Never `PositionClose(_Symbol)`. Close by ticket after `POSITION_MAGIC == InpMagic` and `POSITION_SYMBOL == _Symbol`.
- Never reference `SYMBOL_FILLING_RETURN`. That identifier does not exist. Use `ORDER_FILLING_RETURN` only when execution is **not** Market.
- Lot size comes only from `RiskComputeLot`. Never round volume up. Never size from leverage.
- `InpRiskPercent > 1.0` must `INIT_FAILED`.
- Prefer refuse-and-log over inventing a clever default. The spec is `docs/DESIGN.md`.
- Keep user-visible inputs at 18. Advanced knobs stay `#define`.

## Layout

```
MQL5/Experts/Goldesel/Goldesel.mq5
MQL5/Include/Goldesel/*.mqh
Sets/*.set
```

Copy those folders into a MetaTrader 5 data directory (`File → Open Data Folder`) and compile `Goldesel.mq5`.
