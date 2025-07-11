//+------------------------------------------------------------------+
//|           MultiPositionEA_Weighted_Enhanced_v2.mq5              |
//|         EA multi-positions avec améliorations avancées          |
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
input ulong         MagicNumber               = 123456;

//=========================//
//   ENABLE/DISABLE SWITCH  //
//=========================//
input group "Enable/Disable Indicators and Filters";
input bool UseFastMA            = true;
input bool UseMidMA             = true;
input bool UseSlowMA            = true;
input bool UseLongMA            = true;
input bool UseADX               = true;
input bool UseOsMA              = true;
input bool UseRSI               = true;
input bool UseVolatilityFilter  = true;
input bool UseSpreadFilter      = true;
input bool lotDyna              = false;

// NOUVEAU: Filtre de corrélation des timeframes
input bool UseMultiTimeframeConfirmation = true; // Confirmation multi-timeframe

//=========================//
//    WEIGHTED SYSTEM       //
//=========================//
input group "Signal Weights (Total should be ~100)";
input double WeightFastMA       = 20.0;
input double WeightMidMA        = 18.0;
input double WeightSlowMA       = 15.0;
input double WeightLongMA       = 12.0;
input double WeightADX          = 15.0;
input double WeightOsMA         = 10.0;
input double WeightRSI          = 8.0;
input double WeightVolatility   = 2.0;

// NOUVEAU: Seuils adaptatifs
input double MinScoreToTrade    = 60.0;
input double MinScoreStrong     = 80.0;    // Score pour positions "fortes"
input double MaxScoreOpposite   = 30.0;    // Score max opposé autorisé

//=========================//
//    NOUVEAUX FILTRES      //
//=========================//
input group "Advanced Filters";
input bool UseNewsFilter        = false;   // Éviter trading avant news importantes
input int  NewsAvoidanceMinutes = 30;      // Minutes avant/après news
input bool UseSessionFilter     = true;    // Filtrer selon sessions
input bool TradeLondonSession   = true;    // Trader session Londres
input bool TradeNewYorkSession  = true;    // Trader session New York
input bool TradeAsianSession    = false;   // Trader session Asie

//=========================//
//   GESTION AMÉLIORÉE      //
//=========================//
input group "Enhanced Risk Management";
input bool UseDynamicSL         = true;    // SL basé sur ATR
input double ATRMultiplierSL    = 2.0;     // Multiplicateur ATR pour SL
input bool UseDynamicTP         = true;    // TP basé sur ATR
input double ATRMultiplierTP    = 4.0;     // Multiplicateur ATR pour TP
input bool UseTrailingStop      = true;    // Trailing stop activé
input double TrailingDistance   = 50.0;    // Distance trailing (pips)
input double TrailingStep       = 10.0;    // Pas trailing (pips)

//=========================//
//       TIMEFRAMES         //
//=========================//
input group "Timeframes for Indicators";
input ENUM_TIMEFRAMES FastMATF      = PERIOD_M15;
input ENUM_TIMEFRAMES MidMATF       = PERIOD_M15;
input ENUM_TIMEFRAMES SlowMATF      = PERIOD_M30;
input ENUM_TIMEFRAMES LongMATF      = PERIOD_H1;
input ENUM_TIMEFRAMES ADXTF         = PERIOD_M15;
input ENUM_TIMEFRAMES OsMATF        = PERIOD_M15;
input ENUM_TIMEFRAMES RSITF         = PERIOD_M15;
input ENUM_TIMEFRAMES VolatilityTF  = PERIOD_M15;

// NOUVEAU: Timeframe confirmation
input ENUM_TIMEFRAMES HigherTF      = PERIOD_H1;   // TF supérieur pour confirmation

//=========================//
//        PERIODS           //
//=========================//
input group "Indicator Periods";
input int FastMAPeriod       = 8;
input int MidMAPeriod        = 38;
input int SlowMAPeriod       = 90;
input int LongMAPeriod       = 200;
input int ADXPeriod          = 14;
input int OsMAFastPeriod     = 12;
input int OsMASlowPeriod     = 26;
input int OsMASignalPeriod   = 9;
input int RSIPeriod          = 14;
input int VolatilityPeriod   = 14;
input int ATRPeriod          = 14;      // NOUVEAU: Période ATR

