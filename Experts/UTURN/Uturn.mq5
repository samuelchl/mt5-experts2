//+------------------------------------------------------------------+
//|                                            MA_UTurn_Strategy.mq5 |
//|                                                                  |
//|                    Stratégie basée sur les retournements de MA   |
//+------------------------------------------------------------------+
#property copyright "MA U-Turn Strategy EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

// Paramètres d'entrée
input int MA_Period_Long = 38;              // Période MA longue (signal d'entrée)
input int MA_Period_Short = 8;              // Période MA courte (signal de sortie)
input ENUM_MA_METHOD MA_Method = MODE_SMA;   // Méthode MA (SMA, EMA, SMMA, LWMA)
input ENUM_APPLIED_PRICE MA_Price = PRICE_CLOSE; // Prix appliqué (Close, Open, High, Low, etc.)
input ENUM_TIMEFRAMES Timeframe = PERIOD_M5; // Timeframe
input double StopLoss = 50.0;               // Stop Loss en points
input double TakeProfit = 100.0;            // Take Profit en points
input double LotSize = 0.1;                 // Taille du lot
input int MagicNumber = 12345;              // Numéro magique
input string Comment = "MA_UTurn";          // Commentaire des ordres

// Variables globales
double MA_Long_Current, MA_Long_Previous, MA_Long_Previous2;
double MA_Short_Current, MA_Short_Previous, MA_Short_Previous2;
int LastSignal = 0; // 1 = Buy signal, -1 = Sell signal, 0 = No signal

// Handles des indicateurs
int handle_MA_Long;
int handle_MA_Short;

// Tableaux pour stocker les valeurs
double ma_long_buffer[];
double ma_short_buffer[];

//+------------------------------------------------------------------+
//| Validation des paramètres d'entrée                              |
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
        error_msg += "ERREUR: Les périodes MA ne doivent pas dépasser 1000\n";
        is_valid = false;
    }
    
    // Validation Stop Loss et Take Profit
    if(StopLoss < 0 || TakeProfit < 0)
    {
        error_msg += "ERREUR: Stop Loss et Take Profit ne peuvent pas être négatifs\n";
        is_valid = false;
    }
    
    if(StopLoss > 10000 || TakeProfit > 10000)
    {
        error_msg += "ERREUR: Stop Loss et Take Profit ne doivent pas dépasser 10000 points\n";
        is_valid = false;
    }
    
    // Validation de la taille de lot
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
    
    // Vérification que la taille de lot respecte le pas
    double lot_remainder = MathMod(LotSize, lot_step);
    if(lot_remainder > 0.0001) // Tolérance pour les erreurs de virgule flottante
    {
        error_msg += "ERREUR: Taille de lot (" + DoubleToString(LotSize, 2) + 
                    ") doit être un multiple de " + DoubleToString(lot_step, 2) + "\n";
        is_valid = false;
    }
    
    // Validation du Magic Number
    if(MagicNumber < 0)
    {
        error_msg += "ERREUR: Le Magic Number ne peut pas être négatif\n";
        is_valid = false;
    }
    
    // Validation de la timeframe
    if(Timeframe != PERIOD_M1 && Timeframe != PERIOD_M5 && Timeframe != PERIOD_M15 && 
       Timeframe != PERIOD_M30 && Timeframe != PERIOD_H1 && Timeframe != PERIOD_H4 && 
       Timeframe != PERIOD_D1 && Timeframe != PERIOD_W1 && Timeframe != PERIOD_MN1)
    {
        error_msg += "ERREUR: Timeframe non supportée\n";
        is_valid = false;
    }
    
    // Affichage des erreurs
    if(!is_valid)
    {
        Print("=== PARAMÈTRES INCORRECTS ===");
        Print(error_msg);
        Print("=============================");
        
        // Affichage des limites pour aider l'utilisateur
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
    
    // Validation des paramètres d'entrée
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
    
    // Création des handles d'indicateurs
    handle_MA_Long = iMA(_Symbol, Timeframe, MA_Period_Long, 0, MA_Method, MA_Price);
    handle_MA_Short = iMA(_Symbol, Timeframe, MA_Period_Short, 0, MA_Method, MA_Price);
    
    if(handle_MA_Long == INVALID_HANDLE || handle_MA_Short == INVALID_HANDLE)
    {
        Print("ERREUR: Impossible de créer les handles d'indicateurs");
        Print("Handle MA Long: ", handle_MA_Long);
        Print("Handle MA Short: ", handle_MA_Short);
        return(INIT_FAILED);
    }
    
    // Configuration des tableaux
    ArraySetAsSeries(ma_long_buffer, true);
    ArraySetAsSeries(ma_short_buffer, true);
    
    Print("EA initialisé avec succès!");
    Print("==========================================");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("EA désactivé. Raison: ", reason);
    
    // Libération des handles
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
    // Mise à jour des valeurs de MA
    if(!UpdateMAValues())
        return;
    
    // Vérification des signaux d'entrée
    CheckEntrySignals();
    
    // Vérification des signaux de sortie
    CheckExitSignals();
}

