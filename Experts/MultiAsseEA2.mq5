//+------------------------------------------------------------------+
//|                                         Multi_Asset_CorrEA.mq5   |
//|                        EA Multi-Devises avec Corrélations        |
//+------------------------------------------------------------------+
#property copyright "Multi Asset Correlation EA"
#property version   "1.02"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//|                         Paramètres d'entrée                      |
//+------------------------------------------------------------------+
input ENUM_TIMEFRAMES InpTimeframe            = PERIOD_M15;   // Timeframe de travail
input double        InpRiskPercent            = 1.0;          // Risque max par asset en %
input double        InpStopLoss               = 50.0;         // Stop Loss en points
input double        InpTakeProfit             = 100.0;        // Take Profit en points
input ulong         InpMagicNumber            = 99999;        // Numéro magique
input string        InpComment                = "MultiAsset_EA";// Commentaire des ordres
input bool          InpEnableTrading          = true;         // Activer/désactiver le trading
input double        InpProfitTarget           = 5.0;          // Objectif de profit global en %
input double        InpDrawdownLimit          = 2.0;          // Limite de drawdown en %
input int           InpRSIPeriod              = 14;           // Période RSI
input double        InpRSIOverbought          = 70.0;         // Niveau RSI surachat
input double        InpRSIOversold            = 30.0;         // Niveau RSI survente

input bool          InpUseRSI                 = true;         // true = appliquer le filtre RSI, false = ignorer
input int           InpMinTimeBetweenOrders   = 5;            // Délai minimal (sec) entre deux ouvertures

//+------------------------------------------------------------------+
//|                        Objets de trading                         |
//+------------------------------------------------------------------+
CTrade        trade;
CPositionInfo positionInfo;
COrderInfo    orderInfo;

//+------------------------------------------------------------------+
//|               Structure et données de corrélation                |
//+------------------------------------------------------------------+
struct Correlation
{
   string symbol1;
   string symbol2;
   double value;
};
#define CORRELATION_COUNT 30
Correlation correlations[CORRELATION_COUNT] =
{
   {"EURUSD","USDCHF", -0.871352},
   {"EURUSD","USDCAD", -0.931620},
   {"EURUSD","NZDUSD",  0.919223},
   {"EURUSD","EURCHF",  0.283308},
   {"EURUSD","NZDCAD",  0.821813},

   {"USDCHF","EURUSD", -0.871352},
   {"USDCHF","USDCAD",  0.748369},
   {"USDCHF","NZDUSD", -0.759700},
   {"USDCHF","EURCHF",  0.223059},
   {"USDCHF","NZDCAD", -0.705838},

   {"USDCAD","EURUSD", -0.931620},
   {"USDCAD","USDCHF",  0.748369},
   {"USDCAD","NZDUSD", -0.974826},
   {"USDCAD","EURCHF", -0.392397},
   {"USDCAD","NZDCAD", -0.859300},

   {"NZDUSD","EURUSD",  0.919223},
   {"NZDUSD","USDCHF", -0.759700},
   {"NZDUSD","USDCAD", -0.974826},
   {"NZDUSD","EURCHF",  0.344632},
   {"NZDUSD","NZDCAD",  0.951196},

   {"EURCHF","EURUSD",  0.283308},
   {"EURCHF","USDCHF",  0.223059},
   {"EURCHF","USDCAD", -0.392397},
   {"EURCHF","NZDUSD",  0.344632},
   {"EURCHF","NZDCAD",  0.256326},

   {"NZDCAD","EURUSD",  0.821813},
   {"NZDCAD","USDCHF", -0.705838},
   {"NZDCAD","USDCAD", -0.859300},
   {"NZDCAD","NZDUSD",  0.951196},
   {"NZDCAD","EURCHF",  0.256326}
};

// Seuils pour corrélations
#define CORR_THRESHOLD_POSITIVE 0.80
#define CORR_THRESHOLD_NEGATIVE -0.80

// Retourne la corrélation brute entre deux symboles (dans les deux sens)
double GetCorrelationValue(string s1, string s2)
{
   for(int i = 0; i < CORRELATION_COUNT; i++)
   {
      if(correlations[i].symbol1 == s1 && correlations[i].symbol2 == s2)
         return correlations[i].value;
      if(correlations[i].symbol1 == s2 && correlations[i].symbol2 == s1)
         return correlations[i].value;
   }
   return 0.0;
}
bool IsPositivelyCorrelated(string a, string b)
{
   return ( GetCorrelationValue(a,b) >= CORR_THRESHOLD_POSITIVE );
}
bool IsNegativelyCorrelated(string a, string b)
{
   return ( GetCorrelationValue(a,b) <= CORR_THRESHOLD_NEGATIVE );
}

