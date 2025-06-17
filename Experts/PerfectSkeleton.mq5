//+------------------------------------------------------------------+
//|                                              PerfectSkeleton.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

// Inclusions nécessaires
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

// Déclaration des objets globaux
CTrade trade;
CPositionInfo positionInfo;
CSymbolInfo symbolInfo;

// Énumérations
enum ENUM_SL_TYPE {
    SL_POINTS,      // Points
    SL_PERCENT,     // Pourcentage du prix
    SL_ATR          // ATR * Multiplicateur
};

enum ENUM_TP_TYPE {
    TP_POINTS,      // Points
    TP_PERCENT,     // Pourcentage du prix
    TP_ATR          // ATR * Multiplicateur
};

enum ENUM_SIGNAL_STATE {
    SIGNAL_NONE,    // Pas de signal
    SIGNAL_PENDING, // Signal en attente
    SIGNAL_ACTIVE   // Signal actif
};

// Structure pour les signaux
struct Signal {
    ENUM_SIGNAL_STATE state;
    ENUM_ORDER_TYPE type;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    datetime time;
    double score;
};

// Structure pour les sessions
struct SessionInfo {
    string name;
    int startHour;
    int endHour;
    bool isActive;
    bool isOverlap;
    double volatilityFactor;
};

// Paramètres d'entrée
input group "=== Paramètres Généraux ==="
input string EA_Name = "PerfectSkeleton";           // Nom de l'EA
input ulong Magic_Number = 123456;                  // Magic Number
input bool Enable_Trading = true;                   // Activer le trading
input int Max_Positions = 1;                        // Nombre maximum de positions
input double Risk_Percent = 1.0;                    // Risque par trade (%)
input int Slippage = 3;                            // Slippage autorisé
input bool Process_OnTick = true;                   // Traiter les ticks
input ENUM_TIMEFRAMES OnTick_Timeframe = PERIOD_M1; // Timeframe pour OnTick

input group "=== Paramètres de Trading ==="
input ENUM_TIMEFRAMES Timeframe = PERIOD_H1;        // Timeframe principal
input ENUM_SL_TYPE StopLoss_Type = SL_POINTS;       // Type de Stop Loss
input double StopLoss_Value = 100;                  // Valeur Stop Loss
input double StopLoss_ATR_Multiplier = 2.0;         // Multiplicateur ATR pour SL
input ENUM_TP_TYPE TakeProfit_Type = TP_POINTS;     // Type de Take Profit
input double TakeProfit_Value = 200;                // Valeur Take Profit
input double TakeProfit_ATR_Multiplier = 3.0;       // Multiplicateur ATR pour TP

input group "=== Take Profit Partiel ==="
input bool Use_Partial_TP = false;                  // Utiliser TP partiels
input int Partial_TP_Count = 2;                     // Nombre de TP partiels
input double Partial_TP_Percent_1 = 0.5;            // Pourcentage TP 1
input double Partial_TP_Percent_2 = 0.5;            // Pourcentage TP 2
input double Partial_TP_Level_1 = 0.5;              // Niveau TP 1 (% du TP total)
input double Partial_TP_Level_2 = 1.0;              // Niveau TP 2 (% du TP total)

input group "=== Trailing Stop ==="
input bool Use_TrailingStop = false;                // Utiliser Trailing Stop
input int TrailingStop_Points = 50;                 // Trailing Stop en points
input int TrailingStep_Points = 10;                 // Pas du Trailing Stop
input double TrailingStart_Points = 100;            // Points de profit pour démarrer trailing

input group "=== Break Even ==="
input bool Use_BreakEven = false;                   // Utiliser Break Even
input int BreakEven_Points = 30;                    // Points de profit pour Break Even
input int BreakEven_Offset = 5;                     // Offset Break Even en points

input group "=== Filtres de Session ==="
input bool Use_Session_Filter = true;               // Utiliser filtre de session
input bool Trade_Asia = true;                       // Trader session Asie
input bool Trade_London = true;                     // Trader session Londres
input bool Trade_NY = true;                         // Trader session NY
input int Asia_Start = 0;                           // Début Asie (GMT)
input int Asia_End = 9;                             // Fin Asie (GMT)
input int London_Start = 8;                         // Début Londres (GMT)
input int London_End = 17;                          // Fin Londres (GMT)
input int NY_Start = 13;                            // Début NY (GMT)
input int NY_End = 22;                              // Fin NY (GMT)

input group "=== Autres Filtres ==="
input bool Use_Spread_Filter = true;                // Filtrer par spread
input int Max_Spread_Points = 20;                   // Spread maximum
input bool Use_News_Filter = true;                  // Filtrer les news