//=========================//
//     OTHER SETTINGS       //
//=========================//
input group "Other Indicator Settings";
input ENUM_MA_METHOD MAType           = MODE_LWMA;
input ENUM_APPLIED_PRICE PriceType    = PRICE_CLOSE;
input int FastMATTL               = 6;
input int MidMATTL                = 6;
input int SlowMATTL               = 5;
input int LongMATTL               = 4;
input int ADXTTL                  = 5;
input double ADXThreshold         = 15.0;
input int OsMATTL                 = 6;
input int RSITTL                  = 6;
input double RSIOverboughtLevel   = 70.0;
input double RSIOversoldLevel     = 30.0;
input double MinVolatilityPips    = 3.0;
input double MaxAllowedSpreadPts  = 20;

//=========================//
//     TRADING PARAMETERS    //
//=========================//
input group "Trading Parameters";
input double LotSize             = 0.1;
input double RiskPercent         = 1.0;
input double StopLossPips        = 100;
input double TakeProfitPips      = 300;

//=========================//
//   CYCLIC BREAKEVEN       //
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
input int maxOpenPositions = 5;
input double MaxDrawdownPercent = 10.0;  // NOUVEAU: DD max autorisé

//=========================//
//   RISK LIMIT SETTINGS    //
//=========================//
input group "Risk Limit Settings";
input bool  useRiskLimit       = false;
input double RiskLimitPct      = 1.0;

//=========================//
//       VARIABLES          //
//=========================//
int fastMAHandle = INVALID_HANDLE;
int midMAHandle  = INVALID_HANDLE;
int slowMAHandle = INVALID_HANDLE;
int longMAHandle = INVALID_HANDLE;
int adxHandle    = INVALID_HANDLE;
int osmaHandle   = INVALID_HANDLE;
int rsiHandle    = INVALID_HANDLE;
int atrHandle    = INVALID_HANDLE;      // NOUVEAU: Handle ATR

// Handles pour timeframe supérieur
int higherTF_FastMAHandle = INVALID_HANDLE;
int higherTF_SlowMAHandle = INVALID_HANDLE;

datetime fastMASignalTime = 0;
datetime midMASignalTime  = 0;
datetime slowMASignalTime = 0;
datetime longMASignalTime = 0;
datetime adxSignalTime    = 0;
datetime osmaSignalTime   = 0;
datetime rsiSignalTime    = 0;

static datetime lastBarTime = 0;
static double maxEquity = 0.0;          // NOUVEAU: Pour calcul DD

BreakevenCycliqueContext breakevenCtx;
bool breakevenInitialise = false;

// NOUVEAU: Structure pour statistiques avancées
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

struct SignalSnapshot {
    bool fastMA_active;
    bool midMA_active;
    bool slowMA_active;
    bool longMA_active;
    bool adx_active;
    bool osma_active;
    bool rsi_active;
    bool volatility_ok;
    bool higher_tf_confirm;    // NOUVEAU: Confirmation TF supérieur
    double total_score;
    string signal_summary;
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    if(!ValidateInputs())
    {
        Print("ERREUR: Paramètres d'entrée invalides!");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    InitializeIndicators();
    InitializeStats();

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
            Print("InitBreakevenCycliqueContext a échoué, on désactive la fonctionnalité.");
    }

