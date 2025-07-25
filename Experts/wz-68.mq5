//+------------------------------------------------------------------+
//|                                                        wz-68.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
//+------------------------------------------------------------------+
//| Include                                                          |
//+------------------------------------------------------------------+
#include <Expert\Expert.mqh>
//--- available signals
#include <SignalWZ_68.mqh>
//--- available trailing
#include <Expert\Trailing\TrailingNone.mqh>
//--- available money management
#include <Expert\Money\MoneyFixedMargin.mqh>
//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
//--- inputs for expert
input string Expert_Title                  = "wz-68"; // Document name
ulong        Expert_MagicNumber            = 14312;  //
bool         Expert_EveryTick              = false;  //
//--- inputs for main signal
input int    Signal_ThresholdOpen          = 10;     // Signal threshold value to open [0...100]
input int    Signal_ThresholdClose         = 10;     // Signal threshold value to close [0...100]
input double Signal_PriceLevel             = 0.0;    // Price level to execute a deal
input double Signal_StopLevel              = 50.0;   // Stop Loss level (in points)
input double Signal_TakeLevel              = 50.0;   // Take Profit level (in points)
input int    Signal_Expiration             = 4;      // Expiration of pending orders (in bars)
input int    Signal_ML_TRX_WPR_Pattern_1   = 50;     // FrAMA and Force Index Oscillator Pattern 1
input int    Signal_ML_TRX_WPR_Pattern_4   = 50;     // FrAMA and Force Index Oscillator Pattern 4
input int    Signal_ML_TRX_WPR_Pattern_5   = 50;     // FrAMA and Force Index Oscillator Pattern 5
input int    Signal_ML_TRX_WPR_PatternsUsed = 255;   // FrAMA and Force Index Oscillator Patterns Used BitMap
input double Signal_ML_TRX_WPR_Weight      = 1.0;    // FrAMA and Force Index Oscillator Weight [0...1.0]
//--- inputs for money
input double Money_FixMargin_Percent       = 10.0;   // Percentage of margin
//+------------------------------------------------------------------+
//| Global expert object                                             |
//+------------------------------------------------------------------+
CExpert ExtExpert;
//+------------------------------------------------------------------+
//| Initialization function of the expert                            |
//+------------------------------------------------------------------+
int OnInit()
{
//--- Initializing expert
   if(!ExtExpert.Init(Symbol(), Period(), Expert_EveryTick, Expert_MagicNumber))
   {  //--- failed
      printf(__FUNCTION__ + ": error initializing expert");
      ExtExpert.Deinit();
      return(INIT_FAILED);
   }
//--- Creating signal
   CExpertSignal *signal = new CExpertSignal;
   if(signal == NULL)
   {  //--- failed
      printf(__FUNCTION__ + ": error creating signal");
      ExtExpert.Deinit();
      return(INIT_FAILED);
   }
//---
   ExtExpert.InitSignal(signal);
   signal.ThresholdOpen(Signal_ThresholdOpen);
   signal.ThresholdClose(Signal_ThresholdClose);
   signal.PriceLevel(Signal_PriceLevel);
   signal.StopLevel(Signal_StopLevel);
   signal.TakeLevel(Signal_TakeLevel);
   signal.Expiration(Signal_Expiration);
//--- Creating filter CSignalML_TRX_WPR
   CSignalML_TRX_WPR *filter0 = new CSignalML_TRX_WPR;
   if(filter0 == NULL)
   {  //--- failed
      printf(__FUNCTION__ + ": error creating filter0");
      ExtExpert.Deinit();
      return(INIT_FAILED);
   }
   signal.AddFilter(filter0);
//--- Set filter parameters
   filter0.Pattern_1(Signal_ML_TRX_WPR_Pattern_1);
   filter0.Pattern_4(Signal_ML_TRX_WPR_Pattern_4);
   filter0.Pattern_5(Signal_ML_TRX_WPR_Pattern_5);
   filter0.PatternsUsed(Signal_ML_TRX_WPR_PatternsUsed);
   filter0.Weight(Signal_ML_TRX_WPR_Weight);
//--- Creation of trailing object
   CTrailingNone *trailing = new CTrailingNone;
   if(trailing == NULL)
   {  //--- failed
      printf(__FUNCTION__ + ": error creating trailing");
      ExtExpert.Deinit();
      return(INIT_FAILED);
   }
//--- Add trailing to expert (will be deleted automatically))
   if(!ExtExpert.InitTrailing(trailing))
   {  //--- failed
      printf(__FUNCTION__ + ": error initializing trailing");
      ExtExpert.Deinit();
      return(INIT_FAILED);
   }
//--- Set trailing parameters
//--- Creation of money object
   CMoneyFixedMargin *money = new CMoneyFixedMargin;
   if(money == NULL)
   {  //--- failed
      printf(__FUNCTION__ + ": error creating money");
      ExtExpert.Deinit();
      return(INIT_FAILED);
   }
//--- Add money to expert (will be deleted automatically))
   if(!ExtExpert.InitMoney(money))
   {  //--- failed
      printf(__FUNCTION__ + ": error initializing money");
      ExtExpert.Deinit();
      return(INIT_FAILED);
   }
//--- Set money parameters
   money.Percent(Money_FixMargin_Percent);
//--- Check all trading objects parameters
   if(!ExtExpert.ValidationSettings())
   {  //--- failed
      ExtExpert.Deinit();
      return(INIT_FAILED);
   }
//--- Tuning of all necessary indicators
   if(!ExtExpert.InitIndicators())
   {  //--- failed
      printf(__FUNCTION__ + ": error initializing indicators");
      ExtExpert.Deinit();
      return(INIT_FAILED);
   }
//--- ok
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Deinitialization function of the expert                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{  ExtExpert.Deinit();
}
//+------------------------------------------------------------------+
//| "Tick" event handler function                                    |
//+------------------------------------------------------------------+
void OnTick()
{  ExtExpert.OnTick();
}
//+------------------------------------------------------------------+
//| "Trade" event handler function                                   |
//+------------------------------------------------------------------+
void OnTrade()
{  ExtExpert.OnTrade();
}
//+------------------------------------------------------------------+
//| "Timer" event handler function                                   |
//+------------------------------------------------------------------+
void OnTimer()
{  ExtExpert.OnTimer();
}
//+------------------------------------------------------------------+
