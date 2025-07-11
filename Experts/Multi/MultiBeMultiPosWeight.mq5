//+------------------------------------------------------------------+
//|           MultiPositionEA_Weighted_Enhanced.mq5                 |
//|         EA multi-positions avec système de poids amélioré       |
//|         et génération automatique de commentaires signaux       |
//+------------------------------------------------------------------+
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\Trade.mqh>
#include <SamBotUtils.mqh>
#include <Generic\HashMap.mqh>
#include <BreakevenCyclique.mqh>
#property strict

//=========================//
//         GENERAL          //
//=========================//
input group "General Settings";
input ENUM_TIMEFRAMES TF_EA                   = PERIOD_CURRENT;
input ulong         MagicNumber               = 123456;        // Identifiant unique pour les ordres de cet EA

//=========================//
//   ENABLE/DISABLE SWITCH  //
//=========================//
input group "Enable/Disable Indicators and Filters";
input bool UseFastMA            = true;    // Activer Moyenne Mobile Rapide
input bool UseMidMA             = true;    // Activer Moyenne Mobile Intermédiaire
input bool UseSlowMA            = true;    // Activer Moyenne Mobile Lente
input bool UseLongMA            = true;    // Activer Moyenne Mobile Longue
input bool UseADX               = true;    // Activer ADX
input bool UseOsMA              = true;    // Activer OsMA
input bool UseRSI               = true;    // Activer RSI
input bool UseVolatilityFilter  = true;    // Activer filtre volatilité
input bool UseSpreadFilter      = true;    // Activer filtre spread
input bool lotDyna              = false;   // Activer lot dynamique

//=========================//
//    WEIGHTED SYSTEM       //
//=========================//
input group "Signal Weights (Total should be ~100)";
input double WeightFastMA       = 20.0;    // Poids Fast MA (%)
input double WeightMidMA        = 18.0;    // Poids Mid MA (%)
input double WeightSlowMA       = 15.0;    // Poids Slow MA (%)
input double WeightLongMA       = 12.0;    // Poids Long MA (%)
input double WeightADX          = 15.0;    // Poids ADX (%)
input double WeightOsMA         = 10.0;    // Poids OsMA (%)
input double WeightRSI          = 8.0;     // Poids RSI (%)
input double WeightVolatility   = 2.0;     // Poids Volatilité (%)
input double MinScoreToTrade    = 60.0;    // Score minimum pour trader (%)

//=========================//
//       TIMEFRAMES         //
//=========================//
input group "Timeframes for Indicators";
input ENUM_TIMEFRAMES FastMATF      = PERIOD_M15; // TF Moyenne Mobile Rapide
input ENUM_TIMEFRAMES MidMATF       = PERIOD_M15; // TF Moyenne Mobile Intermédiaire
input ENUM_TIMEFRAMES SlowMATF      = PERIOD_M30; // TF Moyenne Mobile Lente
input ENUM_TIMEFRAMES LongMATF      = PERIOD_H1;  // TF Moyenne Mobile Longue
input ENUM_TIMEFRAMES ADXTF         = PERIOD_M15; // TF ADX
input ENUM_TIMEFRAMES OsMATF        = PERIOD_M15; // TF OsMA
input ENUM_TIMEFRAMES RSITF         = PERIOD_M15; // TF RSI
input ENUM_TIMEFRAMES VolatilityTF  = PERIOD_M15; // TF volatilité

//=========================//
//        PERIODS           //
//=========================//
input group "Indicator Periods";
input int FastMAPeriod       = 8;    // Période MM Rapide
input int MidMAPeriod        = 38;   // Période MM Intermédiaire
input int SlowMAPeriod       = 90;   // Période MM Lente
input int LongMAPeriod       = 200;  // Période MM Longue
input int ADXPeriod          = 14;   // Période ADX
input int OsMAFastPeriod     = 12;   // Période rapide OsMA
input int OsMASlowPeriod     = 26;   // Période lente OsMA
input int OsMASignalPeriod   = 9;    // Période signal OsMA
input int RSIPeriod          = 14;   // Période RSI
input int VolatilityPeriod   = 14;   // Période volatilité

