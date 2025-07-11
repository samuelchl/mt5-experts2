#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/Trade.mqh>

// Structure de suivi pour chaque position
struct TPTracker
{
  ulong ticket;             // ticket de la position
  double initVolume;        // volume initial à l'ouverture
  int    lastClosedPallier; // dernier palier déjà fermé
};
// Tableau et compteur statiques pour suivre les positions
static TPTracker s_trackers[100];
static int       s_trackerCount = 0;

//--- Classe stateless contenant toutes les fonctions
class SamBotUtils
{





public:
   // 1) Fonction de rejet (inspirée de Pine)
   static bool isRejet3WMA(double fast0, double fast1,
                           double slow0, double slow1,
                           double trend,
                           string sens, double seuil)
   {
      double diffNow  = fast0 - slow0;
      double diffPrev = fast1 - slow1;
      double ecart    = MathAbs(diffNow);
      bool proche     = ecart <= MathAbs(slow0 * seuil / 100.0);

      bool rejet = false;
      if(sens == "up")
         rejet = (diffPrev < 0 && diffNow > 0 && fast0 > trend && slow0 > trend);
      else if(sens == "down")
         rejet = (diffPrev > 0 && diffNow < 0 && fast0 < trend && slow0 < trend);

      return rejet && proche;
   }
   
      // Fonction de rejet (inspirée de Pine)
   static bool isRejet3WMARenforce(double fast0, double fast1, double slow0, double slow1, double trend,
                    string sens, double seuil)
   {
      double diffNow  = fast0 - slow0;
      double diffPrev = fast1 - slow1;
      double ecart    = MathAbs(diffNow);
      bool proche     = ecart <= MathAbs(slow0 * seuil / 100.0);
   
      bool rejet = false;
      if(sens == "up")
         rejet = (diffPrev < 0 && diffNow > 0 && fast0 > trend && slow0 > trend);
      else if(sens == "down")
         rejet = (diffPrev > 0 && diffNow < 0 && fast0 < trend && slow0 < trend);
   
      return rejet && proche;
   }


