//+------------------------------------------------------------------+
//|                                    Strategie_ADX_Enhanced_v3.mq5 |
//|                                             Adaptation MT5       |
//+------------------------------------------------------------------+
#property copyright "Adaptation MT5"
#property version   "3.00"
#property strict

#include <SamBotUtils.mqh>

//+------------------------------------------------------------------+
//| Énumérations                                                     |
//+------------------------------------------------------------------+
enum ENUM_TREND_DIRECTION
{
   TREND_UP = 1,      // Tendance haussière
   TREND_DOWN = -1,   // Tendance baissière  
   TREND_FLAT = 0     // Tendance plate/indécise
};

enum ENUM_TRADING_SESSION
{
   SESSION_ALL = 0,       // Toutes les sessions
   SESSION_LONDON = 1,    // Session de Londres (8h-17h GMT)
   SESSION_NEW_YORK = 2,  // Session de New York (13h-22h GMT)
   SESSION_ASIA = 3,      // Session d'Asie (0h-9h GMT)
   SESSION_LONDON_NY = 4, // Londres + New York
   SESSION_CUSTOM = 5     // Horaires personnalisés
};

//+------------------------------------------------------------------+
//| Structures                                                       |
//+------------------------------------------------------------------+
struct IndicatorDirection
{
   ENUM_TREND_DIRECTION main_line;    // Direction ligne principale (ADX)
   ENUM_TREND_DIRECTION plus_di;      // Direction +DI
   ENUM_TREND_DIRECTION minus_di;     // Direction -DI
};

struct SessionTime
{
   int start_hour;
   int start_minute;
   int end_hour;
   int end_minute;
};

//+------------------------------------------------------------------+
//| Classe pour détecter les directions                             |
//+------------------------------------------------------------------+
class CIndicatorDirectionDetector
{
private:
   int m_periods_to_check;
   double m_threshold;

public:
   CIndicatorDirectionDetector(int periods = 3, double threshold = 0.0001)
   {
      m_periods_to_check = periods;
      m_threshold = threshold;
   }
   
   ENUM_TREND_DIRECTION DetectDirection(double &values[], int start_index = 0)
   {
      if(ArraySize(values) < m_periods_to_check + start_index)
         return TREND_FLAT;
      
      double first_value = values[start_index + m_periods_to_check - 1];
      double last_value = values[start_index];
      
      double difference = last_value - first_value;
      
      if(MathAbs(difference) < m_threshold)
         return TREND_FLAT;
         
      return (difference > 0) ? TREND_UP : TREND_DOWN;
   }
   
   IndicatorDirection AnalyzeADX(int adx_handle)
   {
      IndicatorDirection result = {};
      
      if(adx_handle == INVALID_HANDLE)
         return result;
      
      double adx_main[], plus_di[], minus_di[];
      ArraySetAsSeries(adx_main, true);
      ArraySetAsSeries(plus_di, true);
      ArraySetAsSeries(minus_di, true);
      
      if(CopyBuffer(adx_handle, 0, 0, m_periods_to_check, adx_main) > 0)
         result.main_line = DetectDirection(adx_main);
         
      if(CopyBuffer(adx_handle, 1, 0, m_periods_to_check, plus_di) > 0)
         result.plus_di = DetectDirection(plus_di);
         
      if(CopyBuffer(adx_handle, 2, 0, m_periods_to_check, minus_di) > 0)
         result.minus_di = DetectDirection(minus_di);
      
      return result;
   }
};

//+------------------------------------------------------------------+
//| PARAMÈTRES D'ENTRÉE ORGANISÉS PAR GROUPES                      |
//+------------------------------------------------------------------+

//=== PARAMÈTRES GÉNÉRAUX ===
input group "=== PARAMÈTRES GÉNÉRAUX ==="
input ENUM_TIMEFRAMES TF                    = PERIOD_CURRENT;  // Timeframe
input int    MAGIC_NUMBER                   = 15975344;        // Numéro magique
input bool   showAlive                      = false;           // Afficher les signaux de vie
input bool   tradeVendredi                  = false;           // Autoriser le trading le vendredi

//=== GESTION DES RISQUES ===
input group "=== GESTION DES RISQUES ==="
input double stop_loss_pct                  = 1.0;            // Stop Loss (%)
input double take_profit_pct                = 2.0;            // Take Profit (%)
input bool   sortie_dynamique               = true;           // Sortie dynamique activée
input double MaxDrawdownPct                 = 5.0;            // Max Drawdown pour arrêt (%)
input double RisqueMaxParSymbole            = 1.0;            // Risque max par symbole (%)
input int    MaxPositionsParSymbole         = 3;              // Nombre max de positions par symbole