//+------------------------------------------------------------------+
//|                     Paires surveillées                           |
//+------------------------------------------------------------------+
string watchedSymbols[6] = { "EURUSD","USDCHF","USDCAD","NZDUSD","EURCHF","NZDCAD" };

// Structure pour données de marché et signaux
struct MarketData
{
   double close;
   double rsi;
   int    signal; // +1=Candidate BUY, -1=Candidate SELL (avec RSI), 0=None
};
MarketData marketData[6];

// Handles RSI
int rsiHandles[6];
datetime lastAnalysisTime = 0;

// Variables equity
double initialBalance;
double peakEquity;

// Horodatage pour délai entre ouvertures
datetime nextAllowedOpenTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("EA Multi-Asset Corrélations initialisé");

   // Configurer le trading
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(3);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   // Stocker le solde initial et le pic d’équité
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   peakEquity     = initialBalance;

   // Création des handles RSI pour chaque paire
   for(int i = 0; i < 6; i++)
   {
      rsiHandles[i] = iRSI(watchedSymbols[i], InpTimeframe, InpRSIPeriod, PRICE_CLOSE);
      if(rsiHandles[i] == INVALID_HANDLE)
      {
         Print("Erreur création handle RSI pour ", watchedSymbols[i]);
         return(INIT_FAILED);
      }
   }

   // Validation des paramètres
   if(InpRiskPercent <= 0 || InpRiskPercent > 100)
   {
      Print("Erreur: InpRiskPercent doit être entre 0 et 100 (actuel=", InpRiskPercent, ")");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpProfitTarget <= 0)
   {
      Print("Erreur: InpProfitTarget doit être > 0 (actuel=", InpProfitTarget, ")");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpDrawdownLimit <= 0)
   {
      Print("Erreur: InpDrawdownLimit doit être > 0 (actuel=", InpDrawdownLimit, ")");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpMinTimeBetweenOrders < 0)
   {
      Print("Erreur: InpMinTimeBetweenOrders doit être >= 0 (actuel=", InpMinTimeBetweenOrders, ")");
      return(INIT_PARAMETERS_INCORRECT);
   }

   Print("Paramètres :");
   Print("  - Timeframe = ", EnumToString(InpTimeframe));
   Print("  - Risque max par asset = ", InpRiskPercent, "%");
   Print("  - SL = ", InpStopLoss, " pts, TP = ", InpTakeProfit, " pts");
   Print("  - ProfitTarget = ", InpProfitTarget, "%, DrawdownLimit = ", InpDrawdownLimit, "%");
   Print("  - RSI activé = ", InpUseRSI, " (Période=", InpRSIPeriod,
         ", Overbought=", InpRSIOverbought, ", Oversold=", InpRSIOversold, ")");
   Print("  - Délai min entre ordres = ", InpMinTimeBetweenOrders, " sec");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA désactivé. Raison=", reason);

   for(int i = 0; i < 6; i++)
      if(rsiHandles[i] != INVALID_HANDLE)
         IndicatorRelease(rsiHandles[i]);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!InpEnableTrading)
      return;

   // Exécuter une fois par nouvelle bougie M15
   datetime t = iTime(_Symbol, InpTimeframe, 0);
   if(t != lastAnalysisTime)
   {
      lastAnalysisTime = t;

      // 1) Mise à jour des prix et RSI
      UpdateAllMarketData();

      // 2) Surveiller l’équité + fermer si TP global ou Drawdown atteint
      MonitorGlobalEquity();

      // 3) Calculer les signaux (RSI si activé, sinon tous candidats)
      AnalyzeMultiAssetSignals();

      // 4) Exécuter la stratégie avec délai entre ordres
      ExecuteMultiAssetStrategy();
   }
}

//+------------------------------------------------------------------+
//| Mise à jour de toutes les données de marché (close + RSI)        |
//+------------------------------------------------------------------+
void UpdateAllMarketData()
{
   for(int i = 0; i < 6; i++)
   {
      string sym = watchedSymbols[i];
      marketData[i].close = iClose(sym, InpTimeframe, 0);

      double rsiBuf[1];
      if(CopyBuffer(rsiHandles[i], 0, 0, 1, rsiBuf) > 0)
         marketData[i].rsi = rsiBuf[0];
      else
         marketData[i].rsi = 50.0; // Valeur neutre si erreur
      marketData[i].signal = 0;
   }
}