   // 2) Vérifie s'il existe une position ouverte pour ce MAGIC/SYM
   static bool IsTradeOpen(const string symbol, const ulong __MAGIC_NUMBER)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong position_ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(position_ticket))
         {
            if(PositionGetInteger(POSITION_MAGIC) == __MAGIC_NUMBER
               && PositionGetString(POSITION_SYMBOL) == symbol )
               return true;
         }
      }
      return false;
   }

   // 3) Calcul de la taille de lot
   static double CalculerLotSize(const string symbol,
                                 double slPips,
                                 bool   _GestionDynamiqueLot,
                                 double _LotFixe,
                                 double _RisqueParTradePct)
   {
      if(!_GestionDynamiqueLot)
         return(_LotFixe);

      double valeurTick = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tailleTick = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      
      
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double max_balance = 100000.0;
      
      if (balance > max_balance)
          balance = max_balance;

      double montantRisque = balance * _RisqueParTradePct / 100.0;
      double lot = montantRisque / (slPips * (valeurTick / tailleTick));

      double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

      lot = MathFloor(lot / lotStep) * lotStep;
      lot = MathMax(minLot, MathMin(maxLot, lot));
      return NormalizeDouble(lot, 2);
   }

   // 4) Ouverture d’un ordre
   static void tradeOpen(const string      symbol,
                         const ulong       _MAGIC_NUMBER,
                         ENUM_ORDER_TYPE   type,
                         double            sl_pct,
                         double            tp_pct,
                         bool              _GestionDynamiqueLot,
                         double            _LotFixe,
                         double            _RisqueParTradePct,
                         bool              _UseMaxSpread   = false,
                         int               _MaxSpreadPoints= 20)
   {
   
      //--- 0) Filtre de spread si activé
      if(_UseMaxSpread)
        {
         int spread_points = (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
         if(spread_points > _MaxSpreadPoints)
           {
            PrintFormat("Spread trop élevé (%d pts > %d pts) → ordre annulé",
                        spread_points, _MaxSpreadPoints);
            return;
           }
        }
   
      double price = SymbolInfoDouble(symbol, type == ORDER_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID);
      double sl    = price - (type==ORDER_TYPE_BUY?1:-1)*price*sl_pct/100.0;
      double tp    = price + (type==ORDER_TYPE_BUY?1:-1)*price*tp_pct/100.0;
      if(type == ORDER_TYPE_SELL && tp < 0)
         tp = 1.0;

      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      request.action   = TRADE_ACTION_DEAL;
      request.symbol   = symbol;
      request.magic    = _MAGIC_NUMBER;
      request.type     = type;
      double slPips    = MathAbs(price - sl) / SymbolInfoDouble(symbol, SYMBOL_POINT) / 10.0;
      request.volume   = CalculerLotSize(symbol, slPips, _GestionDynamiqueLot, _LotFixe, _RisqueParTradePct);
      request.price    = price;
      request.sl       = NormalizeDouble(sl, _Digits);
      request.tp       = NormalizeDouble(tp, _Digits);
      request.deviation= 10;

      if(!OrderSend(request, result))
         Print("Erreur ouverture ordre : ", result.comment);
   }
   
    // 4) Ouverture d’un ordre
   static void tradeOpenNoSL(const string      symbol,
                         const ulong       _MAGIC_NUMBER,
                         ENUM_ORDER_TYPE   type,
                         double            sl_pct,
                         double            tp_pct,
                         bool              _GestionDynamiqueLot,
                         double            _LotFixe,
                         double            _RisqueParTradePct,
                         bool              _UseMaxSpread   = false,
                         int               _MaxSpreadPoints= 20)
   {
   
      //--- 0) Filtre de spread si activé
      if(_UseMaxSpread)
        {
         int spread_points = (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
         if(spread_points > _MaxSpreadPoints)
           {
            PrintFormat("Spread trop élevé (%d pts > %d pts) → ordre annulé",
                        spread_points, _MaxSpreadPoints);
            return;
           }
        }
   
      double price = SymbolInfoDouble(symbol, type == ORDER_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID);
      double sl    = price - (type==ORDER_TYPE_BUY?1:-1)*price*sl_pct/100.0;
      double tp    = price + (type==ORDER_TYPE_BUY?1:-1)*price*tp_pct/100.0;
      if(type == ORDER_TYPE_SELL && tp < 0)
         tp = 1.0;

      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      request.action   = TRADE_ACTION_DEAL;
      request.symbol   = symbol;
      request.magic    = _MAGIC_NUMBER;
      request.type     = type;
      double slPips    = MathAbs(price - sl) / SymbolInfoDouble(symbol, SYMBOL_POINT) / 10.0;
      request.volume   = CalculerLotSize(symbol, slPips, _GestionDynamiqueLot, _LotFixe, _RisqueParTradePct);
      request.price    = price;
      //request.sl       = NormalizeDouble(sl, _Digits);
      request.tp       = NormalizeDouble(tp, _Digits);
      request.deviation= 10;

      if(!OrderSend(request, result))
         Print("Erreur ouverture ordre : ", result.comment);
   }
   
   

   // 5) Fermeture complète d’un ticket
   static void tradeClose(const string symbol,
                          const ulong  _MAGIC_NUMBER,
                          const ulong  ticket)
   {
      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      if(!PositionSelectByTicket(ticket))
         return;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double price = SymbolInfoDouble(symbol, type == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK);

      request.action   = TRADE_ACTION_DEAL;
      request.symbol   = symbol;
      request.position = ticket;
      request.volume   = PositionGetDouble(POSITION_VOLUME);
      request.price    = price;
      request.type     = (type == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
      request.deviation= 10;

      if(!OrderSend(request, result))
         Print("Erreur fermeture ordre : ", result.comment);
   }

   // 6) Trailing Stop
   static void GererTrailingStop(const string symbol,
                                 const ulong  _MAGIC_NUMBER,
                                 bool          _utiliser_trailing_stop,
                                 double        _trailing_stop_pct)
   {
      if(!_utiliser_trailing_stop) return;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket))
            continue;

         if(PositionGetInteger(POSITION_MAGIC) != _MAGIC_NUMBER
            || PositionGetString(POSITION_SYMBOL) != symbol)
            continue;

         double prix_actuel_bid = SymbolInfoDouble(symbol, SYMBOL_BID);
         double prix_actuel_ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
         double prix_position   = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl_actuel       = PositionGetDouble(POSITION_SL);
         ENUM_POSITION_TYPE type= (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         double nouveau_sl;

         if(type == POSITION_TYPE_BUY)
            nouveau_sl = prix_actuel_bid - (prix_actuel_bid * _trailing_stop_pct / 100.0);
         else
            nouveau_sl = prix_actuel_ask + (prix_actuel_ask * _trailing_stop_pct / 100.0);

         if((type == POSITION_TYPE_BUY  && nouveau_sl > prix_position && (nouveau_sl > sl_actuel || sl_actuel == 0)) ||
            (type == POSITION_TYPE_SELL && nouveau_sl < prix_position && (nouveau_sl < sl_actuel || sl_actuel == 0)))
            ModifierSL(symbol, ticket, nouveau_sl);
      }
   }


struct PositionInfo
{
   ulong ticket;
   ulong magic;
   string symbol;
   int type;
   double profit;
   datetime open_time;
};

static void GetOpenPositions(const string symbol, const ulong magic, PositionInfo &positions[], int &count)
{
   count = 0;
   ArrayResize(positions, 0);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong position_ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(position_ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == magic
            && PositionGetString(POSITION_SYMBOL) == symbol)
         {
            PositionInfo info;
            info.ticket = position_ticket;
            info.magic = magic;
            info.symbol = symbol;
            info.type = (int)PositionGetInteger(POSITION_TYPE);
            info.profit = PositionGetDouble(POSITION_PROFIT);
            info.open_time = (datetime)PositionGetInteger(POSITION_TIME);
            
            ArrayResize(positions, count + 1);
            positions[count] = info;
            count++;
         }
      }
   }
}




