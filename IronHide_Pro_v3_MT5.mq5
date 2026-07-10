//+------------------------------------------------------------------+
//|                               IronHide_Pro_v3_MT5.mq5            |
//|   Intelligent Market Structure & Price Action EA - Phase 1       |
//|   Architecture-first implementation aligned to user specification |
//+------------------------------------------------------------------+
#property copyright "krazysoundsproduction-bit"
#property version   "3.10"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//=================== ENUMS ===================
enum ePositionMode { PM_BuyAndSell, PM_BuyOnly, PM_SellOnly };
enum eMarketRegime {
   MR_StrongBullish,
   MR_Bullish,
   MR_WeakBullish,
   MR_Sideways,
   MR_WeakBearish,
   MR_Bearish,
   MR_StrongBearish
};
enum eZoneType { ZT_Support, ZT_Resistance };
enum eZoneStrength { ZS_Weak, ZS_Medium, ZS_Strong, ZS_Institutional };
enum eObservationState {
   OBS_None,
   OBS_AtSupport,
   OBS_AtResistance,
   OBS_WaitBreakRetestSupport,
   OBS_WaitBreakRetestResistance
};

//=================== INPUTS ===================
input group "=== Identification ==="
input long            Strategy_ID                 = 903300;
input string          Execution_Label             = "IronHidePro";
input ePositionMode   Position_Mode               = PM_BuyAndSell;

input group "=== Core Timeframes ==="
input ENUM_TIMEFRAMES StructureTF                 = PERIOD_M5;
input ENUM_TIMEFRAMES ExecutionTF                 = PERIOD_M1;
input ENUM_TIMEFRAMES ContextTF                   = PERIOD_M15;

input group "=== Structure & Swings ==="
input int             SwingLeftBars               = 3;
input int             SwingRightBars              = 3;
input int             MaxStoredSwings             = 200;

input group "=== Zones ==="
input int             MaxZones                    = 60;
input int             ZoneATRPaddingPoints        = 20;
input int             ZoneTouchLookbackBars       = 300;
input int             ZoneInvalidationBufferPts   = 25;

input group "=== Observation Mode ==="
input int             ObservationBarsMin          = 2;
input int             ObservationBarsMax          = 10;
input bool            RequireRetestAfterBreak     = true;

input group "=== Price Action ==="
input bool            EnableEngulfing             = true;
input bool            EnablePinBars               = true;
input bool            EnableInsideOutside         = true;

input group "=== Probability Engine ==="
input int             WeightStructure             = 15;
input int             WeightZone                  = 15;
input int             WeightSupplyDemandProxy     = 15;
input int             WeightPriceAction           = 15;
input int             WeightLiquidity             = 10;
input int             WeightVolumeProxy           = 10;
input int             WeightMomentum              = 10;
input int             WeightVolatility            = 5;
input int             WeightRisk                  = 5;
input int             WeightContext               = 10;
input int             MinProbabilityToTrade       = 85;

input group "=== Risk Management ==="
input bool            UseRiskPercent              = true;
input double          RiskPercent                 = 0.5;
input double          FixedLot                    = 0.01;
input int             MaxOpenTrades               = 1;
input double          MaxDailyLossPercent         = 3.0;
input double          MaxDrawdownPercent          = 12.0;
input int             MaxConsecutiveLosses        = 3;
input bool            EmergencyShutdownEnabled    = true;
input double          EmergencyMinMarginLevel     = 120.0;

input group "=== Execution Filters ==="
input bool            EnableSpreadProtection      = true;
input int             MaxSpreadPoints             = 45;
input bool            NewsProtection              = true;
input int             NewsPauseBefore_m           = 60;
input int             NewsPauseAfter_m            = 60;
input bool            USDEventFilter              = true;
input bool            EUREventFilter              = true;

input group "=== Sessions ==="
input bool            Trading24h                  = false;
input bool            MondayTrading               = true;
input string          MondaySessionStart          = "08:00";
input string          MondaySessionEnd            = "20:00";
input bool            TuesdayTrading              = true;
input string          TuesdaySessionStart         = "08:00";
input string          TuesdaySessionEnd           = "20:00";
input bool            WednesdayTrading            = true;
input string          WednesdaySessionStart       = "08:00";
input string          WednesdaySessionEnd         = "20:00";
input bool            ThursdayTrading             = true;
input string          ThursdaySessionStart        = "08:00";
input string          ThursdaySessionEnd          = "20:00";
input bool            FridayTrading               = true;
input string          FridaySessionStart          = "08:00";
input string          FridaySessionEnd            = "18:00";