//=== GESTION DES LOTS ===
input group "=== GESTION DES LOTS ==="
input bool   GestionDynamiqueLot            = false;          // Gestion dynamique des lots
input double RisqueParTradePct              = 1.0;            // Risque par trade (%)
input double LotFixe                        = 0.1;            // Lot fixe

//=== PARAMÈTRES ADX ===
input group "=== PARAMÈTRES ADX ==="
input int    ADX_Period                     = 14;             // Période ADX
input double Seuil_ADX                      = 25.0;           // Seuil ADX minimum
input double Seuil_ADX_Fort                 = 35.0;           // Seuil ADX signal fort
input int    Periodes_Direction             = 3;              // Périodes pour direction
input double Seuil_Direction                = 0.1;            // Seuil minimum mouvement
input bool   Exiger_ADX_Montant             = true;           // ADX doit monter
input bool   Exiger_DI_Divergent            = true;           // +DI et -DI divergent
input double Ecart_DI_Minimum               = 5.0;            // Écart minimum +DI/-DI

//=== SESSIONS DE TRADING ===
input group "=== SESSIONS DE TRADING ==="
input ENUM_TRADING_SESSION Session_Trading  = SESSION_ALL;    // Session de trading
input int    Heure_Debut_Custom             = 8;              // Heure début (custom)
input int    Minute_Debut_Custom            = 0;              // Minute début (custom)
input int    Heure_Fin_Custom               = 17;             // Heure fin (custom)
input int    Minute_Fin_Custom              = 0;              // Minute fin (custom)

//=== TRAILING STOP ===
input group "=== TRAILING STOP ==="
input bool   utiliser_trailing_stop         = false;          // Utiliser trailing stop
input double trailing_stop_pct              = 0.5;            // Trailing stop (%)

//=== PRISES DE PROFIT PARTIELLES ===
input group "=== PRISES DE PROFIT PARTIELLES ==="
input bool   utiliser_prise_profit_partielle= false;          // Utiliser TP partiels
input double tranche_prise_profit_pct       = 0.02;           // Tranche TP (%)
input int    nb_tp_partiel                  = 2;              // Nombre de TP partiels
input bool   SL_BreakEVEN_after_first_partialTp = false;      // SL à BE après 1er TP

//=== CONTRÔLE DU SPREAD ===
input group "=== CONTRÔLE DU SPREAD ==="
input bool   UseMaxSpread                   = false;          // Utiliser spread max
input int    MaxSpreadPoints                = 40;             // Spread max (points)

//=== CONTRÔLE DE VOLUME ===
input group "=== CONTRÔLE DE VOLUME ==="
input bool   closeIfVolumeLow               = false;          // Fermer si volume faible
input double percentToCloseTrade            = 0.20;           // % pour fermer trade

//--- Variables globales
int handle_ADX;
double ADXBuf[], plusDIBuf[], minusDIBuf[];
CIndicatorDirectionDetector *detector;
double InitialBalance;
double MaxEquityReached;
bool TradingBlocked = false;

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   // Création du handle ADX
   handle_ADX = iADX(_Symbol, TF, ADX_Period);
   if(handle_ADX == INVALID_HANDLE)
   {
      Print("Erreur à la création du handle ADX");
      return(INIT_FAILED);
   }
   
   // Création du détecteur de direction
   detector = new CIndicatorDirectionDetector(Periodes_Direction, Seuil_Direction);
   
   // Initialisation des variables de contrôle DD
   InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   MaxEquityReached = AccountInfoDouble(ACCOUNT_EQUITY);
   TradingBlocked = false;
   
   Print("EA ADX Enhanced v3.0 initialisé avec succès");
   Print("Balance initiale: ", DoubleToString(InitialBalance, 2));
   Print("Session de trading: ", EnumToString(Session_Trading));
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Fonction pour vérifier les sessions de trading                 |
//+------------------------------------------------------------------+
bool IsInTradingSession()
{
   if(Session_Trading == SESSION_ALL)
      return true;
      
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int current_hour = dt.hour;
   int current_minute = dt.min;
   
   SessionTime session = {};
   
   switch(Session_Trading)
   {
      case SESSION_LONDON:
         session.start_hour = 8; session.start_minute = 0;
         session.end_hour = 17; session.end_minute = 0;
         break;
         
      case SESSION_NEW_YORK:
         session.start_hour = 13; session.start_minute = 0;
         session.end_hour = 22; session.end_minute = 0;
         break;
         
      case SESSION_ASIA:
         session.start_hour = 0; session.start_minute = 0;
         session.end_hour = 9; session.end_minute = 0;
         break;
         
      case SESSION_LONDON_NY:
         // Chevauchement Londres-NY (13h-17h GMT)
         session.start_hour = 13; session.start_minute = 0;
         session.end_hour = 17; session.end_minute = 0;
         break;
         
      case SESSION_CUSTOM:
         session.start_hour = Heure_Debut_Custom;
         session.start_minute = Minute_Debut_Custom;
         session.end_hour = Heure_Fin_Custom;
         session.end_minute = Minute_Fin_Custom;
         break;
         
      default:
         return true;
   }
   
   int current_time_minutes = current_hour * 60 + current_minute;
   int start_time_minutes = session.start_hour * 60 + session.start_minute;
   int end_time_minutes = session.end_hour * 60 + session.end_minute;
   
   // Gestion du passage de minuit
   if(start_time_minutes > end_time_minutes)
   {
      return (current_time_minutes >= start_time_minutes || current_time_minutes <= end_time_minutes);
   }
   else
   {
      return (current_time_minutes >= start_time_minutes && current_time_minutes <= end_time_minutes);
   }
}