// Variables globales
datetime lastBarTime = 0;
double initialBalance = 0;
double maxEquity = 0;
bool isNewBar = false;
Signal currentSignal;
SessionInfo sessions[3];
int atrHandle = INVALID_HANDLE;

// Structure pour les statistiques
struct TradingStats {
    int totalTrades;
    int winTrades;
    int loseTrades;
    double totalProfit;
    double maxDD;
    double winRate;
    datetime lastUpdate;
};
TradingStats stats;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Configuration de l'objet trade
    trade.SetExpertMagicNumber(Magic_Number);
    trade.SetDeviationInPoints(Slippage);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    trade.SetTypeFillingBySymbol(_Symbol);
    
    // Initialisation des variables
    initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    maxEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    lastBarTime = 0;
    
    // Initialisation du signal
    currentSignal.state = SIGNAL_NONE;
    
    // Initialisation des sessions
    InitializeSessions();
    
    // Initialisation de l'ATR si nécessaire
    if(StopLoss_Type == SL_ATR || TakeProfit_Type == TP_ATR)
    {
        atrHandle = iATR(_Symbol, Timeframe, 14);
        if(atrHandle == INVALID_HANDLE)
        {
            Print("Erreur à la création du handle ATR");
            return INIT_FAILED;
        }
    }
    
    // Initialisation des statistiques
    stats.totalTrades = 0;
    stats.winTrades = 0;
    stats.loseTrades = 0;
    stats.totalProfit = 0;
    stats.maxDD = 0;
    stats.winRate = 0;
    stats.lastUpdate = TimeCurrent();
    
    Print("EA ", EA_Name, " initialisé avec succès");
    Print("Symbole: ", _Symbol);
    Print("Timeframe: ", EnumToString(Timeframe));
    Print("Balance initiale: ", DoubleToString(initialBalance, 2));
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("EA désactivé. Raison: ", reason);
    
    // Nettoyage des handles
    if(atrHandle != INVALID_HANDLE)
        IndicatorRelease(atrHandle);
    
    // Nettoyage si nécessaire
    switch(reason)
    {
        case REASON_PARAMETERS:
            Print("Changement de paramètres");
            break;
        case REASON_RECOMPILE:
            Print("Recompilation du code");
            break;
        case REASON_REMOVE:
            Print("Suppression de l'EA");
            break;
        case REASON_CHARTCHANGE:
            Print("Changement de graphique");
            break;
        default:
            Print("Autre raison d'arrêt: ", reason);
            break;
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Vérification si le trading est activé
    if(!Enable_Trading) return;
    
    // Vérification de la nouvelle barre
    if(!IsNewBar()) return;
    
    // Mise à jour des statistiques
    UpdateStats();
    
    // Vérification des filtres
    if(!CheckFilters()) return;
    
    // Création du signal
    CreateSignal();
    
    // Confirmation du signal
    if(currentSignal.state == SIGNAL_PENDING)
    {
        if(ConfirmSignal())
        {
            currentSignal.state = SIGNAL_ACTIVE;
            ExecuteSignal();
        }
    }
    
    // Gestion des positions existantes
    ManagePositions();
}

//+------------------------------------------------------------------+
//| Initialisation des sessions                                      |
//+------------------------------------------------------------------+
void InitializeSessions()
{
    // Session Asie
    sessions[0].name = "ASIA";
    sessions[0].startHour = Asia_Start;
    sessions[0].endHour = Asia_End;
    sessions[0].isActive = false;
    sessions[0].isOverlap = false;
    sessions[0].volatilityFactor = 0.7;
    
    // Session Londres
    sessions[1].name = "LONDON";
    sessions[1].startHour = London_Start;
    sessions[1].endHour = London_End;
    sessions[1].isActive = false;
    sessions[1].isOverlap = false;
    sessions[1].volatilityFactor = 1.2;
    
    // Session NY
    sessions[2].name = "NY";
    sessions[2].startHour = NY_Start;
    sessions[2].endHour = NY_End;
    sessions[2].isActive = false;
    sessions[2].isOverlap = false;
    sessions[2].volatilityFactor = 1.0;
}