//-----------------------------------------------------------------------------
// Retourne le volume initial (à l'ouverture) d'une position déjà sélectionnée
// (PositionSelectByTicket doit déjà avoir été appelée)
//-----------------------------------------------------------------------------
static double GetVolumeInitial()
{
   // 1️⃣ Récupérer l'identifiant (ticket) de l'ordre d'ouverture
   ulong orderTicket = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   if(orderTicket == 0)
   {
      //Print("GetVolumeInitial(): position non valide");
      return(0.0);
   }

   // 2️⃣ Charger l'historique des deals de cette position
   //    HistorySelectByPosition charge ORDRES et DEALS liés à l'ID de position
   if(!HistorySelectByPosition(orderTicket))
   {
      //PrintFormat("GetVolumeInitial(): HistorySelectByPosition failed (%d)", GetLastError());
      return(0.0);
   }

   // 3️⃣ Balayer les deals pour trouver le(s) DEAL_ENTRY_IN
   int    totalDeals = HistoryDealsTotal();
   double openVol    = 0.0;
   datetime earliest = LONG_MAX;
   for(int i = 0; i < totalDeals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_IN)
      {
         // on prend le deal d'entrée le plus ancien (cas scaling-in)
         datetime t = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
         if(t < earliest)
         {
            earliest = t;
            openVol  = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
         }
      }
   }

   return(openVol);
}



   // 7) Fonction pour modifier le SL
   static void ModifierSL(const string symbol,
                          ulong  ticket,
                          double nouveau_sl)
   {
      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      request.action   = TRADE_ACTION_SLTP;
      request.symbol   = symbol;
      request.position = ticket;
      request.sl       = NormalizeDouble(nouveau_sl, _Digits);
      request.tp       = PositionGetDouble(POSITION_TP);

      if(!OrderSend(request, result))
         Print("Erreur Trailing Stop : ", result.comment);
   }

   // 8) Prises profit partielles
   static void GererPrisesProfitsPartielles(const string symbol,
                                            const ulong  _MAGIC_NUMBER,
                                            bool          _utiliser_prise_profit_partielle,
                                            double        _tranche_prise_profit_pct,
                                            int           _nb_tp_partiel,
                                            bool          mettre_SL_en_breakeven = false,
                                            bool _closeIfVolumeLow = false,
                                            double _percentToCloseTrade = 0.20)
   {
      if(!_utiliser_prise_profit_partielle)
         return;

      double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      int    prec    = (int)MathRound(-MathLog(lotStep)/MathLog(10.0));

      int totalPos = PositionsTotal();
      for(int i = totalPos - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket))
            continue;

         if(PositionGetInteger(POSITION_MAGIC) != _MAGIC_NUMBER
            || PositionGetString(POSITION_SYMBOL) != symbol)
            continue;


         
         double OpenVolumeInitial = GetVolumeInitial();
         
         double prixOuverture  = PositionGetDouble(POSITION_PRICE_OPEN);
         double prixTPFinal    = PositionGetDouble(POSITION_TP);
         ENUM_POSITION_TYPE typePos = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double volumeInitial  = PositionGetDouble(POSITION_VOLUME);
         double volumeRestant  = volumeInitial;

         
               // Vérifier si le SL est déjà en positif
         double slActuel = PositionGetDouble(POSITION_SL);
         
         if(_closeIfVolumeLow && volumeRestant <= _percentToCloseTrade * OpenVolumeInitial)
         {
            tradeClose(symbol,(ulong)_MAGIC_NUMBER ,ticket); // Fermer complètement la position
            Print("volume trop petit => on close");
            return; // Sortir de la fonction après avoir fermé la position
         }

        // --- On stacke les volumes à fermer ---
        double volumeTotalAClore = 0;

         for(int n = 1; n <= _nb_tp_partiel; n++)
         {
            double pct     = _tranche_prise_profit_pct * n;
            double tpLevel = (typePos == POSITION_TYPE_BUY)
                              ? prixOuverture + pct * (prixTPFinal - prixOuverture)
                              : prixOuverture - pct * (prixOuverture - prixTPFinal);
            double prixActu = (typePos == POSITION_TYPE_BUY)
                              ? SymbolInfoDouble(symbol, SYMBOL_BID)
                              : SymbolInfoDouble(symbol, SYMBOL_ASK);

            if((typePos == POSITION_TYPE_BUY  && prixActu >= tpLevel) ||
               (typePos == POSITION_TYPE_SELL && prixActu <= tpLevel))
            {
               double volToClose = NormalizeDouble(volumeInitial * _tranche_prise_profit_pct, prec);
               if(volToClose < minLot)
                  volToClose = minLot;
               if(volumeRestant - volToClose < minLot)
                  volToClose = volumeRestant - minLot;
               if(volToClose >= minLot)
               {
                   volumeTotalAClore += volToClose;
                  volumeRestant -= volToClose;
                  

               }
            }
         }
         
                 // --- On envoie UNE SEULE requête pour fermer tout ce volume ---
        if (volumeTotalAClore >= minLot)
        {
            FermerPartiellement(symbol, ticket, volumeTotalAClore);
            // Ajuste le SL en breakeven une fois, si demandé
            AjusterStopLossAuBreakeven(symbol, ticket, prixOuverture, typePos, slActuel, mettre_SL_en_breakeven);
        }
      }
   }




   // 9) Fonction pour fermer partiellement une position
   static void FermerPartiellement(const string symbol,
                                   ulong        ticket,
                                   double       volume_a_fermer)
   {
      if(volume_a_fermer < 0.01)
         return;

      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      if(!PositionSelectByTicket(ticket))
         return;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double prix = SymbolInfoDouble(symbol, type == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK);

      request.action   = TRADE_ACTION_DEAL;
      request.symbol   = symbol;
      request.position = ticket;
      request.volume   = NormalizeDouble(volume_a_fermer, 2);
      request.price    = prix;
      request.type     = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      request.deviation= 10;

      if(!OrderSend(request, result))
         Print("Erreur prise profit partielle : ", result.comment);
   }
   
   // 8) Prises profit partielles (ancienne logique, sans décrémenter volume_restant)
