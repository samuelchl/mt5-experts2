//+------------------------------------------------------------------+
//|                                      Strategie_ADX_ZScore_opt.mq5|
//|                       EA MT5 : ADX + JMA-ZScore intégré dans EA  |
//|           Version optimisée pour éviter les gels lors du backtest |
//+------------------------------------------------------------------+
#property copyright "Adaptation MT5"
#property version   "1.00"
#property strict

#include <SamBotUtils.mqh>

//====================== INPUTS GÉNÉRAUX EA ======================//
//--- Timeframe & identification
input ENUM_TIMEFRAMES TF                        = PERIOD_CURRENT;
input int             MAGIC_NUMBER               = 15975344;

//--- Stop Loss / Take Profit (en %)
input double          stop_loss_pct              = 1.0;
input double          take_profit_pct            = 2.0;
input bool            sortie_dynamique           = false;

//--- Gestion de lot
input bool            GestionDynamiqueLot        = false;
input double          RisqueParTradePct          = 1.0;
input double          LotFixe                    = 0.1;

//--- Paramètres ADX
input int             ADX_Period                 = 14;
input double          Seuil_ADX                  = 25.0;

//--- Trailing Stop
input bool            utiliser_trailing_stop     = false;
input double          trailing_stop_pct          = 0.5;

//--- Prises de profit partielles
input bool            utiliser_prise_profit_partielle = false;
input double          tranche_prise_profit_pct   = 0.02;
input int             nb_tp_partiel              = 2;

//--- Filtre spread
input bool            UseMaxSpread               = false;
input int             MaxSpreadPoints            = 40;
input bool            SL_BreakEVEN_after_first_partialTp = false;

//--- Désactiver la fermeture combinatoire des petites positions
input bool            Disable_CloseSmallProfits   = true;

//--- Gestion fermeture volume bas
input bool            closeIfVolumeLow           = false;
input double          percentToCloseTrade        = 0.20;

//--- Debug / Alive
input bool            showAlive                  = false;

//--- Filtre trading le vendredi
input bool            tradeVendredi              = false;

//--- Fermeture dynamique sur bougies opposées
input int             OppositecandleConsecutiveToClose = 3;
input ENUM_TIMEFRAMES TF_opposite_candle        = PERIOD_M15;
// Limite de barres à vérifier dans HasConsecutiveBarsSinceOpen
input int             MaxBarsToCheck             = 50;

//--- Nombre maximum de positions ouvertes
input int             MaxOpenPositions           = 5;

//====================== INPUTS “PENDING” ======================//
input double          ZThreshold                 = 1.0;    // Seuil absolu du z-score
input int             MaxPendingBars             = 3;      // Nb max de bougies à attendre

//====================== INPUTS JMA-ZSCORE ======================//
// Pour la partie JMA, nous n’avons besoin que de la période et du phase
input int             inpPeriod   = 14;           // Période pour JMA (smooth)
input double          inpPhase    = 0.0;          // Phase pour JMA

// Période de calcul du z-score (doit être >= 2)
input int             inpZsPeriod = 30;           // Taille de la fenêtre pour le z-score

input bool useZScoreFilter = true;

//====================== VARIABLES GLOBALES ======================//
// Handle ADX
int     handle_ADX       = INVALID_HANDLE;
double  ADXBuf[], plusDIBuf[], minusDIBuf[];

// Flags internes pour “pending”
bool    pendingBuy       = false;
bool    pendingSell      = false;
int     pendingBarsCount = 0;

// Compteur de bougies traitées, utilisé dans le lissage JMA
int     smoothCount      = 0;

// Buffer circulaire pour stocker les dernières valeurs JMA (pour calcul de z-score)
double  zHistory[];    // sera dimensionné à inpZsPeriod
int     zCount          = 0; // Nombre de valeurs initialisées dans zHistory[]

#define _smoothInstances     1
#define _smoothInstancesSize 10
#define _smoothRingSize      11
// Tableau de travail pour iSmooth (JMA) : [anneau][instances * taille]
double workSmooth[_smoothRingSize][_smoothInstances * _smoothInstancesSize];

