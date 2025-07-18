//+------------------------------------------------------------------+
//|                                         DoubleSignalEA.mq5       |
//|   Basé sur le squelette Generic_EA_Skeleton                     |
//|   Stratégie : Mean Reversion + Trend Following sur log returns |
//|   Version optimisée pour backtests rapides                      |
//+------------------------------------------------------------------+
#property copyright "Double Signal EA"
#property version   "1.20"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "=== TRADING SETTINGS ==="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5;        // Timeframe
input double InpLotSize = 0.1;                         // Lot Size
input ulong InpMagicNumber = 12345;                    // Magic Number
input string InpComment = "DoubleSignalEA";            // Comment
input bool InpEnableTrading = true;                    // Enable Trading
input int InpMaxPositions = 1;                         // Max Positions
input int InpSlippage = 3;                             // Slippage (points)

input group "=== RISK MANAGEMENT ==="
input double InpStopLoss = 50.0;                       // Stop Loss (pips)
input double InpTakeProfit = 100.0;                    // Take Profit (pips)
input double InpMaxSpread = 3.0;                       // Max Spread (pips)
input double InpRiskPercent = 0.0;                     // Risk % (0=fixed lot)

input group "=== STRATEGY PARAMETERS ==="
input int InpZScorePeriod = 30;                        // Z-Score Period
input double InpZScoreThreshold = 2.0;                 // Z-Score Threshold
input int InpLookbackLog = 20;                         // Log Returns Lookback
input bool InpUseMeanReversion = true;                 // Use Mean Reversion
input bool InpUseTrendFollowing = true;                // Use Trend Following

input group "=== TIME FILTER ==="
input bool InpUseTimeFilter = false;                   // Use Time Filter
input int InpStartHour = 8;                            // Start Hour
input int InpEndHour = 18;                             // End Hour

input group "=== SIGNAL FILTER ==="
input bool InpUseMinInterval = true;                   // Use Min Interval Between Trades
input int InpMinIntervalMinutes = 30;                  // Min Interval (minutes)
input double InpMinVolatility = 0.0001;                // Min Volatility Required

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo positionInfo;

// Variables de cache pour optimisation
datetime lastBarTime = 0;
int lastSignal = 0;
datetime lastTradeTime = 0;

// Variables calculées une seule fois
double pointValue;
double tickSize;
double maxSpreadValue;
double slPips, tpPips;
int symbolDigits;
double minLot, maxLot, stepLot;
double calculatedLotSize;
int minIntervalSeconds;

// Cache pour les données de marché
double logReturnsBuffer[];
double pricesBuffer[];
int bufferSize;
bool bufferInitialized = false;

// Variables pour calculs statistiques optimisés
double runningSum = 0.0;
double runningSumSquares = 0.0;
int validDataPoints = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validation rapide des paramètres
   if (InpLotSize <= 0 || InpZScorePeriod < 10 || InpStopLoss <= 0 || InpTakeProfit <= 0) {
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Configuration du trade
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   
   // Pré-calcul des valeurs constantes
   pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   maxSpreadValue = InpMaxSpread * pointValue * 10;
   slPips = InpStopLoss * pointValue * 10;
   tpPips = InpTakeProfit * pointValue * 10;
   symbolDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   minIntervalSeconds = InpMinIntervalMinutes * 60;
   
   // Pré-calcul des paramètres de lot
   minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   calculatedLotSize = CalculateLotSizeOnce();
   
   // Initialisation des buffers
   bufferSize = InpZScorePeriod + 10;
   ArrayResize(logReturnsBuffer, bufferSize);
   ArrayResize(pricesBuffer, bufferSize + 1);
   ArraySetAsSeries(logReturnsBuffer, true);
   ArraySetAsSeries(pricesBuffer, true);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if (!InpEnableTrading) return;
   
   // Check rapide nouvelle barre
   datetime currentBarTime = iTime(_Symbol, InpTimeframe, 0);
   if(currentBarTime == lastBarTime || currentBarTime <= 0) return;
   lastBarTime = currentBarTime;
   
   // Filtres rapides
   if (InpUseTimeFilter && !IsValidTradingTimeOptimized()) return;
   if (CountOpenPositions() >= InpMaxPositions) return;
   if (InpUseMinInterval && (TimeCurrent() - lastTradeTime) < minIntervalSeconds) return;
   
   AnalyzeMarketOptimized();
   if (lastSignal != 0) ExecuteSignalsOptimized();
}

//+------------------------------------------------------------------+
//| Time filter optimized                                            |
//+------------------------------------------------------------------+
bool IsValidTradingTimeOptimized()
{
   static int lastHour = -1;
   static bool lastResult = true;
   
   MqlDateTime dt;
   TimeCurrent(dt);
   
   if (dt.hour != lastHour) {
      lastHour = dt.hour;
      lastResult = (dt.hour >= InpStartHour && dt.hour < InpEndHour);
   }
   
   return lastResult;
}

