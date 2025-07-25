#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\Trade.mqh>
#include <SamBotUtils.mqh>
#include <Generic\HashMap.mqh>
#include <BreakevenCyclique.mqh>
#property strict

//=========================//
//         GENERAL         //
//=========================//
input group "General Settings";
input ENUM_TIMEFRAMES TF_EA = PERIOD_CURRENT;
input ulong MagicNumber = 123456; // Identifiant unique pour les ordres de cet EA

//=========================//
//        TOGGLE SWITCHES        //
//=========================//
input group "Enable/Disable Indicators and Filters";
input bool UseFastMA = true; // Activer l'utilisation de la Moyenne Mobile Rapide
input bool UseMidMA = true;  // Activer l'utilisation de la Moyenne Mobile Intermédiaire
input bool UseSlowMA = true; // Activer l'utilisation de la Moyenne Mobile Lente
input bool UseLongMA = true; // Activer l'utilisation de la Moyenne Mobile Longue
input bool UseADX = true;    // Activer l'utilisation de l'ADX
input bool UseOsMA = true;   // Activer l'utilisation de l'OsMA
input bool UseRSI = true;    // Activer l'utilisation du RSI
input bool UseVolatilityFilter = true; // Activer le filtre de volatilité
input bool UseSpreadFilter = true;    // Activer le filtre de spread
input bool lotDyna = false;           // Activer la gestion dynamique de la taille des lots

//=========================//
//         TIMEFRAMES        //
//=========================//
input group "Timeframes for Indicators";
input ENUM_TIMEFRAMES FastMATF = PERIOD_M15;   // Timeframe de la Moyenne Mobile Rapide
input ENUM_TIMEFRAMES MidMATF = PERIOD_M15;    // Timeframe de la Moyenne Mobile Intermédiaire
input ENUM_TIMEFRAMES SlowMATF = PERIOD_M30;   // Timeframe de la Moyenne Mobile Lente
input ENUM_TIMEFRAMES LongMATF = PERIOD_H1;    // Timeframe de la Moyenne Mobile Longue
input ENUM_TIMEFRAMES ADXTF = PERIOD_M15;     // Timeframe de l'ADX
input ENUM_TIMEFRAMES OsMATF = PERIOD_M15;    // Timeframe de l'OsMA
input ENUM_TIMEFRAMES RSITF = PERIOD_M15;     // Timeframe du RSI
input ENUM_TIMEFRAMES VolatilityTF = PERIOD_M15; // Timeframe pour le calcul de la volatilité

//=========================//
//          PERIODS          //
//=========================//
input group "Indicator Periods";
input int FastMAPeriod = 8;    // Période de la Moyenne Mobile Rapide
input int MidMAPeriod = 38;   // Période de la Moyenne Mobile Intermédiaire
input int SlowMAPeriod = 90;  // Période de la Moyenne Mobile Lente
input int LongMAPeriod = 200; // Période de la Moyenne Mobile Longue
input int ADXPeriod = 14;     // Période de l'ADX
input int OsMAFastPeriod = 12;  // Période rapide de l'OsMA
input int OsMASlowPeriod = 26;  // Période lente de l'OsMA
input int OsMASignalPeriod = 9; // Période du signal de l'OsMA
input int RSIPeriod = 14;     // Période du RSI
input int VolatilityPeriod = 14; // Période pour le calcul de la volatilité

//=========================//
//      OTHER SETTINGS       //
//=========================//
input group "Other Indicator Settings";
input ENUM_MA_METHOD MAType = MODE_LWMA;       // Méthode de calcul des Moyennes Mobiles
input ENUM_APPLIED_PRICE PriceType = PRICE_CLOSE; // Prix appliqué pour les Moyennes Mobiles
input int FastMATTL = 3;                     // Nombre de bougies pour la validité du signal Fast MA
input int MidMATTL = 3;                      // Nombre de bougies pour la validité du signal Mid MA
input int SlowMATTL = 3;                     // Nombre de bougies pour la validité du signal Slow MA
input int LongMATTL = 3;                     // Nombre de bougies pour la validité du signal Long MA
input int ADXTTL = 3;                      // Nombre de bougies pour la validité du signal ADX
input double ADXThreshold = 20.0;           // Seuil de l'ADX pour considérer la tendance comme forte
input int OsMATTL = 3;                     // Nombre de bougies pour la validité du signal OsMA
input int RSITTL = 3;                      // Nombre de bougies pour la validité du signal RSI
input double RSIOverboughtLevel = 70.0;      // Niveau de surachat du RSI
input double RSIOversoldLevel = 30.0;       // Niveau de survente du RSI
input double MinVolatilityPips = 5.0;       // Volatilité minimale en pips pour autoriser le trading
input double MaxAllowedSpreadPts = 20;      // Spread maximal autorisé en points