//-------------------------------------------------------------------
//| Expert initialization                                           |
//-------------------------------------------------------------------
int OnInit()
  {
   // 1) Création du handle ADX
   handle_ADX = iADX(_Symbol, TF, ADX_Period);
   if(handle_ADX == INVALID_HANDLE)
     {
      Print("Erreur à la création du handle ADX");
      return(INIT_FAILED);
     }

   // 2) Dimensionner le buffer zHistory[] pour le z-score
   if(inpZsPeriod < 2)
     {
      Print("inpZsPeriod doit être >= 2");
      return(INIT_FAILED);
     }
   ArrayResize(zHistory, inpZsPeriod);
   ArrayInitialize(zHistory, 0.0);
   zCount = 0;

   // 3) Initialiser workSmooth à zéro
   for(int r = 0; r < _smoothRingSize; r++)
     for(int c = 0; c < _smoothInstances * _smoothInstancesSize; c++)
        workSmooth[r][c] = 0.0;
   smoothCount = 0;

   // 4) Initialiser les buffers ADX (on utilisera CopyBuffer)
   ArraySetAsSeries(ADXBuf, true);
   ArraySetAsSeries(plusDIBuf, true);
   ArraySetAsSeries(minusDIBuf, true);

   return(INIT_SUCCEEDED);
  }

//-------------------------------------------------------------------
//| Expert deinitialization                                         |
//-------------------------------------------------------------------
void OnDeinit(const int reason)
  {
   if(handle_ADX != INVALID_HANDLE)
      IndicatorRelease(handle_ADX);
  }

//-------------------------------------------------------------------
//| Compte le nombre de positions ouvertes pour symbole et Magic    |
//-------------------------------------------------------------------
int GetCountOpenPosition()
  {
   int total = PositionsTotal();
   int count = 0;
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         string symb = PositionGetString(POSITION_SYMBOL);
         ulong  magic= (ulong)PositionGetInteger(POSITION_MAGIC);
         if(symb == _Symbol && magic == (ulong)MAGIC_NUMBER)
            count++;
        }
     }
   return(count);
  }

//-------------------------------------------------------------------
//| Vérifie si on peut ouvrir un trade (vendredi / max positions)   |
//-------------------------------------------------------------------
bool CanOpenTrade()
  {
   // Filtre trading le vendredi (0=dimanche ... 5=vendredi)
   MqlDateTime now; TimeToStruct(TimeCurrent(), now);
   if(now.day_of_week == 5 && !tradeVendredi)
      return(false);

   // Limite du nombre de positions ouvertes
   if(GetCountOpenPosition() >= MaxOpenPositions)
      return(false);

   return(true);
  }

//-------------------------------------------------------------------
//| Détecte N bougies consécutives de couleur “direction”            |
//| Limité à MaxBarsToCheck bougies pour rester rapide              |
//-------------------------------------------------------------------
bool HasConsecutiveBarsSinceOpen(datetime open_time,
                                 int       direction,     // +1 ou -1
                                 int       requiredCount, // ex. 3
                                 ENUM_TIMEFRAMES tf = PERIOD_M15)
  {
   // Trouver index de la bougie tf contenant open_time
   int startBar = iBarShift(_Symbol, tf, open_time, true);
   if(startBar < 0)
      return(false);

   int count = 0;
   // Ne parcourir que MaxBarsToCheck bougies au maximum
   int maxCheck = MathMin(startBar, MaxBarsToCheck);
   for(int i = 1; i <= maxCheck; i++)
     {
      double op = iOpen (_Symbol, tf, i);
      double cl = iClose(_Symbol, tf, i);
      bool sameDir = (direction > 0 ? (cl > op) : (cl < op));
      if(sameDir)
        {
         if(++count >= requiredCount)
            return(true);
        }
      else
        {
         count = 0;
        }
     }
   return(false);
  }

