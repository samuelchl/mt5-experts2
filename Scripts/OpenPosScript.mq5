//+------------------------------------------------------------------+
//|                                             CorrelationHedge.mq5  |
//|  Script MQL5: prend des positions équilibrées selon corrélations |
//|        Avec un délai de 30 secondes entre chaque ouverture       |
//+------------------------------------------------------------------+
#property copyright "Exemple by ChatGPT"
#property version   "1.01"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Structure pour stocker une paire et sa corrélation
struct Correlation
  {
   string Pair1;
   string Pair2;
   double Corr;
  };

//--- Nombre total d’entrées dans le tableau (30)
#define CORRELATION_COUNT 30

//--- Tableau des corrélations tel que fourni par l’utilisateur
Correlation correlations[CORRELATION_COUNT]=
  {
   {"EURUSD", "USDCHF", -0.871352},
   {"EURUSD", "USDCAD", -0.931620},
   {"EURUSD", "NZDUSD",  0.919223},
   {"EURUSD", "EURCHF",  0.283308},
   {"EURUSD", "NZDCAD",  0.821813},

   {"USDCHF", "EURUSD", -0.871352},
   {"USDCHF", "USDCAD",  0.748369},
   {"USDCHF", "NZDUSD", -0.759700},
   {"USDCHF", "EURCHF",  0.223059},
   {"USDCHF", "NZDCAD", -0.705838},

   {"USDCAD", "EURUSD", -0.931620},
   {"USDCAD", "USDCHF",  0.748369},
   {"USDCAD", "NZDUSD", -0.974826},
   {"USDCAD", "EURCHF", -0.392397},
   {"USDCAD", "NZDCAD", -0.859300},

   {"NZDUSD", "EURUSD",  0.919223},
   {"NZDUSD", "USDCHF", -0.759700},
   {"NZDUSD", "USDCAD", -0.974826},
   {"NZDUSD", "EURCHF",  0.344632},
   {"NZDUSD", "NZDCAD",  0.951196},

   {"EURCHF", "EURUSD",  0.283308},
   {"EURCHF", "USDCHF",  0.223059},
   {"EURCHF", "USDCAD", -0.392397},
   {"EURCHF", "NZDUSD",  0.344632},
   {"EURCHF", "NZDCAD",  0.256326},

   {"NZDCAD", "EURUSD",  0.821813},
   {"NZDCAD", "USDCHF", -0.705838},
   {"NZDCAD", "USDCAD", -0.859300},
   {"NZDCAD", "NZDUSD",  0.951196},
   {"NZDCAD", "EURCHF",  0.256326}
  };

//--- Liste des paires uniques à traiter (6 au total)
string uniqueSymbols[6] =
  {
   "EURUSD",
   "USDCHF",
   "USDCAD",
   "NZDUSD",
   "EURCHF",
   "NZDCAD"
  };

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
  {
   double   avgCorr;
   double   sumCorr;
   int      countCorr;
   ENUM_ORDER_TYPE orderType;
   double   volume = 0.01;

   // Parcours de chaque symbole unique
   for(int u = 0; u < ArraySize(uniqueSymbols); u++)
     {
      string symbol = uniqueSymbols[u];

      // S’assurer que le symbole est sélectionné dans Market Watch
      if(!SymbolSelect(symbol, true))
        {
         Print("Erreur: impossible d’activer le symbole ", symbol);
         continue;
        }

      // Calcul de la corrélation moyenne pour ce symbole par rapport aux autres
      sumCorr   = 0.0;
      countCorr = 0;
      for(int i = 0; i < CORRELATION_COUNT; i++)
        {
         if(correlations[i].Pair1 == symbol)
           {
            sumCorr += correlations[i].Corr;
            countCorr++;
           }
        }
      if(countCorr == 0)
        {
         // En théorie, ne devrait jamais arriver car chaque paire figure 5 fois en tant que Pair1
         PrintFormat("Pas de corrélations trouvées pour %s", symbol);
         continue;
        }
      avgCorr = sumCorr / countCorr;

      // Détermination de la direction en fonction du signe de la corrélation moyenne
      //   - Si corrélation moyenne >= 0 → ouvrir SELL (pour hedger à l’opposé)
      //   - Si corrélation moyenne <  0 → ouvrir BUY
      if(avgCorr >= 0)
         orderType = ORDER_TYPE_SELL;
      else
         orderType = ORDER_TYPE_BUY;

      // Vérifier s’il n’existe pas déjà une position ouverte sur le symbole
      if(HasOpenPosition(symbol))
        {
         PrintFormat("Position déjà ouverte sur %s, on ne réouvre pas.", symbol);
         continue;
        }

      // Ouvrir la position marché
      bool ok=false;
      if(orderType == ORDER_TYPE_BUY)
         ok = trade.Buy(volume, symbol);
      else
         ok = trade.Sell(volume, symbol);

      if(ok)
        {
         PrintFormat("Position %s ouverte sur %s (volume %.2f, corr moy %.6f)",
                     (orderType==ORDER_TYPE_BUY ? "BUY" : "SELL"),
                     symbol, volume, avgCorr);
         // Attendre 30 secondes avant d'ouvrir la position suivante
         Sleep(30000);
        }
      else
         PrintFormat("ERREUR ouverture %s sur %s : %s",
                     (orderType==ORDER_TYPE_BUY ? "BUY" : "SELL"),
                     symbol, trade.ResultComment());
     }
  }

//+------------------------------------------------------------------+
//| Vérifie si une position est déjà ouverte sur un symbole donné    |
//+------------------------------------------------------------------+
bool HasOpenPosition(string symbol)
  {
   // Parcours des positions ouvertes
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == symbol)
            return true;
        }
     }
   return false;
  }
//+------------------------------------------------------------------+