//=================== DATA STRUCTURES ===================
struct SwingPoint
{
   datetime t;
   double   price;
   bool     isHigh;
   bool     isMajor;
};

struct Zone
{
   eZoneType      type;
   eZoneStrength  strength;
   double         low;
   double         high;
   int            touches;
   int            reactionScore;
   int            volumeScore;
   int            timeScore;
   int            relevanceScore;
   bool           active;
   datetime       createdAt;
   datetime       lastTouchedAt;
};

struct MarketState
{
   eMarketRegime regime;
   bool          bosBull;
   bool          bosBear;
   bool          chochBull;
   bool          chochBear;
   double        buyerStrength;   // 0..100
   double        sellerStrength;  // 0..100
   double        momentumScore;   // 0..100
   double        volatilityScore; // 0..100
   int           contextScore;    // 0..10
   int           liquidityScore;  // 0..10
};

struct SignalState
{
   bool bullishPA;
   bool bearishPA;
   bool falseBreakout;
   bool falseBreakdown;
   bool supportHolding;
   bool resistanceHolding;
   bool breakoutRetestBull;
   bool breakoutRetestBear;
};

struct ProbabilityBreakdown
{
   int structure;
   int zone;
   int supplyDemand;
   int priceAction;
   int liquidity;
   int volume;
   int momentum;
   int volatility;
   int risk;
   int context;
   int total;
};

//=================== GLOBALS ===================
SwingPoint swings[];
Zone       zones[];
MarketState market;
SignalState signal;
ProbabilityBreakdown pb;

eObservationState observationState = OBS_None;
int observationBars = 0;
datetime observationStart = 0;
datetime lastProcessedBar = 0;

double dayStartEquity = 0.0;
double peakEquity = 0.0;
int consecutiveLosses = 0;
bool dailyLock = false;

int atrHandle = INVALID_HANDLE;
int rsiHandle = INVALID_HANDLE;
int volHandle = INVALID_HANDLE;

//=================== HELPERS ===================
int TimeStrToMinutes(string hhmm)
{
   string p[];
   StringSplit(hhmm, ':', p);
   if(ArraySize(p) < 2) return 0;
   return (int)StringToInteger(p[0]) * 60 + (int)StringToInteger(p[1]);
}

bool IsWithinTradingSession()
{
   if(Trading24h) return true;

   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);

   bool dayOn = false;
   string startStr = "08:00", endStr = "18:00";

   switch(t.day_of_week)
   {
      case 1: dayOn = MondayTrading;    startStr = MondaySessionStart;    endStr = MondaySessionEnd;    break;
      case 2: dayOn = TuesdayTrading;   startStr = TuesdaySessionStart;   endStr = TuesdaySessionEnd;   break;
      case 3: dayOn = WednesdayTrading; startStr = WednesdaySessionStart; endStr = WednesdaySessionEnd; break;
      case 4: dayOn = ThursdayTrading;  startStr = ThursdaySessionStart;  endStr = ThursdaySessionEnd;  break;
      case 5: dayOn = FridayTrading;    startStr = FridaySessionStart;    endStr = FridaySessionEnd;    break;
      default: return false;
   }

   if(!dayOn) return false;

   int curMin = t.hour * 60 + t.min;
   int st = TimeStrToMinutes(startStr);
   int en = TimeStrToMinutes(endStr);
   return (curMin >= st && curMin <= en);
}

bool IsInNewsBlackout()
{
   if(!NewsProtection) return false;

   datetime from = TimeCurrent() - NewsPauseBefore_m * 60 - 3600;
   datetime to   = TimeCurrent() + NewsPauseAfter_m  * 60 + 3600;

   string currencies[];
   int n = 0;
   if(USDEventFilter) { ArrayResize(currencies, n+1); currencies[n]="USD"; n++; }
   if(EUREventFilter) { ArrayResize(currencies, n+1); currencies[n]="EUR"; n++; }
   if(n == 0) return false;

   for(int c = 0; c < n; c++)
   {
      MqlCalendarValue vals[];
      if(CalendarValueHistory(vals, from, to, NULL, currencies[c]) <= 0) continue;

      for(int i = 0; i < ArraySize(vals); i++)
      {
         MqlCalendarEvent ev;
         if(!CalendarEventById(vals[i].event_id, ev)) continue;
         if(ev.importance < CALENDAR_IMPORTANCE_HIGH) continue;

         datetime evT = vals[i].time;
         if(TimeCurrent() >= evT - NewsPauseBefore_m * 60 && TimeCurrent() <= evT + NewsPauseAfter_m * 60)
            return true;
      }
   }
   return false;
}

