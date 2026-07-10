//+------------------------------------------------------------------+
//|                                   IronHide_v1_10Trades_MT5.mq5   |
//|  Frequency-target MT5 EA (~10 trades/day target, not guarantee)  |
//|  Designed for XAUUSD with strict risk guardrails                 |
//+------------------------------------------------------------------+
#property copyright "krazysoundsproduction-bit"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

#define SAFE_MAX_POSITIONS 2

//=================== ENUMS ===================
enum ePositionMode { PM_BuyAndSell, PM_BuyOnly, PM_SellOnly };
enum eLotMode      { LM_FixedLot, LM_RiskPercent };
enum eExitMode     { EX_Adaptive, EX_Fixed };

//=================== IDENTIFICATION ===================
input group "=== Identification ==="
input long           Strategy_ID             = 444101;
input string         Execution_Label         = "IronHide";
input ePositionMode  Position_Mode           = PM_BuyAndSell;

//=================== SIGNAL ENGINE ===================
input group "=== Signal Engine ==="
input int            EMA_Fast                = 10;
input int            EMA_Slow                = 34;
input int            RSI_Period              = 14;
input double         RSI_BuyThreshold        = 45.0;
input double         RSI_SellThreshold       = 55.0;
input int            ADX_Period              = 14;
input double         MinADX                  = 18.0;
input bool           EnableHTFConfirmation   = true;
input ENUM_TIMEFRAMES HTF_Timeframe          = PERIOD_M5;
input int            HTF_EMA_Fast            = 20;
input int            HTF_EMA_Slow            = 100;

//=================== TRADE FREQUENCY ===================
input group "=== Frequency Controls ==="
input int            TargetTradesPerDay      = 10;
input int            MaxTradesPerDay         = 12;
input bool           SinglePositionMode      = true;
input bool           EnableCooldown          = true;
input int            CooldownMinutesAfterLoss= 20;
input int            MinMinutesBetweenEntries= 8;

//=================== LOT / SIZING ===================
input group "=== Lot Sizing ==="
input eLotMode       LotMode                 = LM_RiskPercent;
input double         Initial_Volume          = 0.01;
input double         Risk_Percent            = 0.35;
input int            MaximumPositions        = 2;

//=================== EXITS ===================
input group "=== Exits ==="
input bool           HiddenTakeProfit        = false;
input eExitMode      TakeProfitMode          = EX_Adaptive;
input int            TakeProfit_Points       = 0;
input bool           HiddenStopLoss          = false;
input eExitMode      StopLossMode            = EX_Adaptive;
input int            StopLoss_Points         = 0;
input eExitMode      TrailingStopMode        = EX_Adaptive;
input int            TrailingStopActivation  = 180;
input int            TrailingStopDistance    = 70;
input int            TrailingStopStep        = 20;
input int            EmergencyBasketStop_Points = 260;
input double         DailyTarget             = 0.0;
input double         EquityProtectionPercent = 4.0;
input int            MaxSlippage             = 10;

//=================== ADAPTIVE ===================
input group "=== Adaptive Engine ==="
input double         AdaptiveTPFactor        = 1.6;
input double         AdaptiveSLFactor        = 1.1;
input double         AdaptiveTrailFactor     = 0.8;

//=================== FILTERS ===================
input group "=== Filters ==="
input bool           EnableSpreadProtection  = true;
input int            MaxSpreadForTrading     = 45;
input bool           EnableATRFilter         = true;
input int            ATRPeriod               = 14;
input double         MinATRMultiplier        = 0.6;
input double         MaxATRMultiplier        = 2.2;
input int            ATRLookback             = 50;

