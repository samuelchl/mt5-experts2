#property strict

//=========================//
//      MA SETTINGS        //
//=========================//

input ENUM_TIMEFRAMES TF_EA = PERIOD_CURRENT;

input bool   UseFastMA           = true;
input int    FastMAPeriod        = 8;
input ENUM_TIMEFRAMES FastMATF   = PERIOD_M15;
input int    FastMATTL           = 3;

input bool   UseMidMA            = true;
input int    MidMAPeriod         = 38;
input ENUM_TIMEFRAMES MidMATF    = PERIOD_M15;
input int    MidMATTL            = 3;

input bool   UseSlowMA           = true;
input int    SlowMAPeriod        = 90;
input ENUM_TIMEFRAMES SlowMATF   = PERIOD_M30;
input int    SlowMATTL           = 3;

input bool   UseLongMA           = true;
input int    LongMAPeriod        = 200;
input ENUM_TIMEFRAMES LongMATF   = PERIOD_H1;
input int    LongMATTL           = 3;

input ENUM_MA_METHOD MAType      = MODE_LWMA;
input ENUM_APPLIED_PRICE PriceType = PRICE_CLOSE;

//=========================//
//      ADX SETTINGS       //
//=========================//
input bool   UseADX              = true;
input int    ADXPeriod           = 14;
input ENUM_TIMEFRAMES ADXTF     = PERIOD_M15;
input int    ADXTTL              = 3;
input double ADXThreshold        = 20.0;

//=========================//
//      OsMA SETTINGS      //
//=========================//
input bool   UseOsMA             = true;
input int    OsMAFastPeriod      = 12;
input int    OsMASlowPeriod      = 26;
input int    OsMASignalPeriod    = 9;
input ENUM_TIMEFRAMES OsMATF     = PERIOD_M15;
input int    OsMATTL             = 3;

//=========================//
//      RSI SETTINGS       //
//=========================//
input bool   UseRSI              = true;
input int    RSIPeriod           = 14;
input ENUM_TIMEFRAMES RSITF      = PERIOD_M15;
input int    RSITTL              = 3;
input double RSIOverboughtLevel  = 70.0;
input double RSIOversoldLevel    = 30.0;

//=========================//
//   VOLATILITY SETTINGS   //
//=========================//
input bool   UseVolatilityFilter = true;
input int    VolatilityPeriod    = 14;
input ENUM_TIMEFRAMES VolatilityTF = PERIOD_M15;
input double MinVolatilityPips   = 5.0;

//=========================//
//     SPREAD SETTINGS     //
//=========================//
input bool   UseSpreadFilter     = true;
input double MaxAllowedSpreadPts = 20;

//=========================//
//   TRADING PARAMETERS    //
//=========================//
input double LotSize             = 0.1;
input double RiskPercent         = 1.0;
input double StopLossPips        = 100;
input double TakeProfitPips      = 300;

//=========================//
//     HANDLES ET TEMPS    //
//=========================//
int fastMAHandle, midMAHandle, slowMAHandle, longMAHandle;
int adxHandle, osmaHandle, rsiHandle;

datetime fastMASignalTime = 0;
datetime midMASignalTime  = 0;
datetime slowMASignalTime = 0;
datetime longMASignalTime = 0;

datetime adxSignalTime    = 0;
datetime osmaSignalTime   = 0;
datetime rsiSignalTime    = 0;

//=========================//
//        INIT / TICK      //
//=========================//
int OnInit()
{
   InitializeIndicators();
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(!IsNewCandle()) return;
   if(!IndicatorsReady()) return;
   if(!IsTradeAllowed()) return;

   UpdateSignalTimestamps();

   if(CheckBuyConditions()) ExecuteBuyTrade();
   else if(CheckSellConditions()) ExecuteSellTrade();
}

//=========================//
//   FONCTIONS DÉCLARÉES   //
//=========================//

//--- Initialisation
void InitializeIndicators()
{
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
       (UseMidMA  && midMAHandle  == INVALID_HANDLE) ||
       (UseSlowMA && slowMAHandle == INVALID_HANDLE) ||
       (UseLongMA && longMAHandle == INVALID_HANDLE) ||
       (UseADX    && adxHandle    == INVALID_HANDLE) ||
       (UseOsMA   && osmaHandle   == INVALID_HANDLE) ||
       (UseRSI    && rsiHandle    == INVALID_HANDLE))
   {
      Print("Erreur lors de la création des handles d’indicateurs.");
      ExpertRemove();
   }
}

datetime lastBarTime = 0;

