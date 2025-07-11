//+------------------------------------------------------------------+
//|                                              DédaleFormation.mq5 |
//|                                   Copyright 2024, Brieuc Leysour  |
//|                          https://www.youtube.com/@LETRADERPAUVRE |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Brieuc Leysour"
#property link      "https://www.youtube.com/@LETRADERPAUVRE"
#property version   "1.00"

#include <Math/Stat/Math.mqh>
#include <Trade/Trade.mqh>

CTrade trade;

enum RISK_MODE_ENUM {
   Pourcentage,
   Argent,
   Fixe
};

//+------------------------------------------------------------------+
//| Paramètres / variables d'entrée                                  |
//+------------------------------------------------------------------+
input group "PARAMÈTRES POINT PIVOTS"
input ENUM_TIMEFRAMES PIVOT_TIMEFRAME = PERIOD_W1;    // Timeframe points pivots
input int PIVOT_NUMBER = 2;                           // Nombre de points pivots
input int TARGET_PROBABILITY = 50;                    // Probabilité de SL


input group "PARAMÈTRES TDI"
input int RSI_PERIOD = 21;                            // Période RSI
input ENUM_APPLIED_PRICE RSI_APP_PRICE = PRICE_CLOSE; // Méthode de calcul du RSI
input ENUM_TIMEFRAMES TDI_TIMEFRAME0 = PERIOD_M15;    // Timeframe TDI 0
input ENUM_TIMEFRAMES TDI_TIMEFRAME1 = PERIOD_M30;    // Timeframe TDI 1
input ENUM_TIMEFRAMES TDI_TIMEFRAME2 = PERIOD_H1;     // Timeframe TDI 2
input ENUM_TIMEFRAMES TDI_TIMEFRAME3 = PERIOD_H4;     // Timeframe TDI 3
input ENUM_TIMEFRAMES TDI_TIMEFRAME4 = PERIOD_D1;     // Timeframe TDI 4
input int TDI_FAST_PERIOD = 2;                        // Tdi période rapide
input int TDI_SLOW_PERIOD = 7;                        // Tdi période lente
input int TDI_MIDDLE_PERIOD = 34;                     // Tdi période milieu
input int TDI_ANGLE_MIN = 20;                         // Angle minimal
input int TDI_ANGLE_MAX = 80;                         // Angle maximal


input group "PARAMÈTRES SIGNAL"
input bool TDI_TIMEFRAME0_CROSS = false;              // Croisement TDI 0
input bool TDI_TIMEFRAME1_CROSS = false;              // Croisement TDI 1
input bool TDI_TIMEFRAME2_CROSS = false;              // Croisement TDI 2
input bool TDI_TIMEFRAME3_CROSS = false;              // Croisement TDI 3
input bool TDI_TIMEFRAME4_CROSS = false;              // Croisement TDI 4
input bool TDI_TIMEFRAME0_TREND = false;              // Tendance TDI 0
input bool TDI_TIMEFRAME1_TREND = false;              // Tendance TDI 1
input bool TDI_TIMEFRAME2_TREND = false;              // Tendance TDI 2
input bool TDI_TIMEFRAME3_TREND = false;              // Tendance TDI 3
input bool TDI_TIMEFRAME4_TREND = false;              // Tendance TDI 4
input bool TDI_TIMEFRAME0_ANGLE = false;              // Angle TDI 0
input bool TDI_TIMEFRAME1_ANGLE = false;              // Angle TDI 1
input bool TDI_TIMEFRAME2_ANGLE = false;              // Angle TDI 2
input bool TDI_TIMEFRAME3_ANGLE = false;              // Angle TDI 3
input bool TDI_TIMEFRAME4_ANGLE = false;              // Angle TDI 4
input int TDI_SHIFT = 1;                              // Shift du TDI



input group "PARAMÈTRES RISQUE"
input double FIXED_LOT_SIZE = 0.5;                    // Taille de lot fixe
input RISK_MODE_ENUM RISK_MODE = 0;                   // Mode de calcul du risque
input double RISK_PCT = 1;                            // Pourcentage du solde
input double RISK_CURRENCY = 1000;                    // Risque en argent


input group "PARAMÈTRES DIVERS"
input int MAGIC_NUMBER = 0;                           // Nombre d'identification de l'algorithme
input bool IS_NEGSWAP_ALLOWED = false;                // Activer les swaps négatifs
input double SPREAD_MAX = 2;                          // Spread maximal
input double SL_DISTANCE_MIN = 20;                    // Distance SL minimale
input double TP_DISTANCE_MIN = 20;                    // Distance TP minimale
input ENUM_TIMEFRAMES TF_ONTICK = PERIOD_CURRENT;              // TF_ONTICK