//=================== SESSION ===================
input group "=== Session ==="
input bool           Trading24h              = false;
input bool           MondayTrading           = true;
input string         MondaySessionStart      = "08:00";
input string         MondaySessionEnd        = "20:00";
input bool           TuesdayTrading          = true;
input string         TuesdaySessionStart     = "08:00";
input string         TuesdaySessionEnd       = "20:00";
input bool           WednesdayTrading        = true;
input string         WednesdaySessionStart   = "08:00";
input string         WednesdaySessionEnd     = "20:00";
input bool           ThursdayTrading         = true;
input string         ThursdaySessionStart    = "08:00";
input string         ThursdaySessionEnd      = "20:00";
input bool           FridayTrading           = true;
input string         FridaySessionStart      = "08:00";
input string         FridaySessionEnd        = "18:00";

//=================== NEWS ===================
input group "=== News Protection ==="
input bool           NewsProtection          = true;
input int            NewsPauseBefore_m       = 60;
input int            NewsPauseAfter_m        = 60;
input bool           USDEventFilter          = true;
input bool           EUREventFilter          = true;

//=================== GLOBALS ===================
int      atrHandle = INVALID_HANDLE;
int      emaFastHandle = INVALID_HANDLE;
int      emaSlowHandle = INVALID_HANDLE;
int      rsiHandle = INVALID_HANDLE;
int      adxHandle = INVALID_HANDLE;
int      htfFastHandle = INVALID_HANDLE;
int      htfSlowHandle = INVALID_HANDLE;

double   dailyStartEquity = 0.0;
datetime lastDayReset = 0;
bool     dailyStopTriggered = false;
int      tradesToday = 0;
datetime lastTradeDay = 0;
datetime cooldownUntil = 0;
datetime lastEntryTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   atrHandle = iATR(_Symbol, PERIOD_CURRENT, ATRPeriod);
   emaFastHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   adxHandle = iADX(_Symbol, PERIOD_CURRENT, ADX_Period);

   if(EnableHTFConfirmation)
   {
      htfFastHandle = iMA(_Symbol, HTF_Timeframe, HTF_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
      htfSlowHandle = iMA(_Symbol, HTF_Timeframe, HTF_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   }

   if(atrHandle == INVALID_HANDLE || emaFastHandle == INVALID_HANDLE || emaSlowHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE || adxHandle == INVALID_HANDLE)
   {
      Print("IronHide: indicator handle creation failed");
      return(INIT_FAILED);
   }

   trade.SetDeviationInPoints(MaxSlippage);
   trade.SetExpertMagicNumber(Strategy_ID);

   dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   lastDayReset = TimeCurrent();
   lastTradeDay = TimeCurrent();

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(emaFastHandle != INVALID_HANDLE) IndicatorRelease(emaFastHandle);
   if(emaSlowHandle != INVALID_HANDLE) IndicatorRelease(emaSlowHandle);
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
   if(adxHandle != INVALID_HANDLE) IndicatorRelease(adxHandle);
   if(htfFastHandle != INVALID_HANDLE) IndicatorRelease(htfFastHandle);
   if(htfSlowHandle != INVALID_HANDLE) IndicatorRelease(htfSlowHandle);
}

void OnTick()
{
   CheckNewDayReset();

   if(!dailyStopTriggered)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double dayPnL = equity - dailyStartEquity;

      if(DailyTarget > 0.0 && dayPnL >= DailyTarget)
      {
         CloseAllBasket("Daily target reached");
         dailyStopTriggered = true;
      }

      if(EquityProtectionPercent > 0.0 && dailyStartEquity > 0 && dayPnL <= -(dailyStartEquity * EquityProtectionPercent / 100.0))
      {
         CloseAllBasket("Daily protection triggered");
         dailyStopTriggered = true;
      }
   }

   if(dailyStopTriggered) return;

   if(EmergencyBasketStop_Points > 0)
      CheckEmergencyBasketStop();

   ManageOpenPositions();

   if(TimeCurrent() < cooldownUntil) return;
   if(!IsWithinTradingSession()) return;
   if(NewsProtection && IsInNewsBlackout()) return;

   if(EnableSpreadProtection && !PassSpreadFilter()) return;
   if(EnableATRFilter && !PassATRFilter()) return;

   TryOpenPositions();
}