bool PassSpreadFilter()
{
   if(!EnableSpreadProtection) return true;
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spread <= MaxSpreadPoints);
}

double GetATR()
{
   double a[1];
   if(CopyBuffer(atrHandle, 0, 0, 1, a) < 1) return 0.0;
   return a[0];
}

//=================== ENGINE: SWING DETECTION ===================
void UpdateSwings()
{
   int bars = Bars(_Symbol, StructureTF);
   if(bars < SwingLeftBars + SwingRightBars + 20) return;

   // scan only recent window for phase 1 stability/performance
   int start = MathMin(500, bars - SwingRightBars - 1);

   for(int i = start; i >= SwingRightBars; i--)
   {
      double hi = iHigh(_Symbol, StructureTF, i);
      double lo = iLow(_Symbol, StructureTF, i);
      bool isSwingHigh = true;
      bool isSwingLow  = true;

      for(int l = 1; l <= SwingLeftBars; l++)
      {
         if(iHigh(_Symbol, StructureTF, i + l) >= hi) isSwingHigh = false;
         if(iLow(_Symbol, StructureTF, i + l) <= lo)  isSwingLow  = false;
      }
      for(int r = 1; r <= SwingRightBars; r++)
      {
         if(iHigh(_Symbol, StructureTF, i - r) > hi) isSwingHigh = false;
         if(iLow(_Symbol, StructureTF, i - r) < lo)  isSwingLow  = false;
      }

      if(isSwingHigh || isSwingLow)
      {
         datetime t = iTime(_Symbol, StructureTF, i);
         bool exists = false;
         for(int k = 0; k < ArraySize(swings); k++)
         {
            if(swings[k].t == t && swings[k].isHigh == isSwingHigh) { exists = true; break; }
         }
         if(!exists)
         {
            SwingPoint sp;
            sp.t = t;
            sp.price = isSwingHigh ? hi : lo;
            sp.isHigh = isSwingHigh;
            sp.isMajor = true;
            int sz = ArraySize(swings);
            ArrayResize(swings, sz + 1);
            swings[sz] = sp;

            if(ArraySize(swings) > MaxStoredSwings)
            {
               // drop oldest
               for(int m = 1; m < ArraySize(swings); m++) swings[m-1] = swings[m];
               ArrayResize(swings, ArraySize(swings)-1);
            }
         }
      }
   }
}

//=================== ENGINE: MARKET STRUCTURE ===================
void UpdateMarketStructure()
{
   // derive HH/HL/LH/LL proxy from last 4 relevant swings
   double lastHigh = 0, prevHigh = 0, lastLow = 0, prevLow = 0;
   int hcount = 0, lcount = 0;

   for(int i = ArraySize(swings) - 1; i >= 0; i--)
   {
      if(swings[i].isHigh && hcount < 2)
      {
         if(hcount == 0) lastHigh = swings[i].price;
         else prevHigh = swings[i].price;
         hcount++;
      }
      if(!swings[i].isHigh && lcount < 2)
      {
         if(lcount == 0) lastLow = swings[i].price;
         else prevLow = swings[i].price;
         lcount++;
      }
      if(hcount >= 2 && lcount >= 2) break;
   }

   bool hh = (hcount >= 2 && lastHigh > prevHigh);
   bool hl = (lcount >= 2 && lastLow > prevLow);
   bool lh = (hcount >= 2 && lastHigh < prevHigh);
   bool ll = (lcount >= 2 && lastLow < prevLow);

   // BOS/CHOCH proxy with closes relative to previous swings
   double close0 = iClose(_Symbol, StructureTF, 1);
   market.bosBull = (hcount >= 2 && close0 > prevHigh);
   market.bosBear = (lcount >= 2 && close0 < prevLow);

   // CHOCH simplistic phase-1 approximation
   market.chochBull = (lh && market.bosBull);
   market.chochBear = (hl && market.bosBear);

   // Regime classification
   if(hh && hl)
   {
      if(market.bosBull) market.regime = MR_StrongBullish;
      else market.regime = MR_Bullish;
   }
   else if(hh || hl)
      market.regime = MR_WeakBullish;
   else if(lh && ll)
   {
      if(market.bosBear) market.regime = MR_StrongBearish;
      else market.regime = MR_Bearish;
   }
   else if(lh || ll)
      market.regime = MR_WeakBearish;
   else
      market.regime = MR_Sideways;
}