static void GererPrisesProfitsPartielles2(const string symbol,
                                         const ulong  _MAGIC_NUMBER,
                                         bool          _utiliser_prise_profit_partielle,
                                         double        _tranche_prise_profit_pct,
                                         int           _nb_tp_partiel)
{
   if(!_utiliser_prise_profit_partielle)
      return;

   int totalPos = PositionsTotal();
   for(int idx = totalPos - 1; idx >= 0; idx--)
   {
      ulong ticket = PositionGetTicket(idx);
      if(!PositionSelectByTicket(ticket))
         continue;

      // filtrage magic + symbole
      if(PositionGetInteger(POSITION_MAGIC) != _MAGIC_NUMBER ||
         PositionGetString (POSITION_SYMBOL)!= symbol)
         continue;

      double prixOuverture = PositionGetDouble(POSITION_PRICE_OPEN);
      double prixTPFinal   = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE typePos = (ENUM_POSITION_TYPE)
                                   PositionGetInteger(POSITION_TYPE);
      double volumeInitial = PositionGetDouble(POSITION_VOLUME);
      double volumeRestant = volumeInitial;

      // cours actuel
      double prixActuBid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double prixActuAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);

      // boucle sur chaque tranche
      for(int n = 1; n <= _nb_tp_partiel; n++)
      {
         double niveauPct = _tranche_prise_profit_pct * n;

         if(typePos == POSITION_TYPE_BUY)
         {
            double tpLevel = prixOuverture + niveauPct * (prixTPFinal - prixOuverture);
            // condition identique à l'ancienne
            if(prixActuBid >= tpLevel
               && volumeRestant >= volumeInitial * (1.0 - _tranche_prise_profit_pct * n))
            {
               // volume à fermer = fraction fixe du volume initial
               double volToClose = volumeInitial * _tranche_prise_profit_pct;
               FermerPartiellement2(symbol, ticket, volToClose);
            }
         }
         else // SELL
         {
            double tpLevel = prixOuverture - niveauPct * (prixOuverture - prixTPFinal);
            if(prixActuAsk <= tpLevel
               && volumeRestant >= volumeInitial * (1.0 - _tranche_prise_profit_pct * n))
            {
               double volToClose = volumeInitial * _tranche_prise_profit_pct;
               FermerPartiellement2(symbol, ticket, volToClose);
            }
         }
      }
   }
}