//+------------------------------------------------------------------+
//| Vérifie si une nouvelle barre est formée                        |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    datetime currentBarTime = iTime(_Symbol, Timeframe, 0);
    if(currentBarTime != lastBarTime)
    {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Vérifie les filtres de trading                                  |
//+------------------------------------------------------------------+
bool CheckFilters()
{
    // Filtre de spread
    if(Use_Spread_Filter)
    {
        long currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
        if(currentSpread > Max_Spread_Points)
        {
            Print("Spread trop élevé: ", currentSpread);
            return false;
        }
    }
    
    // Filtre de session
    if(Use_Session_Filter)
    {
        if(!IsValidTradingSession())
        {
            return false;
        }
    }
    
    // Filtre des news
    if(Use_News_Filter)
    {
        // Implémentez votre logique de filtrage des news ici
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Vérifie si nous sommes dans une session de trading valide       |
//+------------------------------------------------------------------+
bool IsValidTradingSession()
{
    MqlDateTime timeStruct;
    TimeToStruct(TimeGMT(), timeStruct);
    int currentHour = timeStruct.hour;
    
    // Mise à jour des états des sessions
    sessions[0].isActive = (currentHour >= Asia_Start && currentHour < Asia_End);
    sessions[1].isActive = (currentHour >= London_Start && currentHour < London_End);
    sessions[2].isActive = (currentHour >= NY_Start && currentHour < NY_End);
    
    // Vérification des sessions activées
    if(Trade_Asia && sessions[0].isActive) return true;
    if(Trade_London && sessions[1].isActive) return true;
    if(Trade_NY && sessions[2].isActive) return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Crée un signal de trading                                        |
//+------------------------------------------------------------------+
void CreateSignal()
{
    // À implémenter selon votre stratégie
    // Exemple:
    // currentSignal.state = SIGNAL_PENDING;
    // currentSignal.type = ORDER_TYPE_BUY;
    // currentSignal.entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    // currentSignal.stopLoss = CalculateStopLoss();
    // currentSignal.takeProfit = CalculateTakeProfit();
    // currentSignal.time = TimeCurrent();
    // currentSignal.score = CalculateSignalScore();
}

//+------------------------------------------------------------------+
//| Confirme un signal de trading                                    |
//+------------------------------------------------------------------+
bool ConfirmSignal()
{
    // À implémenter selon votre stratégie
    // Exemple: vérification de conditions supplémentaires
    return true;
}

//+------------------------------------------------------------------+
//| Exécute le signal de trading                                     |
//+------------------------------------------------------------------+
void ExecuteSignal()
{
    double lotSize = CalculateLotSize();
    
    if(currentSignal.type == ORDER_TYPE_BUY)
    {
        trade.Buy(lotSize, _Symbol, 0, currentSignal.stopLoss, currentSignal.takeProfit);
    }
    else if(currentSignal.type == ORDER_TYPE_SELL)
    {
        trade.Sell(lotSize, _Symbol, 0, currentSignal.stopLoss, currentSignal.takeProfit);
    }
}

//+------------------------------------------------------------------+
//| Gère les positions existantes                                    |
//+------------------------------------------------------------------+
void ManagePositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == Magic_Number)
            {
                // Gestion du trailing stop
                if(Use_TrailingStop)
                {
                    ManageTrailingStop(positionInfo);
                }
                
                // Gestion du break even
                if(Use_BreakEven)
                {
                    ManageBreakEven(positionInfo);
                }
                
                // Gestion des TP partiels
                if(Use_Partial_TP)
                {
                    ManagePartialTP(positionInfo);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Gère le trailing stop                                            |
//+------------------------------------------------------------------+
void ManageTrailingStop(CPositionInfo &pos)
{
    double currentSL = pos.StopLoss();
    double currentTP = pos.TakeProfit();
    double currentPrice = pos.PriceOpen();
    
    if(pos.PositionType() == POSITION_TYPE_BUY)
    {
        double newSL = SymbolInfoDouble(_Symbol, SYMBOL_BID) - TrailingStop_Points * _Point;
        if(newSL > currentSL + TrailingStep_Points * _Point)
        {
            trade.PositionModify(pos.Ticket(), newSL, currentTP);
        }
    }
    else if(pos.PositionType() == POSITION_TYPE_SELL)
    {
        double newSL = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + TrailingStop_Points * _Point;
        if(newSL < currentSL - TrailingStep_Points * _Point)
        {
            trade.PositionModify(pos.Ticket(), newSL, currentTP);
        }
    }
}

//+------------------------------------------------------------------+
//| Gère le break even                                               |
//+------------------------------------------------------------------+
void ManageBreakEven(CPositionInfo &pos)
{
    double currentSL = pos.StopLoss();
    double currentTP = pos.TakeProfit();
    double currentPrice = pos.PriceOpen();
    double currentProfit = pos.Profit();
    
    if(pos.PositionType() == POSITION_TYPE_BUY)
    {
        if(currentProfit >= BreakEven_Points * _Point && currentSL < currentPrice)
        {
            double newSL = currentPrice + BreakEven_Offset * _Point;
            trade.PositionModify(pos.Ticket(), newSL, currentTP);
        }
    }
    else if(pos.PositionType() == POSITION_TYPE_SELL)
    {
        if(currentProfit >= BreakEven_Points * _Point && currentSL > currentPrice)
        {
            double newSL = currentPrice - BreakEven_Offset * _Point;
            trade.PositionModify(pos.Ticket(), newSL, currentTP);
        }
    }
}

//+------------------------------------------------------------------+
//| Gère les take profits partiels                                   |
//+------------------------------------------------------------------+
void ManagePartialTP(CPositionInfo &pos)
{
    double currentVolume = pos.Volume();
    double initialVolume = pos.Volume();
    double currentProfit = pos.Profit();
    double currentTP = pos.TakeProfit();
    
    // Tableaux pour stocker les valeurs des TP partiels
    double tpPercentages[2] = {Partial_TP_Percent_1, Partial_TP_Percent_2};
    double tpLevels[2] = {Partial_TP_Level_1, Partial_TP_Level_2};
    
    for(int i = 0; i < Partial_TP_Count; i++)
    {
        if(currentVolume > initialVolume * (1 - tpPercentages[i]) &&
           currentProfit >= currentTP * tpLevels[i])
        {
            double closeVolume = initialVolume * tpPercentages[i];
            trade.PositionClosePartial(pos.Ticket(), closeVolume);
            break;
        }
    }
}

//+------------------------------------------------------------------+
//| Calcule les points de stop loss                                 |
//+------------------------------------------------------------------+
double CalculateStopLossPoints()
{
    double basePoints;
    switch(StopLoss_Type)
    {
        case SL_POINTS:
            basePoints = StopLoss_Value;
            break;
            
        case SL_PERCENT:
            basePoints = StopLoss_Value * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 100;
            break;
            
        case SL_ATR:
        {
            double atr[];
            ArraySetAsSeries(atr, true);
            if(CopyBuffer(atrHandle, 0, 0, 1, atr) > 0)
            {
                basePoints = atr[0] * StopLoss_ATR_Multiplier / _Point;
            }
            else
            {
                basePoints = StopLoss_Value; // Fallback
            }
            break;
        }
            
        default:
            basePoints = StopLoss_Value;
            break;
    }
    
    // Ajuster en fonction de la volatilité de la session
    return basePoints * GetCurrentSessionVolatilityFactor();
}

//+------------------------------------------------------------------+
//| Calcule les points de take profit                               |
//+------------------------------------------------------------------+
double CalculateTakeProfitPoints()
{
    double basePoints;
    switch(TakeProfit_Type)
    {
        case TP_POINTS:
            basePoints = TakeProfit_Value;
            break;
            
        case TP_PERCENT:
            basePoints = TakeProfit_Value * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 100;
            break;
            
        case TP_ATR:
        {
            double atr[];
            ArraySetAsSeries(atr, true);
            if(CopyBuffer(atrHandle, 0, 0, 1, atr) > 0)
            {
                basePoints = atr[0] * TakeProfit_ATR_Multiplier / _Point;
            }
            else
            {
                basePoints = TakeProfit_Value; // Fallback
            }
            break;
        }
            
        default:
            basePoints = TakeProfit_Value;
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
    
    // Déterminer la session active
    if(currentHour >= Asia_Start && currentHour < Asia_End)
        return sessions[0].volatilityFactor;  // Session Asie
    else if(currentHour >= London_Start && currentHour < London_End)
        return sessions[1].volatilityFactor;  // Session Londres
    else if(currentHour >= NY_Start && currentHour < NY_End)
        return sessions[2].volatilityFactor;  // Session NY
    
    return 1.0; // Facteur par défaut si aucune session n'est active
}

//+------------------------------------------------------------------+
//| Calcule la taille du lot en fonction du risque                  |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * Risk_Percent / 100;
    double stopLossPoints = CalculateStopLossPoints();
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    // Ajuster le lot size en fonction de la volatilité de la session
    double volatilityFactor = GetCurrentSessionVolatilityFactor();
    double adjustedRiskAmount = riskAmount / volatilityFactor; // Réduire le risque quand la volatilité est plus élevée
    
    double lotSize = NormalizeDouble(adjustedRiskAmount / (stopLossPoints * tickValue), 2);
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Met à jour les statistiques de trading                          |
//+------------------------------------------------------------------+
void UpdateStats()
{
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // Mise à jour du drawdown maximum
    if(currentEquity > maxEquity)
    {
        maxEquity = currentEquity;
    }
    else
    {
        double currentDD = (maxEquity - currentEquity) / maxEquity * 100;
        if(currentDD > stats.maxDD)
        {
            stats.maxDD = currentDD;
        }
    }
    
    // Mise à jour des autres statistiques
    // Implémentez votre logique de mise à jour des statistiques ici
} 