//=================== ENGINE: ZONES (S/R + SupplyDemand proxy) ===================
void RebuildZonesFromSwings()
{
   ArrayResize(zones, 0);
   double atr = GetATR();
   double pad = (atr > 0 ? atr : ZoneATRPaddingPoints * _Point);

   for(int i = 0; i < ArraySize(swings); i++)
   {
      Zone z;
      z.type = swings[i].isHigh ? ZT_Resistance : ZT_Support;
      z.low = swings[i].price - pad;
      z.high = swings[i].price + pad;
      z.touches = 0;
      z.reactionScore = 0;
      z.volumeScore = 0;
      z.timeScore = 0;
      z.relevanceScore = 0;
      z.active = true;
      z.createdAt = swings[i].t;
      z.lastTouchedAt = 0;

      // touch/reaction scoring in lookback
      int lb = MathMin(ZoneTouchLookbackBars, Bars(_Symbol, StructureTF)-2);
      for(int b = 1; b <= lb; b++)
      {
         double h = iHigh(_Symbol, StructureTF, b);
         double l = iLow(_Symbol, StructureTF, b);
         double c = iClose(_Symbol, StructureTF, b);
         double o = iOpen(_Symbol, StructureTF, b);

         bool touch = (h >= z.low && l <= z.high);
         if(touch)
         {
            z.touches++;
            z.lastTouchedAt = iTime(_Symbol, StructureTF, b);

            // reaction proxy: strong rejection candle away from zone
            double body = MathAbs(c - o);
            double range = h - l;
            if(range > 0 && body / range > 0.5) z.reactionScore += 2;
            else z.reactionScore += 1;
         }
      }

      z.volumeScore = 2; // tick-volume proxy placeholder for phase 1
      z.timeScore = (int)MathMin(10, z.touches);
      z.relevanceScore = (int)MathMin(10, z.reactionScore);

      int total = z.touches + z.reactionScore + z.volumeScore + z.timeScore + z.relevanceScore;
      if(total >= 28) z.strength = ZS_Institutional;
      else if(total >= 20) z.strength = ZS_Strong;
      else if(total >= 12) z.strength = ZS_Medium;
      else z.strength = ZS_Weak;

      int sz = ArraySize(zones);
      if(sz < MaxZones)
      {
         ArrayResize(zones, sz + 1);
         zones[sz] = z;
      }
   }
}

//=================== ENGINE: PRICE ACTION ===================
void UpdatePriceActionSignals()
{
   signal.bullishPA = false;
   signal.bearishPA = false;
   signal.falseBreakout = false;
   signal.falseBreakdown = false;

   double o1 = iOpen(_Symbol, ExecutionTF, 1);
   double c1 = iClose(_Symbol, ExecutionTF, 1);
   double h1 = iHigh(_Symbol, ExecutionTF, 1);
   double l1 = iLow(_Symbol, ExecutionTF, 1);

   double o2 = iOpen(_Symbol, ExecutionTF, 2);
   double c2 = iClose(_Symbol, ExecutionTF, 2);
   double h2 = iHigh(_Symbol, ExecutionTF, 2);
   double l2 = iLow(_Symbol, ExecutionTF, 2);

   // engulfing
   if(EnableEngulfing)
   {
      bool bullEng = (c2 < o2 && c1 > o1 && c1 >= o2 && o1 <= c2);
      bool bearEng = (c2 > o2 && c1 < o1 && c1 <= o2 && o1 >= c2);
      if(bullEng) signal.bullishPA = true;
      if(bearEng) signal.bearishPA = true;
   }

   // pin bar proxy
   if(EnablePinBars)
   {
      double range1 = h1 - l1;
      if(range1 > 0)
      {
         double body1 = MathAbs(c1 - o1);
         double upperW = h1 - MathMax(c1, o1);
         double lowerW = MathMin(c1, o1) - l1;

         bool bullPin = (lowerW > body1 * 1.8 && upperW < body1);
         bool bearPin = (upperW > body1 * 1.8 && lowerW < body1);
         if(bullPin) signal.bullishPA = true;
         if(bearPin) signal.bearishPA = true;
      }
   }

   // inside / outside bars (contribute lightly)
   if(EnableInsideOutside)
   {
      bool inside = (h1 < h2 && l1 > l2);
      bool outside = (h1 > h2 && l1 < l2);
      if(inside)
      {
         // neutral compression -> no direct side signal
      }
      if(outside)
      {
         if(c1 > o1) signal.bullishPA = true;
         if(c1 < o1) signal.bearishPA = true;
      }
   }
}