//+------------------------------------------------------------------+
//| Calcul/assignation des signaux (RSI on/off)                      |
//+------------------------------------------------------------------+
void AnalyzeMultiAssetSignals()
{
   for(int i = 0; i < 6; i++)
   {
      marketData[i].signal = 0;

      if(!InpUseRSI)
      {
         // Si RSI désactivé, on marque simplement la paire comme candidate (signal=+1)
         marketData[i].signal = 1;
      }
      else
      {
         double r = marketData[i].rsi;
         if(r < InpRSIOversold)
            marketData[i].signal = +1;
         else if(r > InpRSIOverbought)
            marketData[i].signal = -1;
         else
            marketData[i].signal = 0;
      }

      if(InpUseRSI && marketData[i].signal != 0)
         Print("Signal RSI ", watchedSymbols[i], " = ", marketData[i].signal,
               " (RSI=", DoubleToString(marketData[i].rsi,2), ")");
   }
}

//+------------------------------------------------------------------+
//| Surveiller l’équité, fermer toutes positions si besoin           |
//+------------------------------------------------------------------+
void MonitorGlobalEquity()
{
   double curEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(curEquity > peakEquity)
      peakEquity = curEquity;

   double profitPct   = (curEquity - initialBalance) / initialBalance * 100.0;
   double drawdownPct = (peakEquity - curEquity)    / peakEquity    * 100.0;

   Print("Equity=", curEquity, " | ProfitGlobal=", DoubleToString(profitPct,2),
         "% | Drawdown=", DoubleToString(drawdownPct,2), "%");

   // Fermeture si objectif de profit global atteint
   if(profitPct >= InpProfitTarget)
   {
      Print("=== TP GLOBAL atteint (", DoubleToString(profitPct,2),
            "%) → fermeture de toutes les positions ===");
      CloseAllMultiAssetPositions();
   }
   // Fermeture si drawdown global atteint
   else if(drawdownPct >= InpDrawdownLimit)
   {
      Print("=== Drawdown atteint (", DoubleToString(drawdownPct,2),
            "%) → fermeture de toutes les positions ===");
      CloseAllMultiAssetPositions();
   }
}

