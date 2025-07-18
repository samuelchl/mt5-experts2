//+------------------------------------------------------------------+
//|                                            MA_UTurn_Strategy.mq5 |
//|                                                                  |
//|                         Stratégie basée sur les retournements de MA   |
//+------------------------------------------------------------------+
#property copyright "MA U-Turn Strategy EA"
#property version   "1.02" // Version mise à jour avec corrections
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

// Paramètres d'entrée
input int MA_Period_Long = 38;             // Période MA longue (signal d'entrée)
input int MA_Period_Short = 8;             // Période MA courte (signal de sortie)
input ENUM_MA_METHOD MA_Method = MODE_SMA; // Méthode MA (SMA, EMA, SMMA, LWMA)
input ENUM_APPLIED_PRICE MA_Price = PRICE_CLOSE; // Prix appliqué (Close, Open, High, Low, etc.)
input ENUM_TIMEFRAMES Timeframe = PERIOD_M5; // Timeframe
input double StopLoss = 50.0;              // Stop Loss en points (0 pour désactiver)
input double TakeProfit = 100.0;           // Take Profit en points (0 pour désactiver)
input double LotSize = 0.1;                // Taille du lot
input int MagicNumber = 12345;             // Numéro magique pour identifier les ordres de cet EA
input string Comment = "MA_UTurn";         // Commentaire des ordres
input int MaxSlippage = 5;                 // Slippage maximum acceptable en points pour l'exécution des ordres

// Paramètres avancés pour la détection U-Turn
input int UTurn_LookbackPeriod = 5;        // Nombre de barres à analyser pour le U-Turn (ex: 5 -> analyse de 0 à 4)
input double UTurn_MinChangePercent = 0.01; // Changement minimum requis (en %) pour considérer un mouvement
input bool UTurn_UseSlope = true;          // Utiliser l'analyse de pente pour confirmer le U-Turn
input bool UTurn_ConfirmTrend = true;      // Confirmer la direction du trend après le U-Turn (dernière barre en progression)
input bool UTurn_StrictMonotonicity = false; // Exiger une progression strictement monotone avant et après le point de retournement

// Variables globales
int LastSignal = 0; // 1 = Buy signal, -1 = Sell signal, 0 = No signal / Position closed

// Handles des indicateurs
int handle_MA_Long;
int handle_MA_Short;

// Tableaux pour stocker les valeurs MA
double ma_long_buffer[];
double ma_short_buffer[];

// Variable pour gérer l'exécution une fois par nouvelle barre
datetime last_bar_time = 0;

