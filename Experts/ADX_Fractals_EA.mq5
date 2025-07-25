//+------------------------------------------------------------------+
//|                                     ADX_Confirmed_Signal_EA.mq5 |
//|                      Copyright 2025, MetaQuotes Software Corp. |
//|                                         https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Inputs
input group "ADX Settings"
input ENUM_TIMEFRAMES ADX_Timeframe = PERIOD_CURRENT;
input int             ADX_Period = 14;
input bool            Use_Signal_Strength = true;
input double          Signal_Strength_Min = 20.0;
input double          Signal_Strength_Max = 100.0;

input group "Signal Confirmation"
input bool            Require_ADX_Rising = true;
input int             Signal_Confirmation_Period = 3; // Number of ticks for confirmation

input group "Trading Direction"
input bool            Buy_Only = false;
input bool            Sell_Only = false;

input group "Timing"
input int             Tick_Interval_Seconds = 5;

input group "Position Management"
input double          Volume = 0.1;
input int             Max_Positions = 1;
input int             Take_Profit_Pips = 100;
input int             Stop_Loss_Pips = 50;

input group "Trailing Stop"
input bool            Enable_Trailing_Stop = true;
input int             Trailing_Stop_Distance_Pips = 30;
input bool            Auto_Adjust_TP_For_Trailing = true; // Auto_Adjust_TP_For_Trailing
input double          TP_Multiplier_For_Trailing = 3.0;   // Multiplicateur pour repousser le TP
input int             Trailing_Activation_Pips = 20;     // Pips de profit avant activation du trailing

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

// Structure to hold the state of signal confirmation
struct SignalState
{
    bool buy_signal_detected;
    bool sell_signal_detected;
    int  buy_confirmation_count;
    int  sell_confirmation_count;
};
SignalState signal_state;

// Structure pour tracker les positions avec TP ajusté
struct PositionTracker
{
    ulong ticket;
    bool tp_adjusted;
    bool trailing_active;
};
PositionTracker position_trackers[100]; // Array pour tracker les positions
int tracker_count = 0;

// Forward declarations for functions
void ResetSignalStates();
void OpenPosition(ENUM_ORDER_TYPE type);
double GetPipValue();
void ValidateTPSL(ENUM_ORDER_TYPE type, double price, double &sl, double &tp);
void CloseAllPositions();
void AddPositionTracker(ulong ticket);
void RemovePositionTracker(ulong ticket);
int GetPositionTrackerIndex(ulong ticket);
void CheckAndAdjustTPForTrailing(ulong ticket);
void CleanupPositionTrackers();

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
    if(Signal_Confirmation_Period <= 0)
    {
        Print("Erreur: Signal_Confirmation_Period doit être supérieur à 0");
        return INIT_PARAMETERS_INCORRECT;
    }
    if(TP_Multiplier_For_Trailing <= 1.0)
    {
        Print("Erreur: TP_Multiplier_For_Trailing doit être supérieur à 1.0");
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
    
    // Reset signal states at start
    ResetSignalStates();
    
    // Initialize position trackers
    tracker_count = 0;

    Print("EA ADX avec Confirmation de Signal et TP ajusté initialisé avec succès");
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

    // Check for signals only if no position is being confirmed
    if(!signal_state.buy_signal_detected && !signal_state.sell_signal_detected)
    {
       CheckSignals();
    }
    else // If a signal is being confirmed, continue the confirmation process
    {
       HandleSignalConfirmation();
    }
}