void CheckNewDayReset()
{
   MqlDateTime cur, last, tradeDay;
   TimeToStruct(TimeCurrent(), cur);
   TimeToStruct(lastDayReset, last);
   TimeToStruct(lastTradeDay, tradeDay);

   if(cur.day != last.day || cur.mon != last.mon || cur.year != last.year)
   {
      dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      lastDayReset = TimeCurrent();
      dailyStopTriggered = false;
   }

   if(cur.day != tradeDay.day || cur.mon != tradeDay.mon || cur.year != tradeDay.year)
   {
      tradesToday = 0;
      lastTradeDay = TimeCurrent();
   }
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

   int curMinutes = t.hour * 60 + t.min;
   int startMinutes = TimeStrToMinutes(startStr);
   int endMinutes = TimeStrToMinutes(endStr);

   return (curMinutes >= startMinutes && curMinutes <= endMinutes);
}

int TimeStrToMinutes(string hhmm)
{
   string parts[];
   StringSplit(hhmm, ':', parts);
   if(ArraySize(parts) < 2) return 0;
   return (int)StringToInteger(parts[0]) * 60 + (int)StringToInteger(parts[1]);
}

bool IsInNewsBlackout()
{
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

         datetime evTime = vals[i].time;
         if(TimeCurrent() >= (evTime - NewsPauseBefore_m * 60) && TimeCurrent() <= (evTime + NewsPauseAfter_m * 60))
            return true;
      }
   }
   return false;
}

bool PassSpreadFilter()
{
   long spreadPoints = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spreadPoints <= MaxSpreadForTrading);
}

bool PassATRFilter()
{
   double atrNow[], atrHist[];
   if(CopyBuffer(atrHandle, 0, 0, 1, atrNow) <= 0) return false;
   if(CopyBuffer(atrHandle, 0, 0, ATRLookback, atrHist) <= 0) return false;

   double avgATR = 0.0;
   for(int i = 0; i < ArraySize(atrHist); i++) avgATR += atrHist[i];
   avgATR /= MathMax(1, ArraySize(atrHist));
   if(avgATR <= 0) return false;

   double ratio = atrNow[0] / avgATR;
   return (ratio >= MinATRMultiplier && ratio <= MaxATRMultiplier);
}

bool GetSignal(bool &buySignal, bool &sellSignal)
{
   buySignal = false;
   sellSignal = false;

   double f[2], s[2], r[2], adx[1];
   if(CopyBuffer(emaFastHandle, 0, 0, 2, f) < 2) return false;
   if(CopyBuffer(emaSlowHandle, 0, 0, 2, s) < 2) return false;
   if(CopyBuffer(rsiHandle, 0, 0, 2, r) < 2) return false;
   if(CopyBuffer(adxHandle, 0, 0, 1, adx) < 1) return false;

   bool trendUp = (f[0] > s[0]);
   bool trendDn = (f[0] < s[0]);
   bool rsiBuy = (r[0] > RSI_BuyThreshold && r[1] <= RSI_BuyThreshold);
   bool rsiSell = (r[0] < RSI_SellThreshold && r[1] >= RSI_SellThreshold);
   bool adxOk = (adx[0] >= MinADX);

   bool htfUp = true, htfDn = true;
   if(EnableHTFConfirmation)
   {
      double hf[1], hs[1];
      if(CopyBuffer(htfFastHandle, 0, 0, 1, hf) < 1) return false;
      if(CopyBuffer(htfSlowHandle, 0, 0, 1, hs) < 1) return false;
      htfUp = (hf[0] > hs[0]);
      htfDn = (hf[0] < hs[0]);
   }

   buySignal = trendUp && rsiBuy && adxOk && htfUp;
   sellSignal = trendDn && rsiSell && adxOk && htfDn;

   return true;
}