//+------------------------------------------------------------------+
//| Validation des paramètres d'entrée                               |
//+------------------------------------------------------------------+
bool ValidateInputParameters()
{
    string error_msg = "";
    bool is_valid = true;
    
    // Validation des périodes MA
    if(MA_Period_Long <= MA_Period_Short)
    {
        error_msg += "ERREUR: La période MA longue (" + IntegerToString(MA_Period_Long) + 
                     ") doit être supérieure à la période MA courte (" + IntegerToString(MA_Period_Short) + ")\n";
        is_valid = false;
    }
    
    if(MA_Period_Long < 2 || MA_Period_Short < 2)
    {
        error_msg += "ERREUR: Les périodes MA doivent être >= 2\n";
        is_valid = false;
    }
    
    if(MA_Period_Long > 1000 || MA_Period_Short > 1000)
    {
        error_msg += "ATTENTION: Les périodes MA sont très grandes (>1000). Vérifiez que c'est intentionnel.\n";
    }
    
    if(StopLoss < 0 || TakeProfit < 0)
    {
        error_msg += "ERREUR: Stop Loss et Take Profit ne peuvent pas être négatifs\n";
        is_valid = false;
    }
    
    if(StopLoss > 10000 || TakeProfit > 10000)
    {
        error_msg += "ATTENTION: Stop Loss et Take Profit sont très grands (>10000 points). Vérifiez que c'est intentionnel.\n";
    }
    
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    if(LotSize < min_lot || LotSize > max_lot)
    {
        error_msg += "ERREUR: Taille de lot (" + DoubleToString(LotSize, 2) + 
                     ") doit être entre " + DoubleToString(min_lot, 2) + 
                     " et " + DoubleToString(max_lot, 2) + "\n";
        is_valid = false;
    }
    
    double lot_remainder = fmod(LotSize, lot_step);
    if(lot_remainder > DBL_EPSILON && MathAbs(lot_remainder - lot_step) > DBL_EPSILON) 
    {
        error_msg += "ERREUR: Taille de lot (" + DoubleToString(LotSize, 8) + 
                     ") doit être un multiple de " + DoubleToString(lot_step, 8) + " (reste: " + DoubleToString(lot_remainder, 8) + ")\n";
        is_valid = false;
    }
    
    if(UTurn_LookbackPeriod < 3 || UTurn_LookbackPeriod > 30) 
    {
        error_msg += "ERREUR: UTurn_LookbackPeriod doit être entre 3 et 30\n";
        is_valid = false;
    }
    
    if(UTurn_MinChangePercent < 0 || UTurn_MinChangePercent > 10.0) 
    {
        error_msg += "ERREUR: UTurn_MinChangePercent doit être entre 0 et 10.0%\n";
        is_valid = false;
    }
    
    if(MagicNumber <= 0) 
    {
        error_msg += "ERREUR: Le Magic Number doit être un entier positif (>0)\n";
        is_valid = false;
    }
    
    if(Timeframe != PERIOD_M1 && Timeframe != PERIOD_M5 && Timeframe != PERIOD_M15 && 
       Timeframe != PERIOD_M30 && Timeframe != PERIOD_H1 && Timeframe != PERIOD_H4 && 
       Timeframe != PERIOD_D1 && Timeframe != PERIOD_W1 && Timeframe != PERIOD_MN1)
    {
        error_msg += "ERREUR: Timeframe non supportée ou invalide. Veuillez choisir une timeframe standard.\n";
        is_valid = false;
    }
    
    if (MaxSlippage < 0)
    {
        error_msg += "ERREUR: Le slippage maximum ne peut pas être négatif.\n";
        is_valid = false;
    }
    
    if(!is_valid)
    {
        Print("=== PARAMÈTRES INCORRECTS ===");
        Print(error_msg);
        Print("=============================");
        Print("--- LIMITES DU SYMBOLE ---");
        Print("Lot minimum: ", DoubleToString(min_lot, 2));
        Print("Lot maximum: ", DoubleToString(max_lot, 2));
        Print("Pas de lot: ", DoubleToString(lot_step, 2));
        Print("-------------------------");
    }
    
    return is_valid;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("=== INITIALISATION MA U-Turn Strategy EA ===");
    
    if(!ValidateInputParameters())
    {
        Print("ÉCHEC: Paramètres d'entrée incorrects. EA désactivé.");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    Print("Paramètres validés avec succès:");
    Print("MA Longue: ", MA_Period_Long, " | MA Courte: ", MA_Period_Short);
    Print("Méthode MA: ", EnumToString(MA_Method));
    Print("Prix appliqué: ", EnumToString(MA_Price));
    Print("Timeframe: ", EnumToString(Timeframe));
    Print("Stop Loss: ", StopLoss, " points");
    Print("Take Profit: ", TakeProfit, " points");
    Print("Taille de lot: ", LotSize);
    Print("Magic Number: ", MagicNumber);
    Print("Max Slippage: ", MaxSlippage, " points");
    Print("U-Turn Lookback: ", UTurn_LookbackPeriod);
    Print("U-Turn Min Change: ", UTurn_MinChangePercent, "%");
    Print("U-Turn Use Slope: ", UTurn_UseSlope);
    Print("U-Turn Confirm Trend: ", UTurn_ConfirmTrend);
    Print("U-Turn Strict Monotonicity: ", UTurn_StrictMonotonicity);

    handle_MA_Long = iMA(_Symbol, Timeframe, MA_Period_Long, 0, MA_Method, MA_Price);
    handle_MA_Short = iMA(_Symbol, Timeframe, MA_Period_Short, 0, MA_Method, MA_Price);
    
    if(handle_MA_Long == INVALID_HANDLE || handle_MA_Short == INVALID_HANDLE)
    {
        Print("ERREUR: Impossible de créer les handles d'indicateurs");
        Print("Handle MA Long: ", handle_MA_Long);
        Print("Handle MA Short: ", handle_MA_Short);
        return(INIT_FAILED);
    }
    
    ArraySetAsSeries(ma_long_buffer, true);
    ArraySetAsSeries(ma_short_buffer, true);
    
    Print("EA initialisé avec succès!");
    Print("==========================================");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("EA désactivé. Raison: ", reason);
    
    if(handle_MA_Long != INVALID_HANDLE)
        IndicatorRelease(handle_MA_Long);
    if(handle_MA_Short != INVALID_HANDLE)
        IndicatorRelease(handle_MA_Short);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    datetime current_bar_time = iTime(_Symbol, Timeframe, 0);
    if (current_bar_time == 0 || current_bar_time == last_bar_time)
    {
        return; 
    }
    last_bar_time = current_bar_time; 

    if(!UpdateMAValues())
        return;
    
    CheckEntrySignals();
    CheckExitSignals();
}

//+------------------------------------------------------------------+
//| Mise à jour des valeurs de moyennes mobiles                      |
//+------------------------------------------------------------------+
bool UpdateMAValues()
{
    int bars = iBars(_Symbol, Timeframe);
    int required_bars = MathMax(MA_Period_Long, MA_Period_Short) + UTurn_LookbackPeriod + 2; 
    
    if(bars < required_bars)
    {
        return false; 
    }
    
    int buffer_size = UTurn_LookbackPeriod + 1; 

    if(CopyBuffer(handle_MA_Long, 0, 0, buffer_size, ma_long_buffer) < buffer_size)
    {
        Print("Erreur lors de la copie des données MA longue. Code d'erreur: ", GetLastError());
        return false;
    }
    
    if(CopyBuffer(handle_MA_Short, 0, 0, buffer_size, ma_short_buffer) < buffer_size)
    {
        Print("Erreur lors de la copie des données MA courte. Code d'erreur: ", GetLastError());
        return false;
    }
    
    for(int i = 0; i < buffer_size; i++)
    {
        if(ma_long_buffer[i] <= 0.0 || ma_short_buffer[i] <= 0.0) 
        {
            Print("Valeurs MA invalides détectées (<= 0) à l'index ", i, ". MA_Long[", i, "]=", ma_long_buffer[i], ", MA_Short[", i, "]=", ma_short_buffer[i]);
            return false;
        }
        // Removed CheckPointer calls as per analysis. CopyBuffer success and value checks are primary.
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Calcul de la pente d'une série de valeurs                        |
//+------------------------------------------------------------------+
double CalculateSlope(const double &values[], int start_index, int period)
{
    if(period < 2 || start_index + period > ArraySize(values)) return 0.0;
    
    double sum_x = 0, sum_y = 0, sum_xy = 0, sum_x2 = 0;
    
    for(int i = 0; i < period; i++)
    {
        double x = i;
        double y = values[start_index + i]; // Corrected: values is already a series, start_index is the most recent if ArraySetAsSeries
        
        sum_x += x;
        sum_y += y;
        sum_xy += x * y;
        sum_x2 += x * x;
    }
    
    double denominator = period * sum_x2 - sum_x * sum_x;
    if(MathAbs(denominator) < DBL_EPSILON) return 0.0; 
    
    return (period * sum_xy - sum_x * sum_y) / denominator;
}

//+------------------------------------------------------------------+
//| Détection avancée du pattern U vers le haut                      |
//+------------------------------------------------------------------+
bool IsUTurnUp_Advanced(const double &buffer[])
{
    int lookback = UTurn_LookbackPeriod;
    if(ArraySize(buffer) < lookback + 1) 
    {
        Print("DEBUG U-Turn Up: Taille de buffer insuffisante (", ArraySize(buffer), ", besoin ", lookback + 1, ")");
        return false;
    }
    
    double lowest_value = buffer[0];
    int lowest_index = 0;
    
    for(int i = 0; i <= lookback; i++) 
    {
        if(buffer[i] < lowest_value)
        {
            lowest_value = buffer[i];
            lowest_index = i;
        }
    }
    
    if(lowest_index == 0 || lowest_index == lookback) 
    {
        return false; 
    }
    
    bool left_declining = true;
    bool right_ascending = true;
    
    if (UTurn_StrictMonotonicity)
    {
        for(int i = lowest_index + 1; i <= lookback; i++)
        {
            if(buffer[i] <= buffer[i-1]) 
            {
                left_declining = false;
                break;
            }
        }
        if(!left_declining) return false; // Early exit

        for(int i = lowest_index - 1; i >= 0; i--)
        {
            if(buffer[i] <= buffer[i+1]) 
            {
                right_ascending = false;
                break;
            }
        }
         if(!right_ascending) return false; // Early exit
    }
    else 
    {
        if (buffer[lookback] <= buffer[lowest_index]) left_declining = false;
        if (buffer[0] <= buffer[lowest_index]) right_ascending = false;
    }

    if(!left_declining || !right_ascending) 
    {
        return false;
    }
    
    if(UTurn_MinChangePercent > 0)
    {
        double change_left = MathAbs(buffer[lookback] - lowest_value);
        double change_right = MathAbs(buffer[0] - lowest_value);
        
        double base_value_for_percent = MathAbs(lowest_value); // Use lowest_value as base for percentage calculation
        if (base_value_for_percent < DBL_EPSILON) base_value_for_percent = 1.0; // Avoid division by zero if lowest_value is near zero

        if((change_left / base_value_for_percent * 100.0) < UTurn_MinChangePercent || 
           (change_right / base_value_for_percent * 100.0) < UTurn_MinChangePercent)
        {
            return false;
        }
    }
    
    if(UTurn_UseSlope)
    {
        // Slope calculation needs careful indexing due to ArraySetAsSeries
        // For left slope (descending to lowest_index): data from buffer[lookback] (oldest) to buffer[lowest_index] (pivot)
        // For CalculateSlope, indices are 0 to period-1. We pass buffer and the starting index in *that buffer's view*.
        // Since buffer is already reversed, buffer[lowest_index] is the pivot.
        // The data for left slope is from index 'lowest_index' up to 'lookback' in the buffer.
        double slope_left = CalculateSlope(buffer, lowest_index, lookback - lowest_index + 1); 
        
        // For right slope (ascending from lowest_index): data from buffer[lowest_index] (pivot) to buffer[0] (current)
        // The data for right slope is from index '0' up to 'lowest_index' in the buffer.
        double slope_right = CalculateSlope(buffer, 0, lowest_index + 1); 
        
        // For U-Turn Up: left slope should be negative (prices were falling), right slope positive (prices rising)
        // Adjust tolerance carefully, _Point might be too small for MA values
        if(slope_left >= 0.0 || slope_right <= 0.0) // Simplified: left must be < 0, right must be > 0
        {
            // Print("DEBUG U-Turn Up: Pente incorrecte (Gauche: ", slope_left, ", Droite: ", slope_right, ")");
            return false;
        }
    }
    
    if(UTurn_ConfirmTrend)
    {
        if(buffer[0] <= lowest_value) 
        {
            return false;
        }
        if(buffer[0] <= buffer[1]) // Current bar's MA must be greater than previous bar's MA for confirmation
        {
            // Print("DEBUG U-Turn Up: Barre actuelle MA non ascendante par rapport à la précédente MA");
            return false;
        }
    }
    
    Print("SIGNAL BUY U-TURN UP DETECTÉ ! MA_Long[0]=", buffer[0], ", Lowest Value=", lowest_value, ", Lowest Index=", lowest_index);
    return true;
}

//+------------------------------------------------------------------+
//| Détection avancée du pattern U vers le bas                       |
//+------------------------------------------------------------------+
bool IsUTurnDown_Advanced(const double &buffer[])
{
    int lookback = UTurn_LookbackPeriod;
    if(ArraySize(buffer) < lookback + 1) 
    {
        Print("DEBUG U-Turn Down: Taille de buffer insuffisante (", ArraySize(buffer), ", besoin ", lookback + 1, ")");
        return false;
    }
    
    double highest_value = buffer[0];
    int highest_index = 0;
    
    for(int i = 0; i <= lookback; i++) 
    {
        if(buffer[i] > highest_value)
        {
            highest_value = buffer[i];
            highest_index = i;
        }
    }
    
    if(highest_index == 0 || highest_index == lookback) 
    {
        return false; 
    }
    
    bool left_ascending = true;
    bool right_declining = true;
    
    if (UTurn_StrictMonotonicity)
    {
        // Check STRICT ascent to the left of the peak (older bars)
        for(int i = highest_index + 1; i <= lookback; i++) 
        {
            if(buffer[i] >= buffer[i-1]) // Should be buffer[i] < buffer[i-1] for strict ascent towards peak from older data
            {
                left_ascending = false;
                break;
            }
        }
         if(!left_ascending) return false;

        // Check STRICT descent to the right of the peak (newer bars)
        for(int i = highest_index - 1; i >= 0; i--) 
        {
            if(buffer[i] >= buffer[i+1]) // Should be buffer[i] < buffer[i+1] for strict descent from peak
            {
                right_declining = false;
                break;
            }
        }
        if(!right_declining) return false;
    }
    else 
    {
        if (buffer[lookback] >= buffer[highest_index]) left_ascending = false;
        if (buffer[0] >= buffer[highest_index]) right_declining = false;
    }
    
    if(!left_ascending || !right_declining) 
    {
        return false;
    }
    
    if(UTurn_MinChangePercent > 0)
    {
        double change_left = MathAbs(buffer[lookback] - highest_value);
        double change_right = MathAbs(buffer[0] - highest_value);
        
        double base_value_for_percent = MathAbs(highest_value);
        if (base_value_for_percent < DBL_EPSILON) base_value_for_percent = 1.0; 

        if((change_left / base_value_for_percent * 100.0) < UTurn_MinChangePercent || 
           (change_right / base_value_for_percent * 100.0) < UTurn_MinChangePercent)
        {
            return false;
        }
    }
    
    if(UTurn_UseSlope)
    {
        double slope_left = CalculateSlope(buffer, highest_index, lookback - highest_index + 1);
        double slope_right = CalculateSlope(buffer, 0, highest_index + 1);
        
        // For U-Turn Down: left slope should be positive (prices were rising), right slope negative (prices falling)
        if(slope_left <= 0.0 || slope_right >= 0.0) // Simplified: left must be > 0, right must be < 0
        {
            // Print("DEBUG U-Turn Down: Pente incorrecte (Gauche: ", slope_left, ", Droite: ", slope_right, ")");
            return false;
        }
    }
    
    if(UTurn_ConfirmTrend)
    {
        if(buffer[0] >= highest_value) 
        {
            return false;
        }
        if(buffer[0] >= buffer[1]) // Current bar's MA must be less than previous bar's MA
        {
            // Print("DEBUG U-Turn Down: Barre actuelle MA non descendante par rapport à la précédente MA");
            return false;
        }
    }
    
    Print("SIGNAL SELL U-TURN DOWN DETECTÉ ! MA_Long[0]=", buffer[0], ", Highest Value=", highest_value, ", Highest Index=", highest_index);
    return true;
}

//+------------------------------------------------------------------+
//| Vérification des signaux d'entrée                                |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
    if(HasOpenPositions()) 
        return;
    
    if(IsUTurnUp_Advanced(ma_long_buffer)) 
    {
        if(LastSignal != 1) 
        {
            OpenBuyOrder();
            LastSignal = 1;
        }
    }
    else if(IsUTurnDown_Advanced(ma_long_buffer)) 
    {
        if(LastSignal != -1) 
        {
            OpenSellOrder();
            LastSignal = -1;
        }
    }
}

//+------------------------------------------------------------------+
//| Vérification des signaux de sortie                               |
//+------------------------------------------------------------------+
void CheckExitSignals()
{
    if(!HasOpenPositions()) 
    {
        LastSignal = 0; 
        return;
    }
    
    ENUM_POSITION_TYPE posType = GetPositionType();

    if(posType == POSITION_TYPE_BUY && IsUTurnDown_Advanced(ma_short_buffer)) 
    {
        Print("SIGNAL DE FERMETURE BUY DETECTÉ (MA courte U-Turn Down)!");
        CloseAllPositions(); 
        LastSignal = 0;
    }
    else if(posType == POSITION_TYPE_SELL && IsUTurnUp_Advanced(ma_short_buffer)) 
    {
        Print("SIGNAL DE FERMETURE SELL DETECTÉ (MA courte U-Turn Up)!");
        CloseAllPositions(); 
        LastSignal = 0;
    }
}

//+------------------------------------------------------------------+
//| Validation des niveaux Stop Loss et Take Profit                  |
//+------------------------------------------------------------------+
bool ValidateSLTP(double price, double sl, double tp, bool is_buy)
{
    double min_stop_level_points =(double) SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    // SYMBOL_TRADE_STOPS_LEVEL is in points. _Point is the size of one point.
    // So min_stop_level should be min_stop_level_points * _Point if comparing price differences.
    // Or, compare SL/TP distance in points directly with min_stop_level_points.

    if (min_stop_level_points == 0) return true; // No minimum stop level

    if (sl != 0) // If SL is set
    {
        double distance_sl_points = MathAbs(price - sl) / _Point;
        if (distance_sl_points < min_stop_level_points)
        {
            Print("ATTENTION: Stop Loss trop proche du prix (prix: ", NormalizeDouble(price,_Digits), 
                  ", SL: ", NormalizeDouble(sl,_Digits), 
                  ", distance: ", NormalizeDouble(distance_sl_points,1), " points",
                  ", minimum requis: ", min_stop_level_points, " points)");
            return false;
        }
    }

    if (tp != 0) // If TP is set
    {
        double distance_tp_points = MathAbs(price - tp) / _Point;
        if (distance_tp_points < min_stop_level_points)
        {
            Print("ATTENTION: Take Profit trop proche du prix (prix: ", NormalizeDouble(price,_Digits),
                  ", TP: ", NormalizeDouble(tp,_Digits),
                  ", distance: ", NormalizeDouble(distance_tp_points,1), " points",
                  ", minimum requis: ", min_stop_level_points, " points)");
            return false;
        }
    }
    return true;
}

//+------------------------------------------------------------------+
//| Ouverture d'un ordre d'achat                                     |
//+------------------------------------------------------------------+
void OpenBuyOrder()
{
    MqlTick latest_price;
    if(!SymbolInfoTick(_Symbol, latest_price))
    {
        Print("Erreur lors de l'obtention du prix actuel: ", GetLastError());
        return;
    }
    
    double ask = latest_price.ask;
    double sl_price = (StopLoss > 0) ? NormalizeDouble(ask - StopLoss * _Point, _Digits) : 0.0;
    double tp_price = (TakeProfit > 0) ? NormalizeDouble(ask + TakeProfit * _Point, _Digits) : 0.0;
    
    if(!ValidateSLTP(ask, sl_price, tp_price, true))
    {
        Print("ERREUR: Niveaux SL/TP invalides pour l'ordre BUY, annulation de l'ordre.");
        return;
    }
    
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(MaxSlippage);
    trade.SetTypeFillingBySymbol(_Symbol); 

    if(trade.Buy(LotSize, _Symbol, ask, sl_price, tp_price, Comment)) 
    {
        Print("Ordre BUY ouvert. Ticket: ", trade.ResultOrder(), " | Prix: ", NormalizeDouble(ask, _Digits));
        if(sl_price > 0) Print("Stop Loss: ", NormalizeDouble(sl_price, _Digits));
        if(tp_price > 0) Print("Take Profit: ", NormalizeDouble(tp_price, _Digits));
    }
    else
    {
        Print("Erreur ouverture BUY: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Ouverture d'un ordre de vente                                    |
//+------------------------------------------------------------------+
void OpenSellOrder()
{
    MqlTick latest_price;
    if(!SymbolInfoTick(_Symbol, latest_price))
    {
        Print("Erreur lors de l'obtention du prix actuel: ", GetLastError());
        return;
    }
    
    double bid = latest_price.bid;
    double sl_price = (StopLoss > 0) ? NormalizeDouble(bid + StopLoss * _Point, _Digits) : 0.0;
    double tp_price = (TakeProfit > 0) ? NormalizeDouble(bid - TakeProfit * _Point, _Digits) : 0.0;
    
    if(!ValidateSLTP(bid, sl_price, tp_price, false))
    {
        Print("ERREUR: Niveaux SL/TP invalides pour l'ordre SELL, annulation de l'ordre.");
        return;
    }
    
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(MaxSlippage);
    trade.SetTypeFillingBySymbol(_Symbol);

    if(trade.Sell(LotSize, _Symbol, bid, sl_price, tp_price, Comment)) 
    {
        Print("Ordre SELL ouvert. Ticket: ", trade.ResultOrder(), " | Prix: ", NormalizeDouble(bid, _Digits));
        if(sl_price > 0) Print("Stop Loss: ", NormalizeDouble(sl_price, _Digits));
        if(tp_price > 0) Print("Take Profit: ", NormalizeDouble(tp_price, _Digits));
    }
    else
    {
        Print("Erreur ouverture SELL: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Vérification de l'existence de positions ouvertes par cet EA     |
//+------------------------------------------------------------------+
bool HasOpenPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        // PositionGetSymbol(i) directly gets symbol by index
        if(PositionGetSymbol(i) == _Symbol) 
        {
            ulong ticket = PositionGetTicket(i); // Get ticket for this index
            if(PositionSelectByTicket(ticket)) // Select the position by its ticket
            {
                // Now query properties of the selected position
                if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
                {
                    return true; // Found a position matching symbol and magic number
                }
            }
        }
    }
    return false; // No matching position found
}

//+------------------------------------------------------------------+
//| Obtention du type de la position ouverte par cet EA              |
//+------------------------------------------------------------------+
ENUM_POSITION_TYPE GetPositionType()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetSymbol(i) == _Symbol)
        {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket))
            {
                if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
                {
                    return (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                }
            }
        }
    }
    return WRONG_VALUE; // Indicates no relevant position found or an issue
}

//+------------------------------------------------------------------+
//| Fermeture de toutes les positions ouvertes par cet EA            |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    trade.SetExpertMagicNumber(MagicNumber); 
    trade.SetDeviationInPoints(MaxSlippage);
    trade.SetTypeFillingBySymbol(_Symbol);

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i); // Get ticket by index

        // It's good practice to select and verify properties before attempting to close,
        // even if CTrade might do some checks. This ensures we only try to close *our* EA's positions.
        if(PositionGetSymbol(i) == _Symbol) // Fast check by index
        {
            if(PositionSelectByTicket(ticket)) // Select to check magic number
            {
                if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
                {
                    if(trade.PositionClose(ticket, MaxSlippage)) 
                    {
                        Print("Position ", ticket, " fermée avec succès.");
                    }
                    else
                    {
                        Print("Erreur lors de la fermeture de la position ", ticket, ": ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
                    }
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
//| FIN DU FICHIER                                                   |
//+------------------------------------------------------------------+
