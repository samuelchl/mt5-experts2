
//+------------------------------------------------------------------+
//|                    RatioUtils.mqh                                |
//|    Classe utilitaire pour ratios de performance en MQL5         |
//+------------------------------------------------------------------+
#property strict

class RatioUtils
{
public:
   static double Mean(const double &data[])
   {
      double sum = 0;
      int n = ArraySize(data);
      for (int i = 0; i < n; i++)
         sum += data[i];
      return (n > 0) ? sum / n : 0;
   }

   static double StandardDeviation(const double &data[], double mean)
   {
      double sum = 0;
      int n = ArraySize(data);
      for (int i = 0; i < n; i++)
         sum += (data[i] - mean) * (data[i] - mean);
      return (n > 0) ? sqrt(sum / n) : 0;
   }

   static double Skewness(const double &data[], double mean, double stdDev)
   {
      double sum = 0;
      int n = ArraySize(data);
      if(n < 3 || stdDev == 0)
         return 0;
      for (int i = 0; i < n; i++)
         sum += MathPow((data[i] - mean) / stdDev, 3);
      return (n / ((n - 1.0)*(n - 2.0))) * sum;
   }

   static double Kurtosis(const double &data[], double mean, double stdDev)
   {
      double sum = 0;
      int n = ArraySize(data);
      if(n < 4 || stdDev == 0)
         return 0;
      for (int i = 0; i < n; i++)
         sum += MathPow((data[i] - mean) / stdDev, 4);
      return (n * (n + 1) * sum - 3 * MathPow(n - 1, 2)) / ((n - 1) * (n - 2) * (n - 3));
   }

   static double SharpeRatio(const double &data[], double riskFreeRate = 0)
   {
      double mean = Mean(data) - riskFreeRate;
      double stdDev = StandardDeviation(data, Mean(data));
      return (stdDev != 0) ? mean / stdDev : 0;
   }

   static double SortinoRatio(const double &data[], double riskFreeRate = 0)
   {
      double mean = Mean(data) - riskFreeRate;
      double downsideSum = 0;
      int downsideCount = 0;
      for (int i = 0; i < ArraySize(data); i++)
      {
         if (data[i] < 0)
         {
            downsideSum += data[i] * data[i];
            downsideCount++;
         }
      }
      double downsideDev = (downsideCount > 0) ? sqrt(downsideSum / downsideCount) : 0;
      return (downsideDev != 0) ? mean / downsideDev : 0;
   }

   static double UlcerIndex(const double &data[])
   {
      double peak = 0, sumSq = 0;
      int n = ArraySize(data);
      for (int i = 0; i < n; i++)
      {
         peak = MathMax(peak, data[i]);
         double drawdown = peak - data[i];
         sumSq += drawdown * drawdown;
      }
      return (n > 0) ? sqrt(sumSq / n) : 0;
   }
};