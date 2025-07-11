//+------------------------------------------------------------------+
//|                                          SimplifiedTradingEA.mq5 |
//|                                  Copyright 2025, Trading Strategy |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Trading Strategy"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== SURVEILLANCE DU MARCHÉ ==="
input ENUM_TIMEFRAMES MonitoringTimeframe = PERIOD_M1;    // Timeframe de surveillance (isNewCandle)
input int CandleShift = 1;                                // Décalage bougie (0=current, 1=previous)

input group "=== FRACTALS SETTINGS ==="
input ENUM_TIMEFRAMES FractalTimeframe = PERIOD_H1;       // Timeframe pour les fractals
input int FractalPeriod = 5;                              // Période des fractals (indépendant de la surveillance)

input group "=== FAIR VALUE GAP SETTINGS ==="
input ENUM_TIMEFRAMES FVGTimeframe = PERIOD_H1;           // Timeframe pour les FVG
input double MinFVGSize = 10.0;                           // Taille minimale FVG en points
input int MaxFVGLookback = 100;                           // Nombre de bougies à analyser pour FVG

input group "=== ORDER BLOCK SETTINGS ==="
input ENUM_TIMEFRAMES OrderBlockTimeframe = PERIOD_H1;    // Timeframe pour les Order Blocks
input int OrderBlockLookback = 50;                        // Nombre de bougies pour Order Blocks
input double MinOrderBlockSize = 20.0;                    // Taille minimale Order Block en points

input group "=== VALIDATION SETTINGS ==="
input bool UseStandardValidation = true;                  // Utiliser validation standard
input bool AllowInstantDecision = true;                   // Permettre décision instantanée
input double HighProbabilityThreshold = 0.75;             // Seuil haute probabilité (0-1)

input group "=== TRADE MANAGEMENT ==="
input double RiskPercent = 2.0;                           // Risque par trade en %
input double RewardRiskRatio = 2.0;                       // Ratio Reward/Risk
input int MaxPositions = 1;                               // Nombre max de positions

input group "=== TIMEFRAME HIERARCHY ==="
input ENUM_TIMEFRAMES GlobalTimeframe = PERIOD_D1;        // Timeframe global
input ENUM_TIMEFRAMES LocalTimeframe = PERIOD_H1;         // Timeframe local

//--- Global Variables
CTrade trade;
datetime lastCandleTime = 0;

//--- Structures
struct TradingVariable
{
    int type;           // 0=FVG, 1=Fractal, 2=OrderBlock, 3=RejectionBlock
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
    TradingVariable targetZone;  // Changé de 'finalZone' à 'targetZone'
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
    Print("=== Simplified Trading EA Started ===");
    Print("Monitoring Timeframe: ", EnumToString(MonitoringTimeframe));
    Print("Fractal Timeframe: ", EnumToString(FractalTimeframe));
    Print("Candle Shift: ", CandleShift);
    