// 9) Fonction pour fermer partiellement une position (ancienne logique + minLot)
static void FermerPartiellement2(const string symbol,
                                ulong        ticket,
                                double       volume_a_fermer)
{
   // Récupération du lot minimum et du pas
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   // Précision décimale à appliquer
   int    prec    = (int)MathRound(-MathLog(lotStep)/MathLog(10.0));

   // Si la tranche demandée est inférieure au lot min, on ferme minLot
   double volToClose = volume_a_fermer < minLot ? minLot : volume_a_fermer;
   // On normalise au pas
   volToClose = NormalizeDouble(volToClose, prec);

   // Si après arrondi on est sous le lot min, on renonce
   if(volToClose < minLot)
      return;

   // Sélection de la position
   if(!PositionSelectByTicket(ticket))
      return;

   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double prix = SymbolInfoDouble(
      symbol,
      type == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK
   );

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = symbol;
   request.position  = ticket;
   request.volume    = volToClose;
   request.price     = prix;
   request.type      = (type==POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
   request.deviation = 10;

   if(!OrderSend(request, result))
      Print("Erreur prise profit partielle : ", result.comment);
}

// 8) Prises profit partielles (ancienne logique, sans état interne)
static void GererPrisesProfitsPartielles3(
   const string symbol,
   const ulong  _MAGIC_NUMBER,
   bool          _utiliser_prise_profit_partielle,
   double        _tranche_prise_profit_pct,
   int           _nb_tp_partiel)
{
   if(!_utiliser_prise_profit_partielle)
      return;

   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   int    prec    = (int)MathRound(-MathLog(lotStep)/MathLog(10.0));

   int totalPos = PositionsTotal();
   for(int i = totalPos - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      // filtrage magic + symbole
      if(PositionGetInteger(POSITION_MAGIC) != _MAGIC_NUMBER ||
         PositionGetString (POSITION_SYMBOL)!= symbol)
         continue;

      double prixOuverture = PositionGetDouble(POSITION_PRICE_OPEN);
      double prixTPFinal   = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE typePos      = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double volumeInitial            = PositionGetDouble(POSITION_VOLUME);
      double volumeRestant            = volumeInitial;

      for(int n = 1; n <= _nb_tp_partiel; n++)
      {
         double pct = _tranche_prise_profit_pct * n;
         double tpLevel = (typePos == POSITION_TYPE_BUY)
                          ? prixOuverture + pct * (prixTPFinal - prixOuverture)
                          : prixOuverture - pct * (prixOuverture - prixTPFinal);
         
         double prixActu = (typePos == POSITION_TYPE_BUY)
                           ? SymbolInfoDouble(symbol, SYMBOL_BID)
                           : SymbolInfoDouble(symbol, SYMBOL_ASK);

         if((typePos == POSITION_TYPE_BUY  && prixActu >= tpLevel) ||
            (typePos == POSITION_TYPE_SELL && prixActu <= tpLevel))
         {
            // volume fixe = fraction du volume initial
            double volToClose = NormalizeDouble(volumeInitial * _tranche_prise_profit_pct, prec);
            if(volToClose < minLot)
               volToClose = minLot;
            if(volumeRestant - volToClose < minLot)
               volToClose = volumeRestant - minLot;
            if(volToClose >= minLot)
            {
               FermerPartiellement3(symbol, ticket, volToClose);
               volumeRestant -= volToClose;
            }
         }
      }
   }
}

// 9) Fermer partiellement (ancienne logique, normalisation à 2 décimales)
static void FermerPartiellement3(
   const string symbol,
   ulong        ticket,
   double       volume_a_fermer)
{
   // seuil rigide 0.01
   if(volume_a_fermer < 0.01)
      return;

   if(!PositionSelectByTicket(ticket))
      return;

   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double prix = SymbolInfoDouble(
      symbol,
      type == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK
   );

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = symbol;
   request.position  = ticket;
   request.volume    = NormalizeDouble(volume_a_fermer, 2);
   request.price     = prix;
   request.type      = (type==POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
   request.deviation = 10;

   if(!OrderSend(request, result))
      Print("Erreur prise profit partielle : ", result.comment);
}

//--- Helper : charger les trackers depuis les Global Variables au démarrage
   static void LoadTrackersFromGV()
   {
      s_trackerCount = 0;
      int totalGV = GlobalVariablesTotal();
      for(int i = 0; i < totalGV; i++)
      {
         string name = GlobalVariableName(i);
         if(StringFind(name, "TPTrack_") == 0)
         {
            // nom = "TPTrack_<ticket>"
            ulong ticket = (ulong)StringToInteger(StringSubstr(name, 8));
            double lastP = GlobalVariableGet(name);
            // ne recrée le tracker que si la position existe
            if(PositionSelectByTicket(ticket))
            {
               s_trackers[s_trackerCount].ticket            = ticket;
               s_trackers[s_trackerCount].initVolume        = PositionGetDouble(POSITION_VOLUME);
               s_trackers[s_trackerCount].lastClosedPallier = (int)lastP;
               s_trackerCount++;
            }
            else
            {
               // position déjà fermée, on nettoie la GV
               GlobalVariableDel(name);
            }
         }
      }
   }

   //--- Helper : mettre à jour la liste des trackers à chaque tick
   static void UpdateTrackers(const string symbol, const ulong _MAGIC_NUMBER)
   {
      // 1) retirer les trackers pour tickets clos
      for(int i = 0; i < s_trackerCount; i++)
      {
         bool found = false;
         for(int j = 0; j < PositionsTotal(); j++)
            if(PositionGetTicket(j) == s_trackers[i].ticket)
            {
               found = true;
               break;
            }
         if(!found)
         {
            // supprimer la GV associée
            GlobalVariableDel("TPTrack_" + (string)s_trackers[i].ticket);
            // écraser l'entrée i
            s_trackers[i] = s_trackers[s_trackerCount - 1];
            s_trackerCount--;
            i--;
         }
      }
      // 2) ajouter les nouvelles positions EA
      for(int j = 0; j < PositionsTotal() && s_trackerCount < 100; j++)
      {
         ulong ticket = PositionGetTicket(j);
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetInteger(POSITION_MAGIC) != _MAGIC_NUMBER) continue;
         if(PositionGetString(POSITION_SYMBOL) != symbol)        continue;
         // existe-t-il déjà ?
         bool exists = false;
         for(int i = 0; i < s_trackerCount; i++)
            if(s_trackers[i].ticket == ticket)
            {
               exists = true;
               break;
            }
         if(!exists)
         {
            s_trackers[s_trackerCount].ticket            = ticket;
            s_trackers[s_trackerCount].initVolume        = PositionGetDouble(POSITION_VOLUME);
            s_trackers[s_trackerCount].lastClosedPallier = 0;
            // créer la GV initiale
            GlobalVariableSet("TPTrack_" + (string)ticket, 0.0);
            s_trackerCount++;
         }
      }
   }

   //--- 8) Prises profit partielles 4Corrigé ---
static void GererPrisesProfitsPartielles4Corrige(
   const string symbol,
   const ulong  _MAGIC_NUMBER,
   bool          _utiliser_prise_profit_partielle,
   double        tranche_pct,
   int           _nb_tp_partiel)
{
   if(!_utiliser_prise_profit_partielle) 
      return;

   // Pré-calculs pour les lots
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   int    prec    = (int)MathRound(-MathLog(lotStep)/MathLog(10.0));

   // Charger trackers si besoin (appelé une seule fois)
   static bool loaded = false;
   if(!loaded)
   {
      LoadTrackersFromGV();
      loaded = true;
   }

   // Mettre à jour la liste des positions à suivre
   UpdateTrackers(symbol, _MAGIC_NUMBER);

   // Parcours de chaque position suivie
   for(int i = 0; i < s_trackerCount; i++)
   {
      ulong ticket = s_trackers[i].ticket;
      if(!PositionSelectByTicket(ticket))
         continue;

      // Récupérer ouverture / TP / type / volume courant
      double prixOpen = PositionGetDouble(POSITION_PRICE_OPEN);
      double prixTP   = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE typePos = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double curVol   = PositionGetDouble(POSITION_VOLUME);

      // Calcul de la progression vers le TP
      double prixActu = (typePos==POSITION_TYPE_BUY)
                        ? SymbolInfoDouble(symbol, SYMBOL_BID)
                        : SymbolInfoDouble(symbol, SYMBOL_ASK);
      double moved    = (typePos==POSITION_TYPE_BUY)
                        ? prixActu - prixOpen
                        : prixOpen - prixActu;
      double total    = MathAbs(prixTP - prixOpen);

      // Nombre de paliers déjà atteints
      int reached = 0;
      if(total > 0.0)
         reached = MathMin(_nb_tp_partiel,
                   (int)MathFloor((moved/total)/tranche_pct + 1e-9));

      // Fermer uniquement les nouveaux paliers
      for(int n = s_trackers[i].lastClosedPallier + 1; n <= reached; n++)
      {
         // volume à fermer = tranche % de l'initVolume
         double volToClose = NormalizeDouble(
            s_trackers[i].initVolume * tranche_pct,
            prec
         );
         // respecter minLot et pas dépasser ce qui reste
         if(volToClose < minLot)           volToClose = minLot;
         if(curVol - volToClose < minLot)  volToClose = curVol - minLot;

         if(volToClose >= minLot)
         {
            // Exécution de la prise partielle
            FermerPartiellement4Corrige(symbol, ticket, volToClose, prec);
            curVol -= volToClose;
         }

         // Mise à jour du tracker et de la GV correspondante
         s_trackers[i].lastClosedPallier = n;
         GlobalVariableSet(
            StringFormat("TPTrack_%I64u", ticket),
            (double)n
         );
      }
   }
}

//--- 9) Fermer partiellement une position (4Corrigé) ---
static void FermerPartiellement4Corrige(
   const string symbol,
   ulong        ticket,
   double       volume_a_fermer,
   int          prec)
{
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   if(volume_a_fermer < minLot) 
      return;
   if(!PositionSelectByTicket(ticket)) 
      return;

   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double price = SymbolInfoDouble(
      symbol,
      type==POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK
   );

   MqlTradeRequest request={};
   MqlTradeResult  result ={};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = symbol;
   request.position  = ticket;
   request.volume    = NormalizeDouble(volume_a_fermer, prec);
   request.price     = price;
   request.type      = (type==POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
   request.deviation = 10;

   if(!OrderSend(request, result))
      Print("Erreur prise profit partielle 4Corrigé: ", result.comment);
}



// Fonction pour ajuster le SL à breakeven (ou légèrement au-dessus ou en-dessous)
static void AjusterStopLossAuBreakeven(const string symbol, ulong ticket, double prixOuverture, ENUM_POSITION_TYPE typePos, double slActuel, bool mettre_SL_en_breakeven)
{
   if(!mettre_SL_en_breakeven)
      return;  // Si on ne veut pas ajuster le SL, on sort de la fonction

   double prixBreakeven = prixOuverture;
   if(typePos == POSITION_TYPE_BUY)
   {
      // Pour un achat, on met le SL juste au-dessus du prix d'ouverture
      prixBreakeven = prixOuverture + SymbolInfoDouble(symbol, SYMBOL_POINT);

      // Vérifier si le SL est déjà au-dessus du prix d'ouverture
      if(slActuel < prixBreakeven || slActuel == 0)  // Si SL est encore sous le prix d'ouverture ou inexistant
      {
         // Utiliser la fonction ModifierSL pour ajuster le SL
         ModifierSL(symbol, ticket, prixBreakeven);
      }
   }
   else if(typePos == POSITION_TYPE_SELL)
   {
      // Pour une vente, on met le SL juste en-dessous du prix d'ouverture
      prixBreakeven = prixOuverture - SymbolInfoDouble(symbol, SYMBOL_POINT);

      // Vérifier si le SL est déjà en-dessous du prix d'ouverture
      if(slActuel > prixBreakeven || slActuel == 0)  // Si SL est au-dessus du prix d'ouverture ou inexistant
      {
         // Utiliser la fonction ModifierSL pour ajuster le SL
         ModifierSL(symbol, ticket, prixBreakeven);
      }
   }
}

// Structure pour stocker les infos nécessaires à la fermeture
struct PositionToClose
{
   ulong ticket;
   long  magic;
   string symbol;
   double profit;
};

static void CloseSmallProfitablePositions()
{
   double totalProfit = 0.0;
   PositionToClose toClose[];
   ArrayResize(toClose, 0);

   int total = PositionsTotal();

   // Étape 1 : collecter les positions candidates
   for (int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket))
         continue;

      double volume = NormalizeDouble(PositionGetDouble(POSITION_VOLUME), 2);
      double profit = PositionGetDouble(POSITION_PROFIT);

      if (volume == 0.01)
      {
         PositionToClose p;
         p.ticket = ticket;
         p.magic  = PositionGetInteger(POSITION_MAGIC);
         p.symbol = PositionGetString(POSITION_SYMBOL);

         totalProfit += profit;

         int idx = ArraySize(toClose);
         ArrayResize(toClose, idx + 1);
         toClose[idx] = p;


      }
   }

   // Étape 2 : fermeture uniquement si profit total > 0
   if (totalProfit > 0.0)
   {
      for (int i = 0; i < ArraySize(toClose); i++)
      {
         PositionToClose pos = toClose[i];



         // Clôture avec validation complète
         SamBotUtils::tradeClose(pos.symbol, pos.magic, pos.ticket);
      }

      PrintFormat("✅ Total des profits clôturés (0.01 lots) : %.2f", totalProfit);
   }

}