//=================== ENGINE: LIQUIDITY & FALSE BREAK ===================
void UpdateLiquiditySignals()
{
   market.liquidityScore = 0;

   // equal highs/lows + sweep proxy on recent bars
   double recentHigh = -DBL_MAX;
   double recentLow = DBL_MAX;
   for(int i = 2; i <= 20; i++)
   {
      recentHigh = MathMax(recentHigh, iHigh(_Symbol, ExecutionTF, i));
      recentLow = MathMin(recentLow, iLow(_Symbol, ExecutionTF, i));
   }

   double h1 = iHigh(_Symbol, ExecutionTF, 1);
   double l1 = iLow(_Symbol, ExecutionTF, 1);
   double c1 = iClose(_Symbol, ExecutionTF, 1);

   // false breakout: breaks above then closes back below recentHigh
   if(h1 > recentHigh && c1 < recentHigh) { signal.falseBreakout = true; market.liquidityScore += 5; }
   // false breakdown: breaks below then closes back above recentLow
   if(l1 < recentLow && c1 > recentLow) { signal.falseBreakdown = true; market.liquidityScore += 5; }

   // baseline liquidity context
   if(market.liquidityScore == 0) market.liquidityScore = 3;
}

//=================== ENGINE: MOMENTUM / VOLATILITY / BUYER-SELLER ===================
void UpdateFlowEngines()
{
   // Momentum via RSI + candle expansion
   double r[2];
   if(CopyBuffer(rsiHandle, 0, 0, 2, r) >= 2)
   {
      if(r[0] > 55) market.momentumScore = 70;
      else if(r[0] < 45) market.momentumScore = 30;
      else market.momentumScore = 50;
   }
   else market.momentumScore = 50;

   double range1 = iHigh(_Symbol, ExecutionTF, 1) - iLow(_Symbol, ExecutionTF, 1);
   double rangeAvg = 0.0;
   for(int i = 2; i <= 20; i++)
      rangeAvg += (iHigh(_Symbol, ExecutionTF, i) - iLow(_Symbol, ExecutionTF, i));
   rangeAvg /= 19.0;

   if(rangeAvg > 0)
   {
      double ratio = range1 / rangeAvg;
      if(ratio < 0.7) market.volatilityScore = 30;
      else if(ratio > 1.6) market.volatilityScore = 80;
      else market.volatilityScore = 55;
   }
   else market.volatilityScore = 50;

   // buyer/seller proxy from close location and wick pressure
   double o1 = iOpen(_Symbol, ExecutionTF, 1);
   double c1 = iClose(_Symbol, ExecutionTF, 1);
   double h1 = iHigh(_Symbol, ExecutionTF, 1);
   double l1 = iLow(_Symbol, ExecutionTF, 1);

   double upperW = h1 - MathMax(c1, o1);
   double lowerW = MathMin(c1, o1) - l1;

   double bull = 50, bear = 50;
   if(c1 > o1) { bull += 15; bear -= 10; }
   if(c1 < o1) { bear += 15; bull -= 10; }
   if(lowerW > upperW * 1.2) bull += 10;
   if(upperW > lowerW * 1.2) bear += 10;

   market.buyerStrength = MathMax(0, MathMin(100, bull));
   market.sellerStrength = MathMax(0, MathMin(100, bear));

   // context score 0..10 from regime
   switch(market.regime)
   {
      case MR_StrongBullish: market.contextScore = 9; break;
      case MR_Bullish:       market.contextScore = 8; break;
      case MR_WeakBullish:   market.contextScore = 6; break;
      case MR_Sideways:      market.contextScore = 4; break;
      case MR_WeakBearish:   market.contextScore = 6; break;
      case MR_Bearish:       market.contextScore = 8; break;
      case MR_StrongBearish: market.contextScore = 9; break;
   }
}

//=================== ENGINE: OBSERVATION MODE ===================
bool PriceInZone(int &zoneIndex)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   zoneIndex = -1;

   for(int i = 0; i < ArraySize(zones); i++)
   {
      if(!zones[i].active) continue;
      if(bid >= zones[i].low && bid <= zones[i].high)
      {
         zoneIndex = i;
         return true;
      }
   }
   return false;
}