//=========================//
//    TRADING PARAMETERS     //
//=========================//
input group "Trading Parameters";
input double LotSize = 0.1;       // Taille de lot fixe
input double RiskPercent = 1.0;   // Pourcentage du capital à risquer par trade (pour lot dynamique)
input double StopLossPips = 100;  // Stop Loss en pips
input double TakeProfitPips = 300; // Take Profit en pips


// Dans la section des variables d'entrée:
input group "Cyclic Breakeven Settings";
input bool   useBreakevenCyclique    = false;
input ENUM_TIMEFRAMES timeframeBreakeven = PERIOD_H1;
input int    candlesAvantBreakeven   = 5;
input bool   breakevenEnProfitSeulement = true;
input int    nombreVerificationsBreakeven = 0;


//=========================//
//       HANDLES ET TEMPS    //
//=========================//
int fastMAHandle = INVALID_HANDLE;
int midMAHandle = INVALID_HANDLE;
int slowMAHandle = INVALID_HANDLE;
int longMAHandle = INVALID_HANDLE;
int adxHandle = INVALID_HANDLE;
int osmaHandle = INVALID_HANDLE;
int rsiHandle = INVALID_HANDLE;

datetime fastMASignalTime = 0;
datetime midMASignalTime = 0;
datetime slowMASignalTime = 0;
datetime longMASignalTime = 0;

datetime adxSignalTime = 0;
datetime osmaSignalTime = 0;
datetime rsiSignalTime = 0;

//--- Contexte pour gérer le Breakeven Cyclique
BreakevenCycliqueContext breakevenCtx;
bool   breakevenInitialise = false;

//=========================//
//         INIT / TICK       //
//=========================//
int OnInit() {
    InitializeIndicators();
    
   // --- Initialisation du Breakeven Cyclique si demandé
    if(useBreakevenCyclique)
    {
        breakevenInitialise = InitBreakevenCycliqueContext(
                                 breakevenCtx,
                                 MagicNumber,               // magicNumber de tes ordres EA
                                 _Symbol,                   // on surveille le symbole du chart
                                 timeframeBreakeven,        // input ENUM_TIMEFRAMES
                                 candlesAvantBreakeven,     // input nombre de bougies
                                 breakevenEnProfitSeulement,// input profitOnly
                                 nombreVerificationsBreakeven// input nbVerifications
                              );
        if(!breakevenInitialise)
        {
            Print("InitBreakevenCycliqueContext a échoué.");
            
        }
        
    }
    
    return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    // Libération des handles
    if (fastMAHandle != INVALID_HANDLE)
        IndicatorRelease(fastMAHandle);
    if (midMAHandle != INVALID_HANDLE)
        IndicatorRelease(midMAHandle);
    if (slowMAHandle != INVALID_HANDLE)
        IndicatorRelease(slowMAHandle);
    if (longMAHandle != INVALID_HANDLE)
        IndicatorRelease(longMAHandle);
    if (adxHandle != INVALID_HANDLE)
        IndicatorRelease(adxHandle);
    if (osmaHandle != INVALID_HANDLE)
        IndicatorRelease(osmaHandle);
    if (rsiHandle != INVALID_HANDLE)
        IndicatorRelease(rsiHandle);
        
    // --- Détruire le contexte Breakeven Cyclique s’il a été initialisé
    if(useBreakevenCyclique && breakevenInitialise)
    {
        DeinitBreakevenCycliqueContext(breakevenCtx);
        Print("BreakevenCycliqueContext détruit au OnDeinit.");
    }
}

