//+------------------------------------------------------------------+
//|                                    Strategie_ADX_Enhanced.mq5    |
//|                                             Adaptation MT5       |
//+------------------------------------------------------------------+
#property copyright "Adaptation MT5"
#property version   "2.00"
#property strict

#include <SamBotUtils.mqh>

//+------------------------------------------------------------------+
//| Énumération pour les directions                                   |
//+------------------------------------------------------------------+
enum ENUM_TREND_DIRECTION
{
   TREND_UP = 1,      // Tendance haussière
   TREND_DOWN = -1,   // Tendance baissière  
   TREND_FLAT = 0     // Tendance plate/indécise
};

//+------------------------------------------------------------------+
//| Structure pour stocker les résultats de direction                |
//+------------------------------------------------------------------+
struct IndicatorDirection
{
   ENUM_TREND_DIRECTION main_line;    // Direction ligne principale (ADX)
   ENUM_TREND_DIRECTION plus_di;      // Direction +DI
   ENUM_TREND_DIRECTION minus_di;     // Direction -DI
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
//| Expert configuration                                            |
//+------------------------------------------------------------------+
// Paramètres généraux
input ENUM_TIMEFRAMES TF                    = PERIOD_CURRENT;
input int    MAGIC_NUMBER                   = 15975344;

// Paramètres Stop Loss / Take Profit (en %)
input double stop_loss_pct                  = 1.0;
input double take_profit_pct                = 2.0;
input bool   sortie_dynamique               = true; // Activé par défaut

// Paramètres gestion de lot
input bool   GestionDynamiqueLot            = false;
input double RisqueParTradePct              = 1.0;
input double LotFixe                        = 0.1;

// Paramètres ADX
input int    ADX_Period                     = 14;
input double Seuil_ADX                      = 25.0;
input double Seuil_ADX_Fort                 = 35.0; // Nouveau: seuil pour signal fort

// Paramètres de direction
input int    Periodes_Direction             = 3;  // Périodes pour calculer la direction
input double Seuil_Direction                = 0.1; // Seuil minimum pour détecter mouvement

// Paramètres de signal
input bool   Exiger_ADX_Montant             = true;  // ADX doit monter pour signal
input bool   Exiger_DI_Divergent            = true;  // +DI et -DI doivent diverger
input double Ecart_DI_Minimum               = 5.0;   // Écart minimum entre +DI et -DI

// Paramètres Trailing Stop
input bool   utiliser_trailing_stop         = false;
input double trailing_stop_pct              = 0.5;

// Paramètres Prises de profit partielles
input bool   utiliser_prise_profit_partielle= false;
input double tranche_prise_profit_pct       = 0.02;
input int    nb_tp_partiel                  = 2;

// Paramètres spread
input bool   UseMaxSpread                   = false;
input int    MaxSpreadPoints                = 40;
input bool   SL_BreakEVEN_after_first_partialTp = false;

input bool   closeIfVolumeLow               = false;
input double percentToCloseTrade            = 0.20;
input bool   showAlive                      = false;
input bool   tradeVendredi                  = false;

//--- Variables globales
int handle_ADX;
double ADXBuf[], plusDIBuf[], minusDIBuf[];
CIndicatorDirectionDetector *detector;

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
   
   Print("EA ADX Enhanced initialisé avec succès");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Fonction pour vérifier si on peut trader                       |
//+------------------------------------------------------------------+
bool CanOpenTrade()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   if(now.day_of_week == 5 && !tradeVendredi)
      return false;
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
      // Pour un signal buy: +DI doit monter et -DI descendre (ou au moins pas monter ensemble)
      // Pour un signal sell: -DI doit monter et +DI descendre (ou au moins pas monter ensemble)
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
               (directions.minus_di != TREND_UP); // -DI ne doit pas monter
               
   // Signaux de vente
   sellSignal = tendanceForte && 
                (mDI > pDI) && 
                adxMontant && 
                ecartDISuffisant && 
                diDivergent &&
                (directions.minus_di == TREND_UP || directions.minus_di == TREND_FLAT) &&
                (directions.plus_di != TREND_UP); // +DI ne doit pas monter
   
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
      // Pour une position longue, le signal s'affaiblit si:
      // - ADX descend fortement OU
      // - +DI commence à descendre et -DI à monter OU
      // - -DI dépasse +DI
      return adxFaible || 
             (adxDescendant && adx < Seuil_ADX_Fort) ||
             (directions.plus_di == TREND_DOWN && directions.minus_di == TREND_UP) ||
             (mDI > pDI && directions.minus_di == TREND_UP);
   }
   else if(positionType == POSITION_TYPE_SELL)
   {
      // Pour une position courte, le signal s'affaiblit si:
      // - ADX descend fortement OU
      // - -DI commence à descendre et +DI à monter OU
      // - +DI dépasse -DI
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

   int spread_points = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   if(showAlive)
      Print(IntegerToString(MAGIC_NUMBER) + " alive" + " spread "  + IntegerToString(spread_points));

   // Analyse des signaux
   bool buySignal = false, sellSignal = false, signalFort = false;
   if(!AnalyzeADXSignals(buySignal, sellSignal, signalFort))
      return;

   // Gestion des positions existantes
   bool hasPos = SamBotUtils::IsTradeOpen(_Symbol, (ulong)MAGIC_NUMBER);
   if(hasPos)
   {
      if(sortie_dynamique)
      {
         // Sélection de la position pour obtenir ses informations
         if(PositionSelect(_Symbol))
         {
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            
            // Vérifier si le signal s'affaiblit
            if(IsSignalWeakening(posType))
            {
               Print("Signal affaibli détecté - Fermeture de la position ", ticket);
               SamBotUtils::tradeClose(_Symbol, (ulong)MAGIC_NUMBER, ticket);
            }
         }
      }
   }
   else
   {
      // Ouverture de nouvelles positions
      if(buySignal && CanOpenTrade())
      {
         Print("Signal d'achat détecté - Force: ", signalFort ? "FORTE" : "NORMALE");
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
      else if(sellSignal && CanOpenTrade())
      {
         Print("Signal de vente détecté - Force: ", signalFort ? "FORTE" : "NORMALE");
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

   // Trailing Stop
   SamBotUtils::GererTrailingStop(_Symbol, (ulong)MAGIC_NUMBER,
                                  utiliser_trailing_stop,
                                  trailing_stop_pct);

   // Prises de profit partielles
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
   
   Print("EA ADX Enhanced déinitialisé");
}