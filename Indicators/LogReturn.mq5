//+------------------------------------------------------------------+
//|                                                LogReturn.mq5     |
//|                Indicator: Continuous (Logarithmic) Returns       |
//|                Draws a line in a separate window (RSI‑style)     |
//|                Compatible with MetaTrader 5 (MQL5)               |
//+------------------------------------------------------------------+
#property copyright "2025, OpenAI"
#property version   "1.10"
#property indicator_separate_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDeepSkyBlue
#property indicator_width1  1
#property indicator_label1  "LogReturn"

//--- input parameters
input ENUM_APPLIED_PRICE InpPrice      = PRICE_CLOSE; // Price series used
input int               InpShiftPeriod = 1;           // Period shift (1 = next bar → daily return)

//--- indicator buffer
double LogRetBuffer[];

//+------------------------------------------------------------------+
//|  Helper: get chosen price value                                   |
//+------------------------------------------------------------------+
double GetPrice(const int index,
                const ENUM_APPLIED_PRICE price_mode,
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[])
{
   switch(price_mode)
   {
      case PRICE_OPEN:     return open[index];
      case PRICE_HIGH:     return high[index];
      case PRICE_LOW:      return low[index];
      case PRICE_MEDIAN:   return 0.5*(high[index]+low[index]);
      case PRICE_TYPICAL:  return (high[index]+low[index]+close[index])/3.0;
      case PRICE_WEIGHTED: return (high[index]+low[index]+close[index]+close[index])*0.25;
      case PRICE_CLOSE:
      default:             return close[index];
   }
}

//+------------------------------------------------------------------+
//| Custom indicator initialization function                          |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- map buffer
   SetIndexBuffer(0,LogRetBuffer,INDICATOR_DATA);
   PlotIndexSetString(0,PLOT_LABEL,"LogReturn");
   ArraySetAsSeries(LogRetBuffer,true);
   //--- done
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                               |
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
   //--- make sure we have enough bars
   if(rates_total <= InpShiftPeriod)
      return 0;

   //--- start position for calculation
   int start = (prev_calculated > InpShiftPeriod) ? prev_calculated - InpShiftPeriod : InpShiftPeriod;

   for(int i = start; i < rates_total; ++i)
   {
      double price_curr = GetPrice(i,               InpPrice, open, high, low, close);
      double price_prev = GetPrice(i-InpShiftPeriod,InpPrice, open, high, low, close);

      if(price_curr > 0.0 && price_prev > 0.0)
         LogRetBuffer[i] = MathLog(price_curr/price_prev);
      else
         LogRetBuffer[i] = 0.0; // guard against bad quotes
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| End of file                                                       |
//+------------------------------------------------------------------+
