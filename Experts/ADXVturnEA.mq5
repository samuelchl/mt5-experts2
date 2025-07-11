//+------------------------------------------------------------------+
//|                                     ADX_VTurn_Signal_EA.mq5     |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                         https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "2.00"

#include <Trade\Trade.mqh>

//--- Inputs
input group "ADX Settings"
input ENUM_TIMEFRAMES ADX_Timeframe = PERIOD_CURRENT;
input int             ADX_Period = 14;
input bool            Use_Signal_Strength = false; // Désactivé pour moins de restrictions
input double          Signal_Strength_Min = 15.0;  // Réduit pour plus de flexibilité
input double          Signal_Strength_Max = 100.0;

input group "V-Turn Signal Configuration"
input int             VTurn_History_Ticks = 5;       // Nombre de ticks pour détecter le point bas
input int             VTurn_Confirmation_Ticks = 2;   // Nombre de ticks pour confirmer le retournement
input double          Min_VTurn_Change = 0.5;        // Changement minimum en points pour valider le V (réduit)

input group "Trading Direction"
input bool            Buy_Only = false;
input bool            Sell_Only = false;

input group "Timing"
input int             Tick_Interval_Seconds = 1;     // Réduit pour vérifier à chaque tick

input group "Position Management"
input double          Volume = 0.1;
input int             Max_Positions = 1;
input int             Take_Profit_Pips = 100;
input int             Stop_Loss_Pips = 50;

input group "Trailing Stop"
input bool            Enable_Trailing_Stop = true;
input int             Trailing_Stop_Distance_Pips = 30;
input bool            Auto_Adjust_TP_For_Trailing = true;
input double          TP_Multiplier_For_Trailing = 3.0;
input int             Trailing_Activation_Pips = 20;

input group "Break Even"
input bool            Enable_Break_Even = true;
input int             Break_Even_Trigger_Pips = 20;
input int             input_buffer_be = 0;

input group "Profit Management"
input bool            Enable_Trading = true;
input bool            Enable_Daily_Drawdown = true;
input double          Max_Daily_Drawdown_Percent = 5.0;
input bool            Enable_Global_Profit_Target = true;
input double          Target_Global_Profit_Percent = 20.0;
input bool            Enable_Daily_Profit_Target = true;
input double          Target_Daily_Profit_Percent = 3.0;

input group "System"
input int             Magic_Number = 123456;

//--- Global variables
CTrade   trade;
datetime last_tick_time = 0;
int      adx_handle;
double   initial_balance;
double   daily_start_balance;
datetime current_day;

// Structure pour l'état du signal V-Turn
struct VTurnState
{
    bool buy_vturn_detected;          // V-Turn haussier détecté
    bool sell_vturn_detected;         // V-Turn baissier détecté
    int  buy_confirmation_count;      // Compteur de confirmation haussière
    int  sell_confirmation_count;     // Compteur de confirmation baissière
    double vturn_start_value;         // Valeur +DI/-DI au point de retournement
    bool was_falling;                 // +DI/-DI était en descente avant le retournement
    bool was_rising;                  // +DI/-DI était en montée avant le retournement
    double plus_di_history[];         // Historique des valeurs +DI pour détection
    double minus_di_history[];        // Historique des valeurs -DI pour détection
    int tick_counter;                 // Compteur de ticks pour l'historique
};
VTurnState vturn_state;

// Structure pour tracker les positions avec TP ajusté
struct PositionTracker
{
    ulong ticket;
    bool tp_adjusted;
    bool trailing_active;
};
PositionTracker position_trackers[100];
int tracker_count = 0;