void TryOpenPositions()
{
   int totalCount = CountPositions(POSITION_TYPE_BUY) + CountPositions(POSITION_TYPE_SELL);
   int effectiveMax = MathMin(MaximumPositions, SAFE_MAX_POSITIONS);

   if(totalCount >= effectiveMax) return;
   if(MaxTradesPerDay > 0 && tradesToday >= MaxTradesPerDay) return;
   if(SinglePositionMode && totalCount > 0) return;

   // pacing to avoid burst overtrading
   if(MinMinutesBetweenEntries > 0 && lastEntryTime > 0 && (TimeCurrent() - lastEntryTime) < MinMinutesBetweenEntries * 60)
      return;

   bool buySignal, sellSignal;
   if(!GetSignal(buySignal, sellSignal)) return;

   bool allowBuy = (Position_Mode == PM_BuyAndSell || Position_Mode == PM_BuyOnly);
   bool allowSell = (Position_Mode == PM_BuyAndSell || Position_Mode == PM_SellOnly);

   // Soft booster if running behind target pace late in day
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   int elapsedMinutes = t.hour * 60 + t.min;
   int expectedTrades = (int)MathFloor((double)TargetTradesPerDay * elapsedMinutes / (24.0 * 60.0));
   bool behindPace = (tradesToday + 1 < expectedTrades);

   if(allowBuy && buySignal)
   {
      double lot = ComputeLot();
      if(behindPace) lot = NormalizeLot(lot * 1.05); // tiny boost, still bounded by symbol rules
      if(OpenTrade(ORDER_TYPE_BUY, lot))
      {
         tradesToday++;
         lastEntryTime = TimeCurrent();
      }
      return;
   }

   if(allowSell && sellSignal)
   {
      double lot = ComputeLot();
      if(behindPace) lot = NormalizeLot(lot * 1.05);
      if(OpenTrade(ORDER_TYPE_SELL, lot))
      {
         tradesToday++;
         lastEntryTime = TimeCurrent();
      }
      return;
   }
}

double ComputeLot()
{
   double lot = Initial_Volume;

   if(LotMode == LM_RiskPercent && Risk_Percent > 0)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskAmount = equity * (Risk_Percent / 100.0);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double slPoints = (StopLossMode == EX_Fixed && StopLoss_Points > 0) ? StopLoss_Points : 180;
      if(tickValue > 0 && slPoints > 0)
         lot = riskAmount / (slPoints * tickValue);
   }

   return NormalizeLot(lot);
}

double NormalizeLot(double lot)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;

   lot = MathRound(lot / step) * step;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   return lot;
}