void OnTick()
{
    bool isNew = IsNewCandle();

    if (isNew)
    {
        if (!IndicatorsReady())
            return; // On sort si les indicateurs ne sont pas prêts sur une nouvelle bougie
        UpdateSignalTimestamps();
    }

     // --- Gestion du breakeven cyclique (si activé et bien initialisé)
    if ( useBreakevenCyclique && breakevenInitialise)
    {
        ManageBreakevenCyclique(breakevenCtx);
    }

    // Logique d'ouverture de trade (s'exécute seulement sur une nouvelle bougie après les vérifications)
    if (isNew && !SamBotUtils::IsTradeOpen(_Symbol, MagicNumber))
    {
        if (CheckBuyConditions())
            ExecuteBuyTrade();
        else if (CheckSellConditions())
            ExecuteSellTrade();
    }
}


//=========================//
//    FONCTIONS DÉCLARÉES   //
//=========================//

//--- Initialisation
void InitializeIndicators() {
    if (UseFastMA)
        fastMAHandle = iMA(_Symbol, FastMATF, FastMAPeriod, 0, MAType, PriceType);

    if (UseMidMA)
        midMAHandle = iMA(_Symbol, MidMATF, MidMAPeriod, 0, MAType, PriceType);

    if (UseSlowMA)
        slowMAHandle = iMA(_Symbol, SlowMATF, SlowMAPeriod, 0, MAType, PriceType);

    if (UseLongMA)
        longMAHandle = iMA(_Symbol, LongMATF, LongMAPeriod, 0, MAType, PriceType);

    if (UseADX)
        adxHandle = iADX(_Symbol, ADXTF, ADXPeriod);

    if (UseOsMA)
        osmaHandle = iOsMA(_Symbol, OsMATF, OsMAFastPeriod, OsMASlowPeriod, OsMASignalPeriod, PRICE_CLOSE);

    if (UseRSI)
        rsiHandle = iRSI(_Symbol, RSITF, RSIPeriod, PRICE_CLOSE);

    // Vérification des handles
    if ((UseFastMA && fastMAHandle == INVALID_HANDLE) ||
        (UseMidMA && midMAHandle == INVALID_HANDLE) ||
        (UseSlowMA && slowMAHandle == INVALID_HANDLE) ||
        (UseLongMA && longMAHandle == INVALID_HANDLE) ||
        (UseADX && adxHandle == INVALID_HANDLE) ||
        (UseOsMA && osmaHandle == INVALID_HANDLE) ||
        (UseRSI && rsiHandle == INVALID_HANDLE)) {
        Print("Erreur création handles indicateurs.");
        ExpertRemove();
    }
}

static datetime lastBarTime = 0;

