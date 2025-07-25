//+------------------------------------------------------------------+
//|                                             QuickIntradayEA.mq5  |
//|         Ouvre N positions (une par paire) à chaque nouvelle     |
//|         bougie et ferme tout quand profit, drawdown ou TTL       |
//+------------------------------------------------------------------+
#property strict
#property copyright "Quick Intraday EA"
#property version   "1.03"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//|                          Paramètres d'entrée                     |
//+------------------------------------------------------------------+
input ENUM_TIMEFRAMES InpTimeframe        = PERIOD_M15;    // Timeframe pour nouvelles bougies
input double        InpInitialCapital     = 10000.0;       // Capital initial de référence (en unité du compte)
input double        InpPctProfit          = 2.0;           // Profit global cible en % (par rapport à InpInitialCapital)
input double        InpPctDrawdown        = 1.0;           // Drawdown max en % (par rapport à pic equity sur InpInitialCapital)
input double        InpRiskPerAsset       = 1.0;           // Risque max par asset en % (par rapport à InpInitialCapital)
input double        InpStopLossPips       = 20.0;          // Stop Loss en pips
input double        InpTakeProfitPips     = 40.0;          // Take Profit en pips
input int           InpOrderDelaySeconds  = 1;             // Délai minimal (sec) entre deux ouvertures
input int           InpMaxTradeSeconds    = 0;          // TTL max d’une position (en secondes) (0 desactivé)
input double        InpMaxVolume          = 1.0;           // Volume maximum par trade
input double        InpMinVolume          = 0.01;          // Volume minimum par trade
input ulong         InpMagicNumber        = 202500;        // Numéro magique
input bool          InpEnableTrading      = true;          // Activer/désactiver trading

//+------------------------------------------------------------------+
//|         Liste des paires sur lesquelles on ouvre trades         |
//+------------------------------------------------------------------+
string watchedSymbols[6] = { "EURUSD", "USDCHF", "USDCAD", "GBPUSD", "AUDUSD", "NZDUSD" };

//+------------------------------------------------------------------+
//|         Objets de trading                                        |
//+------------------------------------------------------------------+
CTrade        trade;
CPositionInfo positionInfo;
COrderInfo    orderInfo;

//+------------------------------------------------------------------+
//|         Variables globales                                       |
//+------------------------------------------------------------------+
double   initialBalance;           // Valeur de référence pour le profit/drawdown (reprend InpInitialCapital)
double   peakEquity;               // Pic d'équité le plus élevé atteint depuis dernier reset
datetime lastBarTime       = 0;    // Timestamp de la dernière bougie traitée

