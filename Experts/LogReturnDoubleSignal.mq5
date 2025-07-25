//+------------------------------------------------------------------+
//|                                         DoubleSignalEA.mq5       |
//|   Basé sur le squelette Generic_EA_Skeleton                     |
//|   Stratégie : Mean Reversion + Trend Following sur log returns |
//+------------------------------------------------------------------+
#property copyright "Double Signal EA"
#property version   "1.10"
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
COrderInfo orderInfo;

datetime lastBarTime = 0;
int lastSignal = 0;
datetime lastTradeTime = 0;
double pointValue;
double tickSize;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validation des paramètres
   if (InpLotSize <= 0) {
      Print("Erreur: Lot Size doit être > 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if (InpZScorePeriod < 10) {
      Print("Erreur: Z-Score Period doit être >= 10");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if (InpStopLoss <= 0 || InpTakeProfit <= 0) {
      Print("Erreur: Stop Loss et Take Profit doivent être > 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Configuration du trade
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   
   // Calcul des valeurs de base
   pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   Print("EA initialisé avec succès pour ", _Symbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if (!InpEnableTrading || !IsNewBar()) return;
   
   if (!IsValidTradingTime()) return;
   
   AnalyzeMarket();
   ExecuteSignals();
}

//+------------------------------------------------------------------+
//| Check if new bar                                                 |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, InpTimeframe, 0);
   if(currentBarTime != lastBarTime && currentBarTime > 0)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if valid trading time                                      |
//+------------------------------------------------------------------+
bool IsValidTradingTime()
{
   if (!InpUseTimeFilter) return true;
   
   MqlDateTime dt;
   TimeCurrent(dt);
   
   return (dt.hour >= InpStartHour && dt.hour < InpEndHour);
}

//+------------------------------------------------------------------+
//| Check minimum interval between trades                            |
//+------------------------------------------------------------------+
bool IsMinIntervalPassed()
{
   if (!InpUseMinInterval) return true;
   
   return (TimeCurrent() - lastTradeTime) >= (InpMinIntervalMinutes * 60);
}

//+------------------------------------------------------------------+
//| Calculate volatility                                             |
//+------------------------------------------------------------------+
double CalculateVolatility()
{
   double prices[];
   ArraySetAsSeries(prices, true);
   
   int copied = CopyClose(_Symbol, InpTimeframe, 0, 20, prices);
   if (copied < 20) return 0.0;
   
   double sum = 0.0;
   for (int i = 0; i < 19; i++) {
      double logReturn = MathLog(prices[i] / prices[i+1]);
      sum += MathPow(logReturn, 2);
   }
   
   return MathSqrt(sum / 19);
}

//+------------------------------------------------------------------+
//| Analyse marché : stratégie double signal                        |
//+------------------------------------------------------------------+
void AnalyzeMarket()
{
   lastSignal = 0;
   
   // Vérifier la volatilité minimale
   if (CalculateVolatility() < InpMinVolatility) {
      return;
   }
   
   double prices[];
   ArraySetAsSeries(prices, true);
   
   int copied = CopyClose(_Symbol, InpTimeframe, 0, InpZScorePeriod + 5, prices);
   if (copied < InpZScorePeriod + 5) {
      Print("Pas assez de données pour analyse. Reçu: ", copied, " Requis: ", InpZScorePeriod + 5);
      return;
   }
   
   // Calcul des log returns
   double logReturns[];
   ArrayResize(logReturns, copied - 1);
   ArraySetAsSeries(logReturns, true);
   
   for (int i = 0; i < copied - 1; i++) {
      if (prices[i+1] > 0) {
         logReturns[i] = MathLog(prices[i] / prices[i+1]);
      } else {
         Print("Erreur: Prix invalide à l'index ", i+1);
         return;
      }
   }
   
   // Calcul du z-score
   double mean = 0.0, std = 0.0;
   int len = MathMin(InpZScorePeriod, ArraySize(logReturns));
   
   // Calcul de la moyenne
   for (int i = 0; i < len; i++) {
      mean += logReturns[i];
   }
   mean /= len;
   
   // Calcul de l'écart-type
   for (int i = 0; i < len; i++) {
      std += MathPow(logReturns[i] - mean, 2);
   }
   std = MathSqrt(std / (len - 1)); // Correction de Bessel
   
   if (std <= 0.0) {
      Print("Écart-type invalide: ", std);
      return;
   }
   
   double current = logReturns[0];
   double previous = logReturns[1];
   double z = (current - mean) / std;
   
   // Stratégie Mean Reversion
   if (InpUseMeanReversion) {
      if (z > InpZScoreThreshold) {
         lastSignal = -1; // SELL - prix trop haut
         Print("Signal Mean Reversion SELL - Z-Score: ", DoubleToString(z, 4));
         return;
      } else if (z < -InpZScoreThreshold) {
         lastSignal = 1;  // BUY - prix trop bas
         Print("Signal Mean Reversion BUY - Z-Score: ", DoubleToString(z, 4));
         return;
      }
   }
   
   // Stratégie Trend Following (si pas de signal mean reversion)
   if (InpUseTrendFollowing && MathAbs(z) <= InpZScoreThreshold) {
      if (previous < 0 && current > 0) {
         lastSignal = 1; // BUY - changement de momentum vers le haut
         Print("Signal Trend Following BUY - Changement momentum");
      } else if (previous > 0 && current < 0) {
         lastSignal = -1; // SELL - changement de momentum vers le bas
         Print("Signal Trend Following SELL - Changement momentum");
      }
   }
}

//+------------------------------------------------------------------+
//| Execute trading signals                                          |
//+------------------------------------------------------------------+
void ExecuteSignals()
{
   if (CountOpenPositions() >= InpMaxPositions) return;
   if (!IsMinIntervalPassed()) return;
   
   if (lastSignal == 1 && CanOpenBuy()) {
      OpenBuyPosition();
   } else if (lastSignal == -1 && CanOpenSell()) {
      OpenSellPosition();
   }
}

//+------------------------------------------------------------------+
//| Check if can open buy position                                   |
//+------------------------------------------------------------------+
bool CanOpenBuy()
{
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * pointValue;
   double maxSpreadValue = InpMaxSpread * pointValue * 10; // Conversion pips vers valeur
   
   return (spread <= maxSpreadValue);
}

//+------------------------------------------------------------------+
//| Check if can open sell position                                  |
//+------------------------------------------------------------------+
bool CanOpenSell()
{
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * pointValue;
   double maxSpreadValue = InpMaxSpread * pointValue * 10; // Conversion pips vers valeur
   
   return (spread <= maxSpreadValue);
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                 |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   if (InpRiskPercent <= 0) return InpLotSize;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double stopLossPoints = InpStopLoss * 10; // Conversion pips vers points
   
   if (tickValue <= 0 || stopLossPoints <= 0) return InpLotSize;
   
   double lotSize = riskAmount / (stopLossPoints * tickValue / pointValue);
   
   // Normaliser la taille du lot
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   lotSize = MathRound(lotSize / stepLot) * stepLot;
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Open buy position                                                |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = price - InpStopLoss * pointValue * 10; // Conversion pips
   double tp = price + InpTakeProfit * pointValue * 10; // Conversion pips
   double lotSize = CalculateLotSize();
   
   // Normaliser les prix
   sl = NormalizeDouble(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   tp = NormalizeDouble(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   
   if (trade.Buy(lotSize, _Symbol, price, sl, tp, InpComment)) {
      Print("Position BUY ouverte - Lot: ", lotSize, " SL: ", sl, " TP: ", tp);
      lastTradeTime = TimeCurrent();
   } else {
      Print("Erreur ouverture BUY: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Open sell position                                               |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = price + InpStopLoss * pointValue * 10; // Conversion pips
   double tp = price - InpTakeProfit * pointValue * 10; // Conversion pips
   double lotSize = CalculateLotSize();
   
   // Normaliser les prix
   sl = NormalizeDouble(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   tp = NormalizeDouble(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   
   if (trade.Sell(lotSize, _Symbol, price, sl, tp, InpComment)) {
      Print("Position SELL ouverte - Lot: ", lotSize, " SL: ", sl, " TP: ", tp);
      lastTradeTime = TimeCurrent();
   } else {
      Print("Erreur ouverture SELL: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Count open positions                                             |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA arrêté - Raison: ", reason);
}