//=========================//
//     OTHER SETTINGS       //
//=========================//
input group "Other Indicator Settings";
input ENUM_MA_METHOD MAType           = MODE_LWMA;      // Méthode MM
input ENUM_APPLIED_PRICE PriceType    = PRICE_CLOSE;    // Prix appliqué MM
input int FastMATTL               = 6;     // TTL pour signal Fast MA (augmenté)
input int MidMATTL                = 6;     // TTL pour signal Mid MA (augmenté)
input int SlowMATTL               = 5;     // TTL pour signal Slow MA (augmenté)
input int LongMATTL               = 4;     // TTL pour signal Long MA (augmenté)
input int ADXTTL                  = 5;     // TTL pour signal ADX (augmenté)
input double ADXThreshold         = 15.0;  // Seuil ADX (réduit de 20 à 15)
input int OsMATTL                 = 6;     // TTL pour signal OsMA (augmenté)
input int RSITTL                  = 6;     // TTL pour signal RSI (augmenté)
input double RSIOverboughtLevel   = 70.0;  // Niveau surachat RSI
input double RSIOversoldLevel     = 30.0;  // Niveau survente RSI
input double MinVolatilityPips    = 3.0;   // Volatilité min (réduit de 5 à 3 pips)
input double MaxAllowedSpreadPts  = 20;    // Spread max (points)

//=========================//
//     TRADING PARAMETERS    //
//=========================//
input group "Trading Parameters";
input double LotSize             = 0.1;   // Taille de lot fixe
input double RiskPercent         = 1.0;   // % du capital à risquer (pour lot dynamique)
input double StopLossPips        = 100;   // Stop Loss (pips)
input double TakeProfitPips      = 300;   // Take Profit (pips)

//=========================//
//   CYCLIC BREAKEVEN SETTINGS  //
//=========================//
input group "Cyclic Breakeven Settings";
input bool   useBreakevenCyclique       = false;
input ENUM_TIMEFRAMES timeframeBreakeven = PERIOD_H1;
input int    candlesAvantBreakeven      = 5;
input bool   breakevenEnProfitSeulement = true;
input int    nombreVerificationsBreakeven = 0;

//=========================//
//  MULTI-POSITION SETTINGS  //
//=========================//
input group "Multi-Position Settings";
input int maxOpenPositions = 5;   // Nombre max de positions simultanées (0 = illimité)

//=========================//
//   RISK LIMIT SETTINGS    //
//=========================//
input group "Risk Limit Settings";
input bool  useRiskLimit       = false;     // Activer la limite de risque par symbole
input double RiskLimitPct      = 1.0;       // Pourcentage max du solde à risquer (en %)

//=========================//
//       HANDLES & TIMES     //
//=========================//
int fastMAHandle = INVALID_HANDLE;
int midMAHandle  = INVALID_HANDLE;
int slowMAHandle = INVALID_HANDLE;
int longMAHandle = INVALID_HANDLE;
int adxHandle    = INVALID_HANDLE;
int osmaHandle   = INVALID_HANDLE;
int rsiHandle    = INVALID_HANDLE;

datetime fastMASignalTime = 0;
datetime midMASignalTime  = 0;
datetime slowMASignalTime = 0;
datetime longMASignalTime = 0;
datetime adxSignalTime    = 0;
datetime osmaSignalTime   = 0;
datetime rsiSignalTime    = 0;

static datetime lastBarTime = 0;

//--- Contexte Breakeven Cyclique
BreakevenCycliqueContext breakevenCtx;
bool                    breakevenInitialise = false;

