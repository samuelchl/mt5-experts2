//+------------------------------------------------------------------+
//|                                             SignalML_TRX_WPR.mqh |
//|                             Copyright 2000-2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#include <Expert\ExpertSignal.mqh>

#resource "Python/68_1.onnx" as uchar __68_1[]
#resource "Python/68_4.onnx" as uchar __68_4[]
#resource "Python/68_5.onnx" as uchar __68_5[]
#define __PATTERNS 3
// wizard description start
//+------------------------------------------------------------------+
//| Description of the class                                         |
//| Title=Signals of ML with TRIX and Williams Percent Range         |
//| Type=SignalAdvanced                                              |
//| Name=FrAMA and Force Index Oscillator                            |
//| ShortName=ML_TRX_WPR                                             |
//| Class=CSignalML_TRX_WPR                                          |
//| Page=signal_trx_wpr                                              |
//| Parameter=Pattern_1,int,50,Pattern 1                             |
//| Parameter=Pattern_4,int,50,Pattern 4                             |
//| Parameter=Pattern_5,int,50,Pattern 5                             |
//| Parameter=PatternsUsed,int,255,Patterns Used BitMap              |
//+------------------------------------------------------------------+
// wizard description end
//+------------------------------------------------------------------+
//| Class CSignalML_TRX_WPR.                                         |
//| Purpose: Class of generator of trade signals based on            |
//|          Signals of ML with TRIX and Williams Percent Range      |
//| Is derived from the CExpertSignal class.                         |
//+------------------------------------------------------------------+
#define __PERIOD 3
class CSignalML_TRX_WPR : public CExpertSignal
{
protected:
   CiTriX            m_trix;
   CiWPR             m_wpr;
   int               m_patterns_used;

   long              m_handles[__PATTERNS];
   //--- adjusted parameters

   //--- "weights" of market models (0-100)
   int               m_pattern_1;      // model 1
   int               m_pattern_4;      // model 4
   int               m_pattern_5;      // model 5
   //
   //int               m_patterns_usage;   //

public:
   CSignalML_TRX_WPR(void);
   ~CSignalML_TRX_WPR(void);
   //--- methods of setting adjustable parameters
   //--- methods of adjusting "weights" of market models
   void              Pattern_1(int value)
   {  m_pattern_1 = value;
   }
   void              Pattern_4(int value)
   {  m_pattern_4 = value;
   }
   void              Pattern_5(int value)
   {  m_pattern_5 = value;
   }
   void              PatternsUsed(int value)
   {  m_patterns_used = value;
      PatternsUsage(value);
   }
   //--- method of verification of settings
   virtual bool      ValidationSettings(void);
   //--- method of creating the oscillator and timeseries
   virtual bool      InitIndicators(CIndicators *indicators);
   //--- methods of checking if the market models are formed
   virtual int       LongCondition(void) override;
   virtual int       ShortCondition(void) override;
   virtual double    Direction(void) override;

protected:
   //--- method of initialization of the oscillator
   bool              InitML_TRX_WPR(CIndicators *indicators);
   //--- methods of getting data
   double            TRX(int ind)
   {  //
      m_trix.Refresh(-1);
      return(m_trix.Main(ind));
   }
   double            TRX_MAX(int ind)
   {  //
      m_trix.Refresh(-1);
      return(m_trix.Main(m_trix.Maximum(0, ind, __PERIOD)));
   }
   double            TRX_MIN(int ind)
   {  //
      m_trix.Refresh(-1);
      return(m_trix.Main(m_trix.Minimum(0, ind, __PERIOD)));
   }
   double            WPR(int ind)
   {  //
      m_wpr.Refresh(-1);
      return(m_wpr.Main(ind));
   }
   double            Close(int ind)
   {  //
      m_close.Refresh(-1);
      return(m_close.GetData(ind));
   }
   double            High(int ind)
   {  //
      m_high.Refresh(-1);
      return(m_high.GetData(ind));
   }
   double            Low(int ind)
   {  //
      m_low.Refresh(-1);
      return(m_low.GetData(ind));
   }
   long              Volume(int ind)
   {  //
      m_tick_volume.Refresh(-1);
      return(m_tick_volume.GetData(ind));
   }
   int               X()
   {  //
      return(StartIndex());
   }
   //--- methods to check for patterns
   bool              IsPattern_1(ENUM_POSITION_TYPE T);
   bool              IsPattern_4(ENUM_POSITION_TYPE T);
   bool              IsPattern_5(ENUM_POSITION_TYPE T);

   double            RunModel(int Index, ENUM_POSITION_TYPE T, vectorf &X);
};
//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSignalML_TRX_WPR::CSignalML_TRX_WPR(void) : m_pattern_1(50),
   m_pattern_4(50),
   m_pattern_5(50)