//+------------------------------------------------------------------+
//| Optimized market analysis                                        |
//+------------------------------------------------------------------+
void AnalyzeMarketOptimized()
{
   lastSignal = 0;
   
   // Copie des données une seule fois
   int copied = CopyClose(_Symbol, InpTimeframe, 0, bufferSize + 1, pricesBuffer);
   if (copied < InpZScorePeriod + 2) return;
   
   // Calcul optimisé des log returns avec mise à jour incrémentale
   if (!bufferInitialized) {
      // Premier calcul complet
      InitializeLogReturnsBuffer(copied);
      bufferInitialized = true;
   } else {
      // Mise à jour incrémentale (plus rapide)
      UpdateLogReturnsBuffer();
   }
   
   // Calcul statistiques optimisées
   double mean, std;
   if (!CalculateStatsOptimized(mean, std)) return;
   
   double current = logReturnsBuffer[0];
   double previous = logReturnsBuffer[1];
   double z = (current - mean) / std;
   
   // Signaux optimisés
   if (InpUseMeanReversion) {
      if (z > InpZScoreThreshold) {
         lastSignal = -1;
         return;
      } else if (z < -InpZScoreThreshold) {
         lastSignal = 1;
         return;
      }
   }
   
   if (InpUseTrendFollowing && MathAbs(z) <= InpZScoreThreshold) {
      if (previous < 0 && current > 0) {
         lastSignal = 1;
      } else if (previous > 0 && current < 0) {
         lastSignal = -1;
      }
   }
}

//+------------------------------------------------------------------+
//| Initialize log returns buffer (first time)                      |
//+------------------------------------------------------------------+
void InitializeLogReturnsBuffer(int copied)
{
   runningSum = 0.0;
   runningSumSquares = 0.0;
   validDataPoints = 0;
   
   for (int i = 0; i < copied - 1; i++) {
      if (pricesBuffer[i+1] > 0) {
         logReturnsBuffer[i] = MathLog(pricesBuffer[i] / pricesBuffer[i+1]);
         
         if (i < InpZScorePeriod) {
            runningSum += logReturnsBuffer[i];
            runningSumSquares += logReturnsBuffer[i] * logReturnsBuffer[i];
            validDataPoints++;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update log returns buffer incrementally                          |
//+------------------------------------------------------------------+
void UpdateLogReturnsBuffer()
{
   // Nouveau log return
   if (pricesBuffer[1] > 0) {
      double newLogReturn = MathLog(pricesBuffer[0] / pricesBuffer[1]);
      
      // Retirer l'ancienne valeur des statistiques
      if (validDataPoints >= InpZScorePeriod) {
         double oldValue = logReturnsBuffer[InpZScorePeriod-1];
         runningSum -= oldValue;
         runningSumSquares -= oldValue * oldValue;
      }
      
      // Décaler le buffer et ajouter la nouvelle valeur
      for (int i = bufferSize-2; i > 0; i--) {
         logReturnsBuffer[i] = logReturnsBuffer[i-1];
      }
      logReturnsBuffer[0] = newLogReturn;
      
      // Ajouter la nouvelle valeur aux statistiques
      runningSum += newLogReturn;
      runningSumSquares += newLogReturn * newLogReturn;
      
      if (validDataPoints < InpZScorePeriod) validDataPoints++;
   }
}

//+------------------------------------------------------------------+
//| Calculate statistics optimized                                   |
//+------------------------------------------------------------------+
bool CalculateStatsOptimized(double &mean, double &std)
{
   if (validDataPoints < InpZScorePeriod) return false;
   
   mean = runningSum / validDataPoints;
   double variance = (runningSumSquares / validDataPoints) - (mean * mean);
   
   if (variance <= 0) return false;
   
   std = MathSqrt(variance);
   return (std > 0);
}

//+------------------------------------------------------------------+
//| Execute signals optimized                                        |
//+------------------------------------------------------------------+
void ExecuteSignalsOptimized()
{
   // Check spread une seule fois
   static datetime lastSpreadCheck = 0;
   static bool spreadOK = true;
   
   datetime currentTime = TimeCurrent();
   if (currentTime != lastSpreadCheck) {
      lastSpreadCheck = currentTime;
      double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * pointValue;
      spreadOK = (spread <= maxSpreadValue);
   }
   
   if (!spreadOK) return;
   
   if (lastSignal == 1) {
      OpenPositionOptimized(ORDER_TYPE_BUY);
   } else if (lastSignal == -1) {
      OpenPositionOptimized(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| Open position optimized                                          |
//+------------------------------------------------------------------+
void OpenPositionOptimized(ENUM_ORDER_TYPE orderType)
{
   double price, sl, tp;
   
   if (orderType == ORDER_TYPE_BUY) {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl = NormalizeDouble(price - slPips, symbolDigits);
      tp = NormalizeDouble(price + tpPips, symbolDigits);
      
      if (trade.Buy(calculatedLotSize, _Symbol, price, sl, tp, InpComment)) {
         lastTradeTime = TimeCurrent();
      }
   } else {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = NormalizeDouble(price + slPips, symbolDigits);
      tp = NormalizeDouble(price - tpPips, symbolDigits);
      
      if (trade.Sell(calculatedLotSize, _Symbol, price, sl, tp, InpComment)) {
         lastTradeTime = TimeCurrent();
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size once                                          |
//+------------------------------------------------------------------+
double CalculateLotSizeOnce()
{
   if (InpRiskPercent <= 0) return InpLotSize;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double stopLossPoints = InpStopLoss * 10;
   
   if (tickValue <= 0 || stopLossPoints <= 0) return InpLotSize;
   
   double lotSize = riskAmount / (stopLossPoints * tickValue / pointValue);
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   lotSize = MathRound(lotSize / stepLot) * stepLot;
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Count open positions (optimized)                                |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   static datetime lastCountTime = 0;
   static int lastCount = 0;
   
   datetime currentTime = TimeCurrent();
   if (currentTime != lastCountTime) {
      lastCountTime = currentTime;
      lastCount = 0;
      
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(positionInfo.SelectByIndex(i)) {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber) {
               lastCount++;
            }
         }
      }
   }
   
   return lastCount;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ArrayFree(logReturnsBuffer);
   ArrayFree(pricesBuffer);
}