//+------------------------------------------------------------------+
//| Fonction pour vérifier le drawdown maximum                     |
//+------------------------------------------------------------------+
bool CheckMaxDrawdown()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Mise à jour de l'equity maximum
   if(currentEquity > MaxEquityReached)
      MaxEquityReached = currentEquity;
   
   // Calcul du drawdown depuis le pic
   double drawdownFromPeak = (MaxEquityReached - currentEquity) / MaxEquityReached * 100.0;
   
   if(drawdownFromPeak >= MaxDrawdownPct)
   {
      if(!TradingBlocked)
      {
         Print("ALERTE: Drawdown maximum atteint (", DoubleToString(drawdownFromPeak, 2), "%)");
         Print("Fermeture de toutes les positions et blocage du trading");
         
         // Fermer toutes les positions de ce symbol avec ce magic number
         CloseAllPositions();
         TradingBlocked = true;
      }
      return false;
   }
   
   // Réactivation du trading si le drawdown revient sous le seuil
   if(TradingBlocked && drawdownFromPeak < MaxDrawdownPct * 0.8) // 20% de marge
   {
      Print("Trading réactivé - Drawdown revenu à ", DoubleToString(drawdownFromPeak, 2), "%");
      TradingBlocked = false;
   }
   
   return !TradingBlocked;
}