void UpdateObservationMode()
{
   int zi = -1;
   bool inZone = PriceInZone(zi);

   if(!inZone)
   {
      if(observationState != OBS_None)
      {
         if(observationBars > ObservationBarsMax)
            observationState = OBS_None;
      }
      return;
   }

   if(observationState == OBS_None)
   {
      observationStart = TimeCurrent();
      observationBars = 0;
      if(zones[zi].type == ZT_Support) observationState = OBS_AtSupport;
      else observationState = OBS_AtResistance;
   }

   observationBars++;

   // support/resistance hold logic (phase 1 proxy)
   double c1 = iClose(_Symbol, ExecutionTF, 1);
   signal.supportHolding = false;
   signal.resistanceHolding = false;
   signal.breakoutRetestBull = false;
   signal.breakoutRetestBear = false;

   if(zones[zi].type == ZT_Support)
   {
      if(c1 >= zones[zi].low) signal.supportHolding = true;
      // support break
      if(c1 < zones[zi].low - ZoneInvalidationBufferPts * _Point)
         observationState = OBS_WaitBreakRetestSupport;
   }
   else
   {
      if(c1 <= zones[zi].high) signal.resistanceHolding = true;
      // resistance break
      if(c1 > zones[zi].high + ZoneInvalidationBufferPts * _Point)
         observationState = OBS_WaitBreakRetestResistance;
   }

   // Retest logic
   if(RequireRetestAfterBreak)
   {
      double h1 = iHigh(_Symbol, ExecutionTF, 1);
      double l1 = iLow(_Symbol, ExecutionTF, 1);

      if(observationState == OBS_WaitBreakRetestSupport)
      {
         // old support becomes resistance; retest from below + bearish PA
         if(h1 >= zones[zi].low && c1 < zones[zi].low && signal.bearishPA)
            signal.breakoutRetestBear = true;
      }
      if(observationState == OBS_WaitBreakRetestResistance)
      {
         // old resistance becomes support; retest from above + bullish PA
         if(l1 <= zones[zi].high && c1 > zones[zi].high && signal.bullishPA)
            signal.breakoutRetestBull = true;
      }
   }
}

//=================== ENGINE: RISK ===================
bool PassRiskGuards()
{
   if(dailyLock) return false;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   peakEquity = MathMax(peakEquity, equity);

   // daily loss lock
   double dayPnL = equity - dayStartEquity;
   if(dayStartEquity > 0)
   {
      double dayLossPct = -(dayPnL / dayStartEquity) * 100.0;
      if(dayLossPct >= MaxDailyLossPercent)
      {
         dailyLock = true;
         return false;
      }
   }

   // absolute drawdown lock
   if(peakEquity > 0)
   {
      double ddPct = ((peakEquity - equity) / peakEquity) * 100.0;
      if(ddPct >= MaxDrawdownPercent)
      {
         dailyLock = true;
         return false;
      }
   }

   // emergency margin lock
   if(EmergencyShutdownEnabled)
   {
      double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      if(ml > 0 && ml < EmergencyMinMarginLevel)
      {
         dailyLock = true;
         return false;
      }
   }

   // open trades cap
   int openCnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Strategy_ID) continue;
      openCnt++;
   }
   if(openCnt >= MaxOpenTrades) return false;

   if(consecutiveLosses >= MaxConsecutiveLosses) return false;

   return true;
}

//=================== ENGINE: PROBABILITY ===================
int ClampToWeight(int score0to100, int weight)
{
   int s = (int)MathRound((double)score0to100 / 100.0 * weight);
   if(s < 0) s = 0;
   if(s > weight) s = weight;
   return s;
}

