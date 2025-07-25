//+------------------------------------------------------------------+
//|                                            Generic_EA_Skeleton.mq5 |
//|                                                                  |
//|                    Squelette générique pour Expert Advisor MQL5 |
//+------------------------------------------------------------------+
#property copyright "Generic EA Skeleton MQL5"
#property version   "1.00"

// Inclure les classes nécessaires
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

// Paramètres d'entrée génériques
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5;     // Timeframe de travail
input double InpStopLoss = 50.0;                    // Stop Loss en points
input double InpTakeProfit = 100.0;                 // Take Profit en points
input double InpLotSize = 0.1;                      // Taille du lot
input ulong InpMagicNumber = 12345;                 // Numéro magique unique
input string InpComment = "Generic_EA";             // Commentaire des ordres
input bool InpEnableTrading = true;                 // Activer/désactiver le trading
input int InpMaxPositions = 1;                      // Nombre maximum de positions simultanées
input int InpSlippage = 3;                          // Slippage autorisé

// Objets pour le trading
CTrade trade;
CPositionInfo positionInfo;
COrderInfo orderInfo;

// Variables globales
int lastSignal = 0;                                 // Dernier signal généré (1=Buy, -1=Sell, 0=None)
datetime lastTradeTime = 0;                         // Timestamp du dernier trade
datetime lastBarTime = 0;                           // Timestamp de la dernière barre analysée


struct Correlation
{
   string symbol1;
   string symbol2;
   double value;
};

#define CORRELATION_COUNT 30 // Nombre total d’entrées

