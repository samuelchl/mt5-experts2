//+------------------------------------------------------------------+
//|                                             Strategie_ADX.mq5    |
//|                                             Adaptation MT5       |
//+------------------------------------------------------------------+
#property copyright "Adaptation MT5"
#property version   "1.00"
#property strict

#include <SamBotUtils.mqh>

//+------------------------------------------------------------------+
//| Expert configuration                                            |
//+------------------------------------------------------------------+
// Paramètres généraux
input ENUM_TIMEFRAMES TF                    = PERIOD_CURRENT;
input int    MAGIC_NUMBER                   = 15975344;

// Paramètres Stop Loss / Take Profit (en %)
input double stop_loss_pct                  = 1.0;
input double take_profit_pct                = 2.0;
input bool   sortie_dynamique               = false;

// Paramètres gestion de lot
input bool   GestionDynamiqueLot            = false;
input double RisqueParTradePct              = 1.0;
input double LotFixe                        = 0.1;

// Paramètres ADX
input int    ADX_Period                     = 14;
input double Seuil_ADX                      = 25.0;

// Paramètres Trailing Stop
input bool   utiliser_trailing_stop         = false;
input double trailing_stop_pct              = 0.5;

// Paramètres Prises de profit partielles
input bool   utiliser_prise_profit_partielle= false;
input double tranche_prise_profit_pct       = 0.02;
input int    nb_tp_partiel                  = 2;

// Paramètres spread
input bool   UseMaxSpread                   = false;
input int    MaxSpreadPoints                = 40;
input bool SL_BreakEVEN_after_first_partialTp = false;

input bool closeIfVolumeLow =false;
input double percentToCloseTrade =0.20;
input bool showAlive = false;

input bool tradeVendredi = false;
input int OppositecandleConsecutiveToClose = 3;
input ENUM_TIMEFRAMES TF_opposite_candle                  = PERIOD_CURRENT;

input int MaxOpenPositions = 5;


//--- Handles pour l’ADX
int handle_ADX;
double ADXBuf[], plusDIBuf[], minusDIBuf[];

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   // Création du handle ADX
   handle_ADX = iADX(_Symbol, TF, ADX_Period);
   if(handle_ADX == INVALID_HANDLE)
   {
      Print("Erreur à la création du handle ADX");
      return(INIT_FAILED);
   }
   return(INIT_SUCCEEDED);
}


int GetCountOpenPosition(){


 // Limite de positions ouvertes
   int total = PositionsTotal();
   int count = 0;

   for(int i = 0; i < total; i++)
      {
         if(PositionGetTicket(i))
         {
            string symb = PositionGetString(POSITION_SYMBOL);
            ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
   
            if(symb == _Symbol && magic == (ulong)MAGIC_NUMBER)
            {
               count++;
            }
         }
      }
      
      return count;

}

bool CanOpenTrade()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   // day_of_week: 0=Sunday, 1=Monday,...,5=Friday
   if(now.day_of_week == 5 && !tradeVendredi)
      return false;

   if(GetCountOpenPosition() >= MaxOpenPositions)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Expert tick                                                     |