//m_patterns_usage(255)
{
//--- initialization of protected data
   m_used_series = USE_SERIES_OPEN + USE_SERIES_HIGH + USE_SERIES_LOW + USE_SERIES_CLOSE + USE_SERIES_TICK_VOLUME;
   PatternsUsage(m_patterns_usage);
//--- create model from static buffer
   m_handles[0] = OnnxCreateFromBuffer(__68_1, ONNX_DEFAULT);
   m_handles[1] = OnnxCreateFromBuffer(__68_4, ONNX_DEFAULT);
   m_handles[2] = OnnxCreateFromBuffer(__68_5, ONNX_DEFAULT);
}
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSignalML_TRX_WPR::~CSignalML_TRX_WPR(void)
{
}
//+------------------------------------------------------------------+
//| Validation settings protected data.                              |
//+------------------------------------------------------------------+
bool CSignalML_TRX_WPR::ValidationSettings(void)
{
//--- validation settings of additional filters
   if(!CExpertSignal::ValidationSettings())
      return(false);
//--- initial data checks
//--- initial data checks
   const long _out_shape[] = {1, 1};
   for(int i = 0; i < __PATTERNS; i++)
   {  // Set input shapes
      const long _in_shape[] = {1, 2, 1};
      if(!OnnxSetInputShape(m_handles[i], ONNX_DEFAULT, _in_shape))
      {  Print("OnnxSetInputShape error ", GetLastError(), " for feature: ", i);
         return(false);
      }
      // Set output shapes
      if(!OnnxSetOutputShape(m_handles[i], 0, _out_shape))
      {  Print("OnnxSetOutputShape error ", GetLastError(), " for feature: ", i);
         return(false);
      }
   }
//--- ok
   return(true);
}
//+------------------------------------------------------------------+
//| Create indicators.                                               |
//+------------------------------------------------------------------+
bool CSignalML_TRX_WPR::InitIndicators(CIndicators *indicators)
{
//--- check pointer
   if(indicators == NULL)
      return(false);
//--- initialization of indicators and timeseries of additional filters
   if(!CExpertSignal::InitIndicators(indicators))
      return(false);
//--- create and initialize MA oscillator
   if(!InitML_TRX_WPR(indicators))
      return(false);
//--- ok
   return(true);
}
//+------------------------------------------------------------------+
//| Initialize MA indicators.                                        |
//+------------------------------------------------------------------+
bool CSignalML_TRX_WPR::InitML_TRX_WPR(CIndicators *indicators)
{
//--- check pointer
   if(indicators == NULL)
      return(false);
//--- add object to collection
   if(!indicators.Add(GetPointer(m_trix)))
   {  printf(__FUNCTION__ + ": error adding object");
      return(false);
   }
//--- initialize object
   if(!m_trix.Create(m_symbol.Name(), m_period, __PERIOD, PRICE_CLOSE))
   {  printf(__FUNCTION__ + ": error initializing object");
      return(false);
   }
   if(!m_wpr.Create(m_symbol.Name(), m_period, __PERIOD))
   {  printf(__FUNCTION__ + ": error initializing object");
      return(false);
   }
//--- ok
   return(true);
}
//+------------------------------------------------------------------+
//| Detecting the "weighted" direction                               |
//+------------------------------------------------------------------+
double CSignalML_TRX_WPR::Direction(void)
{  return(LongCondition() - ShortCondition());
}
//+------------------------------------------------------------------+
//| "Voting" that price will grow.                                   |
//+------------------------------------------------------------------+
int CSignalML_TRX_WPR::LongCondition(void)
{  int result  = 0, results = 0;
   vectorf _x;
   _x.Init(2);
   _x.Fill(0.0);
//--- if the model 1 is used
   if(((m_patterns_usage & 0x02) != 0) && IsPattern_1(POSITION_TYPE_BUY))
   {  _x[0] = 1.0f;
      double _y = RunModel(0, POSITION_TYPE_BUY, _x);
      if(_y > 0.0)
      {  result += m_pattern_1;
         results++;
      }
   }
//--- if the model 4 is used
   if(((m_patterns_usage & 0x10) != 0) && IsPattern_4(POSITION_TYPE_BUY))
   {  _x[0] = 1.0f;
      double _y = RunModel(0, POSITION_TYPE_BUY, _x);
      if(_y > 0.0)
      {  result += m_pattern_4;
         results++;
      }
   }
//--- if the model 5 is used
   if(((m_patterns_usage & 0x20) != 0) && IsPattern_5(POSITION_TYPE_BUY))
   {  _x[0] = 1.0f;
      double _y = RunModel(0, POSITION_TYPE_BUY, _x);
      if(_y > 0.0)
      {  result += m_pattern_5;
         results++;
      }
   }
//--- return the result
//if(result > 0)printf(__FUNCSIG__+" result is: %i",result);
   if(results > 0 && result > 0)
   {  return(int(round(result / results)));
   }
   return(0);
}
//+------------------------------------------------------------------+
//| "Voting" that price will fall.                                   |
//+------------------------------------------------------------------+
int CSignalML_TRX_WPR::ShortCondition(void)
{  int result  = 0, results = 0;
   vectorf _x;
   _x.Init(2);
   _x.Fill(0.0);
//--- if the model 1 is used
   if(((m_patterns_usage & 0x02) != 0) && IsPattern_1(POSITION_TYPE_SELL))
   {  _x[1] = 1.0f;
      double _y = RunModel(0, POSITION_TYPE_SELL, _x);
      if(_y < 0.0)
      {  result += m_pattern_1;
         results++;
      }
   }
//--- if the model 4 is used
   if(((m_patterns_usage & 0x10) != 0) && IsPattern_4(POSITION_TYPE_SELL))
   {  _x[1] = 1.0f;
      double _y = RunModel(0, POSITION_TYPE_SELL, _x);
      if(_y < 0.0)
      {  result += m_pattern_4;
         results++;
      }
   }
//--- if the model 5 is used
   if(((m_patterns_usage & 0x20) != 0) && IsPattern_5(POSITION_TYPE_SELL))
   {  _x[1] = 1.0f;
      double _y = RunModel(0, POSITION_TYPE_SELL, _x);
      if(_y < 0.0)
      {  result += m_pattern_5;
         results++;
      }
   }
//--- return the result
//if(result > 0)printf(__FUNCSIG__+" result is: %i",result);
   if(results > 0 && result > 0)
   {  return(int(round(result / results)));
   }
   return(0);
}
//+------------------------------------------------------------------+
//| Check for Pattern 1.                                             |
//+------------------------------------------------------------------+
bool CSignalML_TRX_WPR::IsPattern_1(ENUM_POSITION_TYPE T)
{  if(T == POSITION_TYPE_BUY && Low(X() + 1) > Low(X()) && -80.0 > WPR(X()) && TRX(X()) > TRX(X() + 1))
   {  return(true);
   }
   else if(T == POSITION_TYPE_SELL && High(X()) > High(X() + 1) && WPR(X()) > -20.0 && TRX(X() + 1) > TRX(X()))
   {  return(true);
   }
   return(false);
}
//+------------------------------------------------------------------+
//| Check for Pattern 4.                                             |
//+------------------------------------------------------------------+
bool CSignalML_TRX_WPR::IsPattern_4(ENUM_POSITION_TYPE T)
{  if(T == POSITION_TYPE_BUY && 0.0 < TRX(X()) && 0.0 >  TRX(X() + 1) && TRX(X()) == TRX_MAX(X()) && WPR(X()) > -50.0 && WPR(X()) < -20.0)
   {  return(true);
   }
   else if(T == POSITION_TYPE_SELL &&  0.0 < TRX(X() + 1) && 0.0 >  TRX(X()) && TRX(X()) == TRX_MIN(X()) && WPR(X()) > -80.0 && WPR(X()) < -50.0)
   {  return(true);
   }
   return(false);
}
//+------------------------------------------------------------------+
//| Check for Pattern 5.                                             |
//+------------------------------------------------------------------+
bool CSignalML_TRX_WPR::IsPattern_5(ENUM_POSITION_TYPE T)
{  if(T == POSITION_TYPE_BUY && TRX(X() + 2) < TRX(X() + 1) && TRX(X() + 1) >  TRX(X()) && TRX(X() + 1) == TRX_MAX(X()) && WPR(X() + 1) > -20.0 && WPR(X()) < -20.0)
   {  return(true);
   }
   else if(T == POSITION_TYPE_SELL && TRX(X() + 2) > TRX(X() + 1) && TRX(X() + 1) <  TRX(X()) && TRX(X() + 1) == TRX_MIN(X()) && WPR(X()) > -80.0 && WPR(X() + 1) < -80.0)
   {  return(true);
   }
   return(false);
}
//+------------------------------------------------------------------+
//| Forward Feed Network, to Get Forecast State.                     |
//+------------------------------------------------------------------+
double CSignalML_TRX_WPR::RunModel(int Index, ENUM_POSITION_TYPE T, vectorf &X)
{  vectorf _y(1);
   _y.Fill(0.0);
   ResetLastError();
   if(!OnnxRun(m_handles[Index], ONNX_NO_CONVERSION, X, _y))
   {  printf(__FUNCSIG__ + " failed to get y forecast, err: %i", GetLastError());
      return(double(_y[0]));
   }
   //printf(__FUNCSIG__ + " y: "+DoubleToString(_y[0],5));
   if(T == POSITION_TYPE_BUY && _y[0] > 0.5f)
   {  _y[0] = 2.0f * (_y[0] - 0.5f);
   }
   else if(T == POSITION_TYPE_SELL && _y[0] < 0.5f)
   {  _y[0] = 2.0f * (0.5f - _y[0]);
   }
   return(double(_y[0]));
}
//+------------------------------------------------------------------+
