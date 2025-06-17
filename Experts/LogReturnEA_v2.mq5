//+------------------------------------------------------------------+
//|                                              LogReturnEA_v2.mq5   |
//|                     EA basé sur Mean Reversion avec Log Returns   |
//|                        Version 2.0 avec gestion avancée           |
//+------------------------------------------------------------------+
#property copyright "LogReturn Mean Reversion EA v2"
#property version   "2.00"

// Inclure les classes nécessaires
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\SymbolInfo.mqh>

// Énumérations
enum ENUM_SL_TYPE {
    SL_POINTS,
    SL_PERCENT,
    SL_ATR
};

// Paramètres d'entrée
input group "=== PARAMÈTRES GÉNÉRAUX ==="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15;    // Timeframe de travail
input bool InpEnableTrading = true;                 // Activer/désactiver le trading
input ulong InpMagicNumber = 12345;                 // Numéro magique unique
input string InpComment = "LogReturn_v2";           // Commentaire des ordres
input int InpMaxPositions = 1;                      // Nombre maximum de positions simultanées
input int InpSlippage = 3;                          // Slippage autorisé
input bool InpVerbose = false;                      // Mode verbose

input group "=== PARAMÈTRES DE RISQUE ==="
input double InpRiskPercent = 1.0;                  // Risque par trade (%)
input double InpMaxRiskPercent = 5.0;               // Risque maximum total (%)
input double InpMaxDrawdownPercent = 20.0;          // Drawdown maximum autorisé (%)

input group "=== PARAMÈTRES DE TRADING ==="
input ENUM_APPLIED_PRICE InpPrice = PRICE_CLOSE;    // Prix utilisé pour le calcul
input int InpShiftPeriod = 1;                       // Période de décalage pour log return
input int InpLookbackPeriod = 50;                   // Période pour calcul du z-score
input double InpZScoreThreshold = 2.0;              // Seuil z-score pour signaux
input bool InpUseZScore = true;                     // Utiliser z-score (recommandé)
input double InpMinVolatility = 0.0001;             // Volatilité minimale requise
input ENUM_SL_TYPE InpStopLossType = SL_POINTS;     // Type de Stop Loss
input double InpStopLossValue = 50.0;               // Valeur Stop Loss
input double InpStopLossATRMultiplier = 2.0;        // Multiplicateur ATR pour SL

input group "=== GESTION DES POSITIONS ==="
input bool InpUseBreakeven = true;                  // Utiliser le breakeven
input int InpBreakevenPoints = 20;                  // Points de profit pour breakeven
input int InpBreakevenOffset = 5;                   // Offset du breakeven en points
input bool InpUseTrailingStop = true;               // Utiliser le trailing stop
input int InpTrailingStart = 30;                    // Points de profit pour démarrer trailing
input int InpTrailingStep = 10;                     // Pas du trailing stop
input bool InpUsePartialTP = true;                  // Utiliser le take profit partiel
input double InpPartialTPPercent1 = 50.0;           // % de volume pour TP1
input double InpPartialTPPercent2 = 25.0;           // % de volume pour TP2
input int InpPartialTPLevel1 = 50;                  // Points pour TP1
input int InpPartialTPLevel2 = 100;                 // Points pour TP2

input group "=== FILTRES DE TRADING ==="
input bool InpUseSpreadFilter = true;               // Utiliser le filtre de spread
input int InpMaxSpread = 30;                        // Spread maximum autorisé
input bool InpUseTimeFilter = true;                 // Utiliser le filtre horaire
input int InpStartHour = 8;                         // Heure de début (GMT)
input int InpEndHour = 20;                          // Heure de fin (GMT)
input bool InpUseSessionFilter = true;              // Utiliser le filtre de session
input bool InpTradeAsian = true;                    // Trader session Asie
input bool InpTradeLondon = true;                   // Trader session Londres
input bool InpTradeNY = true;                       // Trader session NY