//+------------------------------------------------------------------+
//| Exécution de la stratégie (1 ouverture par cycle, délai respecté)|
//+------------------------------------------------------------------+
void ExecuteMultiAssetStrategy()
{
   // 1) Vérifier délai entre ouvertures
   if(TimeCurrent() < nextAllowedOpenTime)
      return;

   // 2) Rassembler indices candidats (signal != 0)
   int candidatesCount = 0;
   int candidatesIdx[6];
   for(int i = 0; i < 6; i++)
   {
      if(marketData[i].signal != 0)
         candidatesIdx[candidatesCount++] = i;
   }
   if(candidatesCount == 0)
      return;

   // 3) Séparer en groupes "positif" et "négatif" selon corrélations
   int posCount = 0, negCount = 0;
   int posIdx[6], negIdx[6];

   // 3.a) Groupe "positif" (corr >= +0.80)
   for(int a = 0; a < candidatesCount && posCount < 3; a++)
   {
      int ia = candidatesIdx[a];
      string sa = watchedSymbols[ia];
      for(int b = 0; b < candidatesCount; b++)
      {
         if(a == b) continue;
         int ib = candidatesIdx[b];
         string sb = watchedSymbols[ib];
         if(IsPositivelyCorrelated(sa, sb))
         {
            posIdx[posCount++] = ia;
            break;
         }
      }
   }

   // 3.b) Groupe "négatif" (corr <= -0.80)
   for(int a = 0; a < candidatesCount && negCount < 3; a++)
   {
      int ia = candidatesIdx[a];
      string sa = watchedSymbols[ia];
      for(int b = 0; b < candidatesCount; b++)
      {
         if(a == b) continue;
         int ib = candidatesIdx[b];
         string sb = watchedSymbols[ib];
         if(IsNegativelyCorrelated(sa, sb))
         {
            negIdx[negCount++] = ia;
            break;
         }
      }
   }

   int totalToOpen = posCount + negCount;
   if(totalToOpen == 0)
      return;

   // 4) Construire la liste d’indices à ouvrir (d’abord pos, puis neg)
   int toOpenIdx[6];
   for(int i = 0; i < posCount; i++)
      toOpenIdx[i] = posIdx[i];
   for(int i = 0; i < negCount; i++)
      toOpenIdx[posCount + i] = negIdx[i];

   // 5) Tenter l’ouverture d’une seule position dans cet ordre
   for(int k = 0; k < totalToOpen; k++)
   {
      int idx = toOpenIdx[k];
      string sym = watchedSymbols[idx];

      // a) Ne pas ouvrir si déjà position
      if(HasPositionOnSymbol(sym))
         continue;

      // b) Calculer taille de lot (risque max par asset)
      double lot = CalculateSymbolLotSize(sym);
      if(lot <= 0.0)
         continue;

      // c) Déterminer BUY ou SELL
      bool isInPosGroup = false;
      for(int m = 0; m < posCount; m++)
         if(posIdx[m] == idx) { isInPosGroup = true; break; }

      ENUM_ORDER_TYPE orderType;
      if(InpUseRSI)
      {
         // On s’appuie sur marketData[idx].signal = +1 ou -1
         orderType = (marketData[idx].signal == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      }
      else
      {
         // Sans RSI : corrélations → hedge immédiat
         orderType = (isInPosGroup ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      }

      // d) Préparer prix, SL, TP
      double price = (orderType == ORDER_TYPE_BUY)
                       ? SymbolInfoDouble(sym, SYMBOL_ASK)
                       : SymbolInfoDouble(sym, SYMBOL_BID);
      double ptp   = SymbolInfoDouble(sym, SYMBOL_POINT);
      double sl    = 0.0, tp = 0.0;
      if(InpStopLoss > 0.0)
      {
         sl = (orderType == ORDER_TYPE_BUY)
                ? price - InpStopLoss * ptp
                : price + InpStopLoss * ptp;
      }
      if(InpTakeProfit > 0.0)
      {
         tp = (orderType == ORDER_TYPE_BUY)
                ? price + InpTakeProfit * ptp
                : price - InpTakeProfit * ptp;
      }

      // e) Ouvrir l’ordre
      bool opened = false;
      if(orderType == ORDER_TYPE_BUY)
      {
         opened = trade.Buy(lot, sym, price, sl, tp, InpComment);
         if(opened)
            Print("> BUY ", sym, " lot=", lot, " prix=", price);
      }
      else // SELL
      {
         opened = trade.Sell(lot, sym, price, sl, tp, InpComment);
         if(opened)
            Print("> SELL ", sym, " lot=", lot, " prix=", price);
      }

      if(opened)
      {
         // Mettre à jour le timestamp pour le prochain ordre
         nextAllowedOpenTime = TimeCurrent() + InpMinTimeBetweenOrders;
         break;   // n’ouvrir qu’une position par cycle
      }
      // Sinon, si échec, on essaie le suivant dans la liste
   }
}

//+------------------------------------------------------------------+
//| Vérifier si on peut ouvrir de nouvelles positions (toujours true)|
//+------------------------------------------------------------------+
bool CanOpenNewPositions()
{
   // Désormais, InpRiskPercent est un risque max par asset,
   // donc on ne limite plus le cumul, chaque position est calibrée individuellement.
   return true;
}

//+------------------------------------------------------------------+
//| Vérifier si une position existe déjà sur ce symbole              |
//+------------------------------------------------------------------+
bool HasPositionOnSymbol(string symbol)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == symbol && positionInfo.Magic() == InpMagicNumber)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calculer la taille de lot selon risque max par asset             |
//+------------------------------------------------------------------+
double CalculateSymbolLotSize(string symbol)
{
   double accountBal   = AccountInfoDouble(ACCOUNT_BALANCE);

   // Risque max par asset = InpRiskPercent % du capital
   double baseRiskAmt  = accountBal * (InpRiskPercent / 100.0);

   // Ajustement selon volatilité
   double volatilityWeight = 1.0;
   if(symbol == "NZDUSD" || symbol == "NZDCAD") volatilityWeight = 0.8;
   if(symbol == "EURCHF")                         volatilityWeight = 1.2;
   double riskAmt = baseRiskAmt * volatilityWeight;

   double slPts   = InpStopLoss;
   double tickVal = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(slPts <= 0 || tickVal <= 0)
      return 0.01;  // lot minimal en cas d’erreur

   double lot = riskAmt / (slPts * tickVal);

   // Normaliser selon min, max, pas
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   lot = MathMax(lot, minLot);
   lot = MathMin(lot, maxLot);
   lot = NormalizeDouble(lot / stepLot, 0) * stepLot;

   Print("Lot calculé pour ", symbol, ": ", lot,
         " | Risque($)=", DoubleToString(riskAmt,2));
   return lot;
}

//+------------------------------------------------------------------+
//| Fermer toutes les positions de l’EA                              |
//+------------------------------------------------------------------+
void CloseAllMultiAssetPositions()
{
   Print("=== FERMETURE DE TOUTES LES POSITIONS ===");
   int closedCount = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Magic() == InpMagicNumber)
         {
            ulong ticket = positionInfo.Ticket();
            string sym   = positionInfo.Symbol();
            if(trade.PositionClose(ticket))
            {
               Print("Position fermée: ", sym, " Ticket=", ticket);
               closedCount++;
            }
            else
            {
               Print("Erreur fermeture ", sym, " code=", trade.ResultRetcode());
            }
         }
      }
   }

   Print("Total positions fermées: ", closedCount);
   if(closedCount > 0)
   {
      double newEq = AccountInfoDouble(ACCOUNT_EQUITY);
      initialBalance = newEq;
      peakEquity     = newEq;
   }
}
//+------------------------------------------------------------------+