//-------------------------------------------------------------------
//| calcule le JMA “iSmooth” pour un prix donné                     |
//| price = dernière clôture ; length = inpPeriod ; phase = inpPhase|
//| i = index (nombre de bougies traitées jusqu’ici)                |
//-------------------------------------------------------------------
double iSmooth(double price, double length, double phase, int i, int instance=0)
  {
   int _indP = (i - 1) % _smoothRingSize;
   if(_indP < 0) _indP += _smoothRingSize;
   int _indC = i % _smoothRingSize;
   int _inst = instance * _smoothInstancesSize;

   if(i == 0 || length <= 1.0)
     {
      // Première valeur ou période <= 1: on stocke simplement price
      int k = 0;
      // Indices 5 et 6 pour bsmax, bsmin ; 7 pour volty ; 8 pour vsum ; 9 pour avolty
      for(; k < 7; k++)
         workSmooth[_indC][_inst + k] = price;
      for(; k < _smoothInstancesSize; k++)
         workSmooth[_indC][_inst + k] = 0.0;
      return(price);
     }

   // Calculs intermédiaires pour JMA
   double len1  = MathMax(MathLog(MathSqrt(0.5 * (length - 1.0))) / MathLog(2.0) + 2.0, 0.0);
   double pow1  = MathMax(len1 - 2.0, 0.5);
   double del1  = price - workSmooth[_indP][_inst + 5]; // bsmax
   double absDel1 = MathAbs(del1);
   double del2  = price - workSmooth[_indP][_inst + 6]; // bsmin
   double absDel2 = MathAbs(del2);
   int    _indF = i - MathMin(i, 10);
   _indF = (_indF % _smoothRingSize + _smoothRingSize) % _smoothRingSize;

   workSmooth[_indC][_inst + 7] = (absDel1 > absDel2) ? absDel1 : (absDel1 < absDel2) ? absDel2 : 0.0; // volty
   workSmooth[_indC][_inst + 8] = workSmooth[_indP][_inst + 8] + (workSmooth[_indC][_inst + 7] - workSmooth[_indF][_inst + 7]) * 0.1; // vsum
   workSmooth[_indC][_inst + 9] = workSmooth[_indP][_inst + 9] + (2.0 / (MathMax(4.0 * length, 30.0) + 1.0)) * (workSmooth[_indC][_inst + 8] - workSmooth[_indP][_inst + 9]); // avolty

   double dVolty    = (workSmooth[_indC][_inst + 9] > 0.0) ? workSmooth[_indC][_inst + 7] / workSmooth[_indC][_inst + 9] : 0.0;
   double dVoltyTmp = MathPow(len1, 1.0 / pow1);
   if(dVolty > dVoltyTmp) dVolty = dVoltyTmp;
   if(dVolty < 1.0)       dVolty = 1.0;

   double pow2 = MathPow(dVolty, pow1);
   double len2 = MathSqrt(0.5 * (length - 1.0)) * len1;
   double Kv   = MathPow(len2 / (len2 + 1.0), MathSqrt(pow2));

   workSmooth[_indC][_inst + 5] = (del1 > 0.0) ? price : price - Kv * del1; // bsmax
   workSmooth[_indC][_inst + 6] = (del2 < 0.0) ? price : price - Kv * del2; // bsmin

   double corr  = MathMax(MathMin(phase, 100.0), -100.0) / 100.0 + 1.5;
   double beta  = 0.45 * (length - 1.0) / (0.45 * (length - 1.0) + 2.0);
   double alpha = MathPow(beta, pow2);

   workSmooth[_indC][_inst + 0] = price + alpha * (workSmooth[_indP][_inst + 0] - price);
   workSmooth[_indC][_inst + 1] = (price - workSmooth[_indC][_inst + 0]) * (1.0 - beta) + beta * workSmooth[_indP][_inst + 1];
   workSmooth[_indC][_inst + 2] = workSmooth[_indC][_inst + 0] + corr * workSmooth[_indC][_inst + 1];
   workSmooth[_indC][_inst + 3] = (workSmooth[_indC][_inst + 2] - workSmooth[_indP][_inst + 4]) * ((1.0 - alpha) * (1.0 - alpha)) + (alpha * alpha) * workSmooth[_indP][_inst + 3];
   workSmooth[_indC][_inst + 4] = workSmooth[_indP][_inst + 4] + workSmooth[_indC][_inst + 3];

   return(workSmooth[_indC][_inst + 4]);
  }

