//+------------------------------------------------------------------+
//|                                                  NN_EA.mq5       |
//|                                                 William Nicholas |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "William Nicholas"
#property link      "https://www.mql5.com"
#property version   "2.00"

#include <NeuralNetwork.mqh>

//--- Input Parameters
input int      InpNeurons = 10;            // Number of hidden neurons
input double   InpLearningRate = 0.0001;     // Learning rate
input double   InpAlpha = 0.01;            // Cost threshold for stopping training
input int      InpMaxIterations = 5000;    // Maximum training iterations
input double   InpBeta1 = 0.9;             // Adam optimizer beta1
input double   InpBeta2 = 0.999;           // Adam optimizer beta2
input bool     InpVerbose = true;          // Display training details
input double   InpLotSize = 0.1;           // Lot size
input int      InpMagicBuy = 12345;        // Magic number for buy
input int      InpMagicSell = 12346;       // Magic number for sell
input int      InpTrainPeriod = 50;        // Retraining period (bars)
input double   InpLambda = 0.01;           // L2 regularization parameter
input double   BuyInpThreshold = 0.7;      // Buy decision threshold (0.5-1.0)
input double   SellInpThreshold = 0.7;     // Sell decision threshold (0.5-1.0)
input int      InpStopLoss = 100;          // Stop Loss (points)
input int      InpTakeProfit = 200;        // Take Profit (points)
input int      InpRSIPeriod = 14;          // RSI period
input int      InpADXPeriod = 14;          // ADX period
input int      InpStochK = 5;              // Stochastic %K
input int      InpStochD = 3;              // Stochastic %D
input int      InpStochSlowing = 3;        // Stochastic slowing
input int      InpTimeframeCount = 3;      // Number of timeframes to analyze

// Normalization parameters
input double   InpRSIHigh = 70;            // RSI high level
input double   InpRSILow = 30;             // RSI low level
input double   InpADXStrong = 25;          // ADX strong trend level
input double   InpStochHigh = 80;          // Stochastic high level
input double   InpStochLow = 20;           // Stochastic low level

//--- Global Variables
int tfCount = InpTimeframeCount; // Default timeframe count
int inputSize = tfCount * 4;     // 4 indicators per timeframe
NeuralNetwork nnBuy(1, inputSize, InpNeurons, 1, InpAlpha, InpLearningRate, 
                    InpVerbose, InpBeta1, InpBeta2, InpMaxIterations, InpLambda,
                    "Weights_Buy_1.txt", "Weights_Buy_2.txt");
NeuralNetwork nnSell(1, inputSize, InpNeurons, 1, InpAlpha, InpLearningRate, 
                     InpVerbose, InpBeta1, InpBeta2, InpMaxIterations, InpLambda,
                     "Weights_Sell_1.txt", "Weights_Sell_2.txt");
int trainCounter;
int barsTotal;
datetime lastTrainTime;

// Timeframes to analyze
ENUM_TIMEFRAMES timeframes[] = {PERIOD_M1, PERIOD_M5, PERIOD_M10, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_W1};

// Indicator handles
int handleRSI[];
int handleADX[];
int handleStoch[];