// Forward declarations
void ResetVTurnStates();
void OpenPosition(ENUM_ORDER_TYPE type);
double GetPipValue();
void ValidateTPSL(ENUM_ORDER_TYPE type, double price, double &sl, double &tp);
void CloseAllPositions();
void CloseOppositePositions(ENUM_ORDER_TYPE new_signal_type);
void AddPositionTracker(ulong ticket);
void RemovePositionTracker(ulong ticket);
int GetPositionTrackerIndex(ulong ticket);
void CheckAndAdjustTPForTrailing(ulong ticket);
void CleanupPositionTrackers();
bool DetectVTurnPatternBuy(double &plus_di[], int array_size);
bool DetectVTurnPatternSell(double &minus_di[], int array_size);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(Magic_Number);

    // Validate inputs
    if(Buy_Only && Sell_Only)
    {
        Print("Erreur: Buy_Only et Sell_Only ne peuvent pas être activés simultanément");
        return INIT_PARAMETERS_INCORRECT;
    }
    if(VTurn_History_Ticks < 3)
    {
        Print("Erreur: VTurn_History_Ticks doit être au minimum 3");
        return INIT_PARAMETERS_INCORRECT;
    }
    if(VTurn_Confirmation_Ticks <= 0)
    {
        Print("Erreur: VTurn_Confirmation_Ticks doit être supérieur à 0");
        return INIT_PARAMETERS_INCORRECT;
    }

    // Initialize indicator
    adx_handle = iADX(Symbol(), ADX_Timeframe, ADX_Period);
    if(adx_handle == INVALID_HANDLE)
    {
        Print("Erreur lors de l'initialisation de l'indicateur ADX");
        return INIT_FAILED;
    }

    // Initialize profit tracking
    initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    MqlDateTime dt;
    TimeCurrent(dt);
    current_day = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00", dt.year, dt.mon, dt.day));
    daily_start_balance = initial_balance;
    
   // Initialize V-Turn state
   ResetVTurnStates();
   if(ArrayResize(vturn_state.plus_di_history, VTurn_History_Ticks) < 0 ||
      ArrayResize(vturn_state.minus_di_history, VTurn_History_Ticks) < 0)
   {
       Print("Erreur: Échec du redimensionnement des tableaux d'historique");
       return INIT_FAILED;
   }
   
   // Correction: Initialiser les tableaux correctement
   for(int i = 0; i < VTurn_History_Ticks; i++)
   {
       vturn_state.plus_di_history[i] = 0.0;
       vturn_state.minus_di_history[i] = 0.0;
   }
   vturn_state.tick_counter = 0;
    
    // Initialize position trackers
    tracker_count = 0;

    Print("EA ADX V-Turn Signal initialisé avec succès");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(adx_handle != INVALID_HANDLE)
        IndicatorRelease(adx_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(TimeCurrent() - last_tick_time < Tick_Interval_Seconds)
        return;
    last_tick_time = TimeCurrent();

    if(!Enable_Trading)
        return;

    if(!CheckProfitManagement())
        return;

    ManagePositions();

    // Vérifier les signaux V-Turn
    if(!vturn_state.buy_vturn_detected && !vturn_state.sell_vturn_detected)
    {
        CheckVTurnSignals();
    }
    else
    {
        HandleVTurnConfirmation();
    }
}

