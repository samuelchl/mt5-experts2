//+------------------------------------------------------------------+
//|                                         Multi_Asset_Correlation_EA.mq5 |
//|                                                                  |
//|                Expert Advisor Multi-Devises avec Corrélations   |
//+------------------------------------------------------------------+
#property copyright "Multi Asset Correlation EA"
#property version   "1.00"

// Inclure les classes nécessaires
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

// Paramètres d'entrée
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15;    // Timeframe de travail
input double InpRiskPercent = 1.0;                  // Risque global en %
input double InpStopLoss = 50.0;                    // Stop Loss en points
input double InpTakeProfit = 100.0;                 // Take Profit en points
input ulong InpMagicNumber = 99999;                 // Numéro magique unique
input string InpComment = "MultiAsset_EA";          // Commentaire des ordres
input bool InpEnableTrading = true;                 // Activer/désactiver le trading
input double InpProfitTarget = 5.0;                 // Objectif de profit global en %
input double InpDrawdownLimit = 2.0;                // Limite de drawdown en %
input int InpRSIPeriod = 14;                        // Période RSI
input double InpRSIOverbought = 70.0;               // Niveau RSI surachat
input double InpRSIOversold = 30.0;                 // Niveau RSI survente
input int InpDXYPeriod = 14;                        // Période pour analyse DXY

// Objets pour le trading
CTrade trade;
CPositionInfo positionInfo;
COrderInfo orderInfo;

// Structure pour les corrélations (stockage permanent)
struct Correlation
{
   string symbol1;
   string symbol2;
   double value;
};

// Données de corrélation stockées en dur (à modifier manuellement)
#define CORRELATION_COUNT 30
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

// Paires de devises surveillées
string watchedSymbols[6] = {"EURUSD", "USDCHF", "USDCAD", "NZDUSD", "EURCHF", "NZDCAD"};

// Structure pour les données de marché
struct MarketData
{
   double close;
   double rsi;
   double dxyCorrelation;
   int signal; // 1=Buy, -1=Sell, 0=None
};

MarketData marketData[6];

// Variables globales
double initialBalance;
double peakEquity;
datetime lastAnalysisTime = 0;
int dxyHandle = INVALID_HANDLE;
int rsiHandles[6];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("EA Multi-Asset Correlation initialisé");
    
    // Configuration de l'objet trade
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(3);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    // Initialisation des variables
    initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    peakEquity = initialBalance;
    
    // Initialisation des handles RSI pour chaque paire
    for(int i = 0; i < 6; i++)
    {
        rsiHandles[i] = iRSI(watchedSymbols[i], InpTimeframe, InpRSIPeriod, PRICE_CLOSE);
        if(rsiHandles[i] == INVALID_HANDLE)
        {
            Print("Erreur création handle RSI pour ", watchedSymbols[i]);
            return(INIT_FAILED);
        }
    }
    
    // Validation des paramètres
    if(!ValidateParameters())
        return(INIT_PARAMETERS_INCORRECT);
    
    Print("Configuration:");
    Print("- Risque global: ", InpRiskPercent, "%");
    Print("- Objectif profit: ", InpProfitTarget, "%");
    Print("- Limite drawdown: ", InpDrawdownLimit, "%");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("EA désactivé. Raison: ", reason);
    
    // Nettoyage des handles
    for(int i = 0; i < 6; i++)
    {
        if(rsiHandles[i] != INVALID_HANDLE)
            IndicatorRelease(rsiHandles[i]);
    }
    
    if(dxyHandle != INVALID_HANDLE)
        IndicatorRelease(dxyHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!InpEnableTrading)
        return;
    
    // Analyse seulement à chaque nouvelle barre
    if(!IsNewBar())
        return;
    
    // Mise à jour des données de marché
    UpdateAllMarketData();
    
    // Surveillance de l'equity global
    MonitorGlobalEquity();
    
    // Analyse des signaux de trading
    AnalyzeMultiAssetSignals();
    
    // Exécution des trades
    ExecuteMultiAssetStrategy();
}

