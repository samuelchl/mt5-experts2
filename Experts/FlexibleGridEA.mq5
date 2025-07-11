//+------------------------------------------------------------------+
//|                                                FlexibleGridEA.mq5 |
//|                                        Copyright 2025, Gemini |
//| Un EA flexible qui utilise OscillatingGridManager avec des       |
//| filtres activables/désactivables.                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Gemini"
#property version   "1.00"

#include <OscillatingGridManager2.mqh>

// --- Paramètres de la Grille ---
input group  "Paramètres de la Grille";
input ulong  InpMagicNumber = 12345;
input double InpLotSize = 0.01;
input int    InpGridStepPoints = 100;
input int    InpMaxOpenTrades = 5;

// --- Paramètres du Filtre de Tendance ---
input group  "Filtre de Tendance (MA)";
input bool   InpUseTrendFilter = true;        // Activer le filtre de tendance
input int    InpMaPeriod = 200;               // Période de la Moyenne Mobile

// --- Paramètres du Filtre de Volatilité ---
input group  "Filtre de Volatilité (ATR)";
input bool   InpUseVolatilityFilter = false;  // Activer le filtre de volatilité
input int    InpAtrPeriod = 14;               // Période de l'ATR
input double InpMinAtrPips = 5.0;             // Volatilité minimale en pips pour trader
input double InpMaxAtrPips = 50.0;            // Volatilité maximale en pips

// --- Paramètres du Filtre Temporel (par Sessions) ---
input group  "Filtre Temporel par Sessions";
input bool   InpUseSessionFilter = true;      // Activer le filtre par session

// Les heures ci-dessous sont basées sur l'heure du serveur de trading.
// Elles sont ajustées pour correspondre aux heures de Paris/Berlin,
// en supposant que votre serveur est calé sur l'heure d'Europe Centrale.
input bool   InpTradeAsiaSession = true;       // Trader pendant la session asiatique (ex: 02h-11h Paris)
input bool   InpTradeLondonSession = true;     // Trader pendant la session de Londres (ex: 09h-18h Paris)
input bool   InpTradeNewYorkSession = true;    // Trader pendant la session de New York (ex: 14h-23h Paris)
input group  "trailing";
input bool UseTrailingStop      = true;    // Trailing stop activé
input int TrailingDistance   = 50.0;    // Distance trailing (pips)
input int TrailingStep       = 10.0;    // Pas trailing (pips)

OscillatingGridManager *grid;

//+------------------------------------------------------------------+
int OnInit()
{
    // Crée une instance de notre gestionnaire en lui passant les paramètres pertinents
    grid = new OscillatingGridManager(InpMagicNumber, InpLotSize, InpGridStepPoints, InpMaxOpenTrades, InpUseTrendFilter, InpMaPeriod,UseTrailingStop,TrailingDistance,TrailingStep);
    
    grid.Start();
    
    return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE)
    {
        grid.Stop();
    }
    delete grid;
}
//+------------------------------------------------------------------+
void OnTick()
{
    bool trading_is_allowed = true; // On part du principe que le trading est autorisé

    // --- PORTE 1 : FILTRE TEMPOREL PAR SESSIONS ---
    if(InpUseSessionFilter)
    {
        MqlDateTime current_time;
        TimeCurrent(current_time);
        int current_hour = current_time.hour;
        
        bool in_asia_session = (current_hour >= 2 && current_hour < 11);     // Ex: 02:00 - 10:59
        bool in_london_session = (current_hour >= 9 && current_hour < 18);   // Ex: 09:00 - 17:59
        bool in_newyork_session = (current_hour >= 14 && current_hour < 23); // Ex: 14:00 - 22:59
        
        // Par défaut, si aucun filtre de session n'est activé, on autorise le trading.
        // Si au moins un filtre est activé, on vérifie si l'heure courante correspond à l'une des sessions activées.
        bool session_allowed = false;
        
        if (InpTradeAsiaSession && in_asia_session)
        {
            session_allowed = true;
        }
        
        if (InpTradeLondonSession && in_london_session)
        {
            session_allowed = true;
        }
        
        if (InpTradeNewYorkSession && in_newyork_session)
        {
            session_allowed = true;
        }
        
        // Si aucune session n'est activée mais que le filtre est actif, on bloque tout.
        // Ou si une session est activée mais que l'heure actuelle n'en fait pas partie, on bloque.
        if (!session_allowed && (InpTradeAsiaSession || InpTradeLondonSession || InpTradeNewYorkSession))
        {
            trading_is_allowed = false;
        }
    }

    // --- PORTE 2 : FILTRE DE VOLATILITÉ ---
    // On ne vérifie ce filtre que si le trading est toujours autorisé
    if(trading_is_allowed && InpUseVolatilityFilter)
    {
        double point_to_pip = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) * 10;
        double current_atr_in_points = iATR(_Symbol, _Period, InpAtrPeriod);
        double min_atr_in_points = InpMinAtrPips * point_to_pip;
        double max_atr_in_points = InpMaxAtrPips * point_to_pip;
        
        if(current_atr_in_points < min_atr_in_points || current_atr_in_points > max_atr_in_points)
        {
            trading_is_allowed = false; // Volatilité hors des clous, on bloque
        }
    }

    // --- DÉCISION FINALE ---
    if(trading_is_allowed)
    {
        // Tous les filtres activés ont donné leur feu vert. On laisse la grille travailler.
        grid.Update();
    }
    else
    {
        // Au moins un filtre a bloqué le trading. On s'assure qu'aucun ordre n'est en attente.
        grid.CancelPendingOrders();
    }
}
//+------------------------------------------------------------------+