//+------------------------------------------------------------------+
//| Variables globales                                               |
//+------------------------------------------------------------------+
int rsi_handle[5];
double ask_price, bid_price;
double sl_distance_min = SL_DISTANCE_MIN * _Point * 10;
double tp_distance_min = TP_DISTANCE_MIN * _Point * 10;

//+------------------------------------------------------------------+
int OnInit() {
   if(InitializeIndicators() == false) return INIT_FAILED;
   trade.SetExpertMagicNumber(MAGIC_NUMBER);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {

for(int i = 0; i < 5; i++) {
      if(rsi_handle[i] != INVALID_HANDLE) {
         IndicatorRelease(rsi_handle[i]);
         rsi_handle[i] = INVALID_HANDLE;
      }
   }

 }

//+------------------------------------------------------------------+
void OnTick() {

   static datetime lastTime = 0;
   datetime currentTime = iTime(_Symbol, TF_ONTICK, 0);
   if(lastTime == currentTime) 
      return;
   lastTime = currentTime;

   UpdateBidAsk();
   ExecuteTrade();
}

//+------------------------------------------------------------------+
bool InitializeIndicators() {
   ENUM_TIMEFRAMES tdi_tfs[5] = {TDI_TIMEFRAME0, TDI_TIMEFRAME1, TDI_TIMEFRAME2, TDI_TIMEFRAME3, TDI_TIMEFRAME4};
   for(int i = 0; i < 5; i++) {
      rsi_handle[i] = iRSI(_Symbol, tdi_tfs[i], RSI_PERIOD, RSI_APP_PRICE);
      if(rsi_handle[i] == INVALID_HANDLE) {
         Print("Erreur initialisation RSI ", i);
         return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
double SupportPivot(int idx) {
   double high = iHigh(_Symbol, PIVOT_TIMEFRAME, 1);
   double low  = iLow(_Symbol,  PIVOT_TIMEFRAME, 1);
   double close= iClose(_Symbol, PIVOT_TIMEFRAME, 1);
   double pivots[];
   ArrayResize(pivots, PIVOT_NUMBER + 1);
   pivots[0] = (high + low + close) / 3.0;
   pivots[1] = 2 * pivots[0] - high;
   for(int i = 2; i < ArraySize(pivots); i++)
      pivots[i] = pivots[0] - (high - low) * (i - 1);
   return NormalizeDouble(pivots[idx], _Digits);
}

//+------------------------------------------------------------------+
double ResistancePivot(int idx) {
   double high = iHigh(_Symbol, PIVOT_TIMEFRAME, 1);
   double low  = iLow(_Symbol,  PIVOT_TIMEFRAME, 1);
   double close= iClose(_Symbol, PIVOT_TIMEFRAME, 1);
   double pivots[];
   ArrayResize(pivots, PIVOT_NUMBER + 1);
   pivots[0] = (high + low + close) / 3.0;
   pivots[1] = 2 * pivots[0] - low;
   for(int i = 2; i < ArraySize(pivots); i++)
      pivots[i] = pivots[0] + (high - low) * (i - 1);
   return NormalizeDouble(pivots[idx], _Digits);
}

//+------------------------------------------------------------------+
double CalculateTdiMa_old(int period, int tf_index, int shift) {
   double buffer[];
   if(CopyBuffer(rsi_handle[tf_index], 0, shift, period + 2, buffer) < 0) {
      Print("Erreur CopyBuffer RSI tf ", tf_index);
      return 0.0;
   }
   // moyenne des 'period' dernières valeurs
   double sum = 0.0;
   for(int i = 0; i < period; i++) sum += buffer[i];
   return NormalizeDouble(sum / period, 1);
}

double CalculateTdiMa(int period, int tf_index, int shift) {
   double buffer[];
   // Demande period valeurs (pas period+2), pour simplifier
   int copied = CopyBuffer(rsi_handle[tf_index], 0, shift, period, buffer);
   if(copied < period) {
      PrintFormat("Erreur CopyBuffer RSI tf %d: valeurs demandées %d, reçues %d", tf_index, period, copied);
      // Tu peux retourner 0 ou une valeur spéciale qui signalera une erreur
      return 0.0;
   }
   double sum = 0.0;
   for(int i = 0; i < copied; i++) sum += buffer[i];
   return NormalizeDouble(sum / period, 1);
}


//+------------------------------------------------------------------+
double CalculateTdiAngle(int tf_index) {
   double fast0 = CalculateTdiMa(TDI_FAST_PERIOD, tf_index, 0);
   double fast1 = CalculateTdiMa(TDI_FAST_PERIOD, tf_index, 1);
   double slow0 = CalculateTdiMa(TDI_SLOW_PERIOD, tf_index, 0);
   double slow1 = CalculateTdiMa(TDI_SLOW_PERIOD, tf_index, 1);
   double fast_angle = MathArctan(fast0 - fast1) * 180.0 / M_PI;
   double slow_angle = MathArctan(slow0 - slow1) * 180.0 / M_PI;
   double weight = (double)RSI_PERIOD / (double)TDI_MIDDLE_PERIOD;
   double angle = (slow_angle + fast_angle * weight) / (1.0 + weight);
   return NormalizeDouble(angle, 1);
}

//+------------------------------------------------------------------+
bool CheckTradeSignal(bool direction) {
   int t_check[5] = {
      TDI_TIMEFRAME0_CROSS, TDI_TIMEFRAME1_CROSS, TDI_TIMEFRAME2_CROSS,
      TDI_TIMEFRAME3_CROSS, TDI_TIMEFRAME4_CROSS
   };
   int tr_check[5] = {
      TDI_TIMEFRAME0_TREND, TDI_TIMEFRAME1_TREND, TDI_TIMEFRAME2_TREND,
      TDI_TIMEFRAME3_TREND, TDI_TIMEFRAME4_TREND
   };
   int a_check[5] = {
      TDI_TIMEFRAME0_ANGLE, TDI_TIMEFRAME1_ANGLE, TDI_TIMEFRAME2_ANGLE,
      TDI_TIMEFRAME3_ANGLE, TDI_TIMEFRAME4_ANGLE
   };
   int sum_t = 0, sum_tr = 0, sum_a = 0;
   for(int i=0;i<5;i++){ sum_t+=t_check[i]; sum_tr+=tr_check[i]; sum_a+=a_check[i]; }

   int cnt_t=0, cnt_tr=0, cnt_a=0;
   // calcul des conditions
   for(int i=0; i<5; i++) {
      double fast0=CalculateTdiMa(TDI_FAST_PERIOD,i,0), fast1=CalculateTdiMa(TDI_FAST_PERIOD,i,1);
      double slow0=CalculateTdiMa(TDI_SLOW_PERIOD,i,0), slow1=CalculateTdiMa(TDI_SLOW_PERIOD,i,1);
      double mid0=CalculateTdiMa(TDI_MIDDLE_PERIOD,i,0), mid1=CalculateTdiMa(TDI_MIDDLE_PERIOD,i,1);
      double angle = CalculateTdiAngle(i);
      bool ok;
      // cross
      ok = false;
      if(t_check[i]) {
         if((!direction && fast1 < slow1 && fast0 > slow0) || (direction && fast1>slow1 && fast0<slow0)) ok=true;
      }
      if(ok) cnt_t++;
      // trend
      ok=false;
      if(tr_check[i]) {
         if((!direction && mid1<mid0) || (direction && mid1>mid0)) ok=true;
      }
      if(ok) cnt_tr++;
      // angle
      ok=false;
      if(a_check[i]) {
         if((!direction && angle>=TDI_ANGLE_MIN && angle<=TDI_ANGLE_MAX) ||
            (direction && angle<=-TDI_ANGLE_MIN && angle>=-TDI_ANGLE_MAX)) ok=true;
      }
      if(ok) cnt_a++;
   }
   return (cnt_t==sum_t && cnt_tr==sum_tr && cnt_a==sum_a);
}

//+------------------------------------------------------------------+
void UpdateBidAsk() {
   bid_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   ask_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
}

//+------------------------------------------------------------------+
void ExecuteTrade() {
   double sl, tp;
   if(CheckTradeSignal(false) && !IsTradeOpen(false) && IsTradeAllowed(false)) {
      sl = GetTradeInfo(false, "sl");
      tp = GetTradeInfo(false, "tp");
      trade.Buy(CalculateLotSize(bid_price - sl), _Symbol, ask_price, sl, tp);
   }
   if(CheckTradeSignal(true) && !IsTradeOpen(true) && IsTradeAllowed(true)) {
      sl = GetTradeInfo(true, "sl");
      tp = GetTradeInfo(true, "tp");
      trade.Sell(CalculateLotSize(sl - ask_price), _Symbol, bid_price, sl, tp);
   }
}

//+------------------------------------------------------------------+
double GetTradeInfo(bool direction, string info) {
   int count = PIVOT_NUMBER;
   int total = count * count;
   double sl_val=0, tp_val=0;
   double sl_sz[], tp_sz[], sl_prob[], diff[];
   ArrayResize(sl_sz, count);
   ArrayResize(tp_sz, count);
   ArrayResize(sl_prob, total);
   ArrayResize(diff, total);

   for(int i=0; i<count; i++) {
      double sup = SupportPivot(i+1), res = ResistancePivot(i+1);
      if(!direction) {
         sl_sz[i] = MathAbs((sup - bid_price)/_Point/10);
         tp_sz[i] = MathAbs((res - ask_price)/_Point/10);
      } else {
         sl_sz[i] = MathAbs((res - ask_price)/_Point/10);
         tp_sz[i] = MathAbs((sup - bid_price)/_Point/10);
      }
      sl_sz[i]=NormalizeDouble(sl_sz[i],2);
      tp_sz[i]=NormalizeDouble(tp_sz[i],2);
   }
   // chercher la paire (i,j) la plus proche de TARGET_PROBABILITY
   double min_diff=DBL_MAX; int best_i=0, best_j=0;
   for(int i=0;i<count;i++){
      for(int j=0;j<count;j++){
         int idx=i*count + j;
         bool valid = (!direction && bid_price>SupportPivot(j+1) && ask_price<ResistancePivot(i+1)) ||
                      (direction && bid_price>SupportPivot(i+1) && ask_price<ResistancePivot(j+1));
         if(valid) sl_prob[idx] = tp_sz[i]/(tp_sz[i]+sl_sz[j])*100;
         else sl_prob[idx] = 151;
         diff[idx] = MathAbs(sl_prob[idx] - TARGET_PROBABILITY);
         if(diff[idx] < min_diff) {
            min_diff = diff[idx]; best_i=i; best_j=j;
         }
      }
   }
   if(!direction) {
      sl_val = SupportPivot(best_j+1);
      tp_val = ResistancePivot(best_i+1);
   } else {
      sl_val = ResistancePivot(best_j+1);
      tp_val = SupportPivot(best_i+1);
   }
   if(info == "sl") return sl_val;
   else return tp_val;
}

//+------------------------------------------------------------------+
double CalculateLotSize(double sl_distance) {
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value= SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double vol_step  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double risk_vol  = (sl_distance/tick_size)*tick_value*vol_step;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk, lot=0;
   switch(RISK_MODE) {
      case Pourcentage:
         risk = RISK_PCT * bal / 100.0;
         lot  = MathFloor(risk / risk_vol) * vol_step;
         break;
      case Argent:
         risk = RISK_CURRENCY;
         lot  = MathFloor(risk / risk_vol) * vol_step;
         break;
      case Fixe:
         lot = FIXED_LOT_SIZE;
         break;
   }
   return NormalizeDouble(lot,2);
}

//+------------------------------------------------------------------+
bool IsTradeOpen(bool dir) {
   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         if(PositionGetInteger(POSITION_MAGIC)==MAGIC_NUMBER &&
            PositionGetSymbol(POSITION_SYMBOL)==_Symbol &&
            PositionGetInteger(POSITION_TYPE)==dir) return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool IsTradeAllowed(bool direction) {
   double swap_l = SymbolInfoDouble(_Symbol, SYMBOL_SWAP_LONG);
   double swap_s = SymbolInfoDouble(_Symbol, SYMBOL_SWAP_SHORT);
   double sl = GetTradeInfo(direction, "sl");
   double tp = GetTradeInfo(direction, "tp");
   double spread = (ask_price - bid_price)/_Point;

   if(!direction) {
      if(IsTradeOpen(true)) return false;
      if(!IS_NEGSWAP_ALLOWED && swap_l<=0) return false;
      if(bid_price < sl + sl_distance_min || ask_price > tp - tp_distance_min) return false;
   } else {
      if(IsTradeOpen(false)) return false;
      if(!IS_NEGSWAP_ALLOWED && swap_s<=0) return false;
      if(bid_price < tp + tp_distance_min || ask_price > sl - sl_distance_min) return false;
   }
   if(spread > SPREAD_MAX*10) return false;
   return true;
}