void ComputeProbability(bool isBuy)
{
   // structure score
   int structureRaw = 50;
   if(isBuy)
   {
      if(market.regime == MR_StrongBullish || market.regime == MR_Bullish) structureRaw = 90;
      else if(market.regime == MR_WeakBullish) structureRaw = 70;
      else if(market.regime == MR_Sideways) structureRaw = 45;
      else structureRaw = 20;
   }
   else
   {
      if(market.regime == MR_StrongBearish || market.regime == MR_Bearish) structureRaw = 90;
      else if(market.regime == MR_WeakBearish) structureRaw = 70;
      else if(market.regime == MR_Sideways) structureRaw = 45;
      else structureRaw = 20;
   }

   // zone score
   int zoneRaw = 40;
   int zi=-1;
   if(PriceInZone(zi))
   {
      if(zi >= 0)
      {
         int zbase = 30;
         if(zones[zi].strength == ZS_Medium) zbase = 55;
         if(zones[zi].strength == ZS_Strong) zbase = 75;
         if(zones[zi].strength == ZS_Institutional) zbase = 90;

         if(isBuy && zones[zi].type == ZT_Support) zoneRaw = zbase;
         else if(!isBuy && zones[zi].type == ZT_Resistance) zoneRaw = zbase;
         else zoneRaw = 20;
      }
   }

   // supply/demand proxy from zone type+strength
   int sdRaw = zoneRaw;

   // price action
   int paRaw = 25;
   if(isBuy && signal.bullishPA) paRaw = 85;
   if(!isBuy && signal.bearishPA) paRaw = 85;

   // liquidity
   int liqRaw = market.liquidityScore * 10;
   if(isBuy && signal.falseBreakdown) liqRaw = 85;
   if(!isBuy && signal.falseBreakout) liqRaw = 85;

   // volume proxy
   int volRaw = 60; // phase 1 placeholder

   // momentum
   int momRaw = (int)(isBuy ? market.momentumScore : (100.0 - market.momentumScore));

   // volatility
   int volaRaw = (int)market.volatilityScore;

   // risk
   int riskRaw = PassRiskGuards() ? 90 : 0;

   // context
   int ctxRaw = market.contextScore * 10;

   pb.structure   = ClampToWeight(structureRaw, WeightStructure);
   pb.zone        = ClampToWeight(zoneRaw, WeightZone);
   pb.supplyDemand= ClampToWeight(sdRaw, WeightSupplyDemandProxy);
   pb.priceAction = ClampToWeight(paRaw, WeightPriceAction);
   pb.liquidity   = ClampToWeight(liqRaw, WeightLiquidity);
   pb.volume      = ClampToWeight(volRaw, WeightVolumeProxy);
   pb.momentum    = ClampToWeight(momRaw, WeightMomentum);
   pb.volatility  = ClampToWeight(volaRaw, WeightVolatility);
   pb.risk        = ClampToWeight(riskRaw, WeightRisk);
   pb.context     = ClampToWeight(ctxRaw, WeightContext);

   pb.total = pb.structure + pb.zone + pb.supplyDemand + pb.priceAction + pb.liquidity
            + pb.volume + pb.momentum + pb.volatility + pb.risk + pb.context;
}

//=================== EXECUTION ===================
double ComputeLotByRisk(double slDistancePoints)
{
   if(!UseRiskPercent || RiskPercent <= 0) return FixedLot;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * (RiskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickValue <= 0 || slDistancePoints <= 0) return FixedLot;

   double lot = riskMoney / (slDistancePoints * tickValue);

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;

   lot = MathRound(lot / step) * step;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   return lot;
}