// Indicator data
double rsiData[];
double adxData[];
double stochMainData[];
double stochSignalData[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   tfCount = MathMin(InpTimeframeCount, ArraySize(timeframes)); // Validate timeframe count
   inputSize = tfCount * 4; // Recalculate input size

   // Resize arrays
   ArrayResize(handleRSI, tfCount);
   ArrayResize(handleADX, tfCount);
   ArrayResize(handleStoch, tfCount);
   ArrayResize(rsiData, tfCount);
   ArrayResize(adxData, tfCount);
   ArrayResize(stochMainData, tfCount);
   ArrayResize(stochSignalData, tfCount);

   // Create indicator handles
   for (int i = 0; i < tfCount; i++) {
      handleRSI[i] = iRSI(_Symbol, timeframes[i], InpRSIPeriod, PRICE_CLOSE);
      handleADX[i] = iADX(_Symbol, timeframes[i], InpADXPeriod);
      handleStoch[i] = iStochastic(_Symbol, timeframes[i], InpStochK, InpStochD, InpStochSlowing, MODE_SMA, STO_LOWHIGH);
      
      if (handleRSI[i] == INVALID_HANDLE || handleADX[i] == INVALID_HANDLE || handleStoch[i] == INVALID_HANDLE) {
         Print("Error creating indicator handles for TF: ", EnumToString(timeframes[i]));
         return INIT_FAILED;
      }
   }

   // Load saved weights
   if (nnBuy.LoadWeights()) {
      Print("Loaded buy network weights");
   } else {
      Print("No buy weights found, will train from scratch");
   }
   if (nnSell.LoadWeights()) {
      Print("Loaded sell network weights");
   } else {
      Print("No sell weights found, will train from scratch");
   }

   // Initialize variables
   trainCounter = 0;
   barsTotal = iBars(_Symbol, _Period);
   lastTrainTime = 0;

   Print("Neural Network EA initialized successfully");
   Print("Timeframes: ", tfCount, " | Inputs: ", inputSize, " | Neurons: ", InpNeurons);
   Print("Magic BUY: ", InpMagicBuy, " | Magic SELL: ", InpMagicSell);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   for (int i = 0; i < tfCount; i++) {
      if (handleRSI[i] != INVALID_HANDLE) IndicatorRelease(handleRSI[i]);
      if (handleADX[i] != INVALID_HANDLE) IndicatorRelease(handleADX[i]);
      if (handleStoch[i] != INVALID_HANDLE) IndicatorRelease(handleStoch[i]);
   }
   Print("Neural Network EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   int currentBars = iBars(_Symbol, _Period);
   if (currentBars <= barsTotal) return;
   barsTotal = currentBars;

   if (!CollectIndicatorData()) return;

   trainCounter++;
   if (trainCounter >= InpTrainPeriod || lastTrainTime == 0) {
      TrainNetworks();
      nnBuy.WriteWeights();
      nnSell.WriteWeights();
      trainCounter = 0;
      lastTrainTime = TimeCurrent();
   }

   MakeTradeDecision();
}

//+------------------------------------------------------------------+
//| Collect indicator data                                           |
//+------------------------------------------------------------------+
bool CollectIndicatorData() {
   for (int i = 0; i < tfCount; i++) {
      double rsiBuffer[];
      if (CopyBuffer(handleRSI[i], 0, 1, 1, rsiBuffer) <= 0) {
         Print("RSI error TF:", EnumToString(timeframes[i]), " Error:", GetLastError());
         return false;
      }
      rsiData[i] = rsiBuffer[0];

      double adxBuffer[];
      if (CopyBuffer(handleADX[i], 0, 1, 1, adxBuffer) <= 0) {
         Print("ADX error TF:", EnumToString(timeframes[i]), " Error:", GetLastError());
         return false;
      }
      adxData[i] = adxBuffer[0];

      double stochMainBuffer[];
      if (CopyBuffer(handleStoch[i], 0, 1, 1, stochMainBuffer) <= 0) {
         Print("Stoch Main error TF:", EnumToString(timeframes[i]), " Error:", GetLastError());
         return false;
      }
      stochMainData[i] = stochMainBuffer[0];

      double stochSignalBuffer[];
      if (CopyBuffer(handleStoch[i], 1, 1, 1, stochSignalBuffer) <= 0) {
         Print("Stoch Signal error TF:", EnumToString(timeframes[i]), " Error:", GetLastError());
         return false;
      }
      stochSignalData[i] = stochSignalBuffer[0];
   }
   return true;
}

//+------------------------------------------------------------------+
//| Normalize indicator data (continuous)                            |
//+------------------------------------------------------------------+
void NormalizeIndicatorData(matrix &inputMatrix, int row) {
   int col = 0;
   for (int i = 0; i < tfCount; i++) {
      inputMatrix[row][col++] = (rsiData[i] - InpRSILow) / (InpRSIHigh - InpRSILow);
      inputMatrix[row][col++] = MathMin(adxData[i] / 100.0, 1.0);
      inputMatrix[row][col++] = (stochMainData[i] - InpStochLow) / (InpStochHigh - InpStochLow);
      inputMatrix[row][col++] = (stochSignalData[i] - InpStochLow) / (InpStochHigh - InpStochLow);
   }
}

//+------------------------------------------------------------------+
//| Train neural networks                                            |
//+------------------------------------------------------------------+
void TrainNetworks() {
   Print("Starting neural network training...");
   int dataSize = 100;
   inputSize = tfCount * 4;

   if (iBars(_Symbol, _Period) < dataSize + 10) {
      Print("Insufficient historical data for training");
      return;
   }

   matrix inputMatrix(dataSize, inputSize);
   matrix outputBuyMatrix(dataSize, 1);
   matrix outputSellMatrix(dataSize, 1);

   double closeData[];
   int spreadData[];
   if (CopyClose(_Symbol, _Period, 0, dataSize + 5, closeData) <= 0 ||
       CopySpread(_Symbol, _Period, 0, dataSize + 5, spreadData) <= 0) {
      Print("Error collecting price/spread data");
      return;
   }
   ArraySetAsSeries(closeData, true);
   ArraySetAsSeries(spreadData, true);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double threshold = InpTakeProfit * point;

   for (int bar = dataSize - 1; bar >= 0; bar--) {
      int row = dataSize - 1 - bar;
      if (!CollectHistoricalIndicatorData(bar, inputMatrix, row)) {
         Print("Invalid data at bar ", bar);
         continue;
      }

      if (bar > 0) {
         double currentPrice = closeData[bar];
         double futurePrice = closeData[bar - 1];
         double spread = spreadData[bar] * point;

         outputBuyMatrix[row][0] = (futurePrice - currentPrice > threshold - spread) ? 1.0 : 0.0;
         outputSellMatrix[row][0] = (currentPrice - futurePrice > threshold - spread) ? 1.0 : 0.0;
      } else {
         outputBuyMatrix[row][0] = 0.0;
         outputSellMatrix[row][0] = 0.0;
      }
   }

   Print("Training BUY network...");
   nnBuy.ResetWeights();
   nnBuy.Train(inputMatrix, outputBuyMatrix);

   Print("Training SELL network...");
   nnSell.ResetWeights();
   nnSell.Train(inputMatrix, outputSellMatrix);

   Print("Training completed");
}

//+------------------------------------------------------------------+
//| Collect historical indicator data                                |
//+------------------------------------------------------------------+
bool CollectHistoricalIndicatorData(int bar, matrix &inputMatrix, int row) {
   int col = 0;
   for (int tf = 0; tf < tfCount; tf++) {
      double rsiHist[];
      if (CopyBuffer(handleRSI[tf], 0, bar, 1, rsiHist) <= 0) return false;

      double adxHist[];
      if (CopyBuffer(handleADX[tf], 0, bar, 1, adxHist) <= 0) return false;

      double stochMainHist[], stochSignalHist[];
      if (CopyBuffer(handleStoch[tf], 0, bar, 1, stochMainHist) <= 0) return false;
      if (CopyBuffer(handleStoch[tf], 1, bar, 1, stochSignalHist) <= 0) return false;

      inputMatrix[row][col++] = (rsiHist[0] - InpRSILow) / (InpRSIHigh - InpRSILow);
      inputMatrix[row][col++] = MathMin(adxHist[0] / 100.0, 1.0);
      inputMatrix[row][col++] = (stochMainHist[0] - InpStochLow) / (InpStochHigh - InpStochLow);
      inputMatrix[row][col++] = (stochSignalHist[0] - InpStochLow) / (InpStochHigh - InpStochLow);
   }
   return true;
}

//+------------------------------------------------------------------+
//| Make trade decision                                              |
//+------------------------------------------------------------------+
void MakeTradeDecision() {
   inputSize = tfCount * 4;
   matrix predictionInput(1, inputSize);
   NormalizeIndicatorData(predictionInput, 0);

   matrix buyPrediction = nnBuy.Prediction(predictionInput);
   matrix sellPrediction = nnSell.Prediction(predictionInput);

   double buySignal = buyPrediction[0][0];
   double sellSignal = sellPrediction[0][0];

   if (InpVerbose) {
      Print("Signal BUY: ", NormalizeDouble(buySignal, 4), 
            " | Signal SELL: ", NormalizeDouble(sellSignal, 4));
      PrintIndicatorValues();
   }

   ManageExistingPositions(buySignal, sellSignal);

   if (PositionsTotal() > 0) return;

   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (buySignal > BuyInpThreshold && buySignal > sellSignal + 0.1) {
      OpenBuyOrder(spread);
   } else if (sellSignal > SellInpThreshold && sellSignal > buySignal + 0.1) {
      OpenSellOrder(spread);
   }
}

//+------------------------------------------------------------------+
//| Print indicator values                                           |
//+------------------------------------------------------------------+
void PrintIndicatorValues() {
   string msg = "Indicators - ";
   for (int i = 0; i < tfCount; i++) {
      msg += StringFormat("%s: RSI=%.1f ADX=%.1f StochM=%.1f StochS=%.1f | ", 
                         EnumToString(timeframes[i]), 
                         rsiData[i], adxData[i], 
                         stochMainData[i], stochSignalData[i]);
   }
   Print(msg);
}

//+------------------------------------------------------------------+
//| Open buy order                                                   |
//+------------------------------------------------------------------+
void OpenBuyOrder(double spread) {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double sl = (InpStopLoss > 0) ? ask - InpStopLoss * point : 0;
   double tp = (InpTakeProfit > 0) ? ask + (InpTakeProfit * point - spread) : 0;

   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = InpLotSize;
   request.type = ORDER_TYPE_BUY;
   request.price = ask;
   request.sl = sl;
   request.tp = tp;
   request.magic = InpMagicBuy;
   request.comment = "Neural Buy";

   if (OrderSend(request, result)) {
      Print("Buy order opened: ", result.order, " at ", ask);
   } else {
      Print("Error opening buy order: ", result.retcode);
   }
}

//+------------------------------------------------------------------+
//| Open sell order                                                  |
//+------------------------------------------------------------------+
void OpenSellOrder(double spread) {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double sl = (InpStopLoss > 0) ? bid + InpStopLoss * point : 0;
   double tp = (InpTakeProfit > 0) ? bid - (InpTakeProfit * point - spread) : 0;

   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = InpLotSize;
   request.type = ORDER_TYPE_SELL;
   request.price = bid;
   request.sl = sl;
   request.tp = tp;
   request.magic = InpMagicSell;
   request.comment = "Neural Sell";

   if (OrderSend(request, result)) {
      Print("Sell order opened: ", result.order, " at ", bid);
   } else {
      Print("Error opening sell order: ", result.retcode);
   }
}

//+------------------------------------------------------------------+
//| Manage existing positions                                        |
//+------------------------------------------------------------------+
void ManageExistingPositions(double buySignal, double sellSignal) {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      if (PositionGetTicket(i)) {
         long magic = PositionGetInteger(POSITION_MAGIC);
         long type = PositionGetInteger(POSITION_TYPE);

         if (magic == InpMagicBuy && sellSignal > SellInpThreshold) {
            ClosePosition(PositionGetTicket(i));
         } else if (magic == InpMagicSell && buySignal > BuyInpThreshold) {
            ClosePosition(PositionGetTicket(i));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close position                                                   |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket) {
   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = _Symbol;
   request.volume = PositionGetDouble(POSITION_VOLUME);
   request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price = (request.type == ORDER_TYPE_SELL) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if (OrderSend(request, result)) {
      Print("Position closed: ", ticket);
   } else {
      Print("Error closing position: ", result.retcode);
   }
}

//+------------------------------------------------------------------+
//| Chart event handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &s) {
   if (id == CHARTEVENT_KEYDOWN) {
      if (lparam == 'T' || lparam == 't') {
         Print("Training initiated by user");
         TrainNetworks();
         nnBuy.WriteWeights();
         nnSell.WriteWeights();
      } else if (lparam == 'P' || lparam == 'p') {
         Print("Displaying indicators");
         if (CollectIndicatorData()) PrintIndicatorValues();
      }
   }
}