// Pour gérer l'ouverture différée par tick
int      pendingCount       = 0;   // Nombre de positions restantes à ouvrir
int      pendingIdx[6];            // Indices des paires en attente d'ouverture
datetime nextAllowedOpenTime = 0;   // Heure minimale pour ouvrir le prochain trade

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   // Utiliser InpInitialCapital comme base de calcul (pas le solde réel)
   initialBalance = InpInitialCapital;
   peakEquity     = InpInitialCapital;

   // Configurer le CTrade
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(3);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   Print("QuickIntradayEA initialisé :");
   Print("  Timeframe            = ", EnumToString(InpTimeframe));
   Print("  Capital initial      = ", InpInitialCapital);
   Print("  Profit cible         = ", InpPctProfit, "%");
   Print("  Drawdown max         = ", InpPctDrawdown, "%");
   Print("  Risque/asset         = ", InpRiskPerAsset, "%");
   Print("  SL/mis en pips       = ", InpStopLossPips, " pips");
   Print("  TP/take en pips      = ", InpTakeProfitPips, " pips");
   Print("  Délai entre ordres   = ", InpOrderDelaySeconds, " sec");
   Print("  TTL max par position = ", InpMaxTradeSeconds, " sec");
   Print("  Volume min/max par trade = [", InpMinVolume, " , ", InpMaxVolume, "]");

   // Vérifications basiques
   if(InpInitialCapital <= 0)
   {
      Print("Erreur: InpInitialCapital doit être > 0");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpPctProfit <= 0)
   {
      Print("Erreur: InpPctProfit doit être > 0");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpPctDrawdown <= 0)
   {
      Print("Erreur: InpPctDrawdown doit être > 0");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpRiskPerAsset <= 0)
   {
      Print("Erreur: InpRiskPerAsset doit être > 0");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpStopLossPips <= 0 || InpTakeProfitPips <= 0)
   {
      Print("Erreur: InpStopLossPips et InpTakeProfitPips doivent être > 0");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpOrderDelaySeconds < 0)
   {
      Print("Erreur: InpOrderDelaySeconds doit être >= 0");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpMaxTradeSeconds < 0)
   {
      Print("Erreur: InpMaxTradeSeconds doit être > 0");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpMinVolume < 0)
   {
      Print("Erreur: InpMinVolume doit être >= 0");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpMaxVolume < InpMinVolume)
   {
      Print("Erreur: InpMaxVolume doit être >= InpMinVolume");
      return(INIT_PARAMETERS_INCORRECT);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("QuickIntradayEA désactivé, raison: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!InpEnableTrading)
      return;

   // 0) Vérifier TTL des positions existantes
   CheckTTLAndCloseAllIfExceeded();

   // 1) Détection d'une nouvelle bougie sur InpTimeframe
   datetime curBarTime = iTime(_Symbol, InpTimeframe, 0);
   if(curBarTime == 0)
      return; // Sécurité
   if(curBarTime != lastBarTime)
   {
      lastBarTime = curBarTime;

      // 2) Vérifier profit global ou drawdown
      MonitorEquityAndCloseAllIfNeeded();

      // 3) Repeupler la liste des paires à ouvrir, si trading toujours activé
      if(InpEnableTrading)
      {
         pendingCount = 0;
         for(int i = 0; i < ArraySize(watchedSymbols); i++)
         {
            string sym = watchedSymbols[i];
            if(!HasPositionOnSymbol(sym))
               pendingIdx[pendingCount++] = i;
         }
      }
   }

   // 4) Tenter d'ouvrir une position si liste non vide et délai écoulé
   if(pendingCount > 0 && TimeCurrent() >= nextAllowedOpenTime)
   {
      int idx = pendingIdx[0];
      string sym = watchedSymbols[idx];

      // Calculer lot selon risque par asset (sur InpInitialCapital)
      double lot = CalculateLotForRisk(sym);

      // En plus, imposer bornes min/max volume utilisateur
      if(lot < InpMinVolume) lot = InpMinVolume;
      if(lot > InpMaxVolume) lot = InpMaxVolume;

      // S'assurer aussi des contraintes symboles
      double symMinLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double symMaxLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      double symStepLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);

      if(lot < symMinLot) lot = symMinLot;
      if(lot > symMaxLot) lot = symMaxLot;
      lot = NormalizeDouble(lot / symStepLot, 0) * symStepLot;
      lot = MathMax(lot, symMinLot);

      if(lot > 0.0)
      {
         // Préparer prix, SL, TP
         double ask       = SymbolInfoDouble(sym, SYMBOL_ASK);
         double point     = SymbolInfoDouble(sym, SYMBOL_POINT);
         double pipFactor = 10.0; // 1 pip = 10 points (paires 5 déc)
         double slPrice   = ask - InpStopLossPips * point * pipFactor;
         double tpPrice   = ask + InpTakeProfitPips * point * pipFactor;

         bool opened = trade.Buy(lot, sym, ask, slPrice, tpPrice, "QuickIntradayEA");
         if(opened)
         {
            Print("Ouverture BUY ", sym,
                  " Lot=", lot,
                  " Prix=", ask,
                  " SL=", slPrice,
                  " TP=", tpPrice);
            // Mettre à jour le prochain créneau d'ouverture
            nextAllowedOpenTime = TimeCurrent() + InpOrderDelaySeconds;

            // Retirer la première entrée de pendingIdx[]
            for(int j = 1; j < pendingCount; j++)
               pendingIdx[j-1] = pendingIdx[j];
            pendingCount--;
         }
         else
         {
            Print("Erreur d'ouverture ", sym, " Code=", trade.ResultRetcode());
            // Retirer du tableau pour tenter la suivante plus tard
            for(int j = 1; j < pendingCount; j++)
               pendingIdx[j-1] = pendingIdx[j];
            pendingCount--;
            nextAllowedOpenTime = TimeCurrent() + InpOrderDelaySeconds;
         }
      }
      else
      {
         // Lot calculé invalide, on passe au suivant immédiatement
         Print("Lot calculé invalide pour ", sym, " -> on passe");
         for(int j = 1; j < pendingCount; j++)
            pendingIdx[j-1] = pendingIdx[j];
         pendingCount--;
      }
   }
}

