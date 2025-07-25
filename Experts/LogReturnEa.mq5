//+------------------------------------------------------------------+
//|                                        LogReturn_MeanReversion.mq5 |
//|                     EA basé sur Mean Reversion avec Log Returns   |
//|                        Avec gestion des sessions de trading       |
//+------------------------------------------------------------------+
#property copyright "LogReturn Mean Reversion EA"
#property version   "1.00"

// Inclure les classes nécessaires
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

// Paramètres d'entrée
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15;    // Timeframe de travail
input double InpStopLoss = 50.0;                   // Stop Loss en points
input double InpTakeProfit = 100.0;                // Take Profit en points
input double InpLotSize = 0.1;                     // Taille du lot
input ulong InpMagicNumber = 12345;                // Numéro magique unique
input string InpComment = "LogReturn_EA";          // Commentaire des ordres
input bool InpEnableTrading = true;                // Activer/désactiver le trading
input int InpMaxPositions = 1;                     // Nombre maximum de positions simultanées
input int InpSlippage = 3;                         // Slippage autorisé
input bool UseSpreadFilter = false; 
input int InpMaxSpread = 30; 

// Paramètres spécifiques au Log Return
input ENUM_APPLIED_PRICE InpPrice = PRICE_CLOSE;   // Prix utilisé pour le calcul
input int InpShiftPeriod = 1;                      // Période de décalage pour log return
input int InpLookbackPeriod = 50;                  // Période pour calcul du z-score
input double InpZScoreThreshold = 2.0;             // Seuil z-score pour signaux
input bool InpUseZScore = true;                    // Utiliser z-score (recommandé)

// Paramètres de sessions
input bool filtreTradeSession = false;
input bool InpTradeAsian = true;                   // Trading session Asie
input bool InpTradeLondon = true;                  // Trading session Londres  
input bool InpTradeNY = true;                      // Trading session NY
input int InpAsianStart = 0;                       // Début Asie (heure GMT)
input int InpAsianEnd = 9;                         // Fin Asie (heure GMT)
input int InpLondonStart = 8;                      // Début Londres (heure GMT)
input int InpLondonEnd = 17;                       // Fin Londres (heure GMT)
input int InpNYStart = 13;                         // Début NY (heure GMT)
input int InpNYEnd = 22;                           // Fin NY (heure GMT)

input bool useIsNewCandle = true;
input bool verbose = true;

// Objets pour le trading
CTrade trade;
CPositionInfo positionInfo;
COrderInfo orderInfo;

// Variables globales
int lastSignal = 0;                                // Dernier signal généré (1=Buy, -1=Sell, 0=None)
datetime lastTradeTime = 0;                        // Timestamp du dernier trade
datetime lastBarTime = 0;                          // Timestamp de la dernière barre analysée

// Buffers pour calculs
double logReturnBuffer[];
double priceBuffer[];
int bufferSize = 200;                              // Taille des buffers

