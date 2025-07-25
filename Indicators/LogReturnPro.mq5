//+------------------------------------------------------------------+
//|                                              LogReturnPro.mq5    |
//|      Multi‑curve indicator: Raw Log‑Return, Z‑Score & CumSum     |
//|      Compatible with MetaTrader 5 (MQL5) – one sub‑window        |
//+------------------------------------------------------------------+
#property copyright "2025, OpenAI"
#property version   "2.1"
#property indicator_separate_window
#property indicator_buffers 3
#property indicator_plots   3

//--- plot 0 : Raw log‑return
#property indicator_label1  "Raw"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_width1  1
//--- plot 1 : Z‑Score
#property indicator_label2  "Z‑Score"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_width2  1
//--- plot 2 : CumSum
#property indicator_label3  "CumSum"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrRed
#property indicator_width3  1

//---- input parameters
input int    ShiftPeriods   = 1;                          // distance for raw return
input ENUM_APPLIED_PRICE PriceType = PRICE_CLOSE;         // price used
input bool   ShowRaw   = true;                            // display raw curve
input bool   ShowZ     = true;                            // display z‑score curve
input bool   ShowCum   = true;                            // display cumulative curve
input int    ZLookback   = 250;                           // window for mean/std
input int    CumLookback = 20;                            // window for cum‑sum
input double ZStdEps     = 1e-10;                         // epsilon for std

//---- indicator buffers
double RawBuf[];
double ZBuf[];
double CumBuf[];

//+------------------------------------------------------------------+
//| Custom indicator initialization                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, RawBuf, INDICATOR_DATA);
   SetIndexBuffer(1, ZBuf,  INDICATOR_DATA);
   SetIndexBuffer(2, CumBuf,INDICATOR_DATA);

   //--- insure series indexing (index 0 = current bar)
   ArraySetAsSeries(RawBuf, true);
   ArraySetAsSeries(ZBuf,  true);
   ArraySetAsSeries(CumBuf,true);

   //--- tell MT5 when each plot starts (replacement for SetIndexDrawBegin)
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, ShiftPeriods);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, ShiftPeriods + ZLookback);
   PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, ShiftPeriods + CumLookback);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Helper: choose price                                              |
//+------------------------------------------------------------------+
double GetPrice(const int i,
                const ENUM_APPLIED_PRICE pt,
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[])
{
   switch(pt)
   {
      case PRICE_OPEN:     return open[i];
      case PRICE_HIGH:     return high[i];
      case PRICE_LOW:      return low[i];
      case PRICE_MEDIAN:   return (high[i]+low[i])*0.5;
      case PRICE_TYPICAL:  return (high[i]+low[i]+close[i])/3.0;
      case PRICE_WEIGHTED: return (high[i]+low[i]+close[i]+close[i])*0.25;
      case PRICE_CLOSE:
      default:             return close[i];
   }
}

//+------------------------------------------------------------------+
//| Custom indicator iteration                                        |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total <= ShiftPeriods)
      return 0;

   //--- we work from the oldest bar that needs to be updated (series indexing)
   int start = (prev_calculated>1) ? prev_calculated-1 : ShiftPeriods;

   //--- Raw log‑returns
   for(int i=start; i<rates_total-ShiftPeriods; ++i)
   {
      double p_cur  = GetPrice(i, PriceType, open, high, low, close);
      double p_prev = GetPrice(i+ShiftPeriods, PriceType, open, high, low, close);

      if(p_cur>0.0 && p_prev>0.0)
         RawBuf[i] = MathLog(p_cur/p_prev);
      else
         RawBuf[i] = 0.0;
   }

   //--- Z‑Score
   if(ZLookback>1)
   {
      for(int i=start; i<rates_total-(ShiftPeriods+ZLookback); ++i)
      {
         double sum=0.0, sum2=0.0;
         for(int j=0;j<ZLookback;++j)
         {
            double v = RawBuf[i+j];
            sum  += v;
            sum2 += v*v;
         }
         double mean = sum / ZLookback;
         double var  = (sum2 / ZLookback) - mean*mean;
         double sd   = MathSqrt(MathMax(var, ZStdEps));

         ZBuf[i] = (sd>0.0) ? (RawBuf[i]-mean)/sd : 0.0;
      }
   }

   //--- Cumulative sum
   if(CumLookback>1)
   {
      for(int i=start; i<rates_total-(ShiftPeriods+CumLookback); ++i)
      {
         double s=0.0;
         for(int j=0;j<CumLookback;++j)
            s += RawBuf[i+j];
         CumBuf[i] = s;
      }
   }

   //--- Visibility flags
   for(int i=start; i<rates_total; ++i)
   {
      if(!ShowRaw) RawBuf[i] = EMPTY_VALUE;
      if(!ShowZ)   ZBuf[i]   = EMPTY_VALUE;
      if(!ShowCum) CumBuf[i] = EMPTY_VALUE;
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