//-------------------------------------------------------------------
//| Calcule le Z-Score à partir du buffer zHistory[]                |
//| Retourne 0 si zCount < inpZsPeriod                              |
//-------------------------------------------------------------------
double computeZScore()
  {
   if(zCount < inpZsPeriod)
      return(0.0);

   double sum = 0.0, sumSq = 0.0;
   for(int i = 0; i < inpZsPeriod; i++)
     {
      sum   += zHistory[i];
      sumSq += zHistory[i] * zHistory[i];
     }
   double mean = sum / inpZsPeriod;
   double variance = (sumSq / inpZsPeriod) - (mean * mean);
   double stddev = (variance > 0.0 ? MathSqrt(variance) : 0.0);
   double lastVal = zHistory[0]; // La valeur JMA la plus récente

   if(stddev == 0.0)
      return(0.0);
   return((lastVal - mean) / stddev);
  }

//-------------------------------------------------------------------
//| Expert tick                                                     |
//-------------------------------------------------------------------
void OnTick()
  {
  
      SamBotUtils::CloseSmallProfitablePositionsV2();
  
   static datetime lastBarTime = 0;
   datetime currTime = iTime(_Symbol, TF, 0);
   if(currTime == lastBarTime) return;
   lastBarTime = currTime;

   // 1) Mise à jour JMA et zHistory (toujours fait, même si on n’utilise pas le filtre)
   {
      double lastClose = iClose(_Symbol, TF, 1);
      double jmaVal     = iSmooth(lastClose, (double)inpPeriod, inpPhase, smoothCount);
      smoothCount++;

      for(int i = inpZsPeriod - 1; i >= 1; i--)
         zHistory[i] = zHistory[i - 1];
      zHistory[0] = jmaVal;
      if(zCount < inpZsPeriod) zCount++;
   }

   // 2) Si on utilise le filtre Z-Score et qu’on est en “pending”, on gère le pending
   if(useZScoreFilter && (pendingBuy || pendingSell))
     {
      pendingBarsCount++;
      if(pendingBarsCount > MaxPendingBars)
        {
         pendingBuy       = false;
         pendingSell      = false;
         pendingBarsCount = 0;
         PrintFormat("⏳ Abandon après %d bougies sans Z-Score.", MaxPendingBars);
         return;
        }

      double z = computeZScore();
      if(pendingBuy && z <= -ZThreshold)
        {
         PrintFormat("🟢 Z=%.3f <= -%.2f → OUVERTURE BUY", z, ZThreshold);
         SamBotUtils::tradeOpen(_Symbol, (ulong)MAGIC_NUMBER,
                                ORDER_TYPE_BUY,
                                stop_loss_pct,
                                take_profit_pct,
                                GestionDynamiqueLot,
                                LotFixe,
                                RisqueParTradePct,
                                UseMaxSpread,
                                MaxSpreadPoints);
         pendingBuy       = false;
         pendingBarsCount = 0;
        }
      else if(pendingSell && z >= +ZThreshold)
        {
         PrintFormat("🔴 Z=%.3f >= +%.2f → OUVERTURE SELL", z, ZThreshold);
         SamBotUtils::tradeOpen(_Symbol, (ulong)MAGIC_NUMBER,
                                ORDER_TYPE_SELL,
                                stop_loss_pct,
                                take_profit_pct,
                                GestionDynamiqueLot,
                                LotFixe,
                                RisqueParTradePct,
                                UseMaxSpread,
                                MaxSpreadPoints);
         pendingSell      = false;
         pendingBarsCount = 0;
        }
      else
        {
         PrintFormat("⏳ J’attends Z=%.3f (seuil=±%.2f), reste %d bougies.",
                     z, ZThreshold, MaxPendingBars - pendingBarsCount + 1);
        }
      return;
     }

   // 3) AUCUN “pending” (ou filtre désactivé) : on évalue ADX immédiatement
   if(handle_ADX == INVALID_HANDLE) 
      return;
   if(CopyBuffer(handle_ADX, 0, 0, 1, ADXBuf)    < 1) return;
   if(CopyBuffer(handle_ADX, 1, 0, 1, plusDIBuf) < 1) return;
   if(CopyBuffer(handle_ADX, 2, 0, 1, minusDIBuf)< 1) return;

   double adxVal = ADXBuf[0];
   double pDI    = plusDIBuf[0];
   double mDI    = minusDIBuf[0];
   bool   forte  = (adxVal > Seuil_ADX);
   bool   buyC   = forte && (pDI > mDI);
   bool   sellC  = forte && (mDI > pDI);

   int spreadPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(UseMaxSpread && spreadPts > MaxSpreadPoints)
      return;

   // Si on n’utilise pas le filtre Z-Score, on peut ouvrir direct sur ADX
   if(!useZScoreFilter)
     {
      if(buyC && CanOpenTrade())
        {
         PrintFormat("🔔 ADX BUY=%.2f → OUVERTURE BUY (pas de Z-Score)", adxVal);
         SamBotUtils::tradeOpen(_Symbol, (ulong)MAGIC_NUMBER,
                                ORDER_TYPE_BUY,
                                stop_loss_pct,
                                take_profit_pct,
                                GestionDynamiqueLot,
                                LotFixe,
                                RisqueParTradePct,
                                UseMaxSpread,
                                MaxSpreadPoints);
         return;
        }
      if(sellC && CanOpenTrade())
        {
         PrintFormat("🔔 ADX SELL=%.2f → OUVERTURE SELL (pas de Z-Score)", adxVal);
         SamBotUtils::tradeOpen(_Symbol, (ulong)MAGIC_NUMBER,
                                ORDER_TYPE_SELL,
                                stop_loss_pct,
                                take_profit_pct,
                                GestionDynamiqueLot,
                                LotFixe,
                                RisqueParTradePct,
                                UseMaxSpread,
                                MaxSpreadPoints);
         return;
        }
     }
   else // Si on utilise le filtre Z-Score, on passe en “pending” sur ADX
     {
      if(buyC && CanOpenTrade())
        {
         pendingBuy       = true;
         pendingSell      = false;
         pendingBarsCount = 1;
         PrintFormat("🔔 ADX BUY=%.2f → en attente Z-Score", adxVal);
         return;
        }
      if(sellC && CanOpenTrade())
        {
         pendingSell      = true;
         pendingBuy       = false;
         pendingBarsCount = 1;
         PrintFormat("🔔 ADX SELL=%.2f → en attente Z-Score", adxVal);
         return;
        }
     }

   // 4) AUCUN signal ADX ou on n’ouvre pas : on gère les sorties classiques
   if(sortie_dynamique && SamBotUtils::IsTradeOpen(_Symbol, (ulong)MAGIC_NUMBER))
     {
      double profit  = PositionGetDouble(POSITION_PROFIT);
      ulong  ticket  = PositionGetInteger(POSITION_TICKET);
      ulong  typePos = PositionGetInteger(POSITION_TYPE);
      datetime open_t = (datetime)PositionGetInteger(POSITION_TIME);

      if(profit < 0.0)
        {
         if(typePos == POSITION_TYPE_BUY &&
            HasConsecutiveBarsSinceOpen(open_t, -1, OppositecandleConsecutiveToClose, TF_opposite_candle))
            SamBotUtils::tradeClose(_Symbol, (ulong)MAGIC_NUMBER, ticket);
         else if(typePos == POSITION_TYPE_SELL &&
                 HasConsecutiveBarsSinceOpen(open_t, +1, OppositecandleConsecutiveToClose, TF_opposite_candle))
            SamBotUtils::tradeClose(_Symbol, (ulong)MAGIC_NUMBER, ticket);
        }
     }
   else
     {
      if(utiliser_trailing_stop)
         SamBotUtils::GererTrailingStop(_Symbol, (ulong)MAGIC_NUMBER,
                                       utiliser_trailing_stop,
                                       trailing_stop_pct);
      if(utiliser_prise_profit_partielle)
         SamBotUtils::GererPrisesProfitsPartielles(_Symbol, (ulong)MAGIC_NUMBER,
                                                   utiliser_prise_profit_partielle,
                                                   tranche_prise_profit_pct,
                                                   nb_tp_partiel,
                                                   SL_BreakEVEN_after_first_partialTp,
                                                   closeIfVolumeLow,
                                                   percentToCloseTrade);
     }

   if(showAlive)
     {
      int openCnt = GetCountOpenPosition();
      PrintFormat("%d alive | Spread=%d | OpenPos=%d",
                  MAGIC_NUMBER, spreadPts, openCnt);
     }
  }

//+------------------------------------------------------------------+