static void CloseSmallProfitablePositionsV2()
{
   int total = PositionsTotal();
   PositionToClose candidates[];
   ArrayResize(candidates, 0);

   // 1. Collecter les positions de volume 0.01
   for (int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket))
         continue;

      double volume = NormalizeDouble(PositionGetDouble(POSITION_VOLUME), 2);
      double profit = PositionGetDouble(POSITION_PROFIT);

      if (volume == 0.01)
      {
         PositionToClose p;
         p.ticket = ticket;
         p.magic  = PositionGetInteger(POSITION_MAGIC);
         p.symbol = PositionGetString(POSITION_SYMBOL);
         p.profit = profit;

         int idx = ArraySize(candidates);
         ArrayResize(candidates, idx + 1);
         candidates[idx] = p;
      }
   }

   // 2. Trier par profit croissant (via tableau d’indices)
   int count = ArraySize(candidates);
   int indices[];
   ArrayResize(indices, count);

   for (int i = 0; i < count; i++)
      indices[i] = i;

   // Tri des indices selon le profit associé
   for (int i = 0; i < count - 1; i++)
   {
      for (int j = i + 1; j < count; j++)
      {
         if (candidates[indices[i]].profit > candidates[indices[j]].profit)
         {
            int tmp = indices[i];
            indices[i] = indices[j];
            indices[j] = tmp;
         }
      }
   }

   // 3. Sélectionner le subset optimal (profit net > 0)
   PositionToClose toClose[];
   ArrayResize(toClose, 0);
   double totalProfit = 0.0;

   for (int i = 0; i < count; i++)
   {
      int idx = indices[i];
      totalProfit += candidates[idx].profit;

      int newIdx = ArraySize(toClose);
      ArrayResize(toClose, newIdx + 1);
      toClose[newIdx] = candidates[idx];

      if (totalProfit > 0.0)
         break;
   }

   // 4. Fermer si subset profitable
   if (totalProfit > 0.0)
   {
      for (int i = 0; i < ArraySize(toClose); i++)
      {
         SamBotUtils::tradeClose(toClose[i].symbol, toClose[i].magic, toClose[i].ticket);
      }

      PrintFormat("✅ V2 - Fermeture subset optimal (0.01 lot) : Profit total = %.2f", totalProfit);
   }
   else
   {
      //Print("⏸ V2 - Aucun subset profitable trouvé.");
   }
}