//+------------------------------------------------------------------+
//| Mise à jour des valeurs de moyennes mobiles                     |
//+------------------------------------------------------------------+
bool UpdateMAValues()
{
    // Vérification que suffisamment de barres sont disponibles
    int bars = iBars(_Symbol, Timeframe);
    if(bars < MathMax(MA_Period_Long, MA_Period_Short) + 3)
    {
        Print("Pas assez de barres historiques disponibles (", bars, " barres)");
        return false;
    }
    
    // Copie des données MA longue
    if(CopyBuffer(handle_MA_Long, 0, 0, 3, ma_long_buffer) < 3)
    {
        Print("Erreur lors de la copie des données MA longue. Code d'erreur: ", GetLastError());
        return false;
    }
    
    // Copie des données MA courte
    if(CopyBuffer(handle_MA_Short, 0, 0, 3, ma_short_buffer) < 3)
    {
        Print("Erreur lors de la copie des données MA courte. Code d'erreur: ", GetLastError());
        return false;
    }
    
    // Attribution des valeurs
    MA_Long_Current = ma_long_buffer[0];
    MA_Long_Previous = ma_long_buffer[1];
    MA_Long_Previous2 = ma_long_buffer[2];
    
    MA_Short_Current = ma_short_buffer[0];
    MA_Short_Previous = ma_short_buffer[1];
    MA_Short_Previous2 = ma_short_buffer[2];
    
    // Vérification que les valeurs ne sont pas nulles ou invalides
    if(MA_Long_Current <= 0 || MA_Long_Previous <= 0 || MA_Long_Previous2 <= 0 ||
       MA_Short_Current <= 0 || MA_Short_Previous <= 0 || MA_Short_Previous2 <= 0)
    {
        Print("Valeurs MA invalides détectées");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Détection du pattern U vers le haut                             |
//+------------------------------------------------------------------+
bool IsUTurnUp(double current, double previous, double previous2)
{
    // Pattern U vers le haut: previous2 > previous < current
    return (previous2 > previous && previous < current);
}

//+------------------------------------------------------------------+
//| Détection du pattern U vers le bas                              |
//+------------------------------------------------------------------+
bool IsUTurnDown(double current, double previous, double previous2)
{
    // Pattern U vers le bas: previous2 < previous > current
    return (previous2 < previous && previous > current);
}

//+------------------------------------------------------------------+
//| Vérification des signaux d'entrée                               |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
    // Éviter les ordres multiples
    if(HasOpenPositions())
        return;
    
    // Signal d'achat: MA longue fait un U vers le haut
    if(IsUTurnUp(MA_Long_Current, MA_Long_Previous, MA_Long_Previous2))
    {
        if(LastSignal != 1) // Éviter les signaux répétés
        {
            OpenBuyOrder();
            LastSignal = 1;
        }
    }
    // Signal de vente: MA longue fait un U vers le bas
    else if(IsUTurnDown(MA_Long_Current, MA_Long_Previous, MA_Long_Previous2))
    {
        if(LastSignal != -1) // Éviter les signaux répétés
        {
            OpenSellOrder();
            LastSignal = -1;
        }
    }
}

//+------------------------------------------------------------------+
//| Vérification des signaux de sortie                              |
//+------------------------------------------------------------------+
void CheckExitSignals()
{
    if(!HasOpenPositions())
        return;
    
    // Signal de fermeture pour position BUY: MA courte fait un U vers le bas
    if(GetPositionType() == POSITION_TYPE_BUY && IsUTurnDown(MA_Short_Current, MA_Short_Previous, MA_Short_Previous2))
    {
        CloseAllPositions();
        LastSignal = 0;
    }
    // Signal de fermeture pour position SELL: MA courte fait un U vers le haut
    else if(GetPositionType() == POSITION_TYPE_SELL && IsUTurnUp(MA_Short_Current, MA_Short_Previous, MA_Short_Previous2))
    {
        CloseAllPositions();
        LastSignal = 0;
    }
}

//+------------------------------------------------------------------+
//| Validation des niveaux Stop Loss et Take Profit                 |
//+------------------------------------------------------------------+
bool ValidateSLTP(double price, double sl, double tp, bool is_buy)
{
    double min_stop_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
    double freeze_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
    
    if(min_stop_level == 0 && freeze_level == 0)
        return true; // Pas de restrictions
    
    if(is_buy)
    {
        // Pour un achat, SL doit être en dessous du prix et TP au-dessus
        if(sl > 0 && (price - sl) < min_stop_level)
        {
            Print("ATTENTION: Stop Loss trop proche du prix (minimum: ", min_stop_level/_Point, " points)");
            return false;
        }
        if(tp > 0 && (tp - price) < min_stop_level)
        {
            Print("ATTENTION: Take Profit trop proche du prix (minimum: ", min_stop_level/_Point, " points)");
            return false;
        }
    }
    else
    {
        // Pour une vente, SL doit être au-dessus du prix et TP en dessous
        if(sl > 0 && (sl - price) < min_stop_level)
        {
            Print("ATTENTION: Stop Loss trop proche du prix (minimum: ", min_stop_level/_Point, " points)");
            return false;
        }
        if(tp > 0 && (price - tp) < min_stop_level)
        {
            Print("ATTENTION: Take Profit trop proche du prix (minimum: ", min_stop_level/_Point, " points)");
            return false;
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Ouverture d'un ordre d'achat                                    |
//+------------------------------------------------------------------+
void OpenBuyOrder()
{
    MqlTick latest_price;
    if(!SymbolInfoTick(_Symbol, latest_price))
    {
        Print("Erreur lors de l'obtention du prix actuel");
        return;
    }
    
    double ask = latest_price.ask;
    double sl = (StopLoss > 0) ? ask - StopLoss * _Point : 0;
    double tp = (TakeProfit > 0) ? ask + TakeProfit * _Point : 0;
    
    // Normalisation des prix
    sl = NormalizeDouble(sl, _Digits);
    tp = NormalizeDouble(tp, _Digits);
    
    // Validation des niveaux SL/TP
    if(!ValidateSLTP(ask, sl, tp, true))
    {
        Print("ERREUR: Niveaux SL/TP incorrects pour l'ordre BUY");
        return;
    }
    
    if(trade.Buy(LotSize, _Symbol, ask, sl, tp, Comment))
    {
        Print("Ordre BUY ouvert. Ticket: ", trade.ResultOrder(), " | Prix: ", ask);
        if(sl > 0) Print("Stop Loss: ", sl);
        if(tp > 0) Print("Take Profit: ", tp);
    }
    else
    {
        Print("Erreur ouverture BUY: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Ouverture d'un ordre de vente                                   |
//+------------------------------------------------------------------+
void OpenSellOrder()
{
    MqlTick latest_price;
    if(!SymbolInfoTick(_Symbol, latest_price))
    {
        Print("Erreur lors de l'obtention du prix actuel");
        return;
    }
    
    double bid = latest_price.bid;
    double sl = (StopLoss > 0) ? bid + StopLoss * _Point : 0;
    double tp = (TakeProfit > 0) ? bid - TakeProfit * _Point : 0;
    
    // Normalisation des prix
    sl = NormalizeDouble(sl, _Digits);
    tp = NormalizeDouble(tp, _Digits);
    
    // Validation des niveaux SL/TP
    if(!ValidateSLTP(bid, sl, tp, false))
    {
        Print("ERREUR: Niveaux SL/TP incorrects pour l'ordre SELL");
        return;
    }
    
    if(trade.Sell(LotSize, _Symbol, bid, sl, tp, Comment))
    {
        Print("Ordre SELL ouvert. Ticket: ", trade.ResultOrder(), " | Prix: ", bid);
        if(sl > 0) Print("Stop Loss: ", sl);
        if(tp > 0) Print("Take Profit: ", tp);
    }
    else
    {
        Print("Erreur ouverture SELL: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Vérification de l'existence de positions ouvertes               |
//+------------------------------------------------------------------+
bool HasOpenPositions()
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetSymbol(i) == _Symbol)
        {
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Obtenir le type de position ouverte                             |
//+------------------------------------------------------------------+
ENUM_POSITION_TYPE GetPositionType()
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetSymbol(i) == _Symbol)
        {
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                return (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            }
        }
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Fermeture de toutes les positions                               |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        if(PositionGetSymbol(i) == _Symbol)
        {
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                ulong ticket = PositionGetInteger(POSITION_TICKET);
                
                if(trade.PositionClose(ticket))
                {
                    Print("Position fermée. Ticket: ", ticket);
                }
                else
                {
                    Print("Erreur fermeture position: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
                }
            }
        }
    }
}