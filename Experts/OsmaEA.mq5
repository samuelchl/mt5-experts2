//+------------------------------------------------------------------+
//|                                                     MAO_EA_OsMA.mq5 |
//|                                  EA basé sur l'indicateur OsMA |
//+------------------------------------------------------------------+
#property copyright   "Votre Nom"
#property version     "1.1"
#property strict

// --- Paramètres de l'indicateur OsMA ---
input int      fast_ema_period  = 12;
input int      slow_ema_period  = 26;
input int      signal_sma_period = 9;
input ENUM_APPLIED_PRICE applied_price = PRICE_CLOSE;
input ENUM_TIMEFRAMES time_frame    = PERIOD_CURRENT;

// --- Paramètres de trading (pour SamBotUtils) ---
input ulong    magic_number     = 12345;     // Magic number pour identifier les ordres de l'EA
input double   stop_loss_pct    = 0.5;       // Stop loss en pourcentage (à définir selon votre Utils)
input double   take_profit_pct  = 1.0;       // Take profit en pourcentage (à définir selon votre Utils)
input bool     dynamic_lot      = false;     // Utiliser la gestion dynamique des lots de SamBotUtils
input double   fixed_lot        = 0.1;       // Taille de lot fixe (si dynamic_lot est false)
input double   risk_per_trade   = 1.0;       // Risque par trade en pourcentage du capital (si dynamic_lot est true)
input bool     use_max_spread   = false;     // Utiliser un spread maximal autorisé par SamBotUtils
input int      max_spread_points = 20;       // Spread maximal autorisé en points

// --- Inclusion de la librairie SamBotUtils ---
#include <SamBotUtils.mqh>

// --- Variables globales ---
bool     position_open = false; // Variable pour suivre si une position est ouverte (peut être gérée par SamBotUtils)

//+------------------------------------------------------------------+
//| Fonction pour obtenir la valeur du buffer d'un indicateur        |
//+------------------------------------------------------------------+
double GetIndicatorBuffer(int handle, int buffer_index, int shift)
{
    double val[];
    if(CopyBuffer(handle, buffer_index, shift, 1, val) <= 0)
    {
        Print("Erreur lors de la récupération du buffer de l'indicateur (", GetLastError(), ")");
        return EMPTY_VALUE;
    }
    return val[0];
}

//+------------------------------------------------------------------+
//| Fonction d'initialisation de l'EA                                |
//+------------------------------------------------------------------+
int OnInit()
{
    // Obtenir le handle de l'indicateur OsMA.
    int indicator_handle = iOsMA(_Symbol, time_frame, fast_ema_period, slow_ema_period, signal_sma_period, applied_price);
    if(indicator_handle == INVALID_HANDLE)
    {
        Print("Erreur lors de la création du handle de l'indicateur OsMA : ", GetLastError());
        return INIT_FAILED;
    }
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Fonction de désinitialisation de l'EA                             |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // L'handle de l'indicateur iOsMA est géré par MetaTrader.
}

//+------------------------------------------------------------------+
//| Fonction de gestion des ticks de prix                            |
//| Conçue pour fonctionner en mode "Open Only" en backtest         |
//+------------------------------------------------------------------+
void OnTick()
{
    static datetime last_time = 0;
    MqlRates rates[];
    if(CopyRates(_Symbol, time_frame, 1, 2, rates) < 2) return;

    datetime current_candle_time = rates[1].time;
    if(current_candle_time == last_time) return;
    last_time = current_candle_time;

    double osma_current = GetIndicatorBuffer(iOsMA(_Symbol, time_frame, fast_ema_period, slow_ema_period, signal_sma_period, applied_price), 0, 1);
    double osma_previous = GetIndicatorBuffer(iOsMA(_Symbol, time_frame, fast_ema_period, slow_ema_period, signal_sma_period, applied_price), 0, 2);

    if(osma_current == EMPTY_VALUE || osma_previous == EMPTY_VALUE)
    {
        Print("Erreur lors de la récupération des valeurs de l'OsMA.");
        return;
    }

    if(PositionSelect(_Symbol))
    {
        ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        ulong ticket = PositionGetInteger(POSITION_TICKET);

        if(position_type == POSITION_TYPE_BUY && osma_previous >= 0 && osma_current < 0)
        {
            SamBotUtils::tradeClose(_Symbol, magic_number, ticket);
        }
        else if(position_type == POSITION_TYPE_SELL && osma_previous <= 0 && osma_current > 0)
        {
            SamBotUtils::tradeClose(_Symbol, magic_number, ticket);
        }
    }
    else
    {
        ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY_LIMIT;
        bool signal_found = false;

        if(osma_previous <= 0 && osma_current > 0)
        {
            orderType = ORDER_TYPE_BUY;
            signal_found = true;
        }
        else if(osma_previous >= 0 && osma_current < 0)
        {
            orderType = ORDER_TYPE_SELL;
            signal_found = true;
        }

        if (signal_found && ( orderType== ORDER_TYPE_BUY || orderType== ORDER_TYPE_SELL))
        {
            SamBotUtils::tradeOpen(_Symbol, magic_number, orderType, stop_loss_pct, take_profit_pct, dynamic_lot, fixed_lot, risk_per_trade, use_max_spread, max_spread_points);
        }
    }
}
//+------------------------------------------------------------------+