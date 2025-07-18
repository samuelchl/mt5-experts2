//+------------------------------------------------------------------+
//|                                          FractalsGrok.mq5        |
//|                                  Copyright 2025, Trading Strategy |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Trading Strategy"
#property link      "https://www.mql5.com"
#property version   "1.15"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input Parameters
input group "=== SURVEILLANCE DU MARCHÉ ==="
input ENUM_TIMEFRAMES MonitoringTimeframe = PERIOD_M5;    // Timeframe de surveillance
input int CandleShift = 1;                                // Décalage bougie (0=current, 1=previous)

input group "=== FRACTALS SETTINGS ==="
input ENUM_TIMEFRAMES FractalTimeframe = PERIOD_H1;       // Timeframe pour les fractals
input int FractalPeriod = 5;                              // Période des fractals
input double MinFractalATR = 0.6;                         // Filtre ATR pour fractals (multiple)

input group "=== FAIR VALUE GAP SETTINGS ==="
input ENUM_TIMEFRAMES FVGTimeframe = PERIOD_H1;           // Timeframe pour les FVG
input double MinFVGSize = 6.0;                           // Taille minimale FVG en points
input int MaxFVGLookback = 50;                            // Nombre de bougies à analyser pour FVG

input group "=== ORDER BLOCK SETTINGS ==="
input ENUM_TIMEFRAMES OrderBlockTimeframe = PERIOD_H1;    // Timeframe pour les Order Blocks
input int OrderBlockLookback = 20;                        // Nombre de bougies pour Order Blocks
input double MinOrderBlockSize = 10.0;                    // Taille minimale Order Block en points

input group "=== VALIDATION SETTINGS ==="
input bool UseStandardValidation = true;                  // Utiliser validation standard
input bool AllowInstantDecision = true;                   // Permettre décision instantanée
input double HighProbabilityThreshold = 0.4;              // Seuil haute probabilité (0-1)
input int RSI_Period = 14;                                // Période RSI pour confirmation
input double RSI_Overbought = 70.0;                       // Niveau RSI surachat
input double RSI_Oversold = 30.0;                         // Niveau RSI survente
input bool RequireCandlePatterns = false;                 // Exiger motifs de bougies

input group "=== TRADE MANAGEMENT ==="
input double RiskPercent = 1.0;                           // Risque par trade en %
input double RewardRiskRatio = 2.5;                       // Ratio Reward/Risk
input int MaxPositions = 2;                               // Nombre max de positions
input int MinSLPoints = 50;                               // Distance minimale SL en points
input int MinTPPoints = 50;                               // Distance minimale TP en points

input group "=== TIMEFRAME HIERARCHY ==="
input ENUM_TIMEFRAMES GlobalTimeframe = PERIOD_D1;        // Timeframe global
input ENUM_TIMEFRAMES LocalTimeframe = PERIOD_H1;         // Timeframe local

input long magicNumber = 15987564236;

//--- Global Variables
CTrade trade;
CPositionInfo  m_position;
datetime lastCandleTime = 0;
int rsiHandle = INVALID_HANDLE;
int atrHandleFractal = INVALID_HANDLE;
int atrHandleFVG = INVALID_HANDLE;
int atrHandleOrderBlock = INVALID_HANDLE;
int atrHandleGeneral = INVALID_HANDLE;

//--- Structures
struct TradingVariable
{
    int type;           // 0=FVG, 1=Fractal, 2=OrderBlock
    int impact;         // 0=Low, 1=High
    double level;       // Prix du niveau
    double upperLevel;  // Prix supérieur (pour zones)
    double lowerLevel;  // Prix inférieur (pour zones)
    ENUM_TIMEFRAMES timeframe;
    datetime time;
    bool isValid;
};

struct TradingIdea
{
    TradingVariable initialZone;
    TradingVariable targetZone;
    int ideaType;       // 0=Global, 1=Local
    bool isValidated;
    double probability;
    bool isTroubleArea;
    datetime formationTime;
};