//--- Nouvelle fonction de calcul de la taille du lot (suffixée _pips)
static double CalculerLotSize_pips(const string symbol, const double stopLossPips, const bool useDynamicLot, const double fixedLot, const double riskPercent) {
    if (!useDynamicLot) {
        return fixedLot;
    }

    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double pointValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    double stopLossInAccountCurrency = stopLossPips * pointValue;
    double riskAmount = accountBalance * riskPercent / 100.0;

    if (stopLossInAccountCurrency <= 0) {
        return 0.01; // Taille de lot minimale par défaut
    }

    double lotSize = NormalizeDouble(riskAmount / stopLossInAccountCurrency, 2); // Exemple simple, nécessite une logique plus robuste

    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

    lotSize = MathMax(minLot, MathMin(maxLot, MathRound(lotSize / lotStep) * lotStep));

    return lotSize;
}

//--- Nouvelle fonction d'ouverture d'ordre avec SL et TP en pips (suffixée _pips)
static void tradeOpen_pips(const string        symbol,
                          const ulong         _MAGIC_NUMBER,
                          ENUM_ORDER_TYPE     type,
                          double              stopLossPips,
                          double              takeProfitPips,
                          bool                _GestionDynamiqueLot,
                          double              _LotFixe,
                          double              _RisqueParTradePct,
                          bool                _UseMaxSpread    = false,
                          int                 _MaxSpreadPoints = 20, string summary = "")
{

    //--- 0) Filtre de spread si activé
    if (_UseMaxSpread)
    {
        int spread_points = (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
        if (spread_points > _MaxSpreadPoints)
        {
            PrintFormat("Spread trop élevé (%d pts > %d pts) → ordre annulé",
                        spread_points, _MaxSpreadPoints);
            return;
        }
    }

    double price = SymbolInfoDouble(symbol, type == ORDER_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

    double sl = (type == ORDER_TYPE_BUY) ? price - stopLossPips * point : price + stopLossPips * point;
    double tp = (type == ORDER_TYPE_BUY) ? price + takeProfitPips * point : price - takeProfitPips * point;

    if (type == ORDER_TYPE_SELL && tp < 0)
        tp = 1.0; // Sécurité pour éviter un TP négatif

    MqlTradeRequest request = {};
    MqlTradeResult  result  = {};

    request.action    = TRADE_ACTION_DEAL;
    request.symbol    = symbol;
    request.magic     = _MAGIC_NUMBER;
    request.type      = type;
    request.volume    = CalculerLotSize_pips(symbol, stopLossPips, _GestionDynamiqueLot, _LotFixe, _RisqueParTradePct); // Utilisation de la nouvelle fonction de calcul du lot
    request.price     = price;
    request.sl        = NormalizeDouble(sl, digits);
    request.tp        = NormalizeDouble(tp, digits);
    request.deviation = 10;
    request.comment = summary;

    if (!OrderSend(request, result))
        Print("Erreur ouverture ordre : ", result.comment);
}



};