//+------------------------------------------------------------------+
//| Validation des paramètres                                       |
//+------------------------------------------------------------------+
bool ValidateParameters()
{
    if(InpRiskPercent <= 0 || InpRiskPercent > 10)
    {
        Print("Erreur: Risque invalide (0-10%): ", InpRiskPercent);
        return false;
    }
    
    if(InpProfitTarget <= 0)
    {
        Print("Erreur: Objectif profit invalide: ", InpProfitTarget);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Détection nouvelle barre                                        |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    datetime currentTime = iTime(_Symbol, InpTimeframe, 0);
    if(currentTime != lastAnalysisTime)
    {
        lastAnalysisTime = currentTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Mise à jour de toutes les données de marché                     |
//+------------------------------------------------------------------+
void UpdateAllMarketData()
{
    for(int i = 0; i < 6; i++)
    {
        string symbol = watchedSymbols[i];
        
        // Prix de clôture actuel
        marketData[i].close = iClose(symbol, InpTimeframe, 0);
        
        // RSI
        double rsiArray[1];
        if(CopyBuffer(rsiHandles[i], 0, 0, 1, rsiArray) > 0)
        {
            marketData[i].rsi = rsiArray[0];
        }
        
        // Corrélation avec DXY (simulée basée sur les corrélations historiques)
        marketData[i].dxyCorrelation = GetDXYCorrelation(symbol);
        
        // Initialiser signal
        marketData[i].signal = 0;
    }
}

//+------------------------------------------------------------------+
//| Obtenir la corrélation DXY pour un symbole                      |
//+------------------------------------------------------------------+
double GetDXYCorrelation(string symbol)
{
    // Corrélations approximatives avec DXY
    if(symbol == "EURUSD") return -0.85;
    if(symbol == "USDCHF") return 0.75;
    if(symbol == "USDCAD") return 0.70;
    if(symbol == "NZDUSD") return -0.80;
    if(symbol == "EURCHF") return -0.15;
    if(symbol == "NZDCAD") return -0.60;
    
    return 0.0;
}

//+------------------------------------------------------------------+
//| Surveillance de l'equity global                                 |
//+------------------------------------------------------------------+
void MonitorGlobalEquity()
{
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    // Mettre à jour le pic d'equity
    if(currentEquity > peakEquity)
        peakEquity = currentEquity;
    
    // Calculer les pourcentages
    double profitPercent = (currentEquity - initialBalance) / initialBalance * 100.0;
    double drawdownPercent = (peakEquity - currentEquity) / peakEquity * 100.0;
    
    Print("Equity: ", currentEquity, " | Profit: ", DoubleToString(profitPercent, 2), "% | DD: ", DoubleToString(drawdownPercent, 2), "%");
    
    // Fermer toutes les positions si objectif atteint ou drawdown dépassé
    if(profitPercent >= InpProfitTarget)
    {
        Print("OBJECTIF DE PROFIT ATTEINT: ", profitPercent, "% - Fermeture de toutes les positions");
        CloseAllMultiAssetPositions();
        peakEquity = currentEquity; // Reset du pic
    }
    else if(drawdownPercent >= InpDrawdownLimit)
    {
        Print("LIMITE DE DRAWDOWN ATTEINTE: ", drawdownPercent, "% - Fermeture de toutes les positions");
        CloseAllMultiAssetPositions();
    }
}

//+------------------------------------------------------------------+
//| Analyse des signaux multi-devises                               |
//+------------------------------------------------------------------+
void AnalyzeMultiAssetSignals()
{
    // Analyser l'indice DXY (simulé par USD strength)
    double usdStrength = CalculateUSDStrength();
    
    for(int i = 0; i < 6; i++)
    {
        string symbol = watchedSymbols[i];
        double rsi = marketData[i].rsi;
        double dxyCorr = marketData[i].dxyCorrelation;
        
        // Logique de signal basée sur RSI et corrélation DXY
        bool isUSDPositive = (usdStrength > 0);
        bool isRSIOversold = (rsi < InpRSIOversold);
        bool isRSIOverbought = (rsi > InpRSIOverbought);
        
        // Signal d'achat
        if(isRSIOversold)
        {
            if((dxyCorr < 0 && isUSDPositive) || (dxyCorr > 0 && !isUSDPositive))
            {
                marketData[i].signal = 1; // BUY
            }
        }
        // Signal de vente
        else if(isRSIOverbought)
        {
            if((dxyCorr < 0 && !isUSDPositive) || (dxyCorr > 0 && isUSDPositive))
            {
                marketData[i].signal = -1; // SELL
            }
        }
        
        if(marketData[i].signal != 0)
        {
            Print("Signal ", symbol, ": ", marketData[i].signal, " | RSI: ", DoubleToString(rsi, 2), " | USD Strength: ", DoubleToString(usdStrength, 4));
        }
    }
}

//+------------------------------------------------------------------+
//| Calculer la force USD (simulée)                                 |
//+------------------------------------------------------------------+
double CalculateUSDStrength()
{
    // Calcul simple basé sur les mouvements des paires USD
    double usdSum = 0;
    int usdCount = 0;
    
    // USDCHF et USDCAD (USD en base)
    double usdchfChange = (iClose("USDCHF", InpTimeframe, 0) - iClose("USDCHF", InpTimeframe, 1)) / iClose("USDCHF", InpTimeframe, 1);
    double usdcadChange = (iClose("USDCAD", InpTimeframe, 0) - iClose("USDCAD", InpTimeframe, 1)) / iClose("USDCAD", InpTimeframe, 1);
    
    usdSum += usdchfChange + usdcadChange;
    usdCount += 2;
    
    // EURUSD et NZDUSD (USD en quote) - inverser le signe
    double eurusdChange = (iClose("EURUSD", InpTimeframe, 0) - iClose("EURUSD", InpTimeframe, 1)) / iClose("EURUSD", InpTimeframe, 1);
    double nzdusdChange = (iClose("NZDUSD", InpTimeframe, 0) - iClose("NZDUSD", InpTimeframe, 1)) / iClose("NZDUSD", InpTimeframe, 1);
    
    usdSum -= (eurusdChange + nzdusdChange);
    usdCount += 2;
    
    return (usdCount > 0) ? usdSum / usdCount : 0.0;
}

//+------------------------------------------------------------------+
//| Exécution de la stratégie multi-devises                         |
//+------------------------------------------------------------------+
void ExecuteMultiAssetStrategy()
{
    // Vérifier le risque global avant d'ouvrir de nouvelles positions
    if(!CanOpenNewPositions())
        return;
    
    // Parcourir tous les signaux
    for(int i = 0; i < 6; i++)
    {
        string symbol = watchedSymbols[i];
        int signal = marketData[i].signal;
        
        if(signal == 0)
            continue;
        
        // Vérifier si on a déjà une position sur ce symbole
        if(HasPositionOnSymbol(symbol))
            continue;
        
        // Calculer la taille de lot pour ce symbole
        double lotSize = CalculateSymbolLotSize(symbol);
        
        if(signal == 1) // BUY Signal
        {
            OpenPositionOnSymbol(symbol, ORDER_TYPE_BUY, lotSize);
        }
        else if(signal == -1) // SELL Signal
        {
            OpenPositionOnSymbol(symbol, ORDER_TYPE_SELL, lotSize);
        }
    }
}

//+------------------------------------------------------------------+
//| Vérifier si on peut ouvrir de nouvelles positions               |
//+------------------------------------------------------------------+
bool CanOpenNewPositions()
{
    // Calculer le risque actuel
    double currentRisk = CalculateCurrentRisk();
    double maxRisk = InpRiskPercent;
    
    if(currentRisk >= maxRisk)
    {
        Print("Risque maximum atteint: ", DoubleToString(currentRisk, 2), "%");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculer le risque actuel                                       |
//+------------------------------------------------------------------+
double CalculateCurrentRisk()
{
    double totalRisk = 0;
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Magic() == InpMagicNumber)
            {
                double positionRisk = MathAbs(positionInfo.PriceOpen() - positionInfo.StopLoss()) * 
                                     positionInfo.Volume() * 
                                     SymbolInfoDouble(positionInfo.Symbol(), SYMBOL_TRADE_TICK_VALUE);
                totalRisk += positionRisk;
            }
        }
    }
    
    return (totalRisk / accountBalance) * 100.0;
}

//+------------------------------------------------------------------+
//| Vérifier si on a une position sur un symbole                    |
//+------------------------------------------------------------------+
bool HasPositionOnSymbol(string symbol)
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == symbol && positionInfo.Magic() == InpMagicNumber)
                return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Calculer la taille de lot pour un symbole                       |
//+------------------------------------------------------------------+
double CalculateSymbolLotSize(string symbol)
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * (InpRiskPercent / 6.0) / 100.0; // Diviser le risque par 6 symboles
    
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double stopLossPoints = InpStopLoss;
    
    if(stopLossPoints <= 0 || tickValue <= 0)
        return 0.01;
    
    double lotSize = riskAmount / (stopLossPoints * tickValue);
    
    // Normaliser selon les spécifications du symbole
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathMax(lotSize, minLot);
    lotSize = MathMin(lotSize, maxLot);
    lotSize = NormalizeDouble(lotSize / stepLot, 0) * stepLot;
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Ouvrir une position sur un symbole spécifique                   |
//+------------------------------------------------------------------+
void OpenPositionOnSymbol(string symbol, ENUM_ORDER_TYPE orderType, double lotSize)
{
    double price, sl, tp;
    
    if(orderType == ORDER_TYPE_BUY)
    {
        price = SymbolInfoDouble(symbol, SYMBOL_ASK);
        sl = (InpStopLoss > 0) ? price - InpStopLoss * SymbolInfoDouble(symbol, SYMBOL_POINT) : 0;
        tp = (InpTakeProfit > 0) ? price + InpTakeProfit * SymbolInfoDouble(symbol, SYMBOL_POINT) : 0;
        
        if(trade.Buy(lotSize, symbol, price, sl, tp, InpComment))
        {
            Print("BUY ", symbol, " ouvert. Lot: ", lotSize, " Prix: ", price);
        }
    }
    else if(orderType == ORDER_TYPE_SELL)
    {
        price = SymbolInfoDouble(symbol, SYMBOL_BID);
        sl = (InpStopLoss > 0) ? price + InpStopLoss * SymbolInfoDouble(symbol, SYMBOL_POINT) : 0;
        tp = (InpTakeProfit > 0) ? price - InpTakeProfit * SymbolInfoDouble(symbol, SYMBOL_POINT) : 0;
        
        if(trade.Sell(lotSize, symbol, price, sl, tp, InpComment))
        {
            Print("SELL ", symbol, " ouvert. Lot: ", lotSize, " Prix: ", price);
        }
    }
}

//+------------------------------------------------------------------+
//| Fermer toutes les positions multi-devises                       |
//+------------------------------------------------------------------+
void CloseAllMultiAssetPositions()
{
    Print("=== FERMETURE DE TOUTES LES POSITIONS ===");
    
    int closedCount = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Magic() == InpMagicNumber)
            {
                ulong ticket = positionInfo.Ticket();
                string symbol = positionInfo.Symbol();
                
                if(trade.PositionClose(ticket))
                {
                    Print("Position fermée: ", symbol, " Ticket: ", ticket);
                    closedCount++;
                }
                else
                {
                    Print("Erreur fermeture ", symbol, ": ", trade.ResultRetcode());
                }
            }
        }
    }
    
    Print("Total positions fermées: ", closedCount);
    
    // Reset des variables
    if(closedCount > 0)
    {
        double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        initialBalance = currentEquity; // Nouveau point de départ
        peakEquity = currentEquity;
    }
}