//+------------------------------------------------------------------+
//| Fermer toutes les positions                                    |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol)
      {
         ulong positionMagic = PositionGetInteger(POSITION_MAGIC);
         if(positionMagic == MAGIC_NUMBER)
         {
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            SamBotUtils::tradeClose(_Symbol, (ulong)MAGIC_NUMBER, ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculer le risque total actuel pour ce symbole               |
//+------------------------------------------------------------------+
double CalculateCurrentSymbolRisk()
{
   double totalRisk = 0.0;
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == _Symbol)
      {
         ulong positionMagic = PositionGetInteger(POSITION_MAGIC);
         if(positionMagic == MAGIC_NUMBER)
         {
            double positionSL = PositionGetDouble(POSITION_SL);
            double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double positionVolume = PositionGetDouble(POSITION_VOLUME);
            
            if(positionSL > 0)
            {
               double slDistance = MathAbs(positionOpenPrice - positionSL);
               double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
               double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
               
               double riskAmount = (slDistance / tickSize) * tickValue * positionVolume;
               totalRisk += (riskAmount / accountBalance) * 100.0;
            }
         }
      }
   }
   
   return totalRisk;
}

//+------------------------------------------------------------------+
//| Compter les positions ouvertes pour ce symbole                |
//+------------------------------------------------------------------+
int CountSymbolPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == _Symbol)
      {
         ulong positionMagic = PositionGetInteger(POSITION_MAGIC);
         if(positionMagic == MAGIC_NUMBER)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Vérifier si on peut ouvrir une nouvelle position              |
//+------------------------------------------------------------------+
bool CanOpenNewPosition()
{
   // Vérifications de base
   if(TradingBlocked) return false;
   if(!IsInTradingSession()) return false;
   
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   if(now.day_of_week == 5 && !tradeVendredi) // Vendredi
      return false;
   
   // Vérifier le nombre maximum de positions
   if(CountSymbolPositions() >= MaxPositionsParSymbole)
   {
      if(showAlive)
         Print("Nombre maximum de positions atteint (", MaxPositionsParSymbole, ")");
      return false;
   }
   
   // Vérifier le risque total pour ce symbole
   double currentRisk = CalculateCurrentSymbolRisk();
   double newTradeRisk = GestionDynamiqueLot ? RisqueParTradePct : 
                        (LotFixe * stop_loss_pct); // Approximation pour lot fixe
   
   if(currentRisk + newTradeRisk > RisqueMaxParSymbole)
   {
      if(showAlive)
         Print("Risque maximum par symbole atteint. Risque actuel: ", 
               DoubleToString(currentRisk, 2), "%, Nouveau trade: ",
               DoubleToString(newTradeRisk, 2), "%, Max autorisé: ",
               DoubleToString(RisqueMaxParSymbole, 2), "%");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Fonction pour analyser les signaux ADX                         |
//+------------------------------------------------------------------+
bool AnalyzeADXSignals(bool &buySignal, bool &sellSignal, bool &signalFort)
{
   // Récupération des valeurs actuelles
   if(CopyBuffer(handle_ADX, 0, 0, 1, ADXBuf) < 1) return false;
   if(CopyBuffer(handle_ADX, 1, 0, 1, plusDIBuf) < 1) return false;
   if(CopyBuffer(handle_ADX, 2, 0, 1, minusDIBuf) < 1) return false;

   double adx = ADXBuf[0];
   double pDI = plusDIBuf[0];
   double mDI = minusDIBuf[0];
   
   // Analyse des directions
   IndicatorDirection directions = detector.AnalyzeADX(handle_ADX);
   
   // Conditions de base
   bool tendanceForte = (adx > Seuil_ADX);
   signalFort = (adx > Seuil_ADX_Fort);
   
   // Conditions avancées
   bool adxMontant = !Exiger_ADX_Montant || (directions.main_line == TREND_UP);
   bool ecartDISuffisant = (MathAbs(pDI - mDI) >= Ecart_DI_Minimum);
   
   // Vérification de la divergence des DI
   bool diDivergent = true;
   if(Exiger_DI_Divergent)
   {
      diDivergent = (directions.plus_di != directions.minus_di) || 
                    (directions.plus_di == TREND_FLAT || directions.minus_di == TREND_FLAT);
   }
   
   // Signaux d'achat
   buySignal = tendanceForte && 
               (pDI > mDI) && 
               adxMontant && 
               ecartDISuffisant && 
               diDivergent &&
               (directions.plus_di == TREND_UP || directions.plus_di == TREND_FLAT) &&
               (directions.minus_di != TREND_UP);
               
   // Signaux de vente
   sellSignal = tendanceForte && 
                (mDI > pDI) && 
                adxMontant && 
                ecartDISuffisant && 
                diDivergent &&
                (directions.minus_di == TREND_UP || directions.minus_di == TREND_FLAT) &&
                (directions.plus_di != TREND_UP);
   
   // Affichage des informations de debug
   if(showAlive && (buySignal || sellSignal))
   {
      Print("=== Signal détecté ===");
      Print("ADX: ", DoubleToString(adx, 2), " (+DI: ", DoubleToString(pDI, 2), 
            ", -DI: ", DoubleToString(mDI, 2), ")");
      Print("Directions - ADX: ", EnumToString(directions.main_line), 
            ", +DI: ", EnumToString(directions.plus_di), 
            ", -DI: ", EnumToString(directions.minus_di));
      Print("Signal fort: ", signalFort ? "OUI" : "NON");
      Print("Positions actuelles: ", CountSymbolPositions(), "/", MaxPositionsParSymbole);
      Print("Risque actuel: ", DoubleToString(CalculateCurrentSymbolRisk(), 2), "% /", 
            DoubleToString(RisqueMaxParSymbole, 2), "%");
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Fonction pour vérifier si le signal s'affaiblit                |
//+------------------------------------------------------------------+
bool IsSignalWeakening(ENUM_POSITION_TYPE positionType)
{
   IndicatorDirection directions = detector.AnalyzeADX(handle_ADX);
   
   double adx = ADXBuf[0];
   double pDI = plusDIBuf[0];
   double mDI = minusDIBuf[0];
   
   bool adxFaible = (adx < Seuil_ADX);
   bool adxDescendant = (directions.main_line == TREND_DOWN);
   
   if(positionType == POSITION_TYPE_BUY)
   {
      return adxFaible || 
             (adxDescendant && adx < Seuil_ADX_Fort) ||
             (directions.plus_di == TREND_DOWN && directions.minus_di == TREND_UP) ||
             (mDI > pDI && directions.minus_di == TREND_UP);
   }
   else if(positionType == POSITION_TYPE_SELL)
   {
      return adxFaible || 
             (adxDescendant && adx < Seuil_ADX_Fort) ||
             (directions.minus_di == TREND_DOWN && directions.plus_di == TREND_UP) ||
             (pDI > mDI && directions.plus_di == TREND_UP);
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Expert tick                                                     |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastTime = 0;
   datetime currentTime = iTime(_Symbol, TF, 0);
   if(lastTime == currentTime) 
      return;
   lastTime = currentTime;

   // Vérification du drawdown maximum
   if(!CheckMaxDrawdown())
      return;

   int spread_points = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   if(showAlive)
   {
      Print(IntegerToString(MAGIC_NUMBER) + " alive" + " spread " + IntegerToString(spread_points));
      Print("Session active: ", IsInTradingSession() ? "OUI" : "NON");
      Print("Positions: ", CountSymbolPositions(), "/", MaxPositionsParSymbole, 
            " - Risque: ", DoubleToString(CalculateCurrentSymbolRisk(), 2), "%");
   }

   // Analyse des signaux
   bool buySignal = false, sellSignal = false, signalFort = false;
   if(!AnalyzeADXSignals(buySignal, sellSignal, signalFort))
      return;

   // Gestion des positions existantes
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol)
      {
         ulong positionMagic = PositionGetInteger(POSITION_MAGIC);
         if(positionMagic == MAGIC_NUMBER)
         {
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            
            if(sortie_dynamique && IsSignalWeakening(posType))
            {
               Print("Signal affaibli détecté - Fermeture de la position ", ticket);
               SamBotUtils::tradeClose(_Symbol, (ulong)MAGIC_NUMBER, ticket);
            }
         }
      }
   }

   // Ouverture de nouvelles positions
   if(CanOpenNewPosition())
   {
      if(buySignal)
      {
         Print("Signal d'achat détecté - Force: ", signalFort ? "FORTE" : "NORMALE");
         Print("Position ", CountSymbolPositions() + 1, "/", MaxPositionsParSymbole);
         
         SamBotUtils::tradeOpen(_Symbol, (ulong)MAGIC_NUMBER,
                                ORDER_TYPE_BUY,
                                stop_loss_pct,
                                take_profit_pct,
                                GestionDynamiqueLot,
                                LotFixe,
                                RisqueParTradePct,
                                UseMaxSpread,
                                MaxSpreadPoints);
      }
      else if(sellSignal)
      {
         Print("Signal de vente détecté - Force: ", signalFort ? "FORTE" : "NORMALE");
         Print("Position ", CountSymbolPositions() + 1, "/", MaxPositionsParSymbole);
         
         SamBotUtils::tradeOpen(_Symbol, (ulong)MAGIC_NUMBER,
                                ORDER_TYPE_SELL,
                                stop_loss_pct,
                                take_profit_pct,
                                GestionDynamiqueLot,
                                LotFixe,
                                RisqueParTradePct,
                                UseMaxSpread,
                                MaxSpreadPoints);
      }
   }

   // Trailing Stop pour toutes les positions
   SamBotUtils::GererTrailingStop(_Symbol, (ulong)MAGIC_NUMBER,
                                  utiliser_trailing_stop,
                                  trailing_stop_pct);

   // Prises de profit partielles pour toutes les positions
   SamBotUtils::GererPrisesProfitsPartielles(_Symbol, (ulong)MAGIC_NUMBER,
                                             utiliser_prise_profit_partielle,
                                             tranche_prise_profit_pct,
                                             nb_tp_partiel,
                                             SL_BreakEVEN_after_first_partialTp, 
                                             closeIfVolumeLow,
                                             percentToCloseTrade);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handle_ADX != INVALID_HANDLE) 
      IndicatorRelease(handle_ADX);
      
   if(detector != NULL)
   {
      delete detector;
      detector = NULL;
   }
   
   Print("EA ADX Enhanced v3.0 déinitialisé");
   
   // Affichage des statistiques finales
   Print("=== STATISTIQUES FINALES ===");
   Print("Balance initiale: ", DoubleToString(InitialBalance, 2));
   Print("Equity finale: ", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
   Print("Equity maximum atteinte: ", DoubleToString(MaxEquityReached, 2));
   
   double finalDrawdown = (MaxEquityReached - AccountInfoDouble(ACCOUNT_EQUITY)) / MaxEquityReached * 100.0;
   Print("Drawdown final depuis le pic: ", DoubleToString(finalDrawdown, 2), "%");
}