//--- Arrays
TradingVariable variables[];
TradingIdea ideas[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("=== FractalsGrok EA Started ===");
    Print("Monitoring Timeframe: ", EnumToString(MonitoringTimeframe));
    Print("Fractal Timeframe: ", EnumToString(FractalTimeframe));
    Print("Candle Shift: ", CandleShift);
    
    // Initialiser RSI
    rsiHandle = iRSI(_Symbol, MonitoringTimeframe, RSI_Period, PRICE_OPEN);
    if(rsiHandle == INVALID_HANDLE)
    {
        Print("Erreur: Impossible d'initialiser RSI");
        return(INIT_FAILED);
    }
    
    // Initialiser ATR handles
    atrHandleFractal = iATR(_Symbol, FractalTimeframe, 14);
    atrHandleFVG = iATR(_Symbol, FVGTimeframe, 14);
    atrHandleOrderBlock = iATR(_Symbol, OrderBlockTimeframe, 14);
    atrHandleGeneral = iATR(_Symbol, MonitoringTimeframe, 14);
    
    if(atrHandleFractal == INVALID_HANDLE || atrHandleFVG == INVALID_HANDLE || 
       atrHandleOrderBlock == INVALID_HANDLE || atrHandleGeneral == INVALID_HANDLE)
    {
        Print("Erreur: Impossible d'initialiser un ou plusieurs handles ATR");
        return(INIT_FAILED);
    }
    
    // Vérifier la disponibilité des données
    if(iBars(_Symbol, MonitoringTimeframe) < 100)
    {
        Print("Erreur: Pas assez de données historiques");
        return(INIT_FAILED);
    }
    
    // Initialisation des tableaux
    ArrayResize(variables, 0);
    ArrayResize(ideas, 0);
    
    trade.SetExpertMagicNumber(magicNumber);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
    if(atrHandleFractal != INVALID_HANDLE) IndicatorRelease(atrHandleFractal);
    if(atrHandleFVG != INVALID_HANDLE) IndicatorRelease(atrHandleFVG);
    if(atrHandleOrderBlock != INVALID_HANDLE) IndicatorRelease(atrHandleOrderBlock);
    if(atrHandleGeneral != INVALID_HANDLE) IndicatorRelease(atrHandleGeneral);
    Print("=== FractalsGrok EA Stopped ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(IsNewCandle(MonitoringTimeframe))
    {
        Print("--- Nouvelle bougie détectée sur ", EnumToString(MonitoringTimeframe), " ---");
        AnalyzeMarket();
    }
}

//+------------------------------------------------------------------+
//| Vérifier nouvelle bougie                                        |
//+------------------------------------------------------------------+
bool IsNewCandle(ENUM_TIMEFRAMES timeframe)
{
    datetime currentTime = iTime(_Symbol, timeframe, 0);
    if(currentTime != lastCandleTime)
    {
        lastCandleTime = currentTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Analyser le marché                                              |
//+------------------------------------------------------------------+
void AnalyzeMarket()
{
    // Vérifier spread
    long spread = 0.0;
    if(!SymbolInfoInteger(_Symbol, SYMBOL_SPREAD, spread))
    {
        Print("Erreur: Impossible de récupérer le spread");
        return;
    }
    spread *= _Point;
    if(spread > 20 * _Point)
    {
        Print("Spread trop élevé: ", spread/_Point, " points. Analyse annulée.");
        return;
    }
    
    IdentifyVariables();
    FormTradingIdeas();
    SynchronizeIdeas();
    ProcessIdeas();
}

//+------------------------------------------------------------------+
//| Identifier les variables du marché                              |
//+------------------------------------------------------------------+
void IdentifyVariables()
{
    ArrayResize(variables, 0);
    
    IdentifyFractals();
    IdentifyFVG();
    IdentifyOrderBlocks();
    
    Print("Variables identifiées: ", ArraySize(variables));
}

//+------------------------------------------------------------------+
//| Identifier les points fractals                                  |
//+------------------------------------------------------------------+
void IdentifyFractals()
{
    int bars = iBars(_Symbol, FractalTimeframe);
    if(bars < FractalPeriod * 2) return;
    
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(atrHandleFractal, 0, 0, 1, atr) <= 0)
    {
        Print("Erreur: Impossible de récupérer ATR pour FractalTimeframe");
        return;
    }
    
    for(int i = FractalPeriod; i < MathMin(bars - FractalPeriod, 50); i++)
    {
        if(IsFractalHigh(FractalTimeframe, i, FractalPeriod))
        {
            double level = iHigh(_Symbol, FractalTimeframe, i);
            if(MathAbs(level - iOpen(_Symbol, FractalTimeframe, 1)) > MinFractalATR * atr[0])
            {
                TradingVariable var;
                var.type = 1;
                var.impact = 1;
                var.level = level;
                var.upperLevel = level;
                var.lowerLevel = level;
                var.timeframe = FractalTimeframe;
                var.time = iTime(_Symbol, FractalTimeframe, i);
                var.isValid = true;
                AddVariable(var);
            }
        }
        
        if(IsFractalLow(FractalTimeframe, i, FractalPeriod))
        {
            double level = iLow(_Symbol, FractalTimeframe, i);
            if(MathAbs(level - iOpen(_Symbol, FractalTimeframe, 1)) > MinFractalATR * atr[0])
            {
                TradingVariable var;
                var.type = 1;
                var.impact = 1;
                var.level = level;
                var.upperLevel = level;
                var.lowerLevel = level;
                var.timeframe = FractalTimeframe;
                var.time = iTime(_Symbol, FractalTimeframe, i);
                var.isValid = true;
                AddVariable(var);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Vérifier si c'est un fractal high                              |
//+------------------------------------------------------------------+
bool IsFractalHigh(ENUM_TIMEFRAMES tf, int index, int period)
{
    double centerHigh = iHigh(_Symbol, tf, index);
    for(int i = 1; i <= period; i++)
    {
        if(iHigh(_Symbol, tf, index - i) >= centerHigh) return false;
        if(iHigh(_Symbol, tf, index + i) >= centerHigh) return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Vérifier si c'est un fractal low                               |
//+------------------------------------------------------------------+
bool IsFractalLow(ENUM_TIMEFRAMES tf, int index, int period)
{
    double centerLow = iLow(_Symbol, tf, index);
    for(int i = 1; i <= period; i++)
    {
        if(iLow(_Symbol, tf, index - i) <= centerLow) return false;
        if(iLow(_Symbol, tf, index + i) <= centerLow) return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Identifier les Fair Value Gaps                                  |
//+------------------------------------------------------------------+
void IdentifyFVG()
{
    int bars = iBars(_Symbol, FVGTimeframe);
    if(bars < 3) return;
    
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(atrHandleFVG, 0, 0, 1, atr) <= 0)
    {
        Print("Erreur: Impossible de récupérer ATR pour FVGTimeframe");
        return;
    }
    
    for(int i = 2; i < MathMin(bars, MaxFVGLookback); i++)
    {
        double gap_low = iLow(_Symbol, FVGTimeframe, i-2);
        double gap_high = iHigh(_Symbol, FVGTimeframe, i);
        double middle_high = iHigh(_Symbol, FVGTimeframe, i-1);
        double middle_low = iLow(_Symbol, FVGTimeframe, i-1);
        
        if(gap_low > middle_high)
        {
            double gapSize = (gap_low - middle_high) / _Point;
            if(gapSize >= MinFVGSize && gapSize > atr[0])
            {
                TradingVariable var;
                var.type = 0;
                var.impact = 1;
                var.level = (gap_low + middle_high) / 2;
                var.upperLevel = gap_low;
                var.lowerLevel = middle_high;
                var.timeframe = FVGTimeframe;
                var.time = iTime(_Symbol, FVGTimeframe, i-1);
                var.isValid = true;
                AddVariable(var);
            }
        }
        
        if(gap_high < middle_low)
        {
            double gapSize = (middle_low - gap_high) / _Point;
            if(gapSize >= MinFVGSize && gapSize > atr[0])
            {
                TradingVariable var;
                var.type = 0;
                var.impact = 1;
                var.level = (gap_high + middle_low) / 2;
                var.upperLevel = middle_low;
                var.lowerLevel = gap_high;
                var.timeframe = FVGTimeframe;
                var.time = iTime(_Symbol, FVGTimeframe, i-1);
                var.isValid = true;
                AddVariable(var);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Identifier les Order Blocks                                     |
//+------------------------------------------------------------------+
void IdentifyOrderBlocks()
{
    int bars = iBars(_Symbol, OrderBlockTimeframe);
    if(bars < 10) return;
    
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(atrHandleOrderBlock, 0, 0, 1, atr) <= 0)
    {
        Print("Erreur: Impossible de récupérer ATR pour OrderBlockTimeframe");
        return;
    }
    
    for(int i = 5; i < MathMin(bars, OrderBlockLookback); i++)
    {
        if(iOpen(_Symbol, OrderBlockTimeframe, i) > iOpen(_Symbol, OrderBlockTimeframe, i-1) &&
           iOpen(_Symbol, OrderBlockTimeframe, i-1) < iOpen(_Symbol, OrderBlockTimeframe, i-2))
        {
            double blockSize = (iHigh(_Symbol, OrderBlockTimeframe, i) - iLow(_Symbol, OrderBlockTimeframe, i)) / _Point;
            if(blockSize >= MinOrderBlockSize && blockSize > atr[0])
            {
                TradingVariable var;
                var.type = 2;
                var.impact = 0;
                var.level = (iHigh(_Symbol, OrderBlockTimeframe, i) + iLow(_Symbol, OrderBlockTimeframe, i)) / 2;
                var.upperLevel = iHigh(_Symbol, OrderBlockTimeframe, i);
                var.lowerLevel = iLow(_Symbol, OrderBlockTimeframe, i);
                var.timeframe = OrderBlockTimeframe;
                var.time = iTime(_Symbol, OrderBlockTimeframe, i);
                var.isValid = true;
                AddVariable(var);
            }
        }
        
        if(iOpen(_Symbol, OrderBlockTimeframe, i) < iOpen(_Symbol, OrderBlockTimeframe, i-1) &&
           iOpen(_Symbol, OrderBlockTimeframe, i-1) > iOpen(_Symbol, OrderBlockTimeframe, i-2))
        {
            double blockSize = (iHigh(_Symbol, OrderBlockTimeframe, i) - iLow(_Symbol, OrderBlockTimeframe, i)) / _Point;
            if(blockSize >= MinOrderBlockSize && blockSize > atr[0])
            {
                TradingVariable var;
                var.type = 2;
                var.impact = 0;
                var.level = (iHigh(_Symbol, OrderBlockTimeframe, i) + iLow(_Symbol, OrderBlockTimeframe, i)) / 2;
                var.upperLevel = iHigh(_Symbol, OrderBlockTimeframe, i);
                var.lowerLevel = iLow(_Symbol, OrderBlockTimeframe, i);
                var.timeframe = OrderBlockTimeframe;
                var.time = iTime(_Symbol, OrderBlockTimeframe, i);
                var.isValid = true;
                AddVariable(var);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Ajouter une variable au tableau                                 |
//+------------------------------------------------------------------+
void AddVariable(TradingVariable &var)
{
    int size = ArraySize(variables);
    ArrayResize(variables, size + 1);
    variables[size] = var;
}

//+------------------------------------------------------------------+
//| Former les idées de trading                                     |
//+------------------------------------------------------------------+
void FormTradingIdeas()
{
    ArrayResize(ideas, 0);
    
    for(int i = 0; i < ArraySize(variables); i++)
    {
        for(int j = 0; j < ArraySize(variables); j++)
        {
            if(i == j) continue;
            if(IsValidIdeaCombination(variables[i], variables[j]))
            {
                TradingIdea idea;
                idea.initialZone = variables[i];
                idea.targetZone = variables[j];
                idea.ideaType = DetermineIdeaType(variables[i], variables[j]);
                idea.isValidated = false;
                idea.probability = CalculateProbability(variables[i], variables[j]);
                idea.formationTime = TimeCurrent();
                AddIdea(idea);
            }
        }
    }
    
    Print("Idées formées: ", ArraySize(ideas));
}

//+------------------------------------------------------------------+
//| Vérifier si c'est une combinaison valide                       |
//+------------------------------------------------------------------+
bool IsValidIdeaCombination(TradingVariable &initial, TradingVariable &target)
{
    if(target.impact != 1) return false;
    if(initial.time >= target.time) return false;
    
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(atrHandleGeneral, 0, 0, 1, atr) <= 0)
    {
        Print("Erreur: Impossible de récupérer ATR pour IsValidIdeaCombination");
        return false;
    }
    
    if(MathAbs(target.level - initial.level) < atr[0]) return false;
    return true;
}

//+------------------------------------------------------------------+
//| Déterminer le type d'idée                                      |
//+------------------------------------------------------------------+
int DetermineIdeaType(TradingVariable &initial, TradingVariable &target)
{
    if(initial.timeframe == GlobalTimeframe || target.timeframe == GlobalTimeframe)
        return 0;
    return 1;
}

//+------------------------------------------------------------------+
//| Calculer la probabilité d'une idée                             |
//+------------------------------------------------------------------+
double CalculateProbability(TradingVariable &initial, TradingVariable &target)
{
    double prob = 0.5;
    if(initial.impact == 1) prob += 0.15;
    if(target.impact == 1) prob += 0.25;
    if(initial.type == 0 || initial.type == 1) prob += 0.1;
    if(target.type == 0 || target.type == 1) prob += 0.1;
    
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(atrHandleGeneral, 0, 0, 1, atr) <= 0)
    {
        Print("Erreur: Impossible de récupérer ATR pour CalculateProbability");
        return prob;
    }
    
    double distance = MathAbs(target.level - initial.level);
    if(distance > 2 * atr[0]) prob += 0.1;
    
    return MathMin(prob, 1.0);
}

//+------------------------------------------------------------------+
//| Ajouter une idée au tableau                                    |
//+------------------------------------------------------------------+
void AddIdea(TradingIdea &idea)
{
    int size = ArraySize(ideas);
    ArrayResize(ideas, size + 1);
    ideas[size] = idea;
}

//+------------------------------------------------------------------+
//| Synchroniser les idées                                         |
//+------------------------------------------------------------------+
void SynchronizeIdeas()
{
    for(int i = 0; i < ArraySize(ideas); i++)
    {
        if(ideas[i].ideaType == 0)
        {
            for(int j = 0; j < ArraySize(ideas); j++)
            {
                if(ideas[j].ideaType == 1 && j != i)
                {
                    if(SameDirection(ideas[i], ideas[j]))
                    {
                        ideas[j].probability += 0.25;
                        Print("Idées synchronisées trouvées - Probabilité augmentée pour idée ", j);
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Vérifier même direction                                         |
//+------------------------------------------------------------------+
bool SameDirection(TradingIdea &global, TradingIdea &local)
{
    bool globalBullish = global.targetZone.level > global.initialZone.level;
    bool localBullish = local.targetZone.level > local.initialZone.level;
    return globalBullish == localBullish;
}

//+------------------------------------------------------------------+
//| Traiter les idées                                              |
//+------------------------------------------------------------------+
void ProcessIdeas()
{
    for(int i = 0; i < ArraySize(ideas); i++)
    {
        if(CheckInvalidation(ideas[i])) continue;
        
        if(UseStandardValidation)
        {
            if(ValidateIdea(ideas[i]))
            {
                ExecuteTrade(ideas[i]);
            }
        }
        
        if(AllowInstantDecision && ideas[i].probability >= HighProbabilityThreshold)
        {
            InstantDecision(ideas[i]);
        }
    }
}

//+------------------------------------------------------------------+
//| Détecter les motifs de bougies                                 |
//+------------------------------------------------------------------+
bool DetectCandlePattern(ENUM_TIMEFRAMES tf, bool isBuy)
{
    double open1 = iOpen(_Symbol, tf, 1);
    double close1 = iClose(_Symbol, tf, 1);
    double high1 = iHigh(_Symbol, tf, 1);
    double low1 = iLow(_Symbol, tf, 1);
    double open2 = iOpen(_Symbol, tf, 2);
    double close2 = iClose(_Symbol, tf, 2);
    
    double body1 = MathAbs(close1 - open1);
    double body2 = MathAbs(close2 - open2);
    double totalRange1 = high1 - low1;
    
    // Bullish Engulfing (pour Buy)
    if(isBuy)
    {
        if(close2 < open2 && close1 > open1 && close1 > open2 && open1 < close2 && body1 >= body2 * 0.5)
        {
            Print("Bullish Engulfing détecté");
            return true;
        }
        // Pin Bar haussier
        if(close1 > open1 && (high1 - close1) < 0.4 * totalRange1 && (open1 - low1) > 0.4 * totalRange1)
        {
            Print("Pin Bar haussier détecté");
            return true;
        }
    }
    // Bearish Engulfing (pour Sell)
    else
    {
        if(close2 > open2 && close1 < open1 && close1 < open2 && open1 > close2 && body1 >= body2 * 0.5)
        {
            Print("Bearish Engulfing détecté");
            return true;
        }
        // Pin Bar baissier
        if(close1 < open1 && (close1 - low1) < 0.4 * totalRange1 && (high1 - open1) > 0.4 * totalRange1)
        {
            Print("Pin Bar baissier détecté");
            return true;
        }
    }
    
    Print("Aucun motif de bougie valide détecté");
    return false;
}

//+------------------------------------------------------------------+
//| Valider une idée                                               |
//+------------------------------------------------------------------+
bool ValidateIdea(TradingIdea &idea)
{
    ENUM_TIMEFRAMES lowerTF = GetLowerTimeframe(idea.initialZone.timeframe);
    double currentPrice = GetCurrentPrice(idea.initialZone.timeframe);
    
    if(IsZoneTested(idea.initialZone, currentPrice))
    {
        bool isBuy = idea.targetZone.level > idea.initialZone.level;
        
        if(RequireCandlePatterns)
        {
            if(DetectCandlePattern(MonitoringTimeframe, isBuy))
            {
                return true;
            }
            Print("Idée rejetée: Aucun motif de bougie valide");
            return false;
        }
        
        if(FindConfirmationZone(lowerTF))
        {
            double rsi[];
            ArraySetAsSeries(rsi, true);
            if(CopyBuffer(rsiHandle, 0, 0, 3, rsi) <= 0)
            {
                Print("Erreur: Impossible de récupérer RSI");
                return false;
            }
            if(isBuy && rsi[1] <= RSI_Oversold) return true;
            if(!isBuy && rsi[1] >= RSI_Overbought) return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Obtenir le prix actuel selon le décalage                       |
//+------------------------------------------------------------------+
double GetCurrentPrice(ENUM_TIMEFRAMES timeframe)
{
    return iOpen(_Symbol, timeframe, CandleShift);
}

//+------------------------------------------------------------------+
//| Vérifier si une zone est testée                                |
//+------------------------------------------------------------------+
bool IsZoneTested(TradingVariable &var, double price)
{
    if(var.type == 0)
    {
        return price >= var.lowerLevel && price <= var.upperLevel;
    }
    else
    {
        double tolerance = 100 * _Point;
        return MathAbs(price - var.level) <= tolerance;
    }
}

//+------------------------------------------------------------------+
//| Trouver zone de confirmation                                    |
//+------------------------------------------------------------------+
bool FindConfirmationZone(ENUM_TIMEFRAMES tf)
{
    double high1 = iHigh(_Symbol, tf, 1);
    double low1 = iLow(_Symbol, tf, 1);
    double high2 = iHigh(_Symbol, tf, 2);
    double low2 = iLow(_Symbol, tf, 2);
    
    return (high1 > high2 && low1 > low2) || (high1 < high2 && low1 < low2);
}

//+------------------------------------------------------------------+
//| Obtenir timeframe inférieur                                    |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetLowerTimeframe(ENUM_TIMEFRAMES tf)
{
    switch(tf)
    {
        case PERIOD_D1: return PERIOD_H4;
        case PERIOD_H4: return PERIOD_H1;
        case PERIOD_H1: return PERIOD_M15;
        case PERIOD_M15: return PERIOD_M5;
        case PERIOD_M5: return PERIOD_M1;
        default: return PERIOD_M1;
    }
}

//+------------------------------------------------------------------+
//| Vérifier invalidation                                          |
//+------------------------------------------------------------------+
bool CheckInvalidation(TradingIdea &idea)
{
    double currentPrice = GetCurrentPrice(idea.initialZone.timeframe);
    
    if(idea.initialZone.type == 0)
    {
        if(currentPrice > idea.initialZone.upperLevel + 50*_Point ||
           currentPrice < idea.initialZone.lowerLevel - 50*_Point)
        {
            Print("Idée invalidée - Zone complètement cassée");
            return true;
        }
    }
    
    if(idea.initialZone.type == 1)
    {
        if(IsZoneTested(idea.initialZone, currentPrice) && !HasReactionAfterTest(idea.initialZone))
        {
            Print("Idée invalidée - Aucune réaction au niveau");
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Vérifier réaction après test                                   |
//+------------------------------------------------------------------+
bool HasReactionAfterTest(TradingVariable &var)
{
    double open1 = iOpen(_Symbol, var.timeframe, 1);
    double open2 = iOpen(_Symbol, var.timeframe, 2);
    
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(atrHandleGeneral, 0, 0, 1, atr) <= 0)
    {
        Print("Erreur: Impossible de récupérer ATR pour HasReactionAfterTest");
        return false;
    }
    
    return MathAbs(open1 - open2) > atr[0] * 0.5;
}

void CalculateAllPositions(int &count_buys,int &count_sells)
  {
   count_buys=0;
   count_sells=0;
   for(int i=PositionsTotal()-1; i>=0; i--)
      if(m_position.SelectByIndex(i)) // selects the position by index for further access to its properties
         //if(m_position.Symbol()==m_symbol.Name() && m_position.Magic()==InpMagic)
        {
         if(m_position.PositionType()==POSITION_TYPE_BUY && m_position.Magic() == magicNumber && m_position.Symbol() == _Symbol)
            count_buys++;
         if(m_position.PositionType()==POSITION_TYPE_SELL && m_position.Magic() == magicNumber && m_position.Symbol() == _Symbol)
            count_sells++;
        }
//---
   //Print(count_buys);
   //Print(count_sells);

   return;
  }
  
  int CalculateAllPositionsTotal()
  {
   int count_buys=0;
   int count_sells=0;
   for(int i=PositionsTotal()-1; i>=0; i--)
      if(m_position.SelectByIndex(i)) // selects the position by index for further access to its properties
         //if(m_position.Symbol()==m_symbol.Name() && m_position.Magic()==InpMagic)
        {
         if(m_position.PositionType()==POSITION_TYPE_BUY && m_position.Magic() == magicNumber && m_position.Symbol() == _Symbol)
            count_buys++;
         if(m_position.PositionType()==POSITION_TYPE_SELL && m_position.Magic() == magicNumber && m_position.Symbol() == _Symbol)
            count_sells++;
        }
//---
   //Print(count_buys);
   //Print(count_sells);

   return count_buys + count_sells;
  }



//+------------------------------------------------------------------+
//| Décision instantanée                                           |
//+------------------------------------------------------------------+
void InstantDecision(TradingIdea &idea)
{

    if(CalculateAllPositionsTotal() >= MaxPositions)
    {
        Print("Décision instantanée rejetée: Maximum de positions atteint");
        return;
    }
    
    bool isBuy = idea.targetZone.level > idea.initialZone.level;
    if(RequireCandlePatterns && !DetectCandlePattern(MonitoringTimeframe, isBuy))
    {
        Print("Décision instantanée rejetée: Aucun motif de bougie valide");
        return;
    }
    
    Print("Décision instantanée pour idée haute probabilité: ", idea.probability);
    ExecuteTrade(idea);
}

//+------------------------------------------------------------------+
//| Vérifier la validité des stops                                 |
//+------------------------------------------------------------------+
bool CheckStopLevels(double entryPrice, double stopLoss, double takeProfit, bool isBuy)
{
    double marketPrice = SymbolInfoDouble(_Symbol, isBuy ? SYMBOL_ASK : SYMBOL_BID);
    long stopLevelPoints = 0;
    if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL, stopLevelPoints))
    {
        Print("Erreur: Impossible de récupérer SYMBOL_TRADE_STOPS_LEVEL, utilisation valeur par défaut 10");
        stopLevelPoints = 10;
    }
    double minSLDistance = MathMax(stopLevelPoints, MinSLPoints) * _Point;
    double minTPDistance = MathMax(stopLevelPoints, MinTPPoints) * _Point;
    
    Print("CheckStopLevels: Entry=", entryPrice, ", SL=", stopLoss, ", TP=", takeProfit, 
          ", MarketPrice=", marketPrice, ", StopLevelPoints=", stopLevelPoints, 
          ", MinSLDistance=", minSLDistance, ", MinTPDistance=", minTPDistance);
    
    if(isBuy)
    {
        if(stopLoss >= entryPrice - minSLDistance || stopLoss >= marketPrice - minSLDistance)
        {
            Print("Erreur: SL invalide pour Buy (trop proche ou au-dessus de l'entrée)");
            return false;
        }
        if(takeProfit <= entryPrice + minTPDistance || takeProfit <= marketPrice + minTPDistance)
        {
            Print("Erreur: TP invalide pour Buy (trop proche ou en-dessous de l'entrée)");
            return false;
        }
    }
    else
    {
        if(stopLoss <= entryPrice + minSLDistance || stopLoss <= marketPrice + minSLDistance)
        {
            Print("Erreur: SL invalide pour Sell (trop proche ou en-dessous de l'entrée)");
            return false;
        }
        if(takeProfit >= entryPrice - minTPDistance || takeProfit >= marketPrice - minTPDistance)
        {
            Print("Erreur: TP invalide pour Sell (trop proche ou au-dessus de l'entrée)");
            return false;
        }
    }
    
    return true;
}



//+------------------------------------------------------------------+
//| Exécuter un trade                                              |
//+------------------------------------------------------------------+
void ExecuteTrade(TradingIdea &idea)
{

    Sleep(100);

    if(CalculateAllPositionsTotal() >= MaxPositions)
    {
        Print("Trade rejeté: Maximum de positions atteint");
        return;
    }
    
    bool isBuy = idea.targetZone.level > idea.initialZone.level;
    double entryPrice = NormalizeDouble(idea.initialZone.level, _Digits);
    double stopLoss = CalculateStopLoss(idea, entryPrice);
    double takeProfit = CalculateTakeProfit(idea, entryPrice, stopLoss);
    double lotSize = CalculateLotSize(entryPrice, stopLoss);
    
    if(lotSize <= 0)
    {
        Print("Erreur: Taille de lot invalide (", lotSize, ")");
        return;
    }
    
    // Vérifier la validité des stops
    if(!CheckStopLevels(entryPrice, stopLoss, takeProfit, isBuy))
    {
        Print("Trade annulé: Stops invalides");
        return;
    }
    
    if(isBuy)
    {
        if(trade.Buy(lotSize, _Symbol, entryPrice, stopLoss, takeProfit, "FractalsGrok Strategy"))
        {
            Print("Position BUY ouverte - Entry: ", entryPrice, " SL: ", stopLoss, " TP: ", takeProfit, " Lot: ", lotSize);
        }
        else
        {
            Print("Erreur ouverture BUY: ", trade.ResultRetcode(), " - Comment: ", trade.ResultComment());
        }
    }
    else
    {
        if(trade.Sell(lotSize, _Symbol, entryPrice, stopLoss, takeProfit, "FractalsGrok Strategy"))
        {
            Print("Position SELL ouverte - Entry: ", entryPrice, " SL: ", stopLoss, " TP: ", takeProfit, " Lot: ", lotSize);
        }
        else
        {
            Print("Erreur ouverture SELL: ", trade.ResultRetcode(), " - Comment: ", trade.ResultComment());
        }
    }
}

//+------------------------------------------------------------------+
//| Calculer stop loss                                             |
//+------------------------------------------------------------------+
double CalculateStopLoss(TradingIdea &idea, double entryPrice)
{
    double stopLoss;
    bool isBuy = idea.targetZone.level > idea.initialZone.level;
    
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(atrHandleGeneral, 0, 0, 1, atr) <= 0)
    {
        Print("Erreur: Impossible de récupérer ATR pour CalculateStopLoss");
        return entryPrice; // Fallback
    }
    
    long stopLevelPoints = 0;
    if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL, stopLevelPoints))
    {
        Print("Erreur: Impossible de récupérer SYMBOL_TRADE_STOPS_LEVEL, utilisation valeur par défaut 10");
        stopLevelPoints = 10;
    }
    double minSLDistance = MathMax(stopLevelPoints, MinSLPoints) * _Point;
    
    if(idea.initialZone.type == 0) // FVG
    {
        if(isBuy)
            stopLoss = idea.initialZone.lowerLevel - MathMax(atr[0], minSLDistance);
        else
            stopLoss = idea.initialZone.upperLevel + MathMax(atr[0], minSLDistance);
    }
    else // Fractal or OrderBlock
    {
        if(isBuy)
            stopLoss = idea.initialZone.level - MathMax(atr[0] * 1.5, minSLDistance);
        else
            stopLoss = idea.initialZone.level + MathMax(atr[0] * 1.5, minSLDistance);
    }
    
    return NormalizeDouble(stopLoss, _Digits);
}

//+------------------------------------------------------------------+
//| Calculer take profit                                           |
//+------------------------------------------------------------------+
double CalculateTakeProfit(TradingIdea &idea, double entryPrice, double stopLoss)
{
    long stopLevelPoints = 0;
    if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL, stopLevelPoints))
    {
        Print("Erreur: Impossible de récupérer SYMBOL_TRADE_STOPS_LEVEL, utilisation valeur par défaut 10");
        stopLevelPoints = 10;
    }
    double minTPDistance = MathMax(stopLevelPoints, MinTPPoints) * _Point;
    
    double riskDistance = MathAbs(entryPrice - stopLoss);
    double rewardDistance = MathMax(riskDistance * RewardRiskRatio, minTPDistance);
    
    bool isBuy = idea.targetZone.level > idea.initialZone.level;
    
    if(isBuy)
        return NormalizeDouble(entryPrice + rewardDistance, _Digits);
    return NormalizeDouble(entryPrice - rewardDistance, _Digits);
}

//+------------------------------------------------------------------+
//| Calculer taille de position                                    |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLoss)
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * RiskPercent / 100.0;
    double riskDistance = MathAbs(entryPrice - stopLoss);
    
    double tickValue = 0.0;
    if(!SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE, tickValue))
    {
        Print("Erreur: Impossible de récupérer SYMBOL_TRADE_TICK_VALUE, utilisation valeur par défaut 1.0");
        tickValue = 1.0;
    }
    
    double tickSize = 0.0;
    if(!SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE, tickSize))
    {
        Print("Erreur: Impossible de récupérer SYMBOL_TRADE_TICK_SIZE, utilisation valeur par défaut ", _Point);
        tickSize = _Point;
    }
    
    double lotSize = riskAmount / (riskDistance / tickSize * tickValue);
    
    double minLot = 0.0;
    if(!SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN, minLot))
    {
        Print("Erreur: Impossible de récupérer SYMBOL_VOLUME_MIN, utilisation valeur par défaut 0.01");
        minLot = 0.01;
    }
    
    double maxLot = 0.0;
    if(!SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX, maxLot))
    {
        Print("Erreur: Impossible de récupérer SYMBOL_VOLUME_MAX, utilisation valeur par défaut 100.0");
        maxLot = 100.0;
    }
    
    double stepLot = 0.0;
    if(!SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP, stepLot))
    {
        Print("Erreur: Impossible de récupérer SYMBOL_VOLUME_STEP, utilisation valeur par défaut 0.01");
        stepLot = 0.01;
    }
    
    Print("CalculateLotSize: RiskAmount=", riskAmount, ", RiskDistance=", riskDistance, 
          ", TickValue=", tickValue, ", TickSize=", tickSize, ", MinLot=", minLot, 
          ", MaxLot=", maxLot, ", StepLot=", stepLot, ", Calculated Lot=", lotSize);
    
    lotSize = MathMax(minLot, lotSize);
    lotSize = MathMin(maxLot, lotSize);
    lotSize = MathRound(lotSize / stepLot) * stepLot;
    
    return NormalizeDouble(lotSize, 2);
}