bool PlaceTrade(bool isBuy)
{
   if(!PassRiskGuards()) return false;

   // final direction permission
   if(isBuy && !(Position_Mode == PM_BuyAndSell || Position_Mode == PM_BuyOnly)) return false;
   if(!isBuy && !(Position_Mode == PM_BuyAndSell || Position_Mode == PM_SellOnly)) return false;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = isBuy ? ask : bid;

   // dynamic SL/TP from zones + ATR buffer
   double atr = GetATR();
   if(atr <= 0) atr = 100 * _Point;

   double sl = 0, tp = 0;

   // locate nearest opposite protective level from swings
   double nearestSwingLow = DBL_MAX;
   double nearestSwingHigh = -DBL_MAX;
   for(int i = ArraySize(swings)-1; i >= 0; i--)
   {
      if(!swings[i].isHigh && swings[i].price < price)
         nearestSwingLow = MathMin(nearestSwingLow, swings[i].price);
      if(swings[i].isHigh && swings[i].price > price)
         nearestSwingHigh = MathMax(nearestSwingHigh, swings[i].price);
   }

   if(isBuy)
   {
      if(nearestSwingLow < DBL_MAX) sl = nearestSwingLow - atr*0.6;
      else sl = price - atr*1.2;
      if(nearestSwingHigh > -DBL_MAX) tp = nearestSwingHigh;
      else tp = price + atr*2.0;
   }
   else
   {
      if(nearestSwingHigh > -DBL_MAX) sl = nearestSwingHigh + atr*0.6;
      else sl = price + atr*1.2;
      if(nearestSwingLow < DBL_MAX) tp = nearestSwingLow;
      else tp = price - atr*2.0;
   }

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   double slPts = MathAbs(price - sl) / _Point;
   double lot = ComputeLotByRisk(slPts);

   trade.SetExpertMagicNumber(Strategy_ID);
   bool ok = false;
   string cmt = Execution_Label + "_" + IntegerToString((int)Strategy_ID);

   if(isBuy) ok = trade.Buy(lot, _Symbol, price, sl, tp, cmt);
   else ok = trade.Sell(lot, _Symbol, price, sl, tp, cmt);

   if(!ok)
      PrintFormat("IronHidePro order failed. Retcode=%d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());

   return ok;
}

//=================== DECISION PIPELINE ===================
void RunDecisionPipeline()
{
   // 1. Structure
   UpdateSwings();
   UpdateMarketStructure();

   // 2. Context, flow
   UpdateFlowEngines();

   // 3. Zones / S-D proxy
   RebuildZonesFromSwings();

   // 4. Observation mode
   UpdatePriceActionSignals();
   UpdateLiquiditySignals();
   UpdateObservationMode();

   // 5..11: Probability and risk validation for each side
   bool buyCandidate = false;
   bool sellCandidate = false;

   // buy logic from observation outcomes
   if(observationState == OBS_AtSupport && signal.supportHolding && signal.bullishPA)
      buyCandidate = true;
   if(observationState == OBS_WaitBreakRetestResistance && signal.breakoutRetestBull)
      buyCandidate = true;

   // sell logic from observation outcomes
   if(observationState == OBS_AtResistance && signal.resistanceHolding && signal.bearishPA)
      sellCandidate = true;
   if(observationState == OBS_WaitBreakRetestSupport && signal.breakoutRetestBear)
      sellCandidate = true;

   // Never trade on single signal: require aligned independent factors
   if(buyCandidate)
   {
      int independent = 0;
      if(signal.bullishPA) independent++;
      if(market.buyerStrength > market.sellerStrength) independent++;
      if(market.regime == MR_Bullish || market.regime == MR_StrongBullish || market.regime == MR_WeakBullish) independent++;
      if(market.liquidityScore >= 4) independent++;
      if(independent >= 3)
      {
         ComputeProbability(true);
         if(pb.total >= MinProbabilityToTrade)
            PlaceTrade(true);
      }
   }

   if(sellCandidate)
   {
      int independent = 0;
      if(signal.bearishPA) independent++;
      if(market.sellerStrength > market.buyerStrength) independent++;
      if(market.regime == MR_Bearish || market.regime == MR_StrongBearish || market.regime == MR_WeakBearish) independent++;
      if(market.liquidityScore >= 4) independent++;
      if(independent >= 3)
      {
         ComputeProbability(false);
         if(pb.total >= MinProbabilityToTrade)
            PlaceTrade(false);
      }
   }
}

void UpdateDailyState()
{
   static datetime lastReset = 0;
   MqlDateTime c, l;
   TimeToStruct(TimeCurrent(), c);
   TimeToStruct(lastReset, l);

   if(lastReset == 0 || c.day != l.day || c.mon != l.mon || c.year != l.year)
   {
      dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(peakEquity <= 0) peakEquity = dayStartEquity;
      dailyLock = false;
      lastReset = TimeCurrent();
   }
}

//=================== LIFECYCLE ===================
int OnInit()
{
   atrHandle = iATR(_Symbol, ExecutionTF, 14);
   rsiHandle = iRSI(_Symbol, ExecutionTF, 14, PRICE_CLOSE);
   volHandle = iVolumes(_Symbol, ExecutionTF, VOLUME_TICK);

   if(atrHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE || volHandle == INVALID_HANDLE)
   {
      Print("IronHide Pro v3: failed creating indicators");
      return(INIT_FAILED);
   }

   dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   peakEquity = dayStartEquity;

   Print("IronHide Pro v3 Phase 1 initialized.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
   if(volHandle != INVALID_HANDLE) IndicatorRelease(volHandle);
}

void OnTick()
{
   // Run once per newly closed execution bar to reduce noise
   datetime barTime = iTime(_Symbol, ExecutionTF, 1);
   if(barTime == 0 || barTime == lastProcessedBar) return;
   lastProcessedBar = barTime;

   UpdateDailyState();

   if(!IsWithinTradingSession()) return;
   if(IsInNewsBlackout()) return;
   if(!PassSpreadFilter()) return;

   RunDecisionPipeline();

   Comment(
      "IronHide Pro v3 (Phase 1)\n",
      "Regime: ", (string)market.regime, "\n",
      "ObsState: ", (string)observationState, " Bars: ", observationBars, "\n",
      "Buyer/Seller: ", DoubleToString(market.buyerStrength,1), " / ", DoubleToString(market.sellerStrength,1), "\n",
      "PB Total: ", pb.total, " (min ", MinProbabilityToTrade, ")\n",
      "BOS bull/bear: ", market.bosBull, " / ", market.bosBear, "\n",
      "CHOCH bull/bear: ", market.chochBull, " / ", market.chochBear
   );
}
//+------------------------------------------------------------------+