//--- Structure pour stocker les signaux actifs
struct SignalSnapshot {
    bool fastMA_active;
    bool midMA_active;
    bool slowMA_active;
    bool longMA_active;
    bool adx_active;
    bool osma_active;
    bool rsi_active;
    bool volatility_ok;
    double total_score;
    string signal_summary;
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Validation des paramètres
    if(!ValidateInputs())
    {
        Print("ERREUR: Paramètres d'entrée invalides!");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    InitializeIndicators();

    // Initialisation du Breakeven Cyclique si demandé
    if(useBreakevenCyclique)
    {
        breakevenInitialise = InitBreakevenCycliqueContext(
                                 breakevenCtx,
                                 MagicNumber,
                                 _Symbol,
                                 timeframeBreakeven,
                                 candlesAvantBreakeven,
                                 breakevenEnProfitSeulement,
                                 nombreVerificationsBreakeven
                              );
        if(!breakevenInitialise)
        {
            Print("InitBreakevenCycliqueContext a échoué, on désactive la fonctionnalité.");
        }
        else
        {
            PrintFormat(
              "BreakevenCyclique activé sur %s H%d, %d bougies (profitOnly=%s, nbVerif=%d), magic=%I64u",
              _Symbol,
              (int)timeframeBreakeven,
              candlesAvantBreakeven,
              breakevenEnProfitSeulement ? "oui" : "non",
              nombreVerificationsBreakeven,
              MagicNumber
            );
        }
    }

    // Affichage de la config des poids
    PrintFormat("=== Configuration Poids Signaux ===");
    PrintFormat("FastMA:%.1f%% | MidMA:%.1f%% | SlowMA:%.1f%% | LongMA:%.1f%%", 
                WeightFastMA, WeightMidMA, WeightSlowMA, WeightLongMA);
    PrintFormat("ADX:%.1f%% | OsMA:%.1f%% | RSI:%.1f%% | Volatilité:%.1f%%", 
                WeightADX, WeightOsMA, WeightRSI, WeightVolatility);
    PrintFormat("Score minimum pour trader: %.1f%%", MinScoreToTrade);
    
    double totalWeight = WeightFastMA + WeightMidMA + WeightSlowMA + WeightLongMA + 
                        WeightADX + WeightOsMA + WeightRSI + WeightVolatility;
    PrintFormat("Poids total configuré: %.1f%% (recommandé: ~100%%)", totalWeight);

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Validation des paramètres d'entrée                               |
//+------------------------------------------------------------------+
bool ValidateInputs()
{
    // Validation des périodes
    if(FastMAPeriod <= 0 || MidMAPeriod <= 0 || SlowMAPeriod <= 0 || LongMAPeriod <= 0)
    {
        Print("ERREUR: Périodes des moyennes mobiles doivent être > 0");
        return false;
    }
    
    // Validation des TTL
    if(FastMATTL < 0 || MidMATTL < 0 || SlowMATTL < 0 || LongMATTL < 0)
    {
        Print("ERREUR: TTL ne peuvent pas être négatifs");
        return false;
    }
    
    // Validation des poids
    if(WeightFastMA < 0 || WeightMidMA < 0 || WeightSlowMA < 0 || WeightLongMA < 0 ||
       WeightADX < 0 || WeightOsMA < 0 || WeightRSI < 0 || WeightVolatility < 0)
    {
        Print("ERREUR: Les poids ne peuvent pas être négatifs");
        return false;
    }
    
    // Validation du score minimum
    if(MinScoreToTrade <= 0 || MinScoreToTrade > 100)
    {
        Print("ERREUR: Score minimum doit être entre 0 et 100");
        return false;
    }
    
    // Validation des paramètres de trading
    if(StopLossPips <= 0 || TakeProfitPips <= 0)
    {
        Print("ERREUR: SL et TP doivent être > 0");
        return false;
    }
    
    if(RiskPercent <= 0 || RiskPercent > 100)
    {
        Print("ERREUR: Pourcentage de risque doit être entre 0 et 100");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Libération des handles
    if(fastMAHandle != INVALID_HANDLE)   IndicatorRelease(fastMAHandle);
    if(midMAHandle != INVALID_HANDLE)    IndicatorRelease(midMAHandle);
    if(slowMAHandle != INVALID_HANDLE)   IndicatorRelease(slowMAHandle);
    if(longMAHandle != INVALID_HANDLE)   IndicatorRelease(longMAHandle);
    if(adxHandle != INVALID_HANDLE)      IndicatorRelease(adxHandle);
    if(osmaHandle != INVALID_HANDLE)     IndicatorRelease(osmaHandle);
    if(rsiHandle != INVALID_HANDLE)      IndicatorRelease(rsiHandle);

    // Détruire le contexte Breakeven Cyclique s'il a été initialisé
    if(useBreakevenCyclique && breakevenInitialise)
    {
        DeinitBreakevenCycliqueContext(breakevenCtx);
        Print("BreakevenCycliqueContext détruit au OnDeinit.");
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    bool isNew = IsNewCandle();

    if(isNew)
    {
        if(!IndicatorsReady())
            return;
        UpdateSignalTimestamps();
    }

    // Gestion du breakeven cyclique (si activé), à chaque tick
    if(useBreakevenCyclique && breakevenInitialise)
        ManageBreakevenCyclique(breakevenCtx);

    // Logique d'ouverture de trade (seulement sur nouvelle bougie)
    if(isNew)
    {
        int openCount = CountOpenPositions();
        if((maxOpenPositions == 0 || openCount < maxOpenPositions) && CheckTradeAllowed())
        {
            // Vérification du risque
            bool okToOpen = true;
            if(useRiskLimit)
            {
                double balance      = AccountInfoDouble(ACCOUNT_BALANCE);
                double existingRisk = ComputeTotalRiskExisting();
                double newRisk      = ComputeNewTradeRisk();
                double totalRisk    = existingRisk + newRisk;
                double pctRisk      = (totalRisk / balance) * 100.0;
                
                if(pctRisk > RiskLimitPct)
                {
                    okToOpen = false;
                    PrintFormat("Ouverture interdite : risque total sur %s = %.2f%% du solde (max = %.2f%%).",
                              _Symbol, pctRisk, RiskLimitPct);
                }
            }

            if(okToOpen)
            {
                // Nouveau système: calcul du score pour BUY et SELL
                SignalSnapshot buySignals = AnalyzeSignals(true);
                SignalSnapshot sellSignals = AnalyzeSignals(false);
                
                // Debug: affichage des scores
                if(buySignals.total_score > 0 || sellSignals.total_score > 0)
                {
                    PrintFormat("Scores calculés - BUY: %.1f%% | SELL: %.1f%% (min: %.1f%%)", 
                              buySignals.total_score, sellSignals.total_score, MinScoreToTrade);
                }
                
                // Exécution si score suffisant
                if(buySignals.total_score >= MinScoreToTrade)
                {
                    ExecuteBuyTrade(buySignals.signal_summary);
                }
                else if(sellSignals.total_score >= MinScoreToTrade)
                {
                    ExecuteSellTrade(sellSignals.signal_summary);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Analyse des signaux avec système de poids                        |
//+------------------------------------------------------------------+
SignalSnapshot AnalyzeSignals(bool isBuy)
{
    SignalSnapshot signals;
    signals.total_score = 0.0;
    signals.signal_summary = "";
    
    // Reset flags
    signals.fastMA_active = false;
    signals.midMA_active = false;
    signals.slowMA_active = false;
    signals.longMA_active = false;
    signals.adx_active = false;
    signals.osma_active = false;
    signals.rsi_active = false;
    signals.volatility_ok = false;
    
    string activeSignals = "";
    
    // Analyse Fast MA
    if(UseFastMA)
    {
        bool fastMAValid = IsSignalValid(fastMASignalTime, FastMATF, FastMATTL);
        bool fastMACondition = isBuy ? IsFastMAAboveMidMA() : IsFastMABelowMidMA();
        
        if(fastMAValid && fastMACondition)
        {
            signals.fastMA_active = true;
            signals.total_score += WeightFastMA;
            activeSignals += "FMA" + (string)FastMAPeriod + " ";
        }
    }
    
    // Analyse Mid MA
    if(UseMidMA)
    {
        bool midMAValid = IsSignalValid(midMASignalTime, MidMATF, MidMATTL);
        bool midMACondition = isBuy ? IsMidMAAboveSlowMA() : IsMidMABelowSlowMA();
        
        if(midMAValid && midMACondition)
        {
            signals.midMA_active = true;
            signals.total_score += WeightMidMA;
            activeSignals += "MMA" + (string)MidMAPeriod + " ";
        }
    }
    
    // Analyse Slow MA
    if(UseSlowMA)
    {
        bool slowMAValid = IsSignalValid(slowMASignalTime, SlowMATF, SlowMATTL);
        bool slowMACondition = isBuy ? IsSlowMAAboveLongMA() : IsSlowMABelowLongMA();
        
        if(slowMAValid && slowMACondition)
        {
            signals.slowMA_active = true;
            signals.total_score += WeightSlowMA;
            activeSignals += "SMA" + (string)SlowMAPeriod + " ";
        }
    }
    
    // Analyse Long MA
    if(UseLongMA)
    {
        bool longMAValid = IsSignalValid(longMASignalTime, LongMATF, LongMATTL);
        bool longMACondition = IsPullbackToMA(isBuy);
        
        if(longMAValid && longMACondition)
        {
            signals.longMA_active = true;
            signals.total_score += WeightLongMA;
            activeSignals += "LMA" + (string)LongMAPeriod + " ";
        }
    }
    
    // Analyse ADX
    if(UseADX)
    {
        bool adxValid = IsSignalValid(adxSignalTime, ADXTF, ADXTTL);
        bool adxCondition = IsADXStrongEnough();
        
        if(adxValid && adxCondition)
        {
            signals.adx_active = true;
            signals.total_score += WeightADX;
            activeSignals += "ADX" + (string)ADXPeriod + " ";
        }
    }
    
    // Analyse OsMA
    if(UseOsMA)
    {
        bool osmaValid = IsSignalValid(osmaSignalTime, OsMATF, OsMATTL);
        bool osmaCondition = IsMomentumResuming(isBuy);
        
        if(osmaValid && osmaCondition)
        {
            signals.osma_active = true;
            signals.total_score += WeightOsMA;
            activeSignals += "OSMA ";
        }
    }
    
    // Analyse RSI
    if(UseRSI)
    {
        bool rsiValid = IsSignalValid(rsiSignalTime, RSITF, RSITTL);
        bool rsiCondition = isBuy ? IsRSIInBuyZone() : IsRSIInSellZone();
        
        if(rsiValid && rsiCondition)
        {
            signals.rsi_active = true;
            signals.total_score += WeightRSI;
            activeSignals += "RSI" + (string)RSIPeriod + " ";
        }
    }
    
    // Analyse Volatilité
    if(UseVolatilityFilter && PassesVolatilityFilter())
    {
        signals.volatility_ok = true;
        signals.total_score += WeightVolatility;
        activeSignals += "VOL ";
    }
    
    // Construction du résumé des signaux
    if(activeSignals != "")
    {
        signals.signal_summary = StringFormat("S%.0f%% [%s]", 
                                            signals.total_score, 
                                            StringSubstr(activeSignals, 0, StringLen(activeSignals)-1));
    }
    else
    {
        signals.signal_summary = "NoSignal";
    }
    
    return signals;
}

//+------------------------------------------------------------------+
//| Initialisation des indicateurs                                   |
//+------------------------------------------------------------------+
void InitializeIndicators()
{
    if(UseFastMA)  fastMAHandle = iMA(_Symbol, FastMATF, FastMAPeriod, 0, MAType, PriceType);
    if(UseMidMA)   midMAHandle  = iMA(_Symbol, MidMATF,  MidMAPeriod,  0, MAType, PriceType);
    if(UseSlowMA)  slowMAHandle = iMA(_Symbol, SlowMATF, SlowMAPeriod, 0, MAType, PriceType);
    if(UseLongMA)  longMAHandle = iMA(_Symbol, LongMATF, LongMAPeriod, 0, MAType, PriceType);
    if(UseADX)     adxHandle    = iADX(_Symbol, ADXTF,     ADXPeriod);
    if(UseOsMA)    osmaHandle   = iOsMA(_Symbol, OsMATF, OsMAFastPeriod, OsMASlowPeriod, OsMASignalPeriod, PRICE_CLOSE);
    if(UseRSI)     rsiHandle    = iRSI(_Symbol, RSITF,    RSIPeriod, PRICE_CLOSE);

    // Vérification individuelle avec messages d'erreur détaillés
    if(UseFastMA && fastMAHandle == INVALID_HANDLE)
    {
        PrintFormat("ERREUR: Impossible de créer l'indicateur Fast MA (période:%d, TF:%s)", 
                   FastMAPeriod, EnumToString(FastMATF));
        ExpertRemove();
        return;
    }
    
    if(UseMidMA && midMAHandle == INVALID_HANDLE)
    {
        PrintFormat("ERREUR: Impossible de créer l'indicateur Mid MA (période:%d, TF:%s)", 
                   MidMAPeriod, EnumToString(MidMATF));
        ExpertRemove();
        return;
    }
    
    if(UseSlowMA && slowMAHandle == INVALID_HANDLE)
    {
        PrintFormat("ERREUR: Impossible de créer l'indicateur Slow MA (période:%d, TF:%s)", 
                   SlowMAPeriod, EnumToString(SlowMATF));
        ExpertRemove();
        return;
    }
    
    if(UseLongMA && longMAHandle == INVALID_HANDLE)
    {
        PrintFormat("ERREUR: Impossible de créer l'indicateur Long MA (période:%d, TF:%s)", 
                   LongMAPeriod, EnumToString(LongMATF));
        ExpertRemove();
        return;
    }
    
    if(UseADX && adxHandle == INVALID_HANDLE)
    {
        PrintFormat("ERREUR: Impossible de créer l'indicateur ADX (période:%d, TF:%s)", 
                   ADXPeriod, EnumToString(ADXTF));
        ExpertRemove();
        return;
    }
    
    if(UseOsMA && osmaHandle == INVALID_HANDLE)
    {
        PrintFormat("ERREUR: Impossible de créer l'indicateur OsMA (TF:%s)", EnumToString(OsMATF));
        ExpertRemove();
        return;
    }
    
    if(UseRSI && rsiHandle == INVALID_HANDLE)
    {
        PrintFormat("ERREUR: Impossible de créer l'indicateur RSI (période:%d, TF:%s)", 
                   RSIPeriod, EnumToString(RSITF));
        ExpertRemove();
        return;
    }
    
    Print("✓ Tous les indicateurs ont été initialisés avec succès");
}

//+------------------------------------------------------------------+
//| Détecte nouvelle bougie                                          |
//+------------------------------------------------------------------+
bool IsNewCandle()
{
    datetime currentBarTime = iTime(_Symbol, TF_EA, 0);
    if(currentBarTime != lastBarTime)
    {
        lastBarTime = currentBarTime;
        return(true);
    }
    return(false);
}

//+------------------------------------------------------------------+
//| Vérifie si les buffers indicateurs sont prêts                    |
//+------------------------------------------------------------------+
bool IndicatorsReady()
{
    double buffer[2];
    if(UseFastMA && CopyBuffer(fastMAHandle, 0, 0, 2, buffer) <= 0)    return(false);
    if(UseMidMA && CopyBuffer(midMAHandle,  0, 0, 2, buffer) <= 0)    return(false);
    if(UseSlowMA && CopyBuffer(slowMAHandle,0, 0, 2, buffer) <= 0)    return(false);
    if(UseLongMA && CopyBuffer(longMAHandle,0, 0, 2, buffer) <= 0)    return(false);
    if(UseADX && CopyBuffer(adxHandle,      0, 0, 1, buffer) <= 0)    return(false);
    if(UseOsMA && CopyBuffer(osmaHandle,    0, 0, 2, buffer) <= 0)    return(false);
    if(UseRSI && CopyBuffer(rsiHandle,      0, 0, 1, buffer) <= 0)    return(false);
    return(true);
}

//+------------------------------------------------------------------+
//| Met à jour les timestamps des signaux                            |
//+------------------------------------------------------------------+
void UpdateSignalTimestamps()
{
    if(UseFastMA && IsFastMAAboveMidMA())        fastMASignalTime = TimeCurrent();
    if(UseMidMA && IsMidMAAboveSlowMA())         midMASignalTime  = TimeCurrent();
    if(UseSlowMA && IsSlowMAAboveLongMA())       slowMASignalTime = TimeCurrent();
    if(UseLongMA && IsPullbackToMA(true))        longMASignalTime = TimeCurrent();
    if(UseADX && IsADXStrongEnough())            adxSignalTime    = TimeCurrent();
    if(UseOsMA && IsMomentumResuming(true))      osmaSignalTime   = TimeCurrent();
    if(UseRSI && IsRSIInBuyZone())               rsiSignalTime    = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Vérifie validité d'un signal selon TTL et TF                     |
//+------------------------------------------------------------------+
bool IsSignalValid(datetime signalTime, ENUM_TIMEFRAMES tf, int ttlCandles)
{
    if(signalTime == 0) return(false);
    int barsSinceSignal = iBarShift(_Symbol, tf, signalTime, false);
    return (barsSinceSignal >= 0 && barsSinceSignal <= ttlCandles);
}

//+------------------------------------------------------------------+
//| Vérifie si trading autorisé                                      |
//+------------------------------------------------------------------+
bool CheckTradeAllowed()
{
    if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == 0)
    {
        Print("Trading non autorisé sur ", _Symbol);
        return(false);
    }
    
    // Vérification du filtre de spread (obligatoire)
    if(UseSpreadFilter && !PassesSpreadFilter())
        return false;
    
    return(true);
}


//+------------------------------------------------------------------+
//| Filtre spread                                                     |
//+------------------------------------------------------------------+
bool PassesSpreadFilter()
{
    if(!UseSpreadFilter) return(true);
    long spread = 0;
    if(!SymbolInfoInteger(_Symbol, SYMBOL_SPREAD, spread))
    {
        Print("Impossible de récupérer le spread.");
        return(false);
    }
    if(spread > MaxAllowedSpreadPts)
    {
        PrintFormat("Spread trop élevé : %d points (max = %.0f)", spread, MaxAllowedSpreadPts);
        return(false);
    }
    return(true);
}

//+------------------------------------------------------------------+
//| Filtre volatilité                                                 |
//+------------------------------------------------------------------+
bool PassesVolatilityFilter()
{
    if(!UseVolatilityFilter) return(true);
    double high = iHigh(_Symbol, VolatilityTF, 1);
    double low  = iLow(_Symbol, VolatilityTF, 1);
    double rangePips = (high - low) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if(rangePips < MinVolatilityPips)
    {
        PrintFormat("Volatilité trop faible : %.2f pips (min = %.2f)", rangePips, MinVolatilityPips);
        return(false);
    }
    return(true);
}

//+------------------------------------------------------------------+
//| Compare Fast MA et Mid MA pour signal achat                       |
//+------------------------------------------------------------------+
bool IsFastMAAboveMidMA()
{
    double valsFast[2], valsMid[2];
    CopyBuffer(fastMAHandle, 0, 0, 2, valsFast);
    CopyBuffer(midMAHandle,  0, 0, 2, valsMid);
    return (valsFast[1] < valsMid[1] && valsFast[0] > valsMid[0]);
}

//+------------------------------------------------------------------+
//| Compare Fast MA et Mid MA pour signal vente                       |
//+------------------------------------------------------------------+
bool IsFastMABelowMidMA()
{
    double valsFast[2], valsMid[2];
    CopyBuffer(fastMAHandle, 0, 0, 2, valsFast);
    CopyBuffer(midMAHandle,  0, 0, 2, valsMid);
    return (valsFast[1] > valsMid[1] && valsFast[0] < valsMid[0]);
}

//+------------------------------------------------------------------+
//| Compare Mid MA et Slow MA pour signal achat                       |
//+------------------------------------------------------------------+
bool IsMidMAAboveSlowMA()
{
    double valsMid[2], valsSlow[2];
    CopyBuffer(midMAHandle,  0, 0, 2, valsMid);
    CopyBuffer(slowMAHandle, 0, 0, 2, valsSlow);
    return (valsMid[1] < valsSlow[1] && valsMid[0] > valsSlow[0]);
}

//+------------------------------------------------------------------+
//| Compare Mid MA et Slow MA pour signal vente                       |
//+------------------------------------------------------------------+
bool IsMidMABelowSlowMA()
{
    double valsMid[2], valsSlow[2];
    CopyBuffer(midMAHandle,  0, 0, 2, valsMid);
    CopyBuffer(slowMAHandle, 0, 0, 2, valsSlow);
    return (valsMid[1] > valsSlow[1] && valsMid[0] < valsSlow[0]);
}

//+------------------------------------------------------------------+
//| Compare Slow MA et Long MA pour signal achat                      |
//+------------------------------------------------------------------+
bool IsSlowMAAboveLongMA()
{
    double valsSlow[2], valsLong[2];
    CopyBuffer(slowMAHandle, 0, 0, 2, valsSlow);
    CopyBuffer(longMAHandle, 0, 0, 2, valsLong);
    return (valsSlow[1] < valsLong[1] && valsSlow[0] > valsLong[0]);
}

//+------------------------------------------------------------------+
//| Compare Slow MA et Long MA pour signal vente                      |
//+------------------------------------------------------------------+
bool IsSlowMABelowLongMA()
{
    double valsSlow[2], valsLong[2];
    CopyBuffer(slowMAHandle, 0, 0, 2, valsSlow);
    CopyBuffer(longMAHandle, 0, 0, 2, valsLong);
    return (valsSlow[1] > valsLong[1] && valsSlow[0] < valsLong[0]);
}

//+------------------------------------------------------------------+
//| Pullback vers la Long MA                                          |
//+------------------------------------------------------------------+
bool IsPullbackToMA(bool isBuy)
{
    double valsLong[2];
    CopyBuffer(longMAHandle, 0, 0, 2, valsLong);
    double ma0    = valsLong[0];
    double price1 = iClose(_Symbol, TF_EA, 1);
    return (isBuy ? (price1 > ma0) : (price1 < ma0));
}

//+------------------------------------------------------------------+
//| Vérifie ADX fort                                                  |
//+------------------------------------------------------------------+
bool IsADXStrongEnough()
{
    double val[1];
    CopyBuffer(adxHandle, 0, 0, 1, val);
    return (val[0] > ADXThreshold);
}

//+------------------------------------------------------------------+
//| Momentum OsMA                                                    |
//+------------------------------------------------------------------+
bool IsMomentumResuming(bool isBuy)
{
    double valsOsma[2];
    CopyBuffer(osmaHandle, 0, 0, 2, valsOsma);
    double hist0 = valsOsma[0], hist1 = valsOsma[1];
    return (isBuy ? (hist1 < 0 && hist0 > 0) : (hist1 > 0 && hist0 < 0));
}

//+------------------------------------------------------------------+
//| RSI en zone achat                                                |
//+------------------------------------------------------------------+
bool IsRSIInBuyZone()
{
    double val[1];
    CopyBuffer(rsiHandle, 0, 0, 1, val);
    return (val[0] < RSIOversoldLevel);
}

//+------------------------------------------------------------------+
//| RSI en zone vente                                                |
//+------------------------------------------------------------------+
bool IsRSIInSellZone()
{
    double val[1];
    CopyBuffer(rsiHandle, 0, 0, 1, val);
    return (val[0] > RSIOverboughtLevel);
}

//+------------------------------------------------------------------+
//| Exécution d'un trade BUY                                         |
//+------------------------------------------------------------------+
void ExecuteBuyTrade(string summary)
{
    SamBotUtils::tradeOpen_pips(
       _Symbol,
       MagicNumber,
       ORDER_TYPE_BUY,
       StopLossPips,
       TakeProfitPips,
       lotDyna,
       LotSize,
       RiskPercent,
       UseSpreadFilter,
       (int)MaxAllowedSpreadPts,
       summary
    );
}

//+------------------------------------------------------------------+
//| Exécution d'un trade SELL                                        |
//+------------------------------------------------------------------+
void ExecuteSellTrade(string summary)
{
    SamBotUtils::tradeOpen_pips(
       _Symbol,
       MagicNumber,
       ORDER_TYPE_SELL,
       StopLossPips,
       TakeProfitPips,
       lotDyna,
       LotSize,
       RiskPercent,
       UseSpreadFilter,
       (int)MaxAllowedSpreadPts,
       summary
    );
}

//+------------------------------------------------------------------+
//| Compte positions ouvertes pour ce symbole + MagicNumber          |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
    int total = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC)  == MagicNumber)
            {
                total++;
            }
        }
    }
    return(total);
}

//+------------------------------------------------------------------+
//| Calcule le risque (en $) d'une position donnée (ticket)          |
//+------------------------------------------------------------------+
double ComputePositionRisk(ulong ticket)
{
    if(!PositionSelectByTicket(ticket))
        return(0.0);

    // Récupère prix d'ouverture, SL et volume
    double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double slPrice    = PositionGetDouble(POSITION_SL);
    double volume     = PositionGetDouble(POSITION_VOLUME);

    // Si SL non défini ou SL déjà en profit, on ignore (risque = 0)
    if(slPrice <= 0.0)
        return(0.0);

    ENUM_POSITION_TYPE typePos = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double riskDistance = 0.0;

    if(typePos == POSITION_TYPE_BUY)
    {
        // Pour BUY : on ne compte que si SL < prix entrée (risque réel)
        if(slPrice < entryPrice)
            riskDistance = entryPrice - slPrice;
        else
            return(0.0);
    }
    else // POSITION_TYPE_SELL
    {
        // Pour SELL : on ne compte que si SL > prix entrée
        if(slPrice > entryPrice)
            riskDistance = slPrice - entryPrice;
        else
            return(0.0);
    }

    // Convertir distance prix en ticks
    double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    if(tickSize <= 0.0 || tickValue <= 0.0)
        return(0.0);

    double ticks      = riskDistance / tickSize;
    double riskAmount = ticks * tickValue * volume; // risque en montant

    return(riskAmount);
}

//+------------------------------------------------------------------+
//| Calcule le risque total des positions existantes (en $) SUR CE   |
//|   SYMBOLE (sans filtrer sur MagicNumber)                         |
//+------------------------------------------------------------------+
double ComputeTotalRiskExisting()
{
    double totalRisk = 0.0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionSelectByTicket(ticket))
        {
            // On somme toutes les positions sur _Symbol, quelle que soit le MagicNumber
            if(PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
                totalRisk += ComputePositionRisk(ticket);
            }
        }
    }
    return(totalRisk);
}

//+------------------------------------------------------------------+
//| Calcule le risque (en $) du nouveau trade potentiel             |
//+------------------------------------------------------------------+
double ComputeNewTradeRisk()
{
    // Volume potentiel du nouveau trade
    double volume = lotDyna ? LotSize : LotSize;
    // On prend LotSize fixe ou volume calculé par lot dynamique
    // (pour gestion fine, intégrer la formule de lot dynamique si besoin)

    // Distance SL en prix = StopLossPips * point
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double riskDistance = StopLossPips * point;
    if(riskDistance <= 0.0)
        return(0.0);

    // Convertir distance prix en ticks
    double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    if(tickSize <= 0.0 || tickValue <= 0.0)
        return(0.0);

    double ticks      = riskDistance / tickSize;
    double riskAmount = ticks * tickValue * volume;

    return(riskAmount);
}