Correlation correlations[CORRELATION_COUNT] =
{
   {"EURUSD", "USDCHF", -0.871352},
   {"EURUSD", "USDCAD", -0.931620},
   {"EURUSD", "NZDUSD",  0.919223},
   {"EURUSD", "EURCHF",  0.283308},
   {"EURUSD", "NZDCAD",  0.821813},

   {"USDCHF", "EURUSD", -0.871352},
   {"USDCHF", "USDCAD",  0.748369},
   {"USDCHF", "NZDUSD", -0.759700},
   {"USDCHF", "EURCHF",  0.223059},
   {"USDCHF", "NZDCAD", -0.705838},

   {"USDCAD", "EURUSD", -0.931620},
   {"USDCAD", "USDCHF",  0.748369},
   {"USDCAD", "NZDUSD", -0.974826},
   {"USDCAD", "EURCHF", -0.392397},
   {"USDCAD", "NZDCAD", -0.859300},

   {"NZDUSD", "EURUSD",  0.919223},
   {"NZDUSD", "USDCHF", -0.759700},
   {"NZDUSD", "USDCAD", -0.974826},
   {"NZDUSD", "EURCHF",  0.344632},
   {"NZDUSD", "NZDCAD",  0.951196},

   {"EURCHF", "EURUSD",  0.283308},
   {"EURCHF", "USDCHF",  0.223059},
   {"EURCHF", "USDCAD", -0.392397},
   {"EURCHF", "NZDUSD",  0.344632},
   {"EURCHF", "NZDCAD",  0.256326},

   {"NZDCAD", "EURUSD",  0.821813},
   {"NZDCAD", "USDCHF", -0.705838},
   {"NZDCAD", "USDCAD", -0.859300},
   {"NZDCAD", "NZDUSD",  0.951196},
   {"NZDCAD", "EURCHF",  0.256326}
};


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("EA Generic Skeleton MQL5 initialisé");
    Print("Symbole: ", _Symbol);
    Print("Timeframe: ", EnumToString(InpTimeframe));
    Print("Trading activé: ", InpEnableTrading ? "Oui" : "Non");
    
    // Configuration de l'objet trade
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(InpSlippage);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    trade.SetTypeFillingBySymbol(_Symbol);
    
    // Validation des paramètres
    if(!ValidateParameters())
    {
        Print("Erreur: Paramètres invalides");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("EA désactivé. Raison: ", reason);
    
    // Nettoyage si nécessaire
    switch(reason)
    {
        case REASON_PARAMETERS:
            Print("Changement de paramètres");
            break;
        case REASON_RECOMPILE:
            Print("Recompilation du code");
            break;
        case REASON_REMOVE:
            Print("Suppression de l'EA");
            break;
        case REASON_CHARTCHANGE:
            Print("Changement de graphique");
            break;
        default:
            Print("Autre raison d'arrêt: ", reason);
            break;
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Vérification des conditions préalables
    if(!InpEnableTrading)
        return;
        
    if(!IsNewBar())
        return;
    
    // Mise à jour des données de marché
    UpdateMarketData();
    
    // Analyse du marché et génération de signaux
    AnalyzeMarket();
    
    // Gestion des positions existantes
    ManagePositions();
    
    // Exécution des ordres si signaux présents
    ExecuteSignals();
}

//+------------------------------------------------------------------+
//| Validation des paramètres d'entrée                              |
//+------------------------------------------------------------------+
bool ValidateParameters()
{
    if(InpLotSize <= 0)
    {
        Print("Erreur: Taille de lot invalide: ", InpLotSize);
        return false;
    }
    
    if(InpStopLoss < 0 || InpTakeProfit < 0)
    {
        Print("Erreur: SL/TP négatifs - SL: ", InpStopLoss, " TP: ", InpTakeProfit);
        return false;
    }
    
    if(InpMaxPositions <= 0)
    {
        Print("Erreur: Nombre maximum de positions invalide: ", InpMaxPositions);
        return false;
    }
    
    // Vérifier les propriétés du symbole
    if(!SymbolInfoInteger(_Symbol, SYMBOL_SELECT))
    {
        Print("Erreur: Symbole non sélectionné dans MarketWatch");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Détection d'une nouvelle barre                                  |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    datetime currentBarTime = iTime(_Symbol, InpTimeframe, 0);
    
    if(currentBarTime != lastBarTime)
    {
        lastBarTime = currentBarTime;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Mise à jour des données de marché                               |
//+------------------------------------------------------------------+
void UpdateMarketData()
{
    // TODO: Ici vous pouvez mettre à jour vos indicateurs,
    // calculer des moyennes, volatilité, etc.
    
    // Exemple de structure pour données de marché:
    // - Prix actuels (Open, High, Low, Close) via iOpen, iHigh, iLow, iClose
    // - Volumes via iVolume
    // - Indicateurs techniques via les fonctions iMA, iRSI, etc.
    // - Données de volatilité
    
    // Exemple d'utilisation:
    /*
    double currentClose = iClose(_Symbol, InpTimeframe, 0);
    double previousClose = iClose(_Symbol, InpTimeframe, 1);
    double currentVolume = iVolume(_Symbol, InpTimeframe, 0);
    */
}

//+------------------------------------------------------------------+
//| Analyse du marché et génération de signaux                      |
//+------------------------------------------------------------------+
void AnalyzeMarket()
{
    // Réinitialiser le signal
    lastSignal = 0;
    
    // TODO: Implémenter votre logique de trading ici
    // Exemples de conditions possibles:
    // - Croisements d'indicateurs
    // - Patterns de prix
    // - Niveaux de support/résistance
    // - Signaux de momentum
    
    // Exemple de structure:
    /*
    if(YourBuyCondition())
    {
        lastSignal = 1;  // Signal d'achat
    }
    else if(YourSellCondition())
    {
        lastSignal = -1; // Signal de vente
    }
    */
}

//+------------------------------------------------------------------+
//| Gestion des positions existantes                                |
//+------------------------------------------------------------------+
void ManagePositions()
{
    if(!HasOpenPositions())
        return;
        
    // TODO: Implémenter votre logique de gestion des positions
    // Exemples:
    // - Trailing stop
    // - Modification des niveaux SL/TP
    // - Fermeture partielle
    // - Fermeture sur signaux contraires
    
    // Exemple de gestion basique:
    /*
    if(ShouldClosePositions())
    {
        CloseAllPositions();
    }
    */
    
    // Exemple de trailing stop:
    /*
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
            {
                ApplyTrailingStop();
            }
        }
    }
    */
}

//+------------------------------------------------------------------+
//| Exécution des signaux de trading                                |
//+------------------------------------------------------------------+
void ExecuteSignals()
{
    // Vérifier s'il y a de la place pour de nouvelles positions
    if(CountOpenPositions() >= InpMaxPositions)
        return;
        
    // Exécuter les signaux
    if(lastSignal == 1) // Signal d'achat
    {
        if(CanOpenBuy())
        {
            OpenBuyPosition();
        }
    }
    else if(lastSignal == -1) // Signal de vente
    {
        if(CanOpenSell())
        {
            OpenSellPosition();
        }
    }
}

//+------------------------------------------------------------------+
//| Vérification des conditions pour position d'achat               |
//+------------------------------------------------------------------+
bool CanOpenBuy()
{
    // TODO: Ajouter vos conditions spécifiques
    // Exemples: spread, liquidité, heures de trading, etc.
    
    // Vérifier le spread
    double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double maxSpread = 0.0003; // 3 pips maximum
    
    if(spread > maxSpread)
    {
        Print("Spread trop élevé pour ouvrir position BUY: ", spread);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Vérification des conditions pour position de vente              |
//+------------------------------------------------------------------+
bool CanOpenSell()
{
    // TODO: Ajouter vos conditions spécifiques
    // Exemples: spread, liquidité, heures de trading, etc.
    
    // Vérifier le spread
    double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double maxSpread = 0.0003; // 3 pips maximum
    
    if(spread > maxSpread)
    {
        Print("Spread trop élevé pour ouvrir position SELL: ", spread);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Ouverture d'une position d'achat                                |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
    double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double sl = (InpStopLoss > 0) ? price - InpStopLoss * SymbolInfoDouble(_Symbol, SYMBOL_POINT) : 0;
    double tp = (InpTakeProfit > 0) ? price + InpTakeProfit * SymbolInfoDouble(_Symbol, SYMBOL_POINT) : 0;
    
    if(trade.Buy(InpLotSize, _Symbol, price, sl, tp, InpComment))
    {
        Print("Position BUY ouverte. Ticket: ", trade.ResultOrder(), " | Prix: ", price);
        lastTradeTime = TimeCurrent();
    }
    else
    {
        Print("Erreur ouverture BUY: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Ouverture d'une position de vente                               |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = (InpStopLoss > 0) ? price + InpStopLoss * SymbolInfoDouble(_Symbol, SYMBOL_POINT) : 0;
    double tp = (InpTakeProfit > 0) ? price - InpTakeProfit * SymbolInfoDouble(_Symbol, SYMBOL_POINT) : 0;
    
    if(trade.Sell(InpLotSize, _Symbol, price, sl, tp, InpComment))
    {
        Print("Position SELL ouverte. Ticket: ", trade.ResultOrder(), " | Prix: ", price);
        lastTradeTime = TimeCurrent();
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
    return (CountOpenPositions() > 0);
}

//+------------------------------------------------------------------+
//| Compter le nombre de positions ouvertes                         |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
            {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Obtenir le type de la première position trouvée                 |
//+------------------------------------------------------------------+
ENUM_POSITION_TYPE GetFirstPositionType()
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
            {
                return positionInfo.PositionType();
            }
        }
    }
    return WRONG_VALUE;
}

//+------------------------------------------------------------------+
//| Fermeture de toutes les positions                               |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
            {
                ulong ticket = positionInfo.Ticket();
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

//+------------------------------------------------------------------+
//| Fermeture d'une position spécifique par ticket                  |
//+------------------------------------------------------------------+
bool ClosePositionByTicket(ulong ticket)
{
    if(trade.PositionClose(ticket))
    {
        Print("Position fermée par ticket: ", ticket);
        return true;
    }
    else
    {
        Print("Erreur fermeture position par ticket: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
        return false;
    }
}

//+------------------------------------------------------------------+
//| Modification du Stop Loss et Take Profit d'une position         |
//+------------------------------------------------------------------+
bool ModifyPosition(ulong ticket, double newSL, double newTP)
{
    if(trade.PositionModify(ticket, newSL, newTP))
    {
        Print("Position modifiée. Ticket: ", ticket, " | SL: ", newSL, " | TP: ", newTP);
        return true;
    }
    else
    {
        Print("Erreur modification position: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
        return false;
    }
}

//+------------------------------------------------------------------+
//| Fonction utilitaire pour obtenir des informations sur les positions |
//+------------------------------------------------------------------+
void PrintPositionsInfo()
{
    Print("=== Informations sur les positions ===");
    Print("Nombre de positions ouvertes: ", CountOpenPositions());
    Print("Dernier signal: ", lastSignal);
    Print("Dernier trade: ", TimeToString(lastTradeTime));
    
    // Afficher les détails de chaque position
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
            {
                Print("Position #", positionInfo.Ticket(), 
                      " | Type: ", EnumToString(positionInfo.PositionType()), 
                      " | Volume: ", positionInfo.Volume(),
                      " | Prix: ", positionInfo.PriceOpen(),
                      " | Profit: ", positionInfo.Profit());
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Fonction pour calculer la taille de lot optimale                |
//+------------------------------------------------------------------+
double CalculateOptimalLotSize(double riskPercent = 2.0)
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * riskPercent / 100.0;
    
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double stopLossPoints = InpStopLoss;
    
    if(stopLossPoints <= 0 || tickValue <= 0)
        return InpLotSize;
    
    double lotSize = riskAmount / (stopLossPoints * tickValue);
    
    // Normaliser la taille du lot selon les spécifications du symbole
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathMax(lotSize, minLot);
    lotSize = MathMin(lotSize, maxLot);
    lotSize = NormalizeDouble(lotSize / stepLot, 0) * stepLot;
    
    return lotSize;
}