    PrintConfiguration();
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| NOUVEAU: Initialisation des statistiques                         |
//+------------------------------------------------------------------+
void InitializeStats()
{
    stats.totalTrades = 0;
    stats.winTrades = 0;
    stats.loseTrades = 0;
    stats.totalProfit = 0.0;
    stats.maxDD = 0.0;
    stats.winRate = 0.0;
    stats.lastUpdate = TimeCurrent();
    maxEquity = AccountInfoDouble(ACCOUNT_EQUITY);
}

//+------------------------------------------------------------------+
//| AMÉLIORÉ: Validation renforcée                                   |
//+------------------------------------------------------------------+
bool ValidateInputs()
{
    // Validation des périodes
    if(FastMAPeriod <= 0 || MidMAPeriod <= 0 || SlowMAPeriod <= 0 || LongMAPeriod <= 0)
    {
        Print("ERREUR: Périodes des moyennes mobiles doivent être > 0");
        return false;
    }
    
    // Validation de la logique des périodes MA
    if(FastMAPeriod >= MidMAPeriod || MidMAPeriod >= SlowMAPeriod || SlowMAPeriod >= LongMAPeriod)
    {
        Print("ERREUR: Les périodes MA doivent être croissantes (Fast < Mid < Slow < Long)");
        return false;
    }
    
    // Validation des poids
    double totalWeight = WeightFastMA + WeightMidMA + WeightSlowMA + WeightLongMA + 
                        WeightADX + WeightOsMA + WeightRSI + WeightVolatility;
    if(totalWeight < 50.0 || totalWeight > 150.0)
        PrintFormat("AVERTISSEMENT: Poids total = %.1f%% (recommandé: 90-110%%)", totalWeight);
    
    // Validation seuils de score
    if(MinScoreToTrade >= MinScoreStrong)
    {
        Print("ERREUR: MinScoreStrong doit être > MinScoreToTrade");
        return false;
    }
    
    // Validation ATR
    if(UseDynamicSL && ATRMultiplierSL <= 0)
    {
        Print("ERREUR: ATRMultiplierSL doit être > 0");
        return false;
    }
    
    if(UseDynamicTP && ATRMultiplierTP <= 0)
    {
        Print("ERREUR: ATRMultiplierTP doit être > 0");
        return false;
    }
    
    // Validation drawdown max
    if(MaxDrawdownPercent < 0 || MaxDrawdownPercent > 100)
    {
        Print("ERREUR: MaxDrawdownPercent doit être entre 0 et 100");
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| AMÉLIORÉ: Initialisation des indicateurs avec gestion d'erreurs  |
//+------------------------------------------------------------------+
void InitializeIndicators()
{
    // Indicateurs principaux
    if(UseFastMA)  
    {
        fastMAHandle = iMA(_Symbol, FastMATF, FastMAPeriod, 0, MAType, PriceType);
        if(fastMAHandle == INVALID_HANDLE)
        {
            PrintFormat("ERREUR: Fast MA (P:%d, TF:%s)", FastMAPeriod, EnumToString(FastMATF));
            ExpertRemove();
            return;
        }
    }
    
    if(UseMidMA)   
    {
        midMAHandle = iMA(_Symbol, MidMATF, MidMAPeriod, 0, MAType, PriceType);
        if(midMAHandle == INVALID_HANDLE)
        {
            PrintFormat("ERREUR: Mid MA (P:%d, TF:%s)", MidMAPeriod, EnumToString(MidMATF));
            ExpertRemove();
            return;
        }
    }
    
    if(UseSlowMA)  
    {
        slowMAHandle = iMA(_Symbol, SlowMATF, SlowMAPeriod, 0, MAType, PriceType);
        if(slowMAHandle == INVALID_HANDLE)
        {
            PrintFormat("ERREUR: Slow MA (P:%d, TF:%s)", SlowMAPeriod, EnumToString(SlowMATF));
            ExpertRemove();
            return;
        }
    }
    
    if(UseLongMA)  
    {
        longMAHandle = iMA(_Symbol, LongMATF, LongMAPeriod, 0, MAType, PriceType);
        if(longMAHandle == INVALID_HANDLE)
        {
            PrintFormat("ERREUR: Long MA (P:%d, TF:%s)", LongMAPeriod, EnumToString(LongMATF));
            ExpertRemove();
            return;
        }
    }
    
    if(UseADX)     
    {
        adxHandle = iADX(_Symbol, ADXTF, ADXPeriod);
        if(adxHandle == INVALID_HANDLE)
        {
            PrintFormat("ERREUR: ADX (P:%d, TF:%s)", ADXPeriod, EnumToString(ADXTF));
            ExpertRemove();
            return;
        }
    }
    
    if(UseOsMA)    
    {
        osmaHandle = iOsMA(_Symbol, OsMATF, OsMAFastPeriod, OsMASlowPeriod, OsMASignalPeriod, PRICE_CLOSE);
        if(osmaHandle == INVALID_HANDLE)
        {
            PrintFormat("ERREUR: OsMA (TF:%s)", EnumToString(OsMATF));
            ExpertRemove();
            return;
        }
    }
    
    if(UseRSI)     
    {
        rsiHandle = iRSI(_Symbol, RSITF, RSIPeriod, PRICE_CLOSE);
        if(rsiHandle == INVALID_HANDLE)
        {
            PrintFormat("ERREUR: RSI (P:%d, TF:%s)", RSIPeriod, EnumToString(RSITF));
            ExpertRemove();
            return;
        }
    }
    
    // NOUVEAU: ATR pour SL/TP dynamiques
    if(UseDynamicSL || UseDynamicTP)
    {
        atrHandle = iATR(_Symbol, TF_EA, ATRPeriod);
        if(atrHandle == INVALID_HANDLE)
        {
            PrintFormat("ERREUR: ATR (P:%d)", ATRPeriod);
            ExpertRemove();
            return;
        }
    }
    
    // NOUVEAU: Indicateurs pour timeframe supérieur
    if(UseMultiTimeframeConfirmation && HigherTF != TF_EA)
    {
        higherTF_FastMAHandle = iMA(_Symbol, HigherTF, FastMAPeriod, 0, MAType, PriceType);
        higherTF_SlowMAHandle = iMA(_Symbol, HigherTF, SlowMAPeriod, 0, MAType, PriceType);
        
        if(higherTF_FastMAHandle == INVALID_HANDLE || higherTF_SlowMAHandle == INVALID_HANDLE)
        {
            Print("ERREUR: Impossible de créer les indicateurs TF supérieur");
            //UseMultiTimeframeConfirmation = false;
        }
    }
    
    Print("✓ Tous les indicateurs initialisés avec succès");
}

//+------------------------------------------------------------------+
//| NOUVEAU: Affichage configuration                                  |
//+------------------------------------------------------------------+
void PrintConfiguration()
{
    PrintFormat("=== Configuration EA Multi-Position Enhanced ===");
    PrintFormat("Symbole: %s | Magic: %I64u | TF: %s", _Symbol, MagicNumber, EnumToString(TF_EA));
    PrintFormat("=== Poids Signaux ===");
    PrintFormat("Fast:%.1f%% Mid:%.1f%% Slow:%.1f%% Long:%.1f%%", 
                WeightFastMA, WeightMidMA, WeightSlowMA, WeightLongMA);
    PrintFormat("ADX:%.1f%% OsMA:%.1f%% RSI:%.1f%% Vol:%.1f%%", 
                WeightADX, WeightOsMA, WeightRSI, WeightVolatility);
    
    double totalWeight = WeightFastMA + WeightMidMA + WeightSlowMA + WeightLongMA + 
                        WeightADX + WeightOsMA + WeightRSI + WeightVolatility;
    PrintFormat("Total: %.1f%% | Min: %.1f%% | Strong: %.1f%%", 
                totalWeight, MinScoreToTrade, MinScoreStrong);
    
    PrintFormat("=== Gestion Risque ===");
    PrintFormat("SL Dyn: %s | TP Dyn: %s | Trailing: %s", 
                UseDynamicSL ? "OUI" : "NON",
                UseDynamicTP ? "OUI" : "NON", 
                UseTrailingStop ? "OUI" : "NON");
    PrintFormat("Max Positions: %d | Max DD: %.1f%%", maxOpenPositions, MaxDrawdownPercent);
}

//+------------------------------------------------------------------+
//| NOUVEAU: Vérification drawdown                                   |
//+------------------------------------------------------------------+
bool CheckDrawdown()
{
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(currentEquity > maxEquity)
        maxEquity = currentEquity;
    
    double currentDD = ((maxEquity - currentEquity) / maxEquity) * 100.0;
    
    if(currentDD > MaxDrawdownPercent)
    {
        PrintFormat("⚠️ DRAWDOWN LIMITE ATTEINTE: %.2f%% (max: %.1f%%) - Trading suspendu", 
                   currentDD, MaxDrawdownPercent);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| NOUVEAU: Filtre de session                                       |
//+------------------------------------------------------------------+
bool IsValidTradingSession()
{
    if(!UseSessionFilter) return true;
    
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int currentHour = dt.hour;
    
    // Sessions approximatives (heure serveur)
    bool asianSession = (currentHour >= 0 && currentHour < 9);      // 00:00-09:00
    bool londonSession = (currentHour >= 8 && currentHour < 17);    // 08:00-17:00  
    bool newYorkSession = (currentHour >= 13 && currentHour < 22);  // 13:00-22:00
    
    if(asianSession && TradeAsianSession) return true;
    if(londonSession && TradeLondonSession) return true;
    if(newYorkSession && TradeNewYorkSession) return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| NOUVEAU: Calcul SL/TP dynamiques basés sur ATR                   |
//+------------------------------------------------------------------+
void CalculateDynamicLevels(double &sl_pips, double &tp_pips)
{
    sl_pips = StopLossPips;     // Valeurs par défaut
    tp_pips = TakeProfitPips;
    
    if(atrHandle == INVALID_HANDLE) return;
    
    double atr[1];
    if(CopyBuffer(atrHandle, 0, 0, 1, atr) <= 0) return;
    
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if(point <= 0) return;
    
    double atr_pips = atr[0] / point;
    
    if(UseDynamicSL)
    {
        sl_pips = atr_pips * ATRMultiplierSL;
        sl_pips = MathMax(sl_pips, 10.0);  // SL minimum 10 pips
        sl_pips = MathMin(sl_pips, 200.0); // SL maximum 200 pips
    }
    
    if(UseDynamicTP)
    {
        tp_pips = atr_pips * ATRMultiplierTP;
        tp_pips = MathMax(tp_pips, sl_pips * 1.5); // TP minimum 1.5x SL
        tp_pips = MathMin(tp_pips, 500.0);         // TP maximum 500 pips
    }
}

//+------------------------------------------------------------------+
//| NOUVEAU: Confirmation timeframe supérieur                        |
//+------------------------------------------------------------------+
bool GetHigherTimeframeConfirmation(bool isBuy)
{
    if(!UseMultiTimeframeConfirmation) return true;
    if(higherTF_FastMAHandle == INVALID_HANDLE || higherTF_SlowMAHandle == INVALID_HANDLE) 
        return true;
    
    double fastMA[1], slowMA[1];
    if(CopyBuffer(higherTF_FastMAHandle, 0, 0, 1, fastMA) <= 0) return true;
    if(CopyBuffer(higherTF_SlowMAHandle, 0, 0, 1, slowMA) <= 0) return true;
    
    if(isBuy)
        return (fastMA[0] > slowMA[0]); // Tendance haussière sur TF supérieur
    else
        return (fastMA[0] < slowMA[0]); // Tendance baissière sur TF supérieur
}

//+------------------------------------------------------------------+
//| AMÉLIORÉ: Analyse des signaux avec confirmation TF supérieur     |
//+------------------------------------------------------------------+
SignalSnapshot AnalyzeSignals(bool isBuy)
{
    SignalSnapshot signals;
    signals.total_score = 0.0;
    signals.signal_summary = "";
    signals.higher_tf_confirm = false;
    
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
    
    // Vérification confirmation TF supérieur
    signals.higher_tf_confirm = GetHigherTimeframeConfirmation(isBuy);
    double tfBonus = signals.higher_tf_confirm ? 5.0 : -10.0; // Bonus/malus
    
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
    
    // Application du bonus/malus TF supérieur
    signals.total_score += tfBonus;
    if(signals.total_score < 0.0) signals.total_score = 0.0;
    
    // Construction du résumé
    string tfStatus = signals.higher_tf_confirm ? "✓" : "✗";
    if(StringLen(activeSignals) > 0)
    {
        signals.signal_summary = StringFormat("S%.0f%% TF%s [%s]", 
                                            signals.total_score, 
                                            tfStatus,
                                            StringSubstr(activeSignals, 0, StringLen(activeSignals)-1));
    }
    else
    {
        signals.signal_summary = StringFormat("NoSignal TF%s", tfStatus);
    }
    
    return signals;
}

//+------------------------------------------------------------------+
//| NOUVEAU: Gestion du trailing stop                                |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
    if(!UseTrailingStop) return;
    
    CTrade trade;
    trade.SetExpertMagicNumber(MagicNumber);
    
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double trailDistance = TrailingDistance * point;
    double trailStep = TrailingStep * point;
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
            
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double price_open = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl = PositionGetDouble(POSITION_SL);
            double current_price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                              : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            if(type == POSITION_TYPE_BUY)
            {
                double new_sl = current_price - trailDistance;
                if(new_sl > sl + trailStep)
                {
                    trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
                }
            }
            else // SELL
            {
                double new_sl = current_price + trailDistance;
                if(new_sl < sl - trailStep)
                {
                    trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| NOUVEAU: (Stub) Filtre news – à compléter selon ton data source   |
//+------------------------------------------------------------------+
bool IsNewsBlockActive()
{
    if(!UseNewsFilter) return false;
    // Ici, tu devrais appeler une fonction externe ou un indicateur de news.
    // Pour l'instant, on fait simple: jamais bloqué. À compléter selon ta source.
    return false;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    static datetime lastUpdateStats = 0;
    
    bool isNew = IsNewCandle();
    if(isNew)
    {
        if(!IndicatorsReady()) return;
        UpdateSignalTimestamps();
    }
    
    // Mise à jour stats périodique (par ex. toutes les minutes)
    if(TimeCurrent() - lastUpdateStats >= 60)
    {
        UpdateStats();
        lastUpdateStats = TimeCurrent();
    }
    
    // Gestion Trailing Stop
    ManageTrailingStop();
    
    // Gestion Breakeven Cyclique
    if(useBreakevenCyclique && breakevenInitialise)
        ManageBreakevenCyclique(breakevenCtx);
    
    if(isNew)
    {
        // Arrête si drawdown trop élevé
        if(!CheckDrawdown()) return;
        
        // Filtre session
        if(!IsValidTradingSession()) return;
        
        // Filtre news
        if(IsNewsBlockActive()) return;
        
        int openCount = CountOpenPositions();
        if((maxOpenPositions == 0 || openCount < maxOpenPositions) && CheckTradeAllowed())
        {
            // Calculer score BUY/SELL
            SignalSnapshot buySignals  = AnalyzeSignals(true);
            SignalSnapshot sellSignals = AnalyzeSignals(false);
            
            // Vérif score opposé
            if(buySignals.total_score >= MinScoreToTrade && sellSignals.total_score <= MaxScoreOpposite)
            {
                ExecuteBuyTrade(buySignals.signal_summary);
            }
            else if(sellSignals.total_score >= MinScoreToTrade && buySignals.total_score <= MaxScoreOpposite)
            {
                ExecuteSellTrade(sellSignals.signal_summary);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Vérifie si trading autorisé                                      |
//+------------------------------------------------------------------+
bool CheckTradeAllowed()
{
    if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == 0)
    {
        Print("Trading non autorisé sur ", _Symbol);
        return false;
    }
    if(UseSpreadFilter && !PassesSpreadFilter())
        return false;
    return true;
}

//+------------------------------------------------------------------+
//| Exécution d'un trade BUY                                         |
//+------------------------------------------------------------------+
void ExecuteBuyTrade(string summary)
{
    double sl_pips, tp_pips;
    CalculateDynamicLevels(sl_pips, tp_pips);
    
    SamBotUtils::tradeOpen_pips(
       _Symbol,
       MagicNumber,
       ORDER_TYPE_BUY,
       sl_pips,
       tp_pips,
       lotDyna,
       LotSize,
       RiskPercent,
       UseSpreadFilter,
       (int)MaxAllowedSpreadPts,
       summary
    );
    stats.totalTrades++;
}

//+------------------------------------------------------------------+
//| Exécution d'un trade SELL                                        |
//+------------------------------------------------------------------+
void ExecuteSellTrade(string summary)
{
    double sl_pips, tp_pips;
    CalculateDynamicLevels(sl_pips, tp_pips);
    
    SamBotUtils::tradeOpen_pips(
       _Symbol,
       MagicNumber,
       ORDER_TYPE_SELL,
       sl_pips,
       tp_pips,
       lotDyna,
       LotSize,
       RiskPercent,
       UseSpreadFilter,
       (int)MaxAllowedSpreadPts,
       summary
    );
    stats.totalTrades++;
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
    return total;
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
            if(PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
                totalRisk += ComputePositionRisk(ticket);
            }
        }
    }
    return totalRisk;
}

//+------------------------------------------------------------------+
//| Calcule le risque (en $) du nouveau trade potentiel             |
//+------------------------------------------------------------------+
double ComputeNewTradeRisk()
{
    double volume = lotDyna ? LotSize : LotSize;
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double riskDistance = StopLossPips * point;
    if(riskDistance <= 0.0) return 0.0;

    double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    if(tickSize <= 0.0 || tickValue <= 0.0) return 0.0;

    double ticks      = riskDistance / tickSize;
    return ticks * tickValue * volume;
}

//+------------------------------------------------------------------+
//| Met à jour les statistics de performance (win/lose, etc.)        |
//+------------------------------------------------------------------+
void UpdateStats()
{
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double profit = equity - balance;
    stats.totalProfit = profit;

    // On parcourt les trades fermés récents pour compter win/lose
    HistorySelect(TimeCurrent() - 3600*24, TimeCurrent()); // 24h
    int deals = HistoryDealsTotal();
    int wins = 0, losses = 0;
    for(int i = 0; i < deals; i++)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealSelect(ticket))
        {
            if(HistoryDealGetInteger(ticket,DEAL_MAGIC) != MagicNumber) continue;
            double profitDeal = HistoryDealGetDouble(ticket, DEAL_PROFIT );
            if(profitDeal > 0) wins++;
            else if(profitDeal < 0) losses++;
        }
    }
    stats.winTrades = wins;
    stats.loseTrades = losses;
    stats.winRate = (stats.totalTrades > 0) ? (double)wins / stats.totalTrades * 100.0 : 0.0;

    // Mettre à jour maxDD
    double currentDD = ((maxEquity - equity) / maxEquity) * 100.0;
    if(currentDD > stats.maxDD) stats.maxDD = currentDD;

    stats.lastUpdate = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(fastMAHandle != INVALID_HANDLE)   IndicatorRelease(fastMAHandle);
    if(midMAHandle != INVALID_HANDLE)    IndicatorRelease(midMAHandle);
    if(slowMAHandle != INVALID_HANDLE)   IndicatorRelease(slowMAHandle);
    if(longMAHandle != INVALID_HANDLE)   IndicatorRelease(longMAHandle);
    if(adxHandle != INVALID_HANDLE)      IndicatorRelease(adxHandle);
    if(osmaHandle != INVALID_HANDLE)     IndicatorRelease(osmaHandle);
    if(rsiHandle != INVALID_HANDLE)      IndicatorRelease(rsiHandle);
    if(atrHandle != INVALID_HANDLE)      IndicatorRelease(atrHandle);
    if(higherTF_FastMAHandle != INVALID_HANDLE) IndicatorRelease(higherTF_FastMAHandle);
    if(higherTF_SlowMAHandle != INVALID_HANDLE) IndicatorRelease(higherTF_SlowMAHandle);

    if(useBreakevenCyclique && breakevenInitialise)
    {
        DeinitBreakevenCycliqueContext(breakevenCtx);
        Print("BreakevenCycliqueContext détruit au OnDeinit.");
    }
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
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Vérifie si les buffers indicateurs sont prêts                    |
//+------------------------------------------------------------------+
bool IndicatorsReady()
{
    double buffer[2];
    if(UseFastMA && CopyBuffer(fastMAHandle, 0, 0, 2, buffer) <= 0)    return false;
    if(UseMidMA && CopyBuffer(midMAHandle,  0, 0, 2, buffer) <= 0)    return false;
    if(UseSlowMA && CopyBuffer(slowMAHandle,0, 0, 2, buffer) <= 0)    return false;
    if(UseLongMA && CopyBuffer(longMAHandle,0, 0, 2, buffer) <= 0)    return false;
    if(UseADX && CopyBuffer(adxHandle,      0, 0, 1, buffer) <= 0)    return false;
    if(UseOsMA && CopyBuffer(osmaHandle,    0, 0, 2, buffer) <= 0)    return false;
    if(UseRSI && CopyBuffer(rsiHandle,      0, 0, 1, buffer) <= 0)    return false;
    if((UseDynamicSL || UseDynamicTP) && CopyBuffer(atrHandle,        0, 0, 1, buffer) <= 0)    return false;
    if(UseMultiTimeframeConfirmation && HigherTF != TF_EA)
    {
        double hfast[1], hslow[1];
        if(CopyBuffer(higherTF_FastMAHandle, 0, 0, 1, hfast) <= 0) return false;
        if(CopyBuffer(higherTF_SlowMAHandle, 0, 0, 1, hslow) <= 0) return false;
    }
    return true;
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
    if(signalTime == 0) return false;
    int barsSinceSignal = iBarShift(_Symbol, tf, signalTime, false);
    return (barsSinceSignal >= 0 && barsSinceSignal <= ttlCandles);
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
//| Filtre spread                                                     |
//+------------------------------------------------------------------+
bool PassesSpreadFilter()
{
    if(!UseSpreadFilter) return true;
    long spread = 0;
    if(!SymbolInfoInteger(_Symbol, SYMBOL_SPREAD, spread))
    {
        Print("Impossible de récupérer le spread.");
        return false;
    }
    if(spread > MaxAllowedSpreadPts)
    {
        PrintFormat("Spread trop élevé : %d points (max = %.0f)", spread, MaxAllowedSpreadPts);
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Filtre volatilité                                                 |
//+------------------------------------------------------------------+
bool PassesVolatilityFilter()
{
    if(!UseVolatilityFilter) return true;
    double high = iHigh(_Symbol, VolatilityTF, 1);
    double low  = iLow(_Symbol, VolatilityTF, 1);
    double rangePips = (high - low) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if(rangePips < MinVolatilityPips)
    {
        PrintFormat("Volatilité trop faible : %.2f pips (min = %.2f)", rangePips, MinVolatilityPips);
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Calcule le risque (en $) d'une position donnée (ticket)          |
//+------------------------------------------------------------------+
double ComputePositionRisk(ulong ticket)
{
    if(!PositionSelectByTicket(ticket))
        return 0.0;

    double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double slPrice    = PositionGetDouble(POSITION_SL);
    double volume     = PositionGetDouble(POSITION_VOLUME);

    if(slPrice <= 0.0)
        return 0.0;

    ENUM_POSITION_TYPE typePos = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double riskDistance = 0.0;

    if(typePos == POSITION_TYPE_BUY)
    {
        if(slPrice < entryPrice)
            riskDistance = entryPrice - slPrice;
        else
            return 0.0;
    }
    else // POSITION_TYPE_SELL
    {
        if(slPrice > entryPrice)
            riskDistance = slPrice - entryPrice;
        else
            return 0.0;
    }

    double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    if(tickSize <= 0.0 || tickValue <= 0.0)
        return 0.0;

    double ticks      = riskDistance / tickSize;
    return ticks * tickValue * volume;
}

//+------------------------------------------------------------------+