//+------------------------------------------------------------------+
//| Afficher les statistiques                                       |
//+------------------------------------------------------------------+
void PrintMultiAssetStats()
{
    Print("=== STATISTIQUES MULTI-DEVISES ===");
    
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double profitPercent = (currentEquity - initialBalance) / initialBalance * 100.0;
    double currentRisk = CalculateCurrentRisk();
    
    Print("Balance initiale: ", initialBalance);
    Print("Equity actuelle: ", currentEquity);
    Print("Profit global: ", DoubleToString(profitPercent, 2), "%");
    Print("Risque actuel: ", DoubleToString(currentRisk, 2), "%");
    Print("Pic equity: ", peakEquity);
    
    // Statistiques par symbole
    for(int i = 0; i < 6; i++)
    {
        string symbol = watchedSymbols[i];
        bool hasPos = HasPositionOnSymbol(symbol);
        double rsi = marketData[i].rsi;
        
        Print(symbol, " | Position: ", (hasPos ? "OUI" : "NON"), " | RSI: ", DoubleToString(rsi, 2));
    }
}

//+------------------------------------------------------------------+
//| Obtenir la corrélation entre deux symboles                      |
//+------------------------------------------------------------------+
double GetCorrelation(string symbol1, string symbol2)
{
    for(int i = 0; i < CORRELATION_COUNT; i++)
    {
        if(correlations[i].symbol1 == symbol1 && correlations[i].symbol2 == symbol2)
        {
            return correlations[i].value;
        }
    }
    return 0.0; // Aucune corrélation trouvée
}