//+------------------------------------------------------------------+
//| Vérifier TTL des positions ; si dépassé, fermer tout            |
//+------------------------------------------------------------------+
void CheckTTLAndCloseAllIfExceeded()
{
   datetime now = TimeCurrent();
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Magic() == InpMagicNumber)
         {
            datetime openTime = positionInfo.Time();
            if((now - openTime) >= InpMaxTradeSeconds && InpMaxTradeSeconds != 0)
            {
               Print(">> TTL dépassé pour ", positionInfo.Symbol(),
                     " (", (now - openTime), " sec) => fermeture de toutes les positions");
               CloseAllPositions();
               // Reset repères après fermeture
               initialBalance = InpInitialCapital;
               peakEquity     = InpInitialCapital;
               pendingCount   = 0;
               return;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Fermer toutes les positions si profit ou drawdown atteint       |
//+------------------------------------------------------------------+
void MonitorEquityAndCloseAllIfNeeded()
{
   // Calculer equity virtuelle basée sur InpInitialCapital + P/L réalisés
   double unrealizedPL = AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE);
   double virtualEquity = initialBalance + unrealizedPL;

   double profitPercent  = (virtualEquity - initialBalance) / initialBalance * 100.0;
   if(virtualEquity > peakEquity)
      peakEquity = virtualEquity;
   double drawdownPercent = (peakEquity - virtualEquity) / peakEquity * 100.0;

   Print("Virtual Equity=", virtualEquity,
         " Profit%=", DoubleToString(profitPercent,2), "%",
         " Drawdown%=", DoubleToString(drawdownPercent,2), "%");

   // Si profit global atteint
   if(profitPercent >= InpPctProfit)
   {
      Print(">> Profit cible atteint (", DoubleToString(profitPercent,2),
            "%) => Fermeture de toutes les positions");
      CloseAllPositions();
      initialBalance = InpInitialCapital;
      peakEquity     = InpInitialCapital;
      pendingCount   = 0;
      return;
   }

   // Si drawdown atteint
   if(drawdownPercent >= InpPctDrawdown)
   {
      Print(">> Drawdown max atteint (", DoubleToString(drawdownPercent,2),
            "%) => Fermeture de toutes les positions");
      CloseAllPositions();
      initialBalance = InpInitialCapital;
      peakEquity     = InpInitialCapital;
      pendingCount   = 0;
   }
}

//+------------------------------------------------------------------+
//| Calculer le lot nécessaire pour risquer InpRiskPerAsset %        |
//+------------------------------------------------------------------+
double CalculateLotForRisk(string symbol)
{
   // Toujours basé sur InpInitialCapital
   double riskAmt = InpInitialCapital * (InpRiskPerAsset / 100.0);

   // Distance en prix du SL = InpStopLossPips * Point * 10
   double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double pipFactor = 10.0; // 1 pip = 10 points (paires 5 décimales)
   double slDist    = InpStopLossPips * point * pipFactor;
   if(slDist <= 0)
      return 0.0;

   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickValue <= 0)
      return 0.0;

   double rawLot = riskAmt / (slDist * tickValue);
   return rawLot;
}

//+------------------------------------------------------------------+
//| Vérifier si une position EA existe déjà sur le symbole           |
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
//| Fermer toutes les positions ouvertes par cet EA                  |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   int totalClosed = 0;
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
               totalClosed++;
               Print("Fermeture ", sym, " Ticket=", ticket);
            }
            else
            {
               Print("Erreur fermeture ", sym, " Code=", trade.ResultRetcode());
            }
         }
      }
   }
   Print("Total positions fermées: ", totalClosed);
}

//+------------------------------------------------------------------+
