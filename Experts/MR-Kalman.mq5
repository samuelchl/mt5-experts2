#include <Trade/Trade.mqh>
CTrade trade;

// Paramètres existants
input double mv = 10;
input double pv = 1.0;
input int Magic = 0;
input int bbPeriod = 100;
input double d = 2.0;
input int maPeriod = 500;
input int ATRPeriod = 14;
input int shift_prev_state = 1;

// Paramètres de gestion des risques
input double TakeProfit = 50.0;        // Take Profit en points
input double StopLoss = 30.0;          // Stop Loss en points
input double LotSize = 0.01;           // Taille des lots
input double MaxDrawdownPercent = 10.0; // Drawdown maximum en %
input double RiskPercent = 1.0;        // Risque maximum par trade en %
input bool BuyOnly = false;            // Mode Buy seulement
input bool SellOnly = false;           // Mode Sell seulement

// Nouveaux paramètres de session
enum SESSION_TYPE {
    SESSION_ALL = 0,        // Toutes les sessions
    SESSION_ASIAN = 1,      // Session asiatique (00:00-09:00 GMT)
    SESSION_LONDON = 2,     // Session Londres (08:00-17:00 GMT)
    SESSION_NY = 3          // Session New York (13:00-22:00 GMT)
};
input SESSION_TYPE TradingSession = SESSION_ALL; // Session de trading

// Paramètres d'amélioration
input bool UseTrailingStop = true;     // Utiliser le trailing stop
input double TrailingDistance = 20.0;  // Distance du trailing stop en points
input int MaxPositions = 3;            // Nombre maximum de positions simultanées
input bool UseNewsFilter = false;      // Filtre actualités (arrêt 30min avant/après)
input int NewsFilterMinutes = 30;      // Minutes d'arrêt avant/après actualités
input bool SendAlerts = true;          // Envoyer des alertes
input bool UseBreakEven = true;        // Utiliser le break-even
input double BreakEvenPoints = 15.0;   // Points pour déclencher le break-even

input ENUM_TIMEFRAMES timeframe_MA  = PERIOD_CURRENT; // Timeframe pour Moyenne Mobile
input ENUM_TIMEFRAMES timeframe_BB  = PERIOD_CURRENT; // Timeframe pour Bollinger Bands
input ENUM_TIMEFRAMES timeframe_ATR = PERIOD_CURRENT; // Timeframe pour ATR
input ENUM_TIMEFRAMES timeframe_tick = PERIOD_CURRENT; // Timeframe pour prix tick


// Variables globales
double prev_state;
double prev_covariance = 1;
int barsTotal = 0;
int handleMa;
int handleBb;
int handleATR;
double initialBalance;
double maxEquity;
datetime lastDrawdownAlert = 0;
bool tradingEnabled = true;