//+------------------------------------------------------------------+
//| Check for V-Turn signals                                        |
//+------------------------------------------------------------------+
void CheckVTurnSignals()
{
    if(CountPositions() >= Max_Positions)
        return;

    // Récupérer les données ADX pour le tick actuel
    double adx_main[], plus_di[], minus_di[];
    ArraySetAsSeries(adx_main, true);
    ArraySetAsSeries(plus_di, true);
    ArraySetAsSeries(minus_di, true);

    if(CopyBuffer(adx_handle, 0, 0, 1, adx_main) < 1 ||
       CopyBuffer(adx_handle, 1, 0, 1, plus_di) < 1 ||
       CopyBuffer(adx_handle, 2, 0, 1, minus_di) < 1)
    {
        Print("Erreur: Impossible de récupérer les données ADX");
        return;
    }

    // Stocker les valeurs +DI et -DI dans l'historique
    if(vturn_state.tick_counter < VTurn_History_Ticks)
    {
        if(vturn_state.tick_counter >= ArraySize(vturn_state.plus_di_history))
        {
            Print("Erreur: tick_counter dépasse la taille du tableau. tick_counter=", vturn_state.tick_counter, ", ArraySize=", ArraySize(vturn_state.plus_di_history));
            return;
        }
        vturn_state.plus_di_history[vturn_state.tick_counter] = plus_di[0];
        vturn_state.minus_di_history[vturn_state.tick_counter] = minus_di[0];
        vturn_state.tick_counter++;
    }
    else
    {
        // Décaler l'historique et ajouter la nouvelle valeur
        for(int i = 0; i < VTurn_History_Ticks - 1; i++)
        {
            vturn_state.plus_di_history[i] = vturn_state.plus_di_history[i + 1];
            vturn_state.minus_di_history[i] = vturn_state.minus_di_history[i + 1];
        }
        vturn_state.plus_di_history[VTurn_History_Ticks - 1] = plus_di[0];
        vturn_state.minus_di_history[VTurn_History_Ticks - 1] = minus_di[0];
    }

    // Vérifier la force du signal ADX si activée
    if(Use_Signal_Strength && (adx_main[0] < Signal_Strength_Min || adx_main[0] > Signal_Strength_Max))
        return;

    // Appliquer les restrictions Buy_Only et Sell_Only
    bool can_buy = !Sell_Only;
    bool can_sell = !Buy_Only;

    // Détecter le pattern V-Turn
    if(vturn_state.tick_counter >= VTurn_History_Ticks)
    {
        Print("Historique complet: +DI=", vturn_state.plus_di_history[VTurn_History_Ticks - 1], ", -DI=", vturn_state.minus_di_history[VTurn_History_Ticks - 1]);
        if(can_buy && DetectVTurnPatternBuy(vturn_state.plus_di_history, VTurn_History_Ticks))
        {
            vturn_state.buy_vturn_detected = true;
            vturn_state.vturn_start_value = plus_di[0];
            Print("Signal V-Turn BUY détecté - Confirmation en cours... (+DI: ", plus_di[0], ")");
        }
        
        if(can_sell && DetectVTurnPatternSell(vturn_state.minus_di_history, VTurn_History_Ticks))
        {
            vturn_state.sell_vturn_detected = true;
            vturn_state.vturn_start_value = minus_di[0];
            Print("Signal V-Turn SELL détecté - Confirmation en cours... (-DI: ", minus_di[0], ")");
        }
    }
}

//+------------------------------------------------------------------+
//| Detect V-Turn BUY pattern in +DI values                         |
//+------------------------------------------------------------------+
bool DetectVTurnPatternBuy(double &plus_di[], int array_size)
{
    if(array_size < 3 || ArraySize(plus_di) < array_size)
    {
        Print("Erreur: Taille du tableau +DI insuffisante. array_size=", array_size, ", ArraySize(plus_di)=", ArraySize(plus_di));
        return false;
    }
    
    // Trouver le point bas dans l'historique
    int lowest_idx = 0;
    double lowest_value = plus_di[0];
    for(int i = 1; i < array_size - 1; i++)
    {
        if(plus_di[i] < lowest_value)
        {
            lowest_value = plus_di[i];
            lowest_idx = i;
        }
    }
    
    // Vérifier si le point actuel est une remontée significative
    if(lowest_idx > 0 && lowest_idx < array_size - 1)
    {
        if(plus_di[array_size - 1] > lowest_value && 
           plus_di[array_size - 1] - lowest_value >= Min_VTurn_Change)
        {
            vturn_state.was_falling = true;
            return true;
        }
    }
    
    return false;
}
//+------------------------------------------------------------------+
//| Detect V-Turn SELL pattern in -DI values                        |
//+------------------------------------------------------------------+
bool DetectVTurnPatternSell(double &minus_di[], int array_size)
{
    if(array_size < 3 || ArraySize(minus_di) < array_size)
    {
        Print("Erreur: Taille du tableau -DI insuffisante. array_size=", array_size, ", ArraySize(minus_di)=", ArraySize(minus_di));
        return false;
    }
    
    // Trouver le point bas dans l'historique
    int lowest_idx = 0;
    double lowest_value = minus_di[0];
    for(int i = 1; i < array_size - 1; i++)
    {
        if(minus_di[i] < lowest_value)
        {
            lowest_value = minus_di[i];
            lowest_idx = i;
        }
    }
    
    // Vérifier si le point actuel est une remontée significative
    if(lowest_idx > 0 && lowest_idx < array_size - 1)
    {
        if(minus_di[array_size - 1] > lowest_value && 
           minus_di[array_size - 1] - lowest_value >= Min_VTurn_Change)
        {
            vturn_state.was_rising = true;
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Handle V-Turn confirmation process                               |
//+------------------------------------------------------------------+
void HandleVTurnConfirmation()
{
    // Récupérer les données fraîches
    double adx_main[], plus_di[], minus_di[];
    ArraySetAsSeries(adx_main, true);
    ArraySetAsSeries(plus_di, true);
    ArraySetAsSeries(minus_di, true);
    
    if(CopyBuffer(adx_handle, 0, 0, 1, adx_main) < 1 ||
       CopyBuffer(adx_handle, 1, 0, 1, plus_di) < 1 ||
       CopyBuffer(adx_handle, 2, 0, 1, minus_di) < 1)
       return;

    if(vturn_state.buy_vturn_detected)
    {
        // Vérifier que +DI continue de monter
        bool adx_ok = !Use_Signal_Strength || (adx_main[0] >= Signal_Strength_Min && adx_main[0] <= Signal_Strength_Max);
        
        if(plus_di[0] > vturn_state.vturn_start_value && adx_ok)
        {
            vturn_state.buy_confirmation_count++;
            Print("Confirmation V-Turn BUY en cours - Tick ", vturn_state.buy_confirmation_count, "/", VTurn_Confirmation_Ticks, " (+DI: ", plus_di[0], ")");

            if(vturn_state.buy_confirmation_count >= VTurn_Confirmation_Ticks)
            {
                Print("Signal V-Turn BUY CONFIRME - Ouverture position");
                CloseOppositePositions(ORDER_TYPE_BUY);
                OpenPosition(ORDER_TYPE_BUY);
                ResetVTurnStates();
            }
        }
        else
        {
            Print("Signal V-Turn BUY invalidé - +DI ne continue pas à monter (+DI: ", plus_di[0], ")");
            ResetVTurnStates();
        }
    }
    else if(vturn_state.sell_vturn_detected)
    {
        // Vérifier que -DI continue de monter
        bool adx_ok = !Use_Signal_Strength || (adx_main[0] >= Signal_Strength_Min && adx_main[0] <= Signal_Strength_Max);
        
        if(minus_di[0] > vturn_state.vturn_start_value && adx_ok)
        {
            vturn_state.sell_confirmation_count++;
            Print("Confirmation V-Turn SELL en cours - Tick ", vturn_state.sell_confirmation_count, "/", VTurn_Confirmation_Ticks, " (-DI: ", minus_di[0], ")");

            if(vturn_state.sell_confirmation_count >= VTurn_Confirmation_Ticks)
            {
                Print("Signal V-Turn SELL CONFIRME - Ouverture position");
                CloseOppositePositions(ORDER_TYPE_SELL);
                OpenPosition(ORDER_TYPE_SELL);
                ResetVTurnStates();
            }
        }
        else
        {
            Print("Signal V-Turn SELL invalidé - -DI ne continue pas à monter (-DI: ", minus_di[0], ")");
            ResetVTurnStates();
        }
    }
}

//+------------------------------------------------------------------+
//| Reset V-Turn states                                              |
//+------------------------------------------------------------------+
void ResetVTurnStates()
{
    vturn_state.buy_vturn_detected = false;
    vturn_state.sell_vturn_detected = false;
    vturn_state.buy_confirmation_count = 0;
    vturn_state.sell_confirmation_count = 0;
    vturn_state.vturn_start_value = 0;
    vturn_state.was_falling = false;
    vturn_state.was_rising = false;
    vturn_state.tick_counter = 0;
    
    // Correction: Réinitialiser les tableaux correctement
    for(int i = 0; i < ArraySize(vturn_state.plus_di_history); i++)
    {
        vturn_state.plus_di_history[i] = 0.0;
    }
    for(int i = 0; i < ArraySize(vturn_state.minus_di_history); i++)
    {
        vturn_state.minus_di_history[i] = 0.0;
    }
}

//+------------------------------------------------------------------+
//| Close opposite positions when new signal confirmed              |
//+------------------------------------------------------------------+
void CloseOppositePositions(ENUM_ORDER_TYPE new_signal_type)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && 
           PositionGetString(POSITION_SYMBOL) == Symbol() && 
           PositionGetInteger(POSITION_MAGIC) == Magic_Number)
        {
            ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            
            // Fermer les positions opposées
            if((new_signal_type == ORDER_TYPE_BUY && pos_type == POSITION_TYPE_SELL) ||
               (new_signal_type == ORDER_TYPE_SELL && pos_type == POSITION_TYPE_BUY))
            {
                if(trade.PositionClose(ticket))
                {
                    Print("Position opposée fermée: ", ticket, " (", EnumToString(pos_type), ")");
                }
                else
                {
                    Print("Erreur fermeture position opposée: ", trade.ResultRetcode());
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Open position                                                    |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE type)
{
    if(CountPositions() >= Max_Positions)
    {
       Print("Impossible d'ouvrir une nouvelle position, maximum atteint.");
       return;
    }

    double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double sl = 0, tp = 0;
    double pip_value = GetPipValue();
    
    if(type == ORDER_TYPE_BUY)
    {
        if(Stop_Loss_Pips > 0) sl = price - Stop_Loss_Pips * pip_value;
        if(Take_Profit_Pips > 0) 
        {
            if(Enable_Trailing_Stop && Auto_Adjust_TP_For_Trailing)
            {
                tp = price + (Take_Profit_Pips * TP_Multiplier_For_Trailing) * pip_value;
                Print("TP ajusté pour trailing stop: ", Take_Profit_Pips * TP_Multiplier_For_Trailing, " pips");
            }
            else
            {
                tp = price + Take_Profit_Pips * pip_value;
            }
        }
    }
    else // SELL
    {
        if(Stop_Loss_Pips > 0) sl = price + Stop_Loss_Pips * pip_value;
        if(Take_Profit_Pips > 0) 
        {
            if(Enable_Trailing_Stop && Auto_Adjust_TP_For_Trailing)
            {
                tp = price - (Take_Profit_Pips * TP_Multiplier_For_Trailing) * pip_value;
                Print("TP ajusté pour trailing stop: ", Take_Profit_Pips * TP_Multiplier_For_Trailing, " pips");
            }
            else
            {
                tp = price - Take_Profit_Pips * pip_value;
            }
        }
    }

    ValidateTPSL(type, price, sl, tp);

    if(trade.PositionOpen(Symbol(), type, Volume, price, sl, tp))
    {
        Print("Position V-Turn ouverte: ", EnumToString(type), " à ", price, " SL:", sl, " TP:", tp);
        
        if(Enable_Trailing_Stop && Auto_Adjust_TP_For_Trailing)
        {
            AddPositionTracker(trade.ResultOrder());
        }
    }
    else
    {
        Print("Erreur ouverture position V-Turn: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Manage existing positions                                        |
//+------------------------------------------------------------------+
void ManagePositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && 
           PositionGetString(POSITION_SYMBOL) == Symbol() && 
           PositionGetInteger(POSITION_MAGIC) == Magic_Number)
        {
            if(Enable_Trailing_Stop && Auto_Adjust_TP_For_Trailing)
            {
                CheckAndAdjustTPForTrailing(ticket);
            }
            
            if(Enable_Break_Even)
                HandleBreakEven(ticket);
            
            if(Enable_Trailing_Stop)
                HandleTrailingStop(ticket);
        }
    }
    
    CleanupPositionTrackers();
}

//+------------------------------------------------------------------+
//| Check and adjust TP for trailing stop activation                |
//+------------------------------------------------------------------+
void CheckAndAdjustTPForTrailing(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return;
    
    int tracker_index = GetPositionTrackerIndex(ticket);
    if(tracker_index < 0) return;
    
    double pip_value = GetPipValue();
    double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double current_tp = PositionGetDouble(POSITION_TP);
    double current_sl = PositionGetDouble(POSITION_SL);
    
    ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    
    double profit_pips = 0;
    if(pos_type == POSITION_TYPE_BUY)
    {
        double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
        profit_pips = (current_price - open_price) / pip_value;
    }
    else
    {
        double current_price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        profit_pips = (open_price - current_price) / pip_value;
    }
    
    if(profit_pips >= Trailing_Activation_Pips && !position_trackers[tracker_index].tp_adjusted)
    {
        double new_tp = 0;
        
        if(pos_type == POSITION_TYPE_BUY)
        {
            new_tp = open_price + (Take_Profit_Pips * TP_Multiplier_For_Trailing * 2) * pip_value;
        }
        else
        {
            new_tp = open_price - (Take_Profit_Pips * TP_Multiplier_For_Trailing * 2) * pip_value;
        }
        
        int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
        new_tp = NormalizeDouble(new_tp, digits);
        
        if(trade.PositionModify(ticket, current_sl, new_tp))
        {
            position_trackers[tracker_index].tp_adjusted = true;
            position_trackers[tracker_index].trailing_active = true;
            Print("TP repoussé pour position V-Turn ", ticket, " - Trailing stop actif. Nouveau TP: ", new_tp);
        }
        else
        {
            Print("Erreur lors du repoussement du TP: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
        }
    }
}

//+------------------------------------------------------------------+
//| Add position tracker                                             |
//+------------------------------------------------------------------+
void AddPositionTracker(ulong ticket)
{
    if(tracker_count < ArraySize(position_trackers))
    {
        position_trackers[tracker_count].ticket = ticket;
        position_trackers[tracker_count].tp_adjusted = false;
        position_trackers[tracker_count].trailing_active = false;
        tracker_count++;
        Print("Tracker ajouté pour position V-Turn ", ticket);
    }
}

//+------------------------------------------------------------------+
//| Remove position tracker                                          |
//+------------------------------------------------------------------+
void RemovePositionTracker(ulong ticket)
{
    for(int i = 0; i < tracker_count; i++)
    {
        if(position_trackers[i].ticket == ticket)
        {
            for(int j = i; j < tracker_count - 1; j++)
            {
                position_trackers[j] = position_trackers[j + 1];
            }
            tracker_count--;
            Print("Tracker supprimé pour position V-Turn ", ticket);
            break;
        }
    }
}

//+------------------------------------------------------------------+
//| Get position tracker index                                      |
//+------------------------------------------------------------------+
int GetPositionTrackerIndex(ulong ticket)
{
    for(int i = 0; i < tracker_count; i++)
    {
        if(position_trackers[i].ticket == ticket)
        {
            return i;
        }
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Clean up trackers for closed positions                          |
//+------------------------------------------------------------------+
void CleanupPositionTrackers()
{
    for(int i = tracker_count - 1; i >= 0; i--)
    {
        bool position_exists = false;
        
        for(int j = 0; j < PositionsTotal(); j++)
        {
            ulong ticket = PositionGetTicket(j);
            if(ticket == position_trackers[i].ticket && 
               PositionGetString(POSITION_SYMBOL) == Symbol() && 
               PositionGetInteger(POSITION_MAGIC) == Magic_Number)
            {
                position_exists = true;
                break;
            }
        }
        
        if(!position_exists)
        {
            RemovePositionTracker(position_trackers[i].ticket);
        }
    }
}

//+------------------------------------------------------------------+
//| Handle break even                                                |
//+------------------------------------------------------------------+
void HandleBreakEven(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return;

    double pip_value = GetPipValue();
    double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double current_sl = PositionGetDouble(POSITION_SL);
    double current_tp = PositionGetDouble(POSITION_TP);
    
    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
    {
        double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
        if(current_price >= open_price + Break_Even_Trigger_Pips * pip_value && (current_sl == 0 || current_sl < open_price))
        {
            if(!trade.PositionModify(ticket, open_price + input_buffer_be * pip_value, current_tp))
            {
                Print("Erreur modification break even: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
            }
        }
    }
    else
    {
        double current_price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        if(current_price <= open_price - Break_Even_Trigger_Pips * pip_value && (current_sl == 0 || current_sl > open_price))
        {
            if(!trade.PositionModify(ticket, open_price - input_buffer_be * pip_value, current_tp))
            {
                Print("Erreur modification break even: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Handle trailing stop                                             |
//+------------------------------------------------------------------+
void HandleTrailingStop(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return;

    double pip_value = GetPipValue();
    double current_sl = PositionGetDouble(POSITION_SL);
    double current_tp = PositionGetDouble(POSITION_TP);
    double new_sl = 0;
    
    int tracker_index = GetPositionTrackerIndex(ticket);
    bool can_trail = true;
    
    if(Auto_Adjust_TP_For_Trailing && tracker_index >= 0)
    {
        can_trail = position_trackers[tracker_index].trailing_active;
    }
    
    if(!can_trail) return;
    
    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
    {
        double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
        new_sl = current_price - Trailing_Stop_Distance_Pips * pip_value;
        if(new_sl > current_sl || current_sl == 0)
        {
            if(!trade.PositionModify(ticket, new_sl, current_tp))
            {
                Print("Erreur modification trailing stop: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
            }
        }
    }
    else
    {
        double current_price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        new_sl = current_price + Trailing_Stop_Distance_Pips * pip_value;
        if(new_sl < current_sl || current_sl == 0)
        {
            if(!trade.PositionModify(ticket, new_sl, current_tp))
            {
                Print("Erreur modification trailing stop: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Count positions                                                  |
//+------------------------------------------------------------------+
int CountPositions()
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && 
           PositionGetString(POSITION_SYMBOL) == Symbol() && 
           PositionGetInteger(POSITION_MAGIC) == Magic_Number)
        {
            count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Check profit management                                          |
//+------------------------------------------------------------------+
bool CheckProfitManagement()
{
    // Check if new day started
    MqlDateTime dt;
    TimeCurrent(dt);
    datetime today = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00", dt.year, dt.mon, dt.day));
    
    if(today != current_day)
    {
        current_day = today;
        daily_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        Print("Nouveau jour - Balance de départ: ", daily_start_balance);
    }
    
    double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    if(Enable_Daily_Drawdown)
    {
        double daily_drawdown_percent = (daily_start_balance - equity) / daily_start_balance * 100;
        if(daily_drawdown_percent >= Max_Daily_Drawdown_Percent)
        {
            Print("Drawdown journalier maximum atteint: ", daily_drawdown_percent, "%. Trading arrêté pour aujourd'hui.");
            CloseAllPositions();
            return false;
        }
    }
    
    if(Enable_Global_Profit_Target)
    {
        double global_profit_percent = (current_balance - initial_balance) / initial_balance * 100;
        if(global_profit_percent >= Target_Global_Profit_Percent)
        {
            Print("Objectif de profit global atteint: ", global_profit_percent, "%. Trading arrêté.");
            CloseAllPositions();
            return false;
        }
    }
    
    if(Enable_Daily_Profit_Target)
    {
        double daily_profit_percent = (current_balance - daily_start_balance) / daily_start_balance * 100;
        if(daily_profit_percent >= Target_Daily_Profit_Percent)
        {
            Print("Objectif de profit journalier atteint: ", daily_profit_percent, "%. Trading arrêté pour aujourd'hui.");
            CloseAllPositions();
            return false;
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Get pip value for current symbol                                 |
//+------------------------------------------------------------------+
double GetPipValue()
{
    double pip_value = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    
    if(digits == 5 || digits == 3)
        pip_value *= 10;
    
    return pip_value;
}

//+------------------------------------------------------------------+
//| Validate and normalize TP/SL levels                              |
//+------------------------------------------------------------------+
void ValidateTPSL(ENUM_ORDER_TYPE type, double price, double &sl, double &tp)
{
    double stop_level = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    
    if(type == ORDER_TYPE_BUY)
    {
        if(sl > 0 && price - sl < stop_level) sl = price - stop_level;
        if(tp > 0 && tp - price < stop_level) tp = price + stop_level;
    }
    else // SELL
    {
        if(sl > 0 && sl - price < stop_level) sl = price + stop_level;
        if(tp > 0 && price - tp < stop_level) tp = price - stop_level;
    }
    
    if(sl > 0) sl = NormalizeDouble(sl, digits);
    if(tp > 0) tp = NormalizeDouble(tp, digits);
}
    
//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && 
           PositionGetString(POSITION_SYMBOL) == Symbol() && 
           PositionGetInteger(POSITION_MAGIC) == Magic_Number)
        {
            trade.PositionClose(ticket);
        }
    }
}