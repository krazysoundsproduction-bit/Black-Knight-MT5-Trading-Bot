# Black Knight MT5 Trading Bot

A hardened, modular Expert Advisor for MetaTrader 5 designed for XAUUSD scalping on XM Global broker with strict risk protections and a validated signal edge.

## Status

🔧 **In Development** — v1 baseline being built with modular signal engine and improved exit logic.

## IronHide Pro v3 (Phase 2)

`IronHide_Pro_v3_MT5.mq5` now includes a Phase 2 upgrade path focused on market-structure confirmation, richer candle psychology scoring, breakout/retest validation, adaptive trade management, and setup statistics scaffolding.

### Phase 2 Highlights

- **Structure engine hardening**
  - Close-confirmed BOS checks using previous closed candle crossing logic
  - Practical internal vs external structure split (ExecutionTF internal, StructureTF external)
  - De-duplication of repeated break events
  - Break timestamps and directional structure state tracking
- **Price action / candle psychology scoring**
  - Directional scoring for engulfing, hammer/shooting-star, pin bars, doji, marubozu, inside/outside bars
  - Morning/evening-star proxies and three-soldiers/three-crows proxies
  - Long-wick rejection and expansion/contraction psychology contributions
- **Breakout/retest validation**
  - Broken support/resistance level tracking
  - Close-confirmed break then retest within configurable bars
  - Retest acceptance/rejection uses close + wick + directional confirmation
  - False-breakout/false-breakdown handling retained
- **Adaptive management**
  - Break-even trigger by configurable R progress
  - Swing-aware trailing stop with ATR fallback
  - Broker stop-distance validation for SL/TP updates
  - Optional invalidation tightening/exit behavior
- **Setup statistics scaffolding (no ML)**
  - Tracks attempts, wins, losses, net P/L, and average R proxy for:
    - support bounce
    - resistance rejection
    - bullish breakout-retest
    - bearish breakout-retest
    - false-break reversal
  - Optional periodic log output

## Features

- **Signal Edge**: EMA trend filter + RSI momentum confirmation (no blind entries)
- **Dynamic Risk**: ATR-based adaptive SL/TP and grid spacing
- **Hard Safety Caps**: Max positions, daily equity guards, margin checks (cannot be overridden)
- **Broker-Safe Execution**: Spread protection, stop-level validation, session/news gating
- **Backtest-Ready**: Parameters tuned for M1 GOLD, includes baseline presets

## Quick Start

1. Copy the latest `.mq5` file to `<MT5_DataFolder>/MQL5/Experts/`
2. Restart MT5 and attach to XAUUSD M1 chart
3. Configure inputs (see **Inputs** section below)
4. Test on demo first, then backtest before going live

### Phase 2 compile/backtest checklist

1. Open `IronHide_Pro_v3_MT5.mq5` in MetaEditor and compile with no errors
2. Confirm indicator handles initialize on target symbol/timeframe
3. Run Strategy Tester with **real ticks** and variable spread
4. Validate:
   - no-trade behavior during spread/session/news locks
   - breakout/retest path activation and expiry (`RetestMaxBars`)
   - break-even and trailing-stop modifications on open positions
   - setup-stats logs and category updates after closed trades
5. Forward-test on demo before any live usage

## Inputs

### Identification
- `Strategy_ID`: Magic number for position tracking (default: 333777)
- `Execution_Label`: Trade comment prefix (default: "BK")

### Position Management
- `Position_Mode`: BuyAndSell / BuyOnly / SellOnly
- `MaximumPositions`: Max concurrent baskets (hard-capped to 3 internally for safety)
- `Distance_Points`: Grid spacing for additional legs (deprecated; use ATR-based in v1)

### Lot Sizing
- `LotMode`: FixedLot or RiskPercent
- `Initial_Volume`: Base lot size (e.g., 0.01)
- `Risk_Percent`: % of equity per trade if RiskPercent mode

### Entry Signals
- `EMA_Fast`: Fast EMA period (default: 12)
- `EMA_Slow`: Slow EMA period (default: 50)
- `RSI_Period`: RSI lookback (default: 14)
- `RSI_BuyThreshold`: RSI level to confirm buy pullback (default: 35)
- `RSI_SellThreshold`: RSI level to confirm sell pullback (default: 65)
- `EnableHTF_Confirmation`: Use higher timeframe bias (optional)

### Exit Settings
- `TakeProfitMode`: Adaptive (ATR-based) or Fixed
- `StopLossMode`: Adaptive or Fixed
- `AdaptiveTPFactor`: ATR multiplier for TP (default: 1.5)
- `AdaptiveSLFactor`: ATR multiplier for SL (default: 2.0)
- `EmergencyBasketStop_Points`: Hard stop on total basket loss (default: 300 pts)
- `DailyTarget`: Daily profit target (0 = disabled)
- `EquityProtectionPercent`: Daily max loss as % of start equity (default: 8%)