//+------------------------------------------------------------------+
//| Structure pour les heures de session                            |
//+------------------------------------------------------------------+
struct SessionHours {
    int startHour;
    int startMinute;
    int endHour;
    int endMinute;
};

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{   
    handleMa = iMA(_Symbol,timeframe_MA,maPeriod,0,MODE_EMA,PRICE_CLOSE);
    handleBb = iBands(_Symbol,timeframe_BB,bbPeriod,0,d,PRICE_CLOSE);
    handleATR = iATR(_Symbol,timeframe_ATR,ATRPeriod);
    prev_state = iClose(_Symbol,timeframe_tick,shift_prev_state);  
    trade.SetExpertMagicNumber(Magic);
    
    // Vérifier les handles
    if(handleMa == INVALID_HANDLE || handleBb == INVALID_HANDLE || handleATR == INVALID_HANDLE) {
        Print("Erreur création des indicateurs");
        return INIT_FAILED;
    }
    
    // Initialiser les variables de contrôle des risques
    initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    maxEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // Vérifier la cohérence des paramètres
    if(BuyOnly && SellOnly) {
        Print("Erreur: BuyOnly et SellOnly ne peuvent pas être tous les deux activés");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    if(MaxPositions <= 0) {
        Print("Erreur: MaxPositions doit être supérieur à 0");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    Print("EA initialisé - Symbol: ", _Symbol, " Magic: ", Magic);
    if(SendAlerts) Alert("EA ", _Symbol, " démarré avec Magic Number: ", Magic);
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinitializer function                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Libérer les handles des indicateurs
    if(handleMa != INVALID_HANDLE) IndicatorRelease(handleMa);
    if(handleBb != INVALID_HANDLE) IndicatorRelease(handleBb);
    if(handleATR != INVALID_HANDLE) IndicatorRelease(handleATR);
    
    Print("EA arrêté - Raison: ", reason);
}

//+------------------------------------------------------------------+
//| OnTick Function                                                 |
//+------------------------------------------------------------------+
void OnTick()
{
    int bars = iBars(_Symbol,timeframe_tick);
    
    if (barsTotal != bars) {
        barsTotal = bars;
        
        // Vérifier les conditions de risque
        if(!CheckDrawdownLimit()) {
            return;
        }
        
        if(!CheckRiskLimit()) {
            return;
        }
        
        // Vérifier la session de trading
        if(!IsInTradingSession()) {
            return;
        }
        
        // Gérer les positions existantes
        ManageExistingPositions();
        
        // Vérifier le nombre maximum de positions
        if(CountPositions() >= MaxPositions) {
            return;
        }
        
        bool NotInPosition = (CountPositions() == 0);
        double price = iClose(_Symbol,timeframe_tick,1); 
        double bbLower[], bbUpper[], bbMiddle[];
        double ma[];
        double kalman = KalmanFilter(price,mv,pv);
        
        CopyBuffer(handleMa,0,1,1,ma);
        CopyBuffer(handleBb,UPPER_BAND,1,1,bbUpper);
        CopyBuffer(handleBb,LOWER_BAND,1,1,bbLower);
        CopyBuffer(handleBb,0,1,1,bbMiddle);
        
        // Signaux de trading avec filtres améliorés
        if(price < bbLower[0] && price > kalman && NotInPosition && !SellOnly && tradingEnabled) {
            if(ValidateSignal(ORDER_TYPE_BUY, price, bbMiddle[0])) {
                executeBuy(_Symbol);
            }
        }
        
        if(price > bbUpper[0] && price < kalman && NotInPosition && !BuyOnly && tradingEnabled) {
            if(ValidateSignal(ORDER_TYPE_SELL, price, bbMiddle[0])) {
                executeSell(_Symbol);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Kalman Filter Function                                          |
//+------------------------------------------------------------------+
double KalmanFilter(double price, double measurement_variance, double process_variance)
{
    double predicted_state = prev_state;
    double predicted_covariance = prev_covariance + process_variance;
    
    double kalman_gain = predicted_covariance / (predicted_covariance + measurement_variance);
    
    double updated_state = predicted_state + kalman_gain * (price - predicted_state);
    double updated_covariance = (1 - kalman_gain) * predicted_covariance;
    
    prev_state = updated_state;
    prev_covariance = updated_covariance;
    
    return updated_state;
}

//+------------------------------------------------------------------+
//| Vérifier et fermer toutes les positions si DD limite atteinte   |
//+------------------------------------------------------------------+
bool CheckDrawdownLimit()
{
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // Mettre à jour l'equity maximum
    if(currentEquity > maxEquity) {
        maxEquity = currentEquity;
    }
    
    // Calculer le drawdown actuel
    double currentDrawdown = ((maxEquity - currentEquity) / maxEquity) * 100.0;
    
    if(currentDrawdown >= MaxDrawdownPercent) {
        // Fermer toutes les positions du Magic Number et Symbol
        CloseAllPositions();
        
        tradingEnabled = false;
        
        // Alerte de drawdown (max une fois par heure)
        if(TimeCurrent() - lastDrawdownAlert > 3600) {
            string message = StringFormat("ALERTE DRAWDOWN: %.2f%% - Toutes les positions fermées pour %s (Magic: %d)", 
                                        currentDrawdown, _Symbol, Magic);
            Print(message);
            if(SendAlerts) Alert(message);
            lastDrawdownAlert = TimeCurrent();
        }
        
        return false;
    }
    
    // Réactiver le trading si le drawdown revient sous la limite
    if(currentDrawdown < MaxDrawdownPercent * 0.8 && !tradingEnabled) {
        tradingEnabled = true;
        Print("Trading réactivé - Drawdown: ", currentDrawdown, "%");
        if(SendAlerts) Alert("Trading réactivé pour ", _Symbol, " - DD: ", currentDrawdown, "%");
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Fermer toutes les positions du Magic Number et Symbol           |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    int closed = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket)) {
            if(PositionGetInteger(POSITION_MAGIC) == Magic && 
               PositionGetString(POSITION_SYMBOL) == _Symbol) {
                if(trade.PositionClose(ticket)) {
                    closed++;
                    Print("Position fermée (DD limite): Ticket ", ticket);
                }
            }
        }
    }
    
    if(closed > 0 && SendAlerts) {
        Alert(closed, " positions fermées pour ", _Symbol, " (Magic: ", Magic, ") - Limite DD atteinte");
    }
}

//+------------------------------------------------------------------+
//| Vérifier la limite de risque                                    |
//+------------------------------------------------------------------+
bool CheckRiskLimit()
{
    double totalRisk = 0.0;
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    // Calculer le risque total des positions ouvertes
    for(int i = 0; i < PositionsTotal(); i++) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetInteger(POSITION_MAGIC) == Magic && PositionGetString(POSITION_SYMBOL) == _Symbol) {
                double positionVolume = PositionGetDouble(POSITION_VOLUME);
                double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                double sl = PositionGetDouble(POSITION_SL);
                
                if(sl > 0) {
                    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
                    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
                    double riskAmount = MathAbs(openPrice - sl) / tickSize * tickValue * positionVolume;
                    totalRisk += riskAmount;
                }
            }
        }
    }
    
    // Calculer le risque d'une nouvelle position
    double newPositionRisk = CalculatePositionRisk();
    double totalRiskPercent = ((totalRisk + newPositionRisk) / balance) * 100.0;
    
    if(totalRiskPercent > RiskPercent) {
        Print("Trading arrêté: Limite de risque atteinte (", totalRiskPercent, "%)");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculer le risque d'une nouvelle position                      |
//+------------------------------------------------------------------+
double CalculatePositionRisk()
{
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double slPoints = StopLoss * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    return (slPoints / tickSize) * tickValue * LotSize;
}

//+------------------------------------------------------------------+
//| Vérifier si nous sommes dans la session de trading              |
//+------------------------------------------------------------------+
bool IsInTradingSession()
{
    if(TradingSession == SESSION_ALL) return true;
    
    MqlDateTime timeStruct;
    TimeToStruct(TimeGMT(), timeStruct);
    int currentHour = timeStruct.hour;
    int currentMinute = timeStruct.min;
    int currentTime = currentHour * 60 + currentMinute;
    
    SessionHours session;
    
    switch(TradingSession) {
        case SESSION_ASIAN:
            session.startHour = 0; session.startMinute = 0;
            session.endHour = 9; session.endMinute = 0;
            break;
            
        case SESSION_LONDON:
            session.startHour = 8; session.startMinute = 0;
            session.endHour = 17; session.endMinute = 0;
            break;
            
        case SESSION_NY:
            session.startHour = 13; session.startMinute = 0;
            session.endHour = 22; session.endMinute = 0;
            break;
            
        default:
            return true;
    }
    
    int sessionStart = session.startHour * 60 + session.startMinute;
    int sessionEnd = session.endHour * 60 + session.endMinute;
    
    return (currentTime >= sessionStart && currentTime <= sessionEnd);
}

//+------------------------------------------------------------------+
//| Compter les positions du Magic Number et Symbol                 |
//+------------------------------------------------------------------+
int CountPositions()
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetInteger(POSITION_MAGIC) == Magic && 
               PositionGetString(POSITION_SYMBOL) == _Symbol) {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Gérer les positions existantes                                  |
//+------------------------------------------------------------------+
void ManageExistingPositions()
{
    double price = iClose(_Symbol,timeframe_tick,1);
    double bbMiddle[];
    CopyBuffer(handleBb,0,1,1,bbMiddle);
    
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket)) {
            if(PositionGetInteger(POSITION_MAGIC) == Magic && 
               PositionGetString(POSITION_SYMBOL) == _Symbol) {
                
                ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                
                // Fermeture sur retour à la moyenne
                if((posType == POSITION_TYPE_BUY && price > bbMiddle[0]) ||
                   (posType == POSITION_TYPE_SELL && price < bbMiddle[0])) {
                    trade.PositionClose(ticket);
                    Print("Position fermée (retour moyenne): Ticket ", ticket);
                    continue;
                }
                
                // Trailing Stop
                if(UseTrailingStop) {
                    ApplyTrailingStop(ticket, posType);
                }
                
                // Break Even
                if(UseBreakEven) {
                    ApplyBreakEven(ticket, posType);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Appliquer le trailing stop                                      |
//+------------------------------------------------------------------+
void ApplyTrailingStop(ulong ticket, ENUM_POSITION_TYPE posType)
{
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentSL = PositionGetDouble(POSITION_SL);
    double currentPrice = (posType == POSITION_TYPE_BUY) ? 
                         SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double trailingDistance = TrailingDistance * point;
    
    double newSL = 0;
    bool shouldModify = false;
    
    if(posType == POSITION_TYPE_BUY) {
        newSL = currentPrice - trailingDistance;
        if(newSL > currentSL && newSL > openPrice) {
            shouldModify = true;
        }
    } else {
        newSL = currentPrice + trailingDistance;
        if((currentSL == 0 || newSL < currentSL) && newSL < openPrice) {
            shouldModify = true;
        }
    }
    
    if(shouldModify) {
        newSL = NormalizeDouble(newSL, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
        if(trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP))) {
            Print("Trailing Stop appliqué: Ticket ", ticket, " New SL: ", newSL);
        }
    }
}

//+------------------------------------------------------------------+
//| Appliquer le break even                                         |
//+------------------------------------------------------------------+
void ApplyBreakEven(ulong ticket, ENUM_POSITION_TYPE posType)
{
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentSL = PositionGetDouble(POSITION_SL);
    double currentPrice = (posType == POSITION_TYPE_BUY) ? 
                         SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double beDistance = BreakEvenPoints * point;
    
    bool shouldApplyBE = false;
    
    if(posType == POSITION_TYPE_BUY) {
        if(currentPrice >= openPrice + beDistance && currentSL < openPrice) {
            shouldApplyBE = true;
        }
    } else {
        if(currentPrice <= openPrice - beDistance && (currentSL == 0 || currentSL > openPrice)) {
            shouldApplyBE = true;
        }
    }
    
    if(shouldApplyBE) {
        double newSL = NormalizeDouble(openPrice, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
        if(trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP))) {
            Print("Break Even appliqué: Ticket ", ticket, " SL: ", newSL);
        }
    }
}

//+------------------------------------------------------------------+
//| Valider le signal de trading                                    |
//+------------------------------------------------------------------+
bool ValidateSignal(ENUM_ORDER_TYPE orderType, double price, double bbMiddle)
{
    // Validation de base - éviter les faux signaux
    double atrBuffer[];
    if(CopyBuffer(handleATR, 0, 1, 1, atrBuffer) <= 0) {
        Print("Erreur lecture ATR");
        return true; // Continuer sans filtre ATR en cas d'erreur
    }
    
    double atr = atrBuffer[0];
    double minDistance = atr * 0.5; // Distance minimum de la moyenne
    
    if(orderType == ORDER_TYPE_BUY) {
        return (bbMiddle - price) >= minDistance;
    } else {
        return (price - bbMiddle) >= minDistance;
    }
}

//+------------------------------------------------------------------+
//| Buy Function                                                     |
//+------------------------------------------------------------------+
void executeBuy(string symbol) 
{
    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    double sl = ask - (StopLoss * point);
    double tp = ask + (TakeProfit * point);
    
    // Normaliser les prix
    sl = NormalizeDouble(sl, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
    tp = NormalizeDouble(tp, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
    
    if(trade.Buy(LotSize, symbol, ask, sl, tp)) {
        Print("Position BUY ouverte: Volume=", LotSize, " SL=", sl, " TP=", tp);
        if(SendAlerts) Alert("BUY ouvert sur ", symbol, " - SL:", sl, " TP:", tp);
    } else {
        Print("Erreur ouverture BUY: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Sell Function                                                    |
//+------------------------------------------------------------------+
void executeSell(string symbol) 
{      
    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    double sl = bid + (StopLoss * point);
    double tp = bid - (TakeProfit * point);
    
    // Normaliser les prix
    sl = NormalizeDouble(sl, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
    tp = NormalizeDouble(tp, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
    
    if(trade.Sell(LotSize, symbol, bid, sl, tp)) {
        Print("Position SELL ouverte: Volume=", LotSize, " SL=", sl, " TP=", tp);
        if(SendAlerts) Alert("SELL ouvert sur ", symbol, " - SL:", sl, " TP:", tp);
    } else {
        Print("Erreur ouverture SELL: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}