// Variables globales
CTrade trade;                                       // Objet de trading
CPositionInfo positionInfo;                         // Information sur les positions
CSymbolInfo symbolInfo;                             // Information sur le symbole
int atrHandle;

// Variables de suivi
datetime lastBarTime = 0;                           // Timestamp de la dernière barre
int lastSignal = 0;                                 // Dernier signal généré
datetime lastTradeTime = 0;                         // Dernier trade exécuté
double maxDrawdown = 0.0;                           // Drawdown maximum
double initialBalance = 0.0;                        // Balance initiale

// Buffers pour calculs
double logReturnBuffer[];                           // Buffer des log returns
double priceBuffer[];                               // Buffer des prix
int bufferSize = 200;                               // Taille des buffers

// Structure pour les sessions
struct SessionInfo {
    int startHour;
    int endHour;
    double volatilityFactor;
    bool enabled;
};

SessionInfo sessions[3];                            // Sessions de trading

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialisation des objets
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(InpSlippage);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    trade.SetTypeFillingBySymbol(_Symbol);
    
    // Initialisation des sessions
    InitializeSessions();
    
    // Initialisation des buffers
    ArrayResize(logReturnBuffer, bufferSize);
    ArrayResize(priceBuffer, bufferSize);
    ArraySetAsSeries(logReturnBuffer, true);
    ArraySetAsSeries(priceBuffer, true);
    
    // Initialisation des variables de suivi
    initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    maxDrawdown = 0.0;
    
    // Initialisation ATR
    atrHandle = iATR(_Symbol, InpTimeframe, 14);
    if(atrHandle == INVALID_HANDLE)
    {
        Print("Erreur création handle ATR");
        return INIT_FAILED;
    }
    
    // Validation des paramètres
    if(!ValidateParameters())
    {
        Print("Erreur: Paramètres invalides");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    Print("EA LogReturn v2 initialisé avec succès");
    Print("Symbole: ", _Symbol);
    Print("Timeframe: ", EnumToString(InpTimeframe));
    Print("Trading activé: ", InpEnableTrading ? "Oui" : "Non");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Initialisation des sessions de trading                           |
//+------------------------------------------------------------------+
void InitializeSessions()
{
    // Session Asie
    sessions[0].startHour = 0;
    sessions[0].endHour = 9;
    sessions[0].volatilityFactor = 0.7;
    sessions[0].enabled = InpTradeAsian;
    
    // Session Londres
    sessions[1].startHour = 8;
    sessions[1].endHour = 17;
    sessions[1].volatilityFactor = 1.2;
    sessions[1].enabled = InpTradeLondon;
    
    // Session NY
    sessions[2].startHour = 13;
    sessions[2].endHour = 22;
    sessions[2].volatilityFactor = 1.0;
    sessions[2].enabled = InpTradeNY;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(atrHandle != INVALID_HANDLE)
        IndicatorRelease(atrHandle);
    Print("EA désactivé. Raison: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!InpEnableTrading)
        return;
        
    if(!IsNewBar())
        return;
    
    // Vérifier les filtres
    if(!CheckFilters())
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
//| Vérification des filtres de trading                             |
//+------------------------------------------------------------------+
bool CheckFilters()
{
    // Filtre de spread
    if(InpUseSpreadFilter)
    {
        long currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
        if(currentSpread > InpMaxSpread)
        {
            if(InpVerbose) Print("Spread trop élevé: ", currentSpread);
            return false;
        }
    }
    
    // Filtre horaire
    if(InpUseTimeFilter)
    {
        MqlDateTime timeStruct;
        TimeToStruct(TimeGMT(), timeStruct);
        int currentHour = timeStruct.hour;
        
        if(currentHour < InpStartHour || currentHour >= InpEndHour)
        {
            if(InpVerbose) Print("Hors des heures de trading");
            return false;
        }
    }
    
    // Filtre de session
    if(InpUseSessionFilter)
    {
        if(!IsTradingSession())
        {
            if(InpVerbose) Print("Hors des sessions de trading autorisées");
            return false;
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Vérification des sessions de trading                            |
//+------------------------------------------------------------------+
bool IsTradingSession()
{
    MqlDateTime timeStruct;
    TimeToStruct(TimeGMT(), timeStruct);
    int currentHour = timeStruct.hour;
    
    for(int i = 0; i < 3; i++)
    {
        if(sessions[i].enabled)
        {
            if(currentHour >= sessions[i].startHour && currentHour < sessions[i].endHour)
                return true;
        }
    }
    
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
        if(currentValue > InpZScoreThreshold)
        {
            lastSignal = -1; // Signal de vente
        }
        else if(currentValue < -InpZScoreThreshold)
        {
            lastSignal = 1;  // Signal d'achat
        }
    }
    else
    {
        // Utiliser directement les log returns
        currentValue = logReturnBuffer[0];
        
        if(currentValue > InpZScoreThreshold)
        {
            lastSignal = -1;
        }
        else if(currentValue < -InpZScoreThreshold)
        {
            lastSignal = 1;
        }
    }
}


bool HasOpenPositions()
{
    return (CountOpenPositions() > 0);
}
//+------------------------------------------------------------------+
//| Gestion des positions existantes                                |
//+------------------------------------------------------------------+
void ManagePositions()
{
    if(!HasOpenPositions())
        return;
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
            {
                // Gestion du breakeven
                if(InpUseBreakeven)
                    ManageBreakeven();
                
                // Gestion du trailing stop
                if(InpUseTrailingStop)
                    ManageTrailingStop();
                
                // Gestion du take profit partiel
                if(InpUsePartialTP)
                    ManagePartialTP();
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Gestion du breakeven                                            |
//+------------------------------------------------------------------+
void ManageBreakeven()
{
    if(!positionInfo.SelectByIndex(0))
        return;
    
    double openPrice = positionInfo.PriceOpen();
    double currentPrice = positionInfo.PriceCurrent();
    double sl = positionInfo.StopLoss();
    double points = symbolInfo.Point();
    
    if(sl == openPrice)
        return;
    
    double profitPoints;
    if(positionInfo.PositionType() == POSITION_TYPE_BUY)
        profitPoints = (currentPrice - openPrice) / points;
    else
        profitPoints = (openPrice - currentPrice) / points;
    
    if(profitPoints >= InpBreakevenPoints)
    {
        double newSL = openPrice + (positionInfo.PositionType() == POSITION_TYPE_BUY ? 
                                  InpBreakevenOffset * points : 
                                  -InpBreakevenOffset * points);
        
        if(trade.PositionModify(positionInfo.Ticket(), newSL, positionInfo.TakeProfit()))
        {
            if(InpVerbose) Print("Breakeven activé pour le ticket: ", positionInfo.Ticket());
        }
    }
}

//+------------------------------------------------------------------+
//| Gestion du trailing stop                                        |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
    if(!positionInfo.SelectByIndex(0))
        return;
    
    double openPrice = positionInfo.PriceOpen();
    double currentPrice = positionInfo.PriceCurrent();
    double sl = positionInfo.StopLoss();
    double points = symbolInfo.Point();
    
    double profitPoints;
    if(positionInfo.PositionType() == POSITION_TYPE_BUY)
        profitPoints = (currentPrice - openPrice) / points;
    else
        profitPoints = (openPrice - currentPrice) / points;
    
    if(profitPoints >= InpTrailingStart)
    {
        double newSL;
        if(positionInfo.PositionType() == POSITION_TYPE_BUY)
        {
            newSL = currentPrice - InpTrailingStep * points;
            if(newSL > sl)
            {
                if(trade.PositionModify(positionInfo.Ticket(), newSL, positionInfo.TakeProfit()))
                {
                    if(InpVerbose) Print("Trailing stop mis à jour pour le ticket: ", positionInfo.Ticket());
                }
            }
        }
        else
        {
            newSL = currentPrice + InpTrailingStep * points;
            if(newSL < sl || sl == 0)
            {
                if(trade.PositionModify(positionInfo.Ticket(), newSL, positionInfo.TakeProfit()))
                {
                    if(InpVerbose) Print("Trailing stop mis à jour pour le ticket: ", positionInfo.Ticket());
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Gestion du take profit partiel                                  |
//+------------------------------------------------------------------+
void ManagePartialTP()
{
    if(!positionInfo.SelectByIndex(0))
        return;
    
    double openPrice = positionInfo.PriceOpen();
    double currentPrice = positionInfo.PriceCurrent();
    double points = symbolInfo.Point();
    
    double profitPoints;
    if(positionInfo.PositionType() == POSITION_TYPE_BUY)
        profitPoints = (currentPrice - openPrice) / points;
    else
        profitPoints = (openPrice - currentPrice) / points;
    
    if(profitPoints >= InpPartialTPLevel1)
    {
        double volumeToClose = positionInfo.Volume() * InpPartialTPPercent1 / 100.0;
        if(trade.PositionClosePartial(positionInfo.Ticket(), volumeToClose))
        {
            if(InpVerbose) Print("TP partiel 1 exécuté pour le ticket: ", positionInfo.Ticket());
        }
    }
    else if(profitPoints >= InpPartialTPLevel2)
    {
        double volumeToClose = positionInfo.Volume() * InpPartialTPPercent2 / 100.0;
        if(trade.PositionClosePartial(positionInfo.Ticket(), volumeToClose))
        {
            if(InpVerbose) Print("TP partiel 2 exécuté pour le ticket: ", positionInfo.Ticket());
        }
    }
}

//+------------------------------------------------------------------+
//| Exécution des signaux de trading                               |
//+------------------------------------------------------------------+
void ExecuteSignals()
{
    if(lastSignal == 0 || !CanOpenNewPosition())
        return;
    
    double lotSize = CalculateLotSize();
    if(lotSize <= 0)
        return;
    
    double sl = 0.0, tp = 0.0;
    CalculateSLTP(sl, tp);
    
    if(lastSignal > 0)
    {
        if(trade.Buy(lotSize, _Symbol, 0, sl, tp, InpComment))
        {
            if(InpVerbose) Print("Ordre d'achat exécuté");
            lastTradeTime = TimeCurrent();
        }
    }
    else if(lastSignal < 0)
    {
        if(trade.Sell(lotSize, _Symbol, 0, sl, tp, InpComment))
        {
            if(InpVerbose) Print("Ordre de vente exécuté");
            lastTradeTime = TimeCurrent();
        }
    }
}

//+------------------------------------------------------------------+
//| Calcul de la taille du lot en fonction du risque                |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * InpRiskPercent / 100.0;
    double stopLossPoints = InpStopLossValue;
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    // Ajuster le lot size en fonction de la volatilité de la session
    double volatilityFactor = GetCurrentSessionVolatilityFactor();
    double adjustedRiskAmount = riskAmount / volatilityFactor;
    
    double lotSize = NormalizeDouble(adjustedRiskAmount / (stopLossPoints * tickValue), 2);
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Calcul des points de stop loss                                 |
//+------------------------------------------------------------------+
double CalculateStopLossPoints()
{
    double basePoints;
    switch(InpStopLossType)
    {
        case SL_POINTS:
            basePoints = InpStopLossValue;
            break;
            
        case SL_PERCENT:
            basePoints = InpStopLossValue * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 100;
            break;
            
        case SL_ATR:
        {
            double atr[];
            ArraySetAsSeries(atr, true);
            if(CopyBuffer(atrHandle, 0, 0, 1, atr) > 0)
            {
                basePoints = atr[0] * InpStopLossATRMultiplier / _Point;
            }
            else
            {
                basePoints = InpStopLossValue; // Fallback
            }
            break;
        }
            
        default:
            basePoints = InpStopLossValue;
            break;
    }
    
    // Ajuster en fonction de la volatilité de la session
    return basePoints * GetCurrentSessionVolatilityFactor();
}

//+------------------------------------------------------------------+
//| Obtient le facteur de volatilité de la session courante         |
//+------------------------------------------------------------------+
double GetCurrentSessionVolatilityFactor()
{
    MqlDateTime timeStruct;
    TimeToStruct(TimeGMT(), timeStruct);
    int currentHour = timeStruct.hour;
    
    for(int i = 0; i < 3; i++)
    {
        if(sessions[i].enabled)
        {
            if(currentHour >= sessions[i].startHour && currentHour < sessions[i].endHour)
                return sessions[i].volatilityFactor;
        }
    }
    
    return 1.0; // Facteur par défaut
}

//+------------------------------------------------------------------+
//| Vérifie si on peut ouvrir une nouvelle position                 |
//+------------------------------------------------------------------+
bool CanOpenNewPosition()
{
    if(CountOpenPositions() >= InpMaxPositions)
        return false;
    
    // Vérifier le drawdown maximum
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double currentDrawdown = (initialBalance - currentBalance) / initialBalance * 100.0;
    
    if(currentDrawdown > InpMaxDrawdownPercent)
    {
        if(InpVerbose) Print("Drawdown maximum atteint: ", currentDrawdown, "%");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Compte le nombre de positions ouvertes                          |
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
//| Vérifie si une nouvelle barre s'est formée                     |
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
//| Validation des paramètres d'entrée                              |
//+------------------------------------------------------------------+
bool ValidateParameters()
{
    if(InpRiskPercent <= 0 || InpRiskPercent > 100)
    {
        Print("Erreur: Pourcentage de risque invalide");
        return false;
    }
    
    if(InpMaxRiskPercent <= 0 || InpMaxRiskPercent > 100)
    {
        Print("Erreur: Risque maximum total invalide");
        return false;
    }
    
    if(InpMaxDrawdownPercent <= 0 || InpMaxDrawdownPercent > 100)
    {
        Print("Erreur: Drawdown maximum invalide");
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
//| Calcul SL/TP                                                     |
//+------------------------------------------------------------------+
void CalculateSLTP(double &sl, double &tp)
{
    double points = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double atr[];
    ArraySetAsSeries(atr, true);
    
    switch(InpStopLossType)
    {
        case SL_POINTS:
            sl = lastSignal > 0 ? 
                 SymbolInfoDouble(_Symbol, SYMBOL_ASK) - InpStopLossValue * points :
                 SymbolInfoDouble(_Symbol, SYMBOL_BID) + InpStopLossValue * points;
            break;
            
        case SL_PERCENT:
            sl = lastSignal > 0 ?
                 SymbolInfoDouble(_Symbol, SYMBOL_ASK) * (1 - InpStopLossValue / 100.0) :
                 SymbolInfoDouble(_Symbol, SYMBOL_BID) * (1 + InpStopLossValue / 100.0);
            break;
            
        case SL_ATR:
            if(CopyBuffer(atrHandle, 0, 0, 1, atr) > 0)
            {
                sl = lastSignal > 0 ?
                     SymbolInfoDouble(_Symbol, SYMBOL_ASK) - atr[0] * InpStopLossATRMultiplier :
                     SymbolInfoDouble(_Symbol, SYMBOL_BID) + atr[0] * InpStopLossATRMultiplier;
            }
            break;
    }
    
    // TP = 2 * SL
    tp = lastSignal > 0 ?
         SymbolInfoDouble(_Symbol, SYMBOL_ASK) + (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - sl) * 2 :
         SymbolInfoDouble(_Symbol, SYMBOL_BID) - (sl - SymbolInfoDouble(_Symbol, SYMBOL_BID)) * 2;
} 