//+------------------------------------------------------------------+
void OnTick()
{

   //if (LotFixe > 0.04)
   SamBotUtils::CloseSmallProfitablePositionsV2();
      
      
   static datetime lastTime = 0;
   datetime currentTime = iTime(_Symbol, TF, 0);
   if(lastTime == currentTime) 
      return;
   lastTime = currentTime;
   
   int spread_points = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   if(showAlive)
      Print(IntegerToString(MAGIC_NUMBER) + " alive" + " spread "  + IntegerToString(spread_points) + "cntOpenPos :" +IntegerToString(GetCountOpenPosition()));

   // Récupération des valeurs ADX, +DI, -DI
   if(CopyBuffer(handle_ADX, 0, 0, 1, ADXBuf)    < 1) return; // buffer 0 = ADX
   if(CopyBuffer(handle_ADX, 1, 0, 1, plusDIBuf)< 1) return; // buffer 1 = +DI
   if(CopyBuffer(handle_ADX, 2, 0, 1, minusDIBuf)< 1) return; // buffer 2 = -DI

   double adx  = ADXBuf[0];
   double pDI  = plusDIBuf[0];
   double mDI  = minusDIBuf[0];

   // Conditions d'entrée
   bool tendanceForte = (adx > Seuil_ADX);
   bool sellCondition  = tendanceForte && (pDI > mDI);
   bool buyCondition = tendanceForte && (mDI > pDI);

   double profit = PositionGetDouble(POSITION_PROFIT);

      
   if(sortie_dynamique && SamBotUtils::IsTradeOpen(_Symbol, (ulong)MAGIC_NUMBER) && profit < 0.0)
     {
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      ulong   type   = PositionGetInteger(POSITION_TYPE);
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);

      // BUY  → 3 bougies rouges M15
      if(type == POSITION_TYPE_BUY
         && HasConsecutiveBarsSinceOpen(open_time, -1, OppositecandleConsecutiveToClose, TF_opposite_candle))
         SamBotUtils::tradeClose(_Symbol, (ulong)MAGIC_NUMBER, ticket);

      // SELL → 3 bougies vertes M15
      else if(type == POSITION_TYPE_SELL
         && HasConsecutiveBarsSinceOpen(open_time, +1, OppositecandleConsecutiveToClose, TF_opposite_candle))
         SamBotUtils::tradeClose(_Symbol, (ulong)MAGIC_NUMBER, ticket);
     }
   else
   {
      // Ouverture de position
      if(buyCondition && CanOpenTrade())
         SamBotUtils::tradeOpen(_Symbol, (ulong)MAGIC_NUMBER,
                                ORDER_TYPE_BUY,
                                stop_loss_pct,
                                take_profit_pct,
                                GestionDynamiqueLot,
                                LotFixe,
                                RisqueParTradePct,
                                UseMaxSpread,
                                MaxSpreadPoints);
      if(sellCondition && CanOpenTrade())
         SamBotUtils::tradeOpen(_Symbol, (ulong)MAGIC_NUMBER,
                                ORDER_TYPE_SELL,
                                stop_loss_pct,
                                take_profit_pct,
                                GestionDynamiqueLot,
                                LotFixe,
                                RisqueParTradePct,
                                UseMaxSpread,
                                MaxSpreadPoints);
   }



   // Trailing Stop
   SamBotUtils::GererTrailingStop(_Symbol, (ulong)MAGIC_NUMBER,
                                  utiliser_trailing_stop,
                                  trailing_stop_pct);

   // Prises de profit partielles
   SamBotUtils::GererPrisesProfitsPartielles(_Symbol, (ulong)MAGIC_NUMBER,
                                             utiliser_prise_profit_partielle,
                                             tranche_prise_profit_pct,
                                             nb_tp_partiel,SL_BreakEVEN_after_first_partialTp, closeIfVolumeLow,percentToCloseTrade);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handle_ADX != INVALID_HANDLE) 
      IndicatorRelease(handle_ADX);
}

//+------------------------------------------------------------------+
//| Fonction générique : détecte N bougies consécutives              |
//|  direction = +1 pour bougies vertes (close>open)                 |
//|  direction = -1 pour bougies rouges (close<open)                 |
//+------------------------------------------------------------------+
bool HasConsecutiveBarsSinceOpen(datetime open_time,
                                 int direction,     // +1 ou -1
                                 int requiredCount, // ex. 3
                                 ENUM_TIMEFRAMES tf = PERIOD_M15)
  {
   // 1) trouver l'index de la bougie tf contenant open_time
   int startBar = iBarShift(_Symbol, tf, open_time, true);
   if(startBar < 0)
      return(false);

   int count = 0;
   // 2) parcourir toutes les bougies fermées après l'ouverture
   for(int i = startBar - 1; i >= 1; i--)
     {
      double op = iOpen (_Symbol, tf, i);
      double cl = iClose(_Symbol, tf, i);

      // test en fonction de la direction
      if(direction > 0 ? (cl > op) : (cl < op))
        {
         if(++count >= requiredCount)
            return(true);
        }
      else
        {
         count = 0; // rupture de la séquence
        }
     }
   return(false);
  }