### Trading Session
- `AllSessions`: Enable all hours or use custom schedule
- `MondayTrading` through `FridayTrading`: Day-of-week gating
- `Trading24h`: Disable time-of-day restrictions

### Safety & Filters
- `EnableSpreadProtection`: Refuse trades if spread > threshold (default: true)
- `MaxSpreadForTrading`: Max allowed spread in points (default: 50)
- `EnableATRFilter`: Block entries in abnormal volatility (default: true)
- `NewsProtection`: Pause during high-impact events (default: true)
- `MaxSlippage`: Execution deviation tolerance in points (default: 10)

## Strategy Logic

### Entry
1. Must pass all active filters (spread, ATR, session, news, etc.)
2. **Trend Filter**: EMA_Fast > EMA_Slow (buy bias) or reverse (sell bias)
3. **Momentum**: RSI crosses threshold level (e.g., RSI > 35 for buy)
4. **First Leg**: Opens at current price if all conditions met
5. **Grid Legs**: Add additional legs only if price moves ATR × GridSpacing further in direction

### Exit
- **Fixed TP/SL**: Predefined points
- **Adaptive**: ATR × Factor applied at entry, adjusted at each tick
- **Trailing Stop**: Optional, activates after reaching activation profit level
- **Emergency**: Full basket closed if cumulative loss exceeds threshold
- **Daily**: All positions closed if target profit or max loss hit

### Risk Management
- **Margin Guard**: Refuses trade if it would drop free margin below 70%
- **Max Positions**: Hard ceiling of 3 (configurable but bounded)
- **Lot Scaling**: Optional recovery/aggressive multipliers (default: flat lots)
- **Cooldown**: Optional pause after losing basket

## Backtesting Protocol

### Recommended Settings
```
Symbol: XAUUSD (XM Global)
Timeframe: M1
Period: 2+ years (include 2023 high volatility + 2024-2025)
Tick Data: Real ticks (highest accuracy)
Spread: Variable (real broker spread, not fixed)
Slippage: 3–10 points (MT5 realistic)
Commission: 0.10 USD per million (XM typical)
```

### Walk-Forward Validation
1. Optimize on first 12 months
2. Validate on next 6 months (no re-fit)
3. Repeat: retrain on newest 12 months, validate on next 6 months
4. Judge by **stability** of monthly returns, not peak equity

### Success Criteria
- Profit Factor > 1.2 (net profit / sum of losses)
- Max Drawdown < 15%
- Consistent positive months (>60% of months profitable)
- Slippage impact < 5% of average trade P&L

## Files

- `SafeLotGuardian_v2_MT5.mq5` — Legacy version (weak entry signal, kept for reference)
- `BlackKnight_v1_MT5.mq5` — **New baseline** (modular signal + improved exits)
- `IronHide_Pro_v3_MT5.mq5` — IronHide Pro architecture with Phase 2 upgrades
- `README.md` — This file

## Phase 2 limitations

- Internal structure classification is a practical proxy inside one EA file (not a full multi-module market map).
- Setup statistics rely on trade transaction/history approximations and should be validated in live terminal context.
- MT5 broker execution rules (stops/freeze/filled price) can alter final SL/TP placement.
- No profitability or trade-frequency guarantees are made.

## Broker Configuration

### XM Global XAUUSD (Spot)
- Minimum lot: 0.01
- Lot step: 0.01
- Stops level: ~30 pips
- Slippage: 2–15 pips typical during liquid hours
- Spread: 0.25–0.50 typical during London/NY, wider during Asia
- Commission: ~0.10 USD per 1M notional (variable by account type)

## Risk Disclaimer

⚠️ **This EA is experimental software. Past backtests do not guarantee live results.**

- Use a **demo account first** (2–4 weeks minimum)
- **Start small** on live (cent account or 1–5% of trading capital)
- **VPS uptime** is critical; terminal disconnects will halt trading
- **Monitor regularly**; no EA is 100% autonomous
- **Leverage amplifies losses**; use position sizing to match your risk tolerance

## Development Roadmap

- [ ] v1.0: Modular signal + ATR exits + safety hardening (in progress)
- [ ] v1.1: Higher-timeframe confirmation module
- [ ] v1.2: Equity curve filter (pause on consecutive losses)
- [ ] v1.3: Multi-symbol capability (EURUSD, GBPUSD, etc.)
- [ ] v2.0: Machine-learning regime detector (optional premium add-on)

## Support & Feedback

For bugs, suggestions, or live trade reports, open an Issue.

---

**Last Updated**: 2026-07-10  
**Author**: krazysoundsproduction-bit  
**License**: Private (use at own risk)