bool IsNewCandle() {
    datetime currentBarTime = iTime(_Symbol, TF_EA, 0);
    if (currentBarTime != lastBarTime) {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}

bool IndicatorsReady() {
    double buffer[2];
    if (UseFastMA && CopyBuffer(fastMAHandle, 0, 0, 2, buffer) <= 0)
        return false;
    if (UseMidMA && CopyBuffer(midMAHandle, 0, 0, 2, buffer) <= 0)
        return false;
    if (UseSlowMA && CopyBuffer(slowMAHandle, 0, 0, 2, buffer) <= 0)
        return false;
    if (UseLongMA && CopyBuffer(longMAHandle, 0, 0, 2, buffer) <= 0)
        return false;
    if (UseADX && CopyBuffer(adxHandle, 0, 0, 1, buffer) <= 0)
        return false;
    if (UseOsMA && CopyBuffer(osmaHandle, 0, 0, 2, buffer) <= 0)
        return false;
    if (UseRSI && CopyBuffer(rsiHandle, 0, 0, 1, buffer) <= 0)
        return false;
    return true;
}

bool CheckTradeAllowed() {
    if (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == 0) {
        Print("Trading non autorisé sur ", _Symbol);
        return false;
    }
    if (SamBotUtils::IsTradeOpen(_Symbol, MagicNumber)) {
        Print("Position déjà ouverte sur ", _Symbol);
        return false;
    }
    return true;
}

void UpdateSignalTimestamps() {
    if (UseFastMA && IsFastMAAboveMidMA())
        fastMASignalTime = TimeCurrent();
    if (UseMidMA && IsMidMAAboveSlowMA())
        midMASignalTime = TimeCurrent();
    if (UseSlowMA && IsSlowMAAboveLongMA())
        slowMASignalTime = TimeCurrent();
    if (UseLongMA && IsPullbackToMA(true))
        longMASignalTime = TimeCurrent();
    if (UseADX && IsADXStrongEnough())
        adxSignalTime = TimeCurrent();
    if (UseOsMA && IsMomentumResuming(true))
        osmaSignalTime = TimeCurrent();
    if (UseRSI && IsRSIInBuyZone())
        rsiSignalTime = TimeCurrent();
}

bool IsSignalValid(datetime signalTime, ENUM_TIMEFRAMES tf, int ttlCandles) {
    if (signalTime == 0)
        return false;
    int barsSinceSignal = iBarShift(_Symbol, tf, signalTime, false);
    return (barsSinceSignal >= 0 && barsSinceSignal <= ttlCandles);
}

bool CheckBuyConditions() {
    if (UseFastMA && !IsSignalValid(fastMASignalTime, FastMATF, FastMATTL))
        return false;
    if (UseMidMA && !IsSignalValid(midMASignalTime, MidMATF, MidMATTL))
        return false;
    if (UseSlowMA && !IsSignalValid(slowMASignalTime, SlowMATF, SlowMATTL))
        return false;
    if (UseLongMA && !IsSignalValid(longMASignalTime, LongMATF, LongMATTL))
        return false;
    if (UseADX && !IsSignalValid(adxSignalTime, ADXTF, ADXTTL))
        return false;
    if (UseOsMA && !IsSignalValid(osmaSignalTime, OsMATF, OsMATTL))
        return false;
    if (UseRSI && !IsSignalValid(rsiSignalTime, RSITF, RSITTL))
        return false;
    if (!PassesSpreadFilter())
        return false;
    if (!PassesVolatilityFilter())
        return false;
    return true;
}

bool CheckSellConditions() {
    if (UseFastMA && !IsFastMABelowMidMA())
        return false;
    if (UseMidMA && !IsMidMABelowSlowMA())
        return false;
    if (UseSlowMA && !IsSlowMABelowLongMA())
        return false;
    if (UseLongMA && !IsSignalValid(longMASignalTime, LongMATF, LongMATTL))
        return false;
    if (UseADX && !IsSignalValid(adxSignalTime, ADXTF, ADXTTL))
        return false;
    if (UseOsMA && !IsSignalValid(osmaSignalTime, OsMATF, OsMATTL))
        return false;
    if (UseRSI && !IsSignalValid(rsiSignalTime, RSITF, RSITTL))
        return false;
    if (!PassesSpreadFilter())
        return false;
    if (!PassesVolatilityFilter())
        return false;
    return true;
}

bool PassesSpreadFilter() {
    if (!UseSpreadFilter)
        return true;
    long spread = 0;
    if (!SymbolInfoInteger(_Symbol, SYMBOL_SPREAD, spread)) {
        Print("Impossible de récupérer le spread.");
        return false;
    }
    if (spread > MaxAllowedSpreadPts) {
        PrintFormat("Spread trop élevé : %d points (max = %.0f)", spread, MaxAllowedSpreadPts);
        return false;
    }
    return true;
}

bool PassesVolatilityFilter() {
    if (!UseVolatilityFilter)
        return true;
    double high = iHigh(_Symbol, VolatilityTF, 1);
    double low = iLow(_Symbol, VolatilityTF, 1);
    double rangePips = (high - low) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if (rangePips < MinVolatilityPips) {
        PrintFormat("Volatilité trop faible : %.2f pips (min = %.2f)", rangePips, MinVolatilityPips);
        return false;
    }
    return true;
}

bool IsFastMAAboveMidMA() {
    double valsFast[2],
           valsMid[2];
    CopyBuffer(fastMAHandle, 0, 0, 2, valsFast);
    CopyBuffer(midMAHandle, 0, 0, 2, valsMid);
    return (valsFast[1] < valsMid[1] && valsFast[0] > valsMid[0]);
}

bool IsFastMABelowMidMA() {
    double valsFast[2],
           valsMid[2];
    CopyBuffer(fastMAHandle, 0, 0, 2, valsFast);
    CopyBuffer(midMAHandle, 0, 0, 2, valsMid);
    return (valsFast[1] > valsMid[1] && valsFast[0] < valsMid[0]);
}

bool IsMidMAAboveSlowMA() {
    double valsMid[2],
           valsSlow[2];
    CopyBuffer(midMAHandle, 0, 0, 2, valsMid);
    CopyBuffer(slowMAHandle, 0, 0, 2, valsSlow);
    return (valsMid[1] < valsSlow[1] && valsMid[0] > valsSlow[0]);
}

bool IsMidMABelowSlowMA() {
    double valsMid[2],
           valsSlow[2];
    CopyBuffer(midMAHandle, 0, 0, 2, valsMid);
    CopyBuffer(slowMAHandle, 0, 0, 2, valsSlow);
    return (valsMid[1] > valsSlow[1] && valsMid[0] < valsSlow[0]);
}

bool IsSlowMAAboveLongMA() {
    double valsSlow[2],
           valsLong[2];
    CopyBuffer(slowMAHandle, 0, 0, 2, valsSlow);
    CopyBuffer(longMAHandle, 0, 0, 2, valsLong);
    return (valsSlow[1] < valsLong[1] && valsSlow[0] > valsLong[0]);
}

bool IsSlowMABelowLongMA() {
    double valsSlow[2],
           valsLong[2];
    CopyBuffer(slowMAHandle, 0, 0, 2, valsSlow);
    CopyBuffer(longMAHandle, 0, 0, 2, valsLong);
    return (valsSlow[1] > valsLong[1] && valsSlow[0] < valsLong[0]);
}

bool IsPullbackToMA(bool isBuy) {
    double valsLong[2];
    CopyBuffer(longMAHandle, 0, 0, 2, valsLong);
    double ma0 = valsLong[0];
    double price = iClose(_Symbol, TF_EA, 1);
    return (isBuy ? (price > ma0) : (price < ma0));
}

bool IsADXStrongEnough() {
    double val[1];
    CopyBuffer(adxHandle, 0, 0, 1, val);
    return (val[0] > ADXThreshold);
}

bool IsMomentumResuming(bool isBuy) {
    double valsOsma[2];
    CopyBuffer(osmaHandle, 0, 0, 2, valsOsma);
    double hist0 = valsOsma[0],
           hist1 = valsOsma[1];
    return (isBuy ? (hist1 < 0 && hist0 > 0) : (hist1 > 0 && hist0 < 0));
}

bool IsRSIInBuyZone() {
    double val[1];
    CopyBuffer(rsiHandle, 0, 0, 1, val);
    return (val[0] < RSIOversoldLevel);
}

bool IsRSIInSellZone() {
    double val[1];
    CopyBuffer(rsiHandle, 0, 0, 1, val);
    return (val[0] > RSIOverboughtLevel);
}

void ExecuteBuyTrade() {
    double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    // Les valeurs de StopLossPips et TakeProfitPips sont déjà en pips.
    SamBotUtils::tradeOpen_pips(_Symbol, MagicNumber, ORDER_TYPE_BUY, StopLossPips, TakeProfitPips, lotDyna, LotSize, RiskPercent, UseSpreadFilter, (int)MaxAllowedSpreadPts);
}

void ExecuteSellTrade() {
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    // Les valeurs de StopLossPips et TakeProfitPips sont déjà en pips.
    SamBotUtils::tradeOpen_pips(_Symbol, MagicNumber, ORDER_TYPE_SELL, StopLossPips, TakeProfitPips, lotDyna, LotSize, RiskPercent, UseSpreadFilter, (int)MaxAllowedSpreadPts);
}

// Fin du fichier