datetime g_bt_start = 0;   // date du premier tick vu
datetime g_bt_end   = 0;   // date du dernier tick vu

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   
     g_bt_start = 0;
      g_bt_end   = 0;
   

    Print("EA LogReturn Mean Reversion initialisé");
    Print("Symbole: ", _Symbol);
    Print("Timeframe: ", EnumToString(InpTimeframe));
    Print("Trading activé: ", InpEnableTrading ? "Oui" : "Non");
    Print("Z-Score activé: ", InpUseZScore ? "Oui" : "Non");
    
    // Configuration de l'objet trade
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(InpSlippage);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    trade.SetTypeFillingBySymbol(_Symbol);
    
    // Initialiser les buffers
    ArrayResize(logReturnBuffer, bufferSize);
    ArrayResize(priceBuffer, bufferSize);
    ArraySetAsSeries(logReturnBuffer, true);
    ArraySetAsSeries(priceBuffer, true);
    
    // Validation des paramètres
    if(!ValidateParameters())
    {
        Print("Erreur: Paramètres invalides");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("EA désactivé. Raison: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{

      if(g_bt_start == 0)
      g_bt_start = TimeCurrent();   // premier tick du back-test

      g_bt_end = TimeCurrent();        // se met à jour à chaque tick
      
      

    if(!InpEnableTrading)
        return;
        
    if(useIsNewCandle && !IsNewBar())
        return;
    
    // Vérifier si on peut trader selon la session
    if(!IsTradingSession())
        return;
    
    // Mise à jour des données de marché
    UpdateMarketData();
    
    // Analyse du marché et génération de signaux
    AnalyzeMarket();
    
    // Gestion des positions existantes
    ManagePositions();
    
    // Exécution des ordres si signaux présents
    ExecuteSignals();
}

//+------------------------------------------------------------------+
//| Validation des paramètres d'entrée                              |
//+------------------------------------------------------------------+
bool ValidateParameters()
{
    if(InpLotSize <= 0)
    {
        Print("Erreur: Taille de lot invalide: ", InpLotSize);
        return false;
    }
    
    if(InpStopLoss < 0 || InpTakeProfit < 0)
    {
        Print("Erreur: SL/TP négatifs - SL: ", InpStopLoss, " TP: ", InpTakeProfit);
        return false;
    }
    
    if(InpLookbackPeriod <= InpShiftPeriod)
    {
        Print("Erreur: Période lookback doit être > période shift");
        return false;
    }
    
    if(InpZScoreThreshold <= 0)
    {
        Print("Erreur: Seuil z-score doit être positif");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Détection d'une nouvelle barre                                  |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    datetime currentBarTime = iTime(_Symbol, InpTimeframe, 0);
    
    if(currentBarTime != lastBarTime)
    {
        lastBarTime = currentBarTime;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Vérification des sessions de trading                            |
//+------------------------------------------------------------------+
bool IsTradingSession()
{
   
      if (!filtreTradeSession)
      return true;
   
    MqlDateTime timeStruct;
    TimeToStruct(TimeCurrent(), timeStruct);
    int currentHour = timeStruct.hour;
    
    // Session Asie (0-9 GMT)
    if(InpTradeAsian && currentHour >= InpAsianStart && currentHour < InpAsianEnd)
        return true;
    
    // Session Londres (8-17 GMT)  
    if(InpTradeLondon && currentHour >= InpLondonStart && currentHour < InpLondonEnd)
        return true;
    
    // Session NY (13-22 GMT)
    if(InpTradeNY && currentHour >= InpNYStart && currentHour < InpNYEnd)
        return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Obtenir le prix selon le type spécifié                         |
//+------------------------------------------------------------------+
double GetPrice(int index, ENUM_APPLIED_PRICE priceType)
{
    switch(priceType)
    {
        case PRICE_OPEN:     return iOpen(_Symbol, InpTimeframe, index);
        case PRICE_HIGH:     return iHigh(_Symbol, InpTimeframe, index);
        case PRICE_LOW:      return iLow(_Symbol, InpTimeframe, index);
        case PRICE_CLOSE:    return iClose(_Symbol, InpTimeframe, index);
        case PRICE_MEDIAN:   return (iHigh(_Symbol, InpTimeframe, index) + iLow(_Symbol, InpTimeframe, index)) / 2.0;
        case PRICE_TYPICAL:  return (iHigh(_Symbol, InpTimeframe, index) + iLow(_Symbol, InpTimeframe, index) + iClose(_Symbol, InpTimeframe, index)) / 3.0;
        case PRICE_WEIGHTED: return (iHigh(_Symbol, InpTimeframe, index) + iLow(_Symbol, InpTimeframe, index) + 2 * iClose(_Symbol, InpTimeframe, index)) / 4.0;
        default:             return iClose(_Symbol, InpTimeframe, index);
    }
}

//+------------------------------------------------------------------+
//| Mise à jour des données de marché                               |
//+------------------------------------------------------------------+
void UpdateMarketData()
{
    // Calculer les log returns pour les dernières barres
    for(int i = 0; i < bufferSize && i < Bars(_Symbol, InpTimeframe) - InpShiftPeriod; i++)
    {
        double priceCurrent = GetPrice(i, InpPrice);
        double pricePrevious = GetPrice(i + InpShiftPeriod, InpPrice);
        
        priceBuffer[i] = priceCurrent;
        
        if(priceCurrent > 0.0 && pricePrevious > 0.0)
        {
            logReturnBuffer[i] = MathLog(priceCurrent / pricePrevious);
        }
        else
        {
            logReturnBuffer[i] = 0.0;
        }
    }
}

//+------------------------------------------------------------------+
//| Calcul du z-score pour les log returns                         |
//+------------------------------------------------------------------+
double CalculateZScore(int index)
{
    if(index + InpLookbackPeriod >= bufferSize)
        return 0.0;
    
    // Calculer la moyenne des log returns sur la période lookback
    double sum = 0.0;
    int validPoints = 0;
    
    for(int i = index + 1; i <= index + InpLookbackPeriod; i++)
    {
        sum += logReturnBuffer[i];
        validPoints++;
    }
    
    if(validPoints == 0)
        return 0.0;
    
    double mean = sum / validPoints;
    
    // Calculer l'écart-type
    double variance = 0.0;
    for(int i = index + 1; i <= index + InpLookbackPeriod; i++)
    {
        double diff = logReturnBuffer[i] - mean;
        variance += diff * diff;
    }
    
    double stdDev = MathSqrt(variance / validPoints);
    
    if(stdDev == 0.0)
        return 0.0;
    
    // Calculer le z-score du log return actuel
    double zScore = (logReturnBuffer[index] - mean) / stdDev;
    
    return zScore;
}

//+------------------------------------------------------------------+
//| Analyse du marché et génération de signaux                      |
//+------------------------------------------------------------------+
void AnalyzeMarket()
{
    lastSignal = 0;
    
    double currentValue;
    
    if(InpUseZScore)
    {
        // Utiliser le z-score
        currentValue = CalculateZScore(0);
        
        // Signal de mean reversion
        // Z-score élevé (positif) -> prix "trop haut" -> signal SELL
        // Z-score faible (négatif) -> prix "trop bas" -> signal BUY
        if(currentValue > InpZScoreThreshold)
        {
            lastSignal = -1; // Signal de vente (mean reversion)
            if (verbose)
               Print("Signal SELL - Z-Score: ", DoubleToString(currentValue, 4));
        }
        else if(currentValue < -InpZScoreThreshold)
        {
            lastSignal = 1;  // Signal d'achat (mean reversion)
            if (verbose)
               Print("Signal BUY - Z-Score: ", DoubleToString(currentValue, 4));
        }
    }
    else
    {
        // Utiliser directement le log return
        currentValue = logReturnBuffer[0];
        double threshold = InpZScoreThreshold * 0.01; // Adapter le seuil
        
        if(currentValue > threshold)
        {
            lastSignal = -1; // Signal de vente
            if (verbose)
               Print("Signal SELL - LogReturn: ", DoubleToString(currentValue, 6));
        }
        else if(currentValue < -threshold)
        {
            lastSignal = 1;  // Signal d'achat
            if (verbose)
               Print("Signal BUY - LogReturn: ", DoubleToString(currentValue, 6));
        }
    }
}

//+------------------------------------------------------------------+
//| Gestion des positions existantes                                |
//+------------------------------------------------------------------+
void ManagePositions()
{
    if(!HasOpenPositions())
        return;
    
    // Logique de sortie: fermer les positions si le z-score revient vers zéro
    double currentValue = InpUseZScore ? CalculateZScore(0) : logReturnBuffer[0];
    double exitThreshold = InpUseZScore ? 0.5 : 0.005; // Seuil de sortie plus faible
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
            {
                bool shouldClose = false;
                
                // Fermer les positions BUY si z-score devient positif
                if(positionInfo.PositionType() == POSITION_TYPE_BUY && currentValue > exitThreshold)
                {
                    shouldClose = true;
                }
                // Fermer les positions SELL si z-score devient négatif
                else if(positionInfo.PositionType() == POSITION_TYPE_SELL && currentValue < -exitThreshold)
                {
                    shouldClose = true;
                }
                
                if(shouldClose)
                {
                    ClosePositionByTicket(positionInfo.Ticket());
                    if (verbose)
                        Print("Position fermée pour retour à la moyenne - Valeur: ", DoubleToString(currentValue, 4));
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Exécution des signaux de trading                                |
//+------------------------------------------------------------------+
void ExecuteSignals()
{
    if(CountOpenPositions() >= InpMaxPositions)
        return;
        
    if(lastSignal == 1) // Signal d'achat
    {
        if(CanOpenBuy())
        {
            OpenBuyPosition();
        }
    }
    else if(lastSignal == -1) // Signal de vente
    {
        if(CanOpenSell())
        {
            OpenSellPosition();
        }
    }
}

//+------------------------------------------------------------------+
//| Vérification des conditions pour position d'achat               |
//+------------------------------------------------------------------+
bool CanOpenBuy()
{
   if (!UseSpreadFilter)
      return true;

    double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double maxSpread = InpMaxSpread; // 3 pips maximum
    
    if(spread > maxSpread)
    {
        Print("Spread trop élevé pour ouvrir position BUY: ", spread);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Vérification des conditions pour position de vente              |
//+------------------------------------------------------------------+
bool CanOpenSell()
{
   if (!UseSpreadFilter)
      return true;
   

    double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double maxSpread = InpMaxSpread; // 3 pips maximum
    
    if(spread > maxSpread)
    {
        Print("Spread trop élevé pour ouvrir position SELL: ", spread);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Ouverture d'une position d'achat                                |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
    double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double sl = (InpStopLoss > 0) ? price - InpStopLoss * SymbolInfoDouble(_Symbol, SYMBOL_POINT) : 0;
    double tp = (InpTakeProfit > 0) ? price + InpTakeProfit * SymbolInfoDouble(_Symbol, SYMBOL_POINT) : 0;
    
    if(trade.Buy(InpLotSize, _Symbol, price, sl, tp, InpComment))
    {
        if(verbose)
            Print("Position BUY ouverte. Ticket: ", trade.ResultOrder(), " | Prix: ", price);
        lastTradeTime = TimeCurrent();
    }
    else
    {
        Print("Erreur ouverture BUY: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Ouverture d'une position de vente                               |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = (InpStopLoss > 0) ? price + InpStopLoss * SymbolInfoDouble(_Symbol, SYMBOL_POINT) : 0;
    double tp = (InpTakeProfit > 0) ? price - InpTakeProfit * SymbolInfoDouble(_Symbol, SYMBOL_POINT) : 0;
    
    if(trade.Sell(InpLotSize, _Symbol, price, sl, tp, InpComment))
    {
        if(verbose)
            Print("Position SELL ouverte. Ticket: ", trade.ResultOrder(), " | Prix: ", price);
        lastTradeTime = TimeCurrent();
    }
    else
    {
        Print("Erreur ouverture SELL: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Vérification de l'existence de positions ouvertes               |
//+------------------------------------------------------------------+
bool HasOpenPositions()
{
    return (CountOpenPositions() > 0);
}

//+------------------------------------------------------------------+
//| Compter le nombre de positions ouvertes                         |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
            {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Fermeture d'une position spécifique par ticket                  |
//+------------------------------------------------------------------+
bool ClosePositionByTicket(ulong ticket)
{
    if(trade.PositionClose(ticket))
    {
        if(verbose)
            Print("Position fermée par ticket: ", ticket);
        return true;
    }
    else
    {
        Print("Erreur fermeture position par ticket: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
        return false;
    }
}

double OnTester()
{
   //--- statistiques « classiques »
   double profit        = TesterStatistics(STAT_PROFIT);
   int    trades        = (int)TesterStatistics(STAT_TRADES);
   double profit_factor = TesterStatistics(STAT_PROFIT_FACTOR);
   double max_dd_pct    = TesterStatistics(STAT_BALANCEDD_PERCENT);
   int    winners       = (int)TesterStatistics(STAT_PROFIT_TRADES);

   //--- durée réelle du back-test en semaines
   double seconds_total   = (double)(g_bt_end - g_bt_start);
   double weeks_total     = seconds_total / 604800.0;
   if(weeks_total < 1.0)  // sécurité pour division
      weeks_total = 1.0;

   double trades_per_week = trades / weeks_total;
   double win_rate        = (trades > 0) ? (winners * 100.0 / trades) : 0;

   //--- filtres d’élimination
   if(trades < 5)            return 0;
   if(profit <= 0)           return 0;
   if(profit_factor < 1.1)   return 0;
   if(max_dd_pct > 25)       return 0;
   if(trades_per_week < 1.0) return 0;   // au moins 1 trade / semaine

   //--- score composite
   double score =
         profit              * 0.30 +
         profit_factor *100  * 0.25 +
         win_rate            * 0.20 +
         trades_per_week*10  * 0.15 +
         (100 - max_dd_pct)  * 0.10;

   return score;
}