bool IsNewCandle()
{
   datetime currentBarTime = iTime(_Symbol, TF_EA, 0);
   if (currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

bool IndicatorsReady()
{
   // Buffers pour vérification
   double buffer[];

   if (UseFastMA && CopyBuffer(fastMAHandle, 0, 0, 2, buffer) <= 0) return false;
   if (UseMidMA  && CopyBuffer(midMAHandle,  0, 0, 2, buffer) <= 0) return false;
   if (UseSlowMA && CopyBuffer(slowMAHandle, 0, 0, 2, buffer) <= 0) return false;
   if (UseLongMA && CopyBuffer(longMAHandle, 0, 0, 2, buffer) <= 0) return false;

   if (UseADX    && CopyBuffer(adxHandle,    0, 0, 2, buffer) <= 0) return false;
   if (UseOsMA   && CopyBuffer(osmaHandle,   0, 0, 2, buffer) <= 0) return false;
   if (UseRSI    && CopyBuffer(rsiHandle,    0, 0, 2, buffer) <= 0) return false;

   return true;
}

bool IsTradeAllowed()
{
   // Vérifie si trading est autorisé (dans les options de la plateforme)
   if (!IsTradeAllowed())
   {
      Print("Trading non autorisé sur ", _Symbol);
      return false;
   }

   // Vérifie qu’il n’y a pas déjà une position ouverte sur ce symbole
   if (PositionSelect(_Symbol))
   {
      Print("Position déjà ouverte sur ", _Symbol);
      return false;
   }

   return true;
}

void UpdateSignalTimestamps()
{
   if (UseFastMA && IsFastMAAboveMidMA())
      fastMASignalTime = TimeCurrent();

   if (UseMidMA && IsMidMAAboveSlowMA())
      midMASignalTime = TimeCurrent();

   if (UseSlowMA && IsSlowMAAboveLongMA())
      slowMASignalTime = TimeCurrent();

   if (UseLongMA && IsPullbackToMA(true))  // Exemple Buy
      longMASignalTime = TimeCurrent();

   if (UseADX && IsADXStrongEnough())
      adxSignalTime = TimeCurrent();

   if (UseOsMA && IsMomentumResuming(true)) // Exemple Buy
      osmaSignalTime = TimeCurrent();

   if (UseRSI && IsRSIInBuyZone())         // Exemple Buy
      rsiSignalTime = TimeCurrent();
}

bool IsSignalValid(datetime signalTime, ENUM_TIMEFRAMES tf, int ttlCandles)
{
   if (signalTime == 0)
      return false; // Aucun signal enregistré

   datetime currentBarTime = iTime(_Symbol, tf, 0);
   int barsSinceSignal = iBarShift(_Symbol, tf, signalTime, false);

   if (barsSinceSignal >= 0 && barsSinceSignal <= ttlCandles)
      return true;

   return false;
}

bool CheckBuyConditions()
{
   if (UseFastMA && !IsSignalValid(fastMASignalTime, FastMATF, FastMATTL)) return false;
   if (UseMidMA  && !IsSignalValid(midMASignalTime, MidMATF, MidMATTL))    return false;
   if (UseSlowMA && !IsSignalValid(slowMASignalTime, SlowMATF, SlowMATTL)) return false;
   if (UseLongMA && !IsSignalValid(longMASignalTime, LongMATF, LongMATTL)) return false;

   if (UseADX    && !IsSignalValid(adxSignalTime, ADXTF, ADXTTLCandles))   return false;
   if (UseOsMA   && !IsSignalValid(osmaSignalTime, OsMATF, OsMATTL))       return false;
   if (UseRSI    && !IsSignalValid(rsiSignalTime, RSITF, RSITTL))          return false;

   if (!PassesSpreadFilter()) return false;
   if (!PassesVolatilityFilter()) return false;

   return true;
}

bool PassesSpreadFilter()
{
   long spread = 0;
   if (!SymbolInfoInteger(_Symbol, SYMBOL_SPREAD, spread))
   {
      Print("Impossible de récupérer le spread.");
      return false;
   }

   if (spread > MaxAllowedSpread)
   {
      Print("Spread trop élevé : ", spread, " points (max autorisé = ", MaxAllowedSpread, ")");
      return false;
   }

   return true;
}



/*
bool IsNewCandle();
bool IndicatorsReady();
bool IsTradeAllowed();

//--- Signaux TTL
void UpdateSignalTimestamps();
bool IsSignalValid(datetime signalTime, ENUM_TIMEFRAMES tf, int ttlCandles);

//--- Conditions BUY / SELL
bool CheckBuyConditions();
bool CheckSellConditions();

//--- Sous-conditions logiques
bool IsFastMAAboveMidMA();
bool IsMidMAAboveSlowMA();
bool IsSlowMAAboveLongMA();
bool IsPullbackToMA(bool isBuy);
bool IsADXStrongEnough();
bool IsMomentumResuming(bool isBuy);
bool IsRSIInBuyZone();
bool IsRSIInSellZone();

//--- Exécution trade
void ExecuteBuyTrade();
void ExecuteSellTrade();
void SetStopLossAndTakeProfit(ulong ticket, double entryPrice, bool isBuy);

//--- Filtres
bool IsSpreadAcceptable();
bool IsVolatilityAcceptable();*/