bool OpenTrade(ENUM_ORDER_TYPE type, double lot)
{
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double marginRequired = 0.0;
   if(!OrderCalcMargin(type, _Symbol, lot, price, marginRequired))
      return false;

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(marginRequired > freeMargin * 0.7) return false;

   double sl = 0, tp = 0;
   ComputeAdaptiveLevels(type, price, sl, tp);
   ValidateStopsBySymbolRules(type, price, sl, tp);

   string cmt = Execution_Label + "_" + IntegerToString((int)Strategy_ID);
   double brokerSL = HiddenStopLoss ? 0 : sl;
   double brokerTP = HiddenTakeProfit ? 0 : tp;

   bool ok = false;
   if(type == ORDER_TYPE_BUY)
      ok = trade.Buy(lot, _Symbol, price, brokerSL, brokerTP, cmt);
   else
      ok = trade.Sell(lot, _Symbol, price, brokerSL, brokerTP, cmt);

   if(!ok)
      PrintFormat("IronHide order fail. Retcode=%d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());

   return ok;
}

void ComputeAdaptiveLevels(ENUM_ORDER_TYPE type, double entry, double &sl, double &tp)
{
   double atr = GetATR();
   if(atr <= 0) atr = 100 * _Point;

   double tpDist = (TakeProfitMode == EX_Adaptive) ? atr * AdaptiveTPFactor : ((TakeProfit_Points > 0) ? TakeProfit_Points * _Point : 0);
   double slDist = (StopLossMode == EX_Adaptive) ? atr * AdaptiveSLFactor : ((StopLoss_Points > 0) ? StopLoss_Points * _Point : 0);

   if(type == ORDER_TYPE_BUY)
   {
      tp = (tpDist > 0) ? entry + tpDist : 0;
      sl = (slDist > 0) ? entry - slDist : 0;
   }
   else
   {
      tp = (tpDist > 0) ? entry - tpDist : 0;
      sl = (slDist > 0) ? entry + slDist : 0;
   }
}

void ValidateStopsBySymbolRules(ENUM_ORDER_TYPE type, double entry, double &sl, double &tp)
{
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopsLevel * _Point;
   if(minDist <= 0) return;

   if(type == ORDER_TYPE_BUY)
   {
      if(sl > 0 && (entry - sl) < minDist) sl = entry - minDist;
      if(tp > 0 && (tp - entry) < minDist) tp = entry + minDist;
   }
   else
   {
      if(sl > 0 && (sl - entry) < minDist) sl = entry + minDist;
      if(tp > 0 && (entry - tp) < minDist) tp = entry - minDist;
   }

   sl = (sl > 0) ? NormalizeDouble(sl, _Digits) : 0;
   tp = (tp > 0) ? NormalizeDouble(tp, _Digits) : 0;
}

void ManageOpenPositions()
{
   double atr = GetATR();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Strategy_ID) continue;

      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curPrice  = (ptype == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(HiddenTakeProfit || HiddenStopLoss)
      {
         double sl, tp;
         ComputeAdaptiveLevels(ptype == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, openPrice, sl, tp);

         if(HiddenTakeProfit && tp > 0)
            if((ptype == POSITION_TYPE_BUY && curPrice >= tp) || (ptype == POSITION_TYPE_SELL && curPrice <= tp))
               trade.PositionClose(ticket);

         if(HiddenStopLoss && sl > 0)
            if((ptype == POSITION_TYPE_BUY && curPrice <= sl) || (ptype == POSITION_TYPE_SELL && curPrice >= sl))
               trade.PositionClose(ticket);
      }

      double activation = TrailingStopActivation * _Point;
      double profitDist = (ptype == POSITION_TYPE_BUY) ? (curPrice - openPrice) : (openPrice - curPrice);
      if(profitDist < activation) continue;

      double trailDist = (TrailingStopMode == EX_Adaptive && atr > 0) ? atr * AdaptiveTrailFactor : TrailingStopDistance * _Point;
      double stepDist = TrailingStopStep * _Point;
      if(trailDist <= 0) continue;

      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);

      if(ptype == POSITION_TYPE_BUY)
      {
         double newSL = NormalizeDouble(curPrice - trailDist, _Digits);
         if(curSL == 0 || newSL > curSL + stepDist)
            trade.PositionModify(ticket, newSL, curTP);
      }
      else
      {
         double newSL = NormalizeDouble(curPrice + trailDist, _Digits);
         if(curSL == 0 || newSL < curSL - stepDist)
            trade.PositionModify(ticket, newSL, curTP);
      }
   }
}

void CheckEmergencyBasketStop()
{
   double totalPoints = 0;
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Strategy_ID) continue;

      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curPrice  = (ptype == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double pts = (ptype == POSITION_TYPE_BUY) ? (curPrice - openPrice) / _Point : (openPrice - curPrice) / _Point;
      totalPoints += pts;
      count++;
   }

   if(count > 0 && totalPoints <= -EmergencyBasketStop_Points)
   {
      CloseAllBasket("Emergency basket stop");
      if(EnableCooldown)
         cooldownUntil = TimeCurrent() + CooldownMinutesAfterLoss * 60;
   }
}

int CountPositions(ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Strategy_ID) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type) count++;
   }
   return count;
}

double GetATR()
{
   double a[1];
   if(CopyBuffer(atrHandle, 0, 0, 1, a) < 1) return 0;
   return a[0];
}

void CloseAllBasket(string reason)
{
   Print("IronHide close basket: ", reason);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Strategy_ID) continue;
      trade.PositionClose(ticket);
   }
}
//+------------------------------------------------------------------+