    // Initialisation des tableaux
    ArrayResize(variables, 0);
    ArrayResize(ideas, 0);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("=== Simplified Trading EA Stopped ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Vérifier nouvelle bougie sur le timeframe de surveillance
    if(IsNewCandle(MonitoringTimeframe))
    {
        Print("--- Nouvelle bougie détectée sur ", EnumToString(MonitoringTimeframe), " ---");
        
        // Analyser le marché
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
//| Analyser le marché (fonction principale)                        |
//+------------------------------------------------------------------+
void AnalyzeMarket()
{
    // 1. Identifier les variables
    IdentifyVariables();
    
    // 2. Former les idées de trading
    FormTradingIdeas();
    
    // 3. Synchroniser les idées globales et locales
    SynchronizeIdeas();
    
    // 4. Validation et exécution
    ProcessIdeas();
}

//+------------------------------------------------------------------+
//| Identifier les variables du marché                              |
//+------------------------------------------------------------------+
void IdentifyVariables()
{
    ArrayResize(variables, 0);
    
    // Identifier les Fractals (HAUT IMPACT)
    IdentifyFractals();
    
    // Identifier les Fair Value Gaps (HAUT IMPACT)  
    IdentifyFVG();
    
    // Identifier les Order Blocks (FAIBLE IMPACT)
    IdentifyOrderBlocks();
    
    Print("Variables identifiées: ", ArraySize(variables));
}

//+------------------------------------------------------------------+
//| Identifier les points fractals                                  |
//+------------------------------------------------------------------+
void IdentifyFractals()
{
    // Utiliser les données du timeframe spécifique aux fractals
    int bars = iBars(_Symbol, FractalTimeframe);
    if(bars < FractalPeriod * 2) return;
    
    // Identifier les fractal highs et lows
    for(int i = FractalPeriod; i < MathMin(bars - FractalPeriod, 100); i++)
    {
        // Fractal High
        if(IsFractalHigh(FractalTimeframe, i, FractalPeriod))
        {
            TradingVariable var;
            var.type = 1; // Fractal
            var.impact = 1; // High impact
            var.level = iHigh(_Symbol, FractalTimeframe, i);
            var.upperLevel = var.level;
            var.lowerLevel = var.level;
            var.timeframe = FractalTimeframe;
            var.time = iTime(_Symbol, FractalTimeframe, i);
            var.isValid = true;
            
            AddVariable(var);
        }
        
        // Fractal Low
        if(IsFractalLow(FractalTimeframe, i, FractalPeriod))
        {
            TradingVariable var;
            var.type = 1; // Fractal
            var.impact = 1; // High impact
            var.level = iLow(_Symbol, FractalTimeframe, i);
            var.upperLevel = var.level;
            var.lowerLevel = var.level;
            var.timeframe = FractalTimeframe;
            var.time = iTime(_Symbol, FractalTimeframe, i);
            var.isValid = true;
            
            AddVariable(var);
        }
    }
}

//+------------------------------------------------------------------+
//| Vérifier si c'est un fractal high                              |
//+------------------------------------------------------------------+
bool IsFractalHigh(ENUM_TIMEFRAMES tf, int index, int period)
{
    double centerHigh = iHigh(_Symbol, tf, index);
    
    // Vérifier les bougies à gauche et à droite
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
    
    // Vérifier les bougies à gauche et à droite
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
    
    for(int i = 2; i < MathMin(bars, MaxFVGLookback); i++)
    {
        // FVG Bullish
        double gap_low = iLow(_Symbol, FVGTimeframe, i-2);
        double gap_high = iHigh(_Symbol, FVGTimeframe, i);
        double middle_high = iHigh(_Symbol, FVGTimeframe, i-1);
        double middle_low = iLow(_Symbol, FVGTimeframe, i-1);
        
        if(gap_low > middle_high) // Gap bullish
        {
            double gapSize = (gap_low - middle_high) / _Point;
            if(gapSize >= MinFVGSize)
            {
                TradingVariable var;
                var.type = 0; // FVG
                var.impact = 1; // High impact
                var.level = (gap_low + middle_high) / 2;
                var.upperLevel = gap_low;
                var.lowerLevel = middle_high;
                var.timeframe = FVGTimeframe;
                var.time = iTime(_Symbol, FVGTimeframe, i-1);
                var.isValid = true;
                
                AddVariable(var);
            }
        }
        
        // FVG Bearish
        if(gap_high < middle_low) // Gap bearish
        {
            double gapSize = (middle_low - gap_high) / _Point;
            if(gapSize >= MinFVGSize)
            {
                TradingVariable var;
                var.type = 0; // FVG
                var.impact = 1; // High impact
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
    
    for(int i = 5; i < MathMin(bars, OrderBlockLookback); i++)
    {
        // Order Block Bullish (dernière bougie bearish avant mouvement bullish)
        if(iClose(_Symbol, OrderBlockTimeframe, i) < iOpen(_Symbol, OrderBlockTimeframe, i) && // Bougie bearish
           iClose(_Symbol, OrderBlockTimeframe, i-1) > iOpen(_Symbol, OrderBlockTimeframe, i-1)) // Bougie suivante bullish
        {
            double blockSize = (iHigh(_Symbol, OrderBlockTimeframe, i) - iLow(_Symbol, OrderBlockTimeframe, i)) / _Point;
            if(blockSize >= MinOrderBlockSize)
            {
                TradingVariable var;
                var.type = 2; // Order Block
                var.impact = 0; // Low impact
                var.level = (iHigh(_Symbol, OrderBlockTimeframe, i) + iLow(_Symbol, OrderBlockTimeframe, i)) / 2;
                var.upperLevel = iHigh(_Symbol, OrderBlockTimeframe, i);
                var.lowerLevel = iLow(_Symbol, OrderBlockTimeframe, i);
                var.timeframe = OrderBlockTimeframe;
                var.time = iTime(_Symbol, OrderBlockTimeframe, i);
                var.isValid = true;
                
                AddVariable(var);
            }
        }
        
        // Order Block Bearish (dernière bougie bullish avant mouvement bearish)
        if(iClose(_Symbol, OrderBlockTimeframe, i) > iOpen(_Symbol, OrderBlockTimeframe, i) && // Bougie bullish
           iClose(_Symbol, OrderBlockTimeframe, i-1) < iOpen(_Symbol, OrderBlockTimeframe, i-1)) // Bougie suivante bearish
        {
            double blockSize = (iHigh(_Symbol, OrderBlockTimeframe, i) - iLow(_Symbol, OrderBlockTimeframe, i)) / _Point;
            if(blockSize >= MinOrderBlockSize)
            {
                TradingVariable var;
                var.type = 2; // Order Block
                var.impact = 0; // Low impact
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
    
    // Former des idées basées sur les variables identifiées
    for(int i = 0; i < ArraySize(variables); i++)
    {
        for(int j = 0; j < ArraySize(variables); j++)
        {
            if(i == j) continue;
            
            // Former une idée si logique appropriée
            if(IsValidIdeaCombination(variables[i], variables[j]))
            {
                TradingIdea idea;
                idea.initialZone = variables[i];
                idea.targetZone = variables[j];  // Utilise targetZone au lieu de finalZone
                idea.ideaType = DetermineIdeaType(variables[i], variables[j]);
                idea.isValidated = false;
                idea.probability = CalculateProbability(variables[i], variables[j]);
                idea.isTroubleArea = false;
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
    // La zone cible devrait prioritairement être à haut impact
    if(target.impact != 1) return false;
    
    // Vérifier la logique temporelle
    if(initial.time >= target.time) return false;
    
    // Autres vérifications logiques
    return true;
}

//+------------------------------------------------------------------+
//| Déterminer le type d'idée                                      |
//+------------------------------------------------------------------+
int DetermineIdeaType(TradingVariable &initial, TradingVariable &target)
{
    // Si un des timeframes est global, c'est une idée globale
    if(initial.timeframe == GlobalTimeframe || target.timeframe == GlobalTimeframe)
        return 0; // Global
    else
        return 1; // Local
}

//+------------------------------------------------------------------+
//| Calculer la probabilité d'une idée                             |
//+------------------------------------------------------------------+
double CalculateProbability(TradingVariable &initial, TradingVariable &target)
{
    double prob = 0.5; // Base
    
    // Bonus pour variables haut impact
    if(initial.impact == 1) prob += 0.1;
    if(target.impact == 1) prob += 0.2;
    
    // Bonus pour FVG et Fractals
    if(initial.type == 0 || initial.type == 1) prob += 0.1; // FVG ou Fractal
    if(target.type == 0 || target.type == 1) prob += 0.1;
    
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
    // Chercher des idées synchronisées (même direction)
    for(int i = 0; i < ArraySize(ideas); i++)
    {
        if(ideas[i].ideaType == 0) // Idée globale
        {
            for(int j = 0; j < ArraySize(ideas); j++)
            {
                if(ideas[j].ideaType == 1 && j != i) // Idée locale
                {
                    if(SameDirection(ideas[i], ideas[j]))
                    {
                        ideas[j].probability += 0.2; // Bonus synchronisation
                        Print("Idées synchronisées trouvées - Probabilité augmentée");
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
        // Vérifier invalidation
        if(CheckInvalidation(ideas[i]))
        {
            continue;
        }
        
        // Processus de validation ou décision instantanée
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
//| Valider une idée                                               |
//+------------------------------------------------------------------+
bool ValidateIdea(TradingIdea &idea)
{
    // Validation par timeframe inférieur
    ENUM_TIMEFRAMES lowerTF = GetLowerTimeframe(idea.initialZone.timeframe);
    
    // Vérifier si la zone initiale a été testée
    double currentPrice = GetCurrentPrice(CandleShift);
    
    if(IsZoneTested(idea.initialZone, currentPrice))
    {
        // Chercher formation de zone de confirmation
        if(FindConfirmationZone(lowerTF))
        {
            idea.isValidated = true;
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Obtenir le prix actuel selon le décalage                       |
//+------------------------------------------------------------------+
double GetCurrentPrice(int shift)
{
    return iClose(_Symbol, MonitoringTimeframe, shift);
}

//+------------------------------------------------------------------+
//| Vérifier si une zone est testée                                |
//+------------------------------------------------------------------+
bool IsZoneTested(TradingVariable &var, double price)
{
    if(var.type == 0) // FVG - zone
    {
        return price >= var.lowerLevel && price <= var.upperLevel;
    }
    else // Niveau
    {
        double tolerance = 10 * _Point;
        return MathAbs(price - var.level) <= tolerance;
    }
}

//+------------------------------------------------------------------+
//| Trouver zone de confirmation                                    |
//+------------------------------------------------------------------+
bool FindConfirmationZone(ENUM_TIMEFRAMES tf)
{
    // Simplification - vérifier formation récente de patterns
    double high1 = iHigh(_Symbol, tf, 1);
    double low1 = iLow(_Symbol, tf, 1);
    double high2 = iHigh(_Symbol, tf, 2);
    double low2 = iLow(_Symbol, tf, 2);
    
    // Signal de confirmation basique
    return (high1 > high2 || low1 < low2);
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
    double currentPrice = GetCurrentPrice(CandleShift);
    
    // Pour les zones de prix
    if(idea.initialZone.type == 0) // FVG
    {
        // Vérifier si complètement cassée
        if(currentPrice > idea.initialZone.upperLevel + 5*_Point ||
           currentPrice < idea.initialZone.lowerLevel - 5*_Point)
        {
            Print("Idée invalidée - Zone complètement cassée");
            return true;
        }
    }
    
    // Pour les niveaux
    if(idea.initialZone.type == 1) // Fractal
    {
        // Vérifier absence de réaction
        if(IsZoneTested(idea.initialZone, currentPrice))
        {
            // Vérifier s'il y a eu réaction dans les bougies suivantes
            if(!HasReactionAfterTest(idea.initialZone))
            {
                Print("Idée invalidée - Aucune réaction au niveau");
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Vérifier réaction après test                                   |
//+------------------------------------------------------------------+
bool HasReactionAfterTest(TradingVariable &var)
{
    // Simplification - vérifier changement de direction
    double close1 = iClose(_Symbol, var.timeframe, 1);
    double close2 = iClose(_Symbol, var.timeframe, 2);
    double close3 = iClose(_Symbol, var.timeframe, 3);
    
    // Basique: 2 bougies consécutives dans direction opposée
    return (close1 > close2 && close2 > close3) || (close1 < close2 && close2 < close3);
}

//+------------------------------------------------------------------+
//| Décision instantanée                                           |
//+------------------------------------------------------------------+
void InstantDecision(TradingIdea &idea)
{
    if(PositionsTotal() >= MaxPositions) return;
    
    Print("Décision instantanée pour idée haute probabilité: ", idea.probability);
    ExecuteTrade(idea);
}

//+------------------------------------------------------------------+
//| Exécuter un trade                                              |
//+------------------------------------------------------------------+
void ExecuteTrade(TradingIdea &idea)
{
    if(PositionsTotal() >= MaxPositions) return;
    
    // Déterminer direction
    bool isBuy = idea.targetZone.level > idea.initialZone.level;
    
    // Calculer prix d'entrée
    double entryPrice = idea.initialZone.level;
    
    // Calculer stop loss
    double stopLoss = CalculateStopLoss(idea, entryPrice);
    
    // Calculer take profit
    double takeProfit = CalculateTakeProfit(idea, entryPrice, stopLoss);
    
    // Calculer taille de position
    double lotSize = CalculateLotSize(entryPrice, stopLoss);
    
    // Exécuter l'ordre
    if(isBuy)
    {
        if(trade.Buy(lotSize, _Symbol, entryPrice, stopLoss, takeProfit, "Simplified Strategy"))
        {
            Print("Position BUY ouverte - Entry: ", entryPrice, " SL: ", stopLoss, " TP: ", takeProfit);
        }
    }
    else
    {
        if(trade.Sell(lotSize, _Symbol, entryPrice, stopLoss, takeProfit, "Simplified Strategy"))
        {
            Print("Position SELL ouverte - Entry: ", entryPrice, " SL: ", stopLoss, " TP: ", takeProfit);
        }
    }
}

double GetStopLevel()
{
    long stopLevel;
    if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL, stopLevel))
        stopLevel = 30; // Valeur par défaut (en points)
    return stopLevel * _Point;
}


//+------------------------------------------------------------------+
//| Calculer stop loss                                             |
//+------------------------------------------------------------------+
double CalculateStopLoss(TradingIdea &idea, double entryPrice)
{
    double stopLoss;
    bool isBuy = idea.targetZone.level > idea.initialZone.level;

    double stopLevel = GetStopLevel(); // distance mini imposée par le broker
    double bufferFVG = 5 * _Point;
    double bufferDefault = 20 * _Point;

    // Déterminer SL théorique
    if(idea.initialZone.type == 0) // FVG
    {
        if(isBuy)
            stopLoss = idea.initialZone.lowerLevel - bufferFVG;
        else
            stopLoss = idea.initialZone.upperLevel + bufferFVG;
    }
    else
    {
        if(isBuy)
            stopLoss = idea.initialZone.level - bufferDefault;
        else
            stopLoss = idea.initialZone.level + bufferDefault;
    }

    // ⚠️ Vérification que le SL est valide en logique de marché
    if(isBuy)
    {
        // Le SL doit être < entryPrice
        if(stopLoss >= entryPrice - stopLevel)
            stopLoss = entryPrice - stopLevel - (2 * _Point);
    }
    else
    {
        // Le SL doit être > entryPrice
        if(stopLoss <= entryPrice + stopLevel)
            stopLoss = entryPrice + stopLevel + (2 * _Point);
    }

    return NormalizeDouble(stopLoss, _Digits);
}



//+------------------------------------------------------------------+
//| Calculer take profit                                           |
//+------------------------------------------------------------------+
double CalculateTakeProfit(TradingIdea &idea, double entryPrice, double stopLoss)
{
    double riskDistance = MathAbs(entryPrice - stopLoss);
    double rewardDistance = riskDistance * RewardRiskRatio;

    bool isBuy = idea.targetZone.level > idea.initialZone.level;

    // Récupérer la distance minimale imposée par le broker
    double stopLevel = GetStopLevel();

    double takeProfit;

    if(isBuy)
    {
        takeProfit = entryPrice + rewardDistance;
        // Sécurité TP trop proche
        if((takeProfit - entryPrice) < stopLevel)
            takeProfit = entryPrice + stopLevel + (2 * _Point);
    }
    else // Vente
    {
        takeProfit = entryPrice - rewardDistance;

        // ⚠️ Sécurité : TP doit être < prix, pas plus haut (comme dans ton erreur)
        if(takeProfit >= entryPrice)
            takeProfit = entryPrice - stopLevel - (2 * _Point);

        // Sécurité TP trop proche
        if((entryPrice - takeProfit) < stopLevel)
            takeProfit = entryPrice - stopLevel - (2 * _Point);
    }

    return NormalizeDouble(takeProfit, _Digits);
}

//+------------------------------------------------------------------+
//| Calculer taille de position                                    |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLoss)
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * RiskPercent / 100.0;
    double riskDistance = MathAbs(entryPrice - stopLoss);
    
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    double lotSize = riskAmount / (riskDistance / tickSize * tickValue);
    
    // Normaliser la taille
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathMax(minLot, lotSize);
    lotSize = MathMin(maxLot, lotSize);
    lotSize = MathRound(lotSize / stepLot) * stepLot;
    
    return lotSize;
}