//+------------------------------------------------------------------+
//| Check for initial ADX signals                                    |
//+------------------------------------------------------------------+
void CheckSignals()
{
    if(CountPositions() >= Max_Positions)
        return;

    // Get ADX values
    int buffer_size = 5; // Need at least 2 values for rising check
    double adx_main[], plus_di[], minus_di[];
    ArraySetAsSeries(adx_main, true);
    ArraySetAsSeries(plus_di, true);
    ArraySetAsSeries(minus_di, true);

    if(CopyBuffer(adx_handle, 0, 0, buffer_size, adx_main) < buffer_size ||
       CopyBuffer(adx_handle, 1, 0, buffer_size, plus_di) < buffer_size ||
       CopyBuffer(adx_handle, 2, 0, buffer_size, minus_di) < buffer_size)
        return;

    // Check signal strength if enabled
    if(Use_Signal_Strength && (adx_main[0] < Signal_Strength_Min || adx_main[0] > Signal_Strength_Max))
    {
        return;
    }

    // Check if ADX is rising (trend strengthening)
    if(Require_ADX_Rising && (adx_main[0] <= adx_main[1]))
    {
        return;
    }

    // Apply Buy_Only and Sell_Only settings
    bool can_buy = !Sell_Only;
    bool can_sell = !Buy_Only;

    // Detect initial crossover signals
    // Buy signal: +DI crosses above -DI
    if(can_buy && plus_di[0] > minus_di[0] && plus_di[1] <= minus_di[1])
    {
        signal_state.buy_signal_detected = true;
        Print("Nouveau signal BUY détecté - Confirmation en cours...");
    }
    // Sell signal: -DI crosses above +DI
    else if(can_sell && minus_di[0] > plus_di[0] && minus_di[1] <= plus_di[1])
    {
        signal_state.sell_signal_detected = true;
        Print("Nouveau signal SELL détecté - Confirmation en cours...");
    }
}

//+------------------------------------------------------------------+
//| Handle signal confirmation process                               |
//+------------------------------------------------------------------+
void HandleSignalConfirmation()
{
    // Get fresh indicator data
    double adx_main[], plus_di[], minus_di[];
    ArraySetAsSeries(adx_main, true);
    ArraySetAsSeries(plus_di, true);
    ArraySetAsSeries(minus_di, true);
    if(CopyBuffer(adx_handle, 0, 0, 2, adx_main) < 2 ||
       CopyBuffer(adx_handle, 1, 0, 2, plus_di) < 2 ||
       CopyBuffer(adx_handle, 2, 0, 2, minus_di) < 2)
       return;

    if(signal_state.buy_signal_detected)
    {
        // Verify the signal is still valid (+DI is still above -DI and ADX conditions met)
        bool adx_ok = !Use_Signal_Strength || (adx_main[0] >= Signal_Strength_Min && adx_main[0] <= Signal_Strength_Max);
        bool adx_rising_ok = !Require_ADX_Rising || (adx_main[0] > adx_main[1]);

        if(plus_di[0] > minus_di[0] && adx_ok && adx_rising_ok)
        {
            signal_state.buy_confirmation_count++;
            Print("Confirmation BUY en cours - Tick ", signal_state.buy_confirmation_count, "/", Signal_Confirmation_Period);

            if(signal_state.buy_confirmation_count >= Signal_Confirmation_Period)
            {
                Print("Signal BUY CONFIRME - Ouverture position");
                OpenPosition(ORDER_TYPE_BUY);
                ResetSignalStates();
            }
        }
        else
        {
            Print("Signal BUY invalidé - Les conditions ne sont plus remplies.");
            ResetSignalStates();
        }
    }
    else if(signal_state.sell_signal_detected)
    {
        // Verify the signal is still valid (-DI is still above +DI and ADX conditions met)
        bool adx_ok = !Use_Signal_Strength || (adx_main[0] >= Signal_Strength_Min && adx_main[0] <= Signal_Strength_Max);
        bool adx_rising_ok = !Require_ADX_Rising || (adx_main[0] > adx_main[1]);

        if(minus_di[0] > plus_di[0] && adx_ok && adx_rising_ok)
        {
            signal_state.sell_confirmation_count++;
            Print("Confirmation SELL en cours - Tick ", signal_state.sell_confirmation_count, "/", Signal_Confirmation_Period);

            if(signal_state.sell_confirmation_count >= Signal_Confirmation_Period)
            {
                Print("Signal SELL CONFIRME - Ouverture position");
                OpenPosition(ORDER_TYPE_SELL);
                ResetSignalStates();
            }
        }
        else
        {
            Print("Signal SELL invalidé - Les conditions ne sont plus remplies.");
            ResetSignalStates();
        }
    }
}

//+------------------------------------------------------------------+
//| Reset signal confirmation states                                 |
//+------------------------------------------------------------------+
void ResetSignalStates()
{
    signal_state.buy_signal_detected = false;
    signal_state.sell_signal_detected = false;
    signal_state.buy_confirmation_count = 0;
    signal_state.sell_confirmation_count = 0;
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
            // Si le trailing stop est activé et l'ajustement automatique aussi
            if(Enable_Trailing_Stop && Auto_Adjust_TP_For_Trailing)
            {
                // Repousser le TP selon le multiplicateur
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
            // Si le trailing stop est activé et l'ajustement automatique aussi
            if(Enable_Trailing_Stop && Auto_Adjust_TP_For_Trailing)
            {
                // Repousser le TP selon le multiplicateur
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
        Print("Position ouverte: ", EnumToString(type), " à ", price, " SL:", sl, " TP:", tp);
        
        // Ajouter le tracker pour cette position
        if(Enable_Trailing_Stop && Auto_Adjust_TP_For_Trailing)
        {
            AddPositionTracker(trade.ResultOrder());
        }
    }
    else
    {
        Print("Erreur ouverture position: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
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
            // Vérifier et ajuster le TP si nécessaire avant d'activer le trailing
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
    
    // Nettoyer les trackers des positions fermées
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
    
    // Calculer le profit actuel en pips
    double profit_pips = 0;
    if(pos_type == POSITION_TYPE_BUY)
    {
        double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
        profit_pips = (current_price - open_price) / pip_value;
    }
    else // SELL
    {
        double current_price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        profit_pips = (open_price - current_price) / pip_value;
    }
    
    // Si le profit atteint le seuil d'activation du trailing et le TP n'a pas encore été ajusté
    if(profit_pips >= Trailing_Activation_Pips && !position_trackers[tracker_index].tp_adjusted)
    {
        double new_tp = 0;
        
        if(pos_type == POSITION_TYPE_BUY)
        {
            // Repousser le TP beaucoup plus loin
            new_tp = open_price + (Take_Profit_Pips * TP_Multiplier_For_Trailing * 2) * pip_value;
        }
        else // SELL
        {
            // Repousser le TP beaucoup plus loin
            new_tp = open_price - (Take_Profit_Pips * TP_Multiplier_For_Trailing * 2) * pip_value;
        }
        
        // Normaliser et valider le nouveau TP
        int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
        new_tp = NormalizeDouble(new_tp, digits);
        
        if(trade.PositionModify(ticket, current_sl, new_tp))
        {
            position_trackers[tracker_index].tp_adjusted = true;
            position_trackers[tracker_index].trailing_active = true;
            Print("TP repoussé pour position ", ticket, " - Trailing stop maintenant actif. Nouveau TP: ", new_tp);
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
        Print("Tracker ajouté pour position ", ticket);
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
            // Déplacer les éléments suivants
            for(int j = i; j < tracker_count - 1; j++)
            {
                position_trackers[j] = position_trackers[j + 1];
            }
            tracker_count--;
            Print("Tracker supprimé pour position ", ticket);
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
        
        // Vérifier si la position existe encore
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
    else // SELL
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
    
    // Vérifier si le trailing est actif pour cette position
    int tracker_index = GetPositionTrackerIndex(ticket);
    bool can_trail = true;
    
    if(Auto_Adjust_TP_For_Trailing && tracker_index >= 0)
    {
        can_trail = position_trackers[tracker_index].trailing_active;
    }
    
    if(!can_trail) return; // Ne pas trailler si pas encore activé
    
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
    else // SELL
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