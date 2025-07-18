//+------------------------------------------------------------------+
//|           MultiPositionEA_Breakeven_RiskLimit_PerSymbol.mq5      |
//|         Exemple d'EA multi-positions avec Breakeven et Limite     |
//|         de risque par symbole                                     |
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
input int FastMATTL               = 3;     // TTL pour signal Fast MA
input int MidMATTL                = 3;     // TTL pour signal Mid MA
input int SlowMATTL               = 3;     // TTL pour signal Slow MA
input int LongMATTL               = 3;     // TTL pour signal Long MA
input int ADXTTL                  = 3;     // TTL pour signal ADX
input double ADXThreshold         = 20.0;  // Seuil ADX
input int OsMATTL                 = 3;     // TTL pour signal OsMA
input int RSITTL                  = 3;     // TTL pour signal RSI
input double RSIOverboughtLevel   = 70.0;  // Niveau surachat RSI
input double RSIOversoldLevel     = 30.0;  // Niveau survente RSI
input double MinVolatilityPips    = 5.0;   // Volatilité min (pips)
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

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
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

    return(INIT_SUCCEEDED);
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
            // Calcul du risque AGGRÉGÉ existant (pour ce symbole) + risque potentiel du nouveau trade
            double balance      = AccountInfoDouble(ACCOUNT_BALANCE);
            double existingRisk = ComputeTotalRiskExisting();  // Ne somme que positions sur _Symbol
            double newRisk      = ComputeNewTradeRisk();

            bool okToOpen = true;
            if(useRiskLimit)
            {
                double totalRisk = existingRisk + newRisk;
                double pctRisk   = (totalRisk / balance) * 100.0;
                if(pctRisk > RiskLimitPct)
                {
                    okToOpen = false;
                    PrintFormat(
                      "Ouverture interdite : risque total sur %s = %.2f%% du solde (max = %.2f%%).",
                      _Symbol, pctRisk, RiskLimitPct
                    );
                }
            }

            if(okToOpen)
            {
                if(CheckBuyConditions())
                    ExecuteBuyTrade();
                else if(CheckSellConditions())
                    ExecuteSellTrade();
            }
        }
    }
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

    if((UseFastMA && fastMAHandle == INVALID_HANDLE) ||
       (UseMidMA && midMAHandle   == INVALID_HANDLE) ||
       (UseSlowMA && slowMAHandle == INVALID_HANDLE) ||
       (UseLongMA && longMAHandle == INVALID_HANDLE) ||
       (UseADX    && adxHandle    == INVALID_HANDLE) ||
       (UseOsMA   && osmaHandle   == INVALID_HANDLE) ||
       (UseRSI    && rsiHandle    == INVALID_HANDLE))
    {
        Print("Erreur création handles indicateurs.");
        ExpertRemove();
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
//| Conditions d'achat                                               |
//+------------------------------------------------------------------+
bool CheckBuyConditions()
{
    if(UseFastMA && !IsSignalValid(fastMASignalTime, FastMATF, FastMATTL))   return(false);
    if(UseMidMA && !IsSignalValid(midMASignalTime,  MidMATF,  MidMATTL))      return(false);
    if(UseSlowMA && !IsSignalValid(slowMASignalTime, SlowMATF, SlowMATTL))     return(false);
    if(UseLongMA && !IsSignalValid(longMASignalTime, LongMATF, LongMATTL))     return(false);
    if(UseADX && !IsSignalValid(adxSignalTime,      ADXTF,     ADXTTL))        return(false);
    if(UseOsMA && !IsSignalValid(osmaSignalTime,    OsMATF,    OsMATTL))       return(false);
    if(UseRSI && !IsSignalValid(rsiSignalTime,      RSITF,     RSITTL))       return(false);
    if(!PassesSpreadFilter())    return(false);
    if(!PassesVolatilityFilter())return(false);
    return(true);
}

//+------------------------------------------------------------------+
//| Conditions de vente                                              |
//+------------------------------------------------------------------+
bool CheckSellConditions()
{
    if(UseFastMA && !IsFastMABelowMidMA())         return(false);
    if(UseMidMA && !IsMidMABelowSlowMA())          return(false);
    if(UseSlowMA && !IsSlowMABelowLongMA())        return(false);
    if(UseLongMA && !IsSignalValid(longMASignalTime, LongMATF, LongMATTL))    return(false);
    if(UseADX && !IsSignalValid(adxSignalTime,       ADXTF,     ADXTTL))      return(false);
    if(UseOsMA && !IsSignalValid(osmaSignalTime,     OsMATF,    OsMATTL))     return(false);
    if(UseRSI && !IsSignalValid(rsiSignalTime,       RSITF,     RSITTL))     return(false);
    if(!PassesSpreadFilter())     return(false);
    if(!PassesVolatilityFilter()) return(false);
    return(true);
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
void ExecuteBuyTrade()
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
       (int)MaxAllowedSpreadPts
    );
}

//+------------------------------------------------------------------+
//| Exécution d'un trade SELL                                        |
//+------------------------------------------------------------------+
void ExecuteSellTrade()
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
       (int)MaxAllowedSpreadPts
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
