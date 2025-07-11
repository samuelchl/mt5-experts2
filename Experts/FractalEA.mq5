//+------------------------------------------------------------------+
//|                                            Fractal_EA.mq5         |
//|                                                                  |
//|                    EA basé sur les fractals, moyennes mobiles    |
//|                    et gestion des sessions de trading            |
//+------------------------------------------------------------------+
#property copyright "Fractal EA MQL5"
#property version   "1.00"

// Inclure les classes nécessaires
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--------------------------------------------------------------------
// Énumération pour les sessions de trading
enum ENUM_TRADING_SESSION
{
    SESSION_NONE   = 0,      // Aucune session
    SESSION_ASIA   = 1,      // Session Asiatique
    SESSION_LONDON = 2,      // Session de Londres
    SESSION_NY     = 3,      // Session de New York
    SESSION_ALL    = 4       // Toutes les sessions
};

//--------------------------------------------------------------------
// Paramètres d'entrée génériques
input ENUM_TIMEFRAMES   InpTimeframe                 = PERIOD_M5;    // Timeframe de travail
input double            InpStopLoss                  = 50.0;        // Stop Loss en points
input double            InpTakeProfit                = 100.0;       // Take Profit en points
input double            InpLotSize                   = 0.1;         // Taille du lot
input ulong             InpMagicNumber               = 12345;       // Numéro magique unique
input string            InpComment                   = "Fractal_EA"; // Commentaire des ordres
input bool              InpEnableTrading             = true;        // Activer/désactiver le trading
input int               InpMaxPositions              = 1;           // Nombre maximum de positions simultanées
input int               InpSlippage                  = 3;           // Slippage autorisé

//--------------------------------------------------------------------
// Paramètres spécifiques aux fractals et MA
input int               InpMAFastPeriod              = 10;          // Période MA rapide
input int               InpMASlowPeriod              = 50;          // Période MA lente
input ENUM_MA_METHOD    InpMAMethod                  = MODE_EMA;    // Méthode de calcul MA
input ENUM_APPLIED_PRICE InpMAPrice                  = PRICE_CLOSE; // Prix appliqué pour MA
input double            InpBreakoutPips              = 5.0;         // Pips de cassure pour validation
input double            InpRejectionPips             = 3.0;         // Pips de rejet pour validation

//--------------------------------------------------------------------
// Paramètres de gestion des risques
input double            InpMaxSpread                 = 3.0;         // Spread maximum autorisé (en pips)
input bool              InpUseRiskManagement         = true;        // Utiliser la gestion du risque
input double            InpRiskPercent               = 2.0;         // Pourcentage de risque par trade
input int               InpMinBarsBetweenTrades      = 5;           // Barres minimum entre trades
input double            InpMinProfitToClose          = 10.0;        // Profit minimum pour fermeture anticipée (en devise de compte)

//--------------------------------------------------------------------
// Paramètres de sessions de trading
input string            InpSessionSeparator          = "=== PARAMÈTRES SESSIONS ===";  // Séparateur
input bool              InpUseSessionFilter          = true;         // Utiliser le filtre de sessions
input ENUM_TRADING_SESSION InpAllowedSessions        = SESSION_ALL;  // Sessions autorisées
input bool              InpTradeAsiaSession          = true;         // Trader pendant la session Asie
input bool              InpTradeLondonSession        = true;         // Trader pendant la session Londres
input bool              InpTradeNYSession            = true;         // Trader pendant la session New York
input bool              InpTradeOverlapOnly          = false;        // Trader uniquement pendant les chevauchements
input bool              InpCloseAtSessionEnd         = false;        // Fermer positions à la fin de session
input bool              InpBreakoutOnSessionOpen     = true;         // Priorité aux cassures à l'ouverture de session
input double            InpSessionVolatilityMultiplier = 1.0;        // Multiplicateur de volatilité par session

// Paramètres horaires des sessions (en heure GMT)
input string            InpAsiaHours                 = "--- Session Asie (GMT) ---";
input int               InpAsiaStartHour             = 23;           // Début session Asie (GMT)
input int               InpAsiaEndHour               = 8;            // Fin session Asie (GMT)
input string            InpLondonHours               = "--- Session Londres (GMT) ---";
input int               InpLondonStartHour           = 7;            // Début session Londres (GMT)
input int               InpLondonEndHour             = 16;           // Fin session Londres (GMT)
input string            InpNYHours                   = "--- Session New York (GMT) ---";
input int               InpNYStartHour               = 12;           // Début session NY (GMT)
input int               InpNYEndHour                 = 21;           // Fin session NY (GMT)

//--------------------------------------------------------------------
// Objets pour le trading
CTrade          trade;
CPositionInfo   positionInfo;
COrderInfo      orderInfo;

//--------------------------------------------------------------------
// Variables globales
int             lastSignal              = 0;        // Dernier signal généré (1=Buy, -1=Sell, 0=None)
datetime        lastTradeTime           = 0;        // Timestamp du dernier trade
datetime        lastBarTime             = 0;        // Timestamp de la dernière barre analysée
int             barsSinceLastTrade      = 0;        // Nombre de barres depuis le dernier trade

ENUM_TRADING_SESSION currentSession      = SESSION_NONE; // Session actuelle
ENUM_TRADING_SESSION previousSession     = SESSION_NONE; // Session précédente
bool            sessionJustOpened       = false;    // Flag pour nouvelle session

//--------------------------------------------------------------------
// Handles des indicateurs
int             fractalHandle;
int             maFastHandle;
int             maSlowHandle;

//--------------------------------------------------------------------
// Structures pour stocker les fractals
struct FractalLevel
{
    double      price;
    datetime    time;
    int         barIndex;
    bool        isValid;
    ENUM_TRADING_SESSION session;  // Session où le fractal a été formé
};

// Arrays pour stocker les 5 derniers fractals
FractalLevel    upperFractals[5];
FractalLevel    lowerFractals[5];

// Arrays pour les données des indicateurs
double          fractalUpBuffer[];
double          fractalDownBuffer[];
double          maFastBuffer[];
double          maSlowBuffer[];

//--------------------------------------------------------------------
// Structure pour les informations de session
struct SessionInfo
{
    string      name;
    int         startHour;
    int         endHour;
    bool        isActive;
    bool        isOverlap;
    double      volatilityFactor;
};

SessionInfo     sessions[3]; // Asia, London, NY

//--------------------------------------------------------------------
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("EA Fractal Trading Strategy avec gestion des sessions initialisé");
    Print("Symbole: ", _Symbol);
    Print("Timeframe: ", EnumToString(InpTimeframe));
    Print("Trading activé: ", InpEnableTrading ? "Oui" : "Non");
    Print("Filtre de sessions: ", InpUseSessionFilter ? "Activé" : "Désactivé");

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

    // Initialisation des sessions
    InitializeSessions();

    // Initialisation des indicateurs
    if(!InitializeIndicators())
    {
        Print("Erreur: Impossible d'initialiser les indicateurs");
        return(INIT_FAILED);
    }

    // Initialisation des arrays de fractals
    InitializeFractalArrays();

    // Configuration des arrays
    ArraySetAsSeries(fractalUpBuffer, true);
    ArraySetAsSeries(fractalDownBuffer, true);
    ArraySetAsSeries(maFastBuffer, true);
    ArraySetAsSeries(maSlowBuffer, true);

    // Affichage des informations des sessions
    PrintSessionsInfo();

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("EA désactivé. Raison: ", reason);

    // Libération des handles
    if(fractalHandle != INVALID_HANDLE)
        IndicatorRelease(fractalHandle);
    if(maFastHandle != INVALID_HANDLE)
        IndicatorRelease(maFastHandle);
    if(maSlowHandle != INVALID_HANDLE)
        IndicatorRelease(maSlowHandle);

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
        
    // Vérifier nouvelle barre
    if(!IsNewBar())
        return;

    // Mettre à jour les informations de session
    UpdateSessionInfo();

    // Vérifier le filtre de session
    if(InpUseSessionFilter && !IsInAllowedSession())
    {
        // Fermer les positions si nécessaire
        if(InpCloseAtSessionEnd && HasOpenPositions())
        {
            CloseAllPositions();
        }
        return;
    }



    // Incrémenter le compteur de barres
    barsSinceLastTrade++;

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
//| Initialisation des sessions de trading                           |
//+------------------------------------------------------------------+
void InitializeSessions()
{
    // Session Asie
    sessions[0].name             = "ASIA";
    sessions[0].startHour        = InpAsiaStartHour;
    sessions[0].endHour          = InpAsiaEndHour;
    sessions[0].isActive         = false;
    sessions[0].isOverlap        = false;
    sessions[0].volatilityFactor = 0.7; // Session généralement moins volatile

    // Session Londres
    sessions[1].name             = "LONDON";
    sessions[1].startHour        = InpLondonStartHour;
    sessions[1].endHour          = InpLondonEndHour;
    sessions[1].isActive         = false;
    sessions[1].isOverlap        = false;
    sessions[1].volatilityFactor = 1.2; // Session très active

    // Session New York
    sessions[2].name             = "NY";
    sessions[2].startHour        = InpNYStartHour;
    sessions[2].endHour          = InpNYEndHour;
    sessions[2].isActive         = false;
    sessions[2].isOverlap        = false;
    sessions[2].volatilityFactor = 1.0; // Session de référence

    Print("Sessions initialisées:");
    Print("ASIA:   ", sessions[0].startHour, ":00 - ", sessions[0].endHour, ":00 GMT");
    Print("LONDON: ", sessions[1].startHour, ":00 - ", sessions[1].endHour, ":00 GMT");
    Print("NY:     ", sessions[2].startHour, ":00 - ", sessions[2].endHour, ":00 GMT");
}

//+------------------------------------------------------------------+
//| Afficher les informations des sessions                            |
//+------------------------------------------------------------------+
void PrintSessionsInfo()
{
    Print("=== Informations des sessions ===");
    for(int i=0; i<3; i++)
    {
        Print(sessions[i].name, ": de ", sessions[i].startHour, ":00 à ", sessions[i].endHour, ":00 GMT | Volatilité x", sessions[i].volatilityFactor);
    }
}

//+------------------------------------------------------------------+
//| Mise à jour des informations de session                           |
//+------------------------------------------------------------------+
void UpdateSessionInfo()
{
    previousSession = currentSession;
    currentSession  = GetCurrentSession();

    // Détecter l'ouverture d'une nouvelle session
    if(currentSession != previousSession && currentSession != SESSION_NONE)
    {
        sessionJustOpened = true;
        Print("Nouvelle session active: ", GetSessionName(currentSession));

        // Cas spécial pour la priorité aux cassures à l'ouverture
        if(InpBreakoutOnSessionOpen)
        {
            Print("Mode cassure prioritaire activé pour la session: ", GetSessionName(currentSession));
        }
    }
    else
    {
        sessionJustOpened = false;
    }

    // Mettre à jour le statut de toutes les sessions
    UpdateSessionsStatus();
}

//+------------------------------------------------------------------+
//| Mise à jour du statut de toutes les sessions                      |
//+------------------------------------------------------------------+
void UpdateSessionsStatus()
{
    MqlDateTime timeStruct;
    TimeToStruct(TimeGMT(), timeStruct);
    int currentHour = timeStruct.hour;

    // Vérifier chaque session pour l'activité
    for(int i = 0; i < 3; i++)
    {
        sessions[i].isActive = IsHourInSession(currentHour, sessions[i].startHour, sessions[i].endHour);
    }

    // Détecter les chevauchements
    sessions[0].isOverlap = sessions[0].isActive && (sessions[1].isActive || sessions[2].isActive); // Asie chevauche Londres/NY
    sessions[1].isOverlap = sessions[1].isActive && sessions[2].isActive;                           // Londres chevauche NY
    sessions[2].isOverlap = sessions[2].isActive && sessions[1].isActive;                           // NY chevauche Londres
}

//+------------------------------------------------------------------+
//| Obtenir la session courante                                       |
//+------------------------------------------------------------------+
ENUM_TRADING_SESSION GetCurrentSession()
{
    MqlDateTime timeStruct;
    TimeToStruct(TimeGMT(), timeStruct);
    int hour = timeStruct.hour;

    // Si on ne trade qu'en chevauchement
    if(InpTradeOverlapOnly)
    {
        // Priorité chevauchement Londres-NY
        if(IsHourInSession(hour, InpLondonStartHour, InpLondonEndHour) &&
           IsHourInSession(hour, InpNYStartHour, InpNYEndHour))
        {
            return SESSION_LONDON; // Priorité à Londres pendant chevauchement
        }
        // Chevauchement Asie-Londres
        if(IsHourInSession(hour, InpAsiaStartHour, InpAsiaEndHour) &&
           IsHourInSession(hour, InpLondonStartHour, InpLondonEndHour))
        {
            return SESSION_LONDON;
        }
        return SESSION_NONE;
    }

    // Sessions individuelles (ordre de priorité)
    if(InpTradeLondonSession && IsHourInSession(hour, InpLondonStartHour, InpLondonEndHour))
        return SESSION_LONDON;
    if(InpTradeNYSession && IsHourInSession(hour, InpNYStartHour, InpNYEndHour))
        return SESSION_NY;
    if(InpTradeAsiaSession && IsHourInSession(hour, InpAsiaStartHour, InpAsiaEndHour))
        return SESSION_ASIA;

    return SESSION_NONE;
}

//+------------------------------------------------------------------+
//| Vérifier si une heure est dans une session                        |
//+------------------------------------------------------------------+
bool IsHourInSession(int hour, int startHour, int endHour)
{
    if(startHour <= endHour)
    {
        return (hour >= startHour && hour < endHour);
    }
    else // Session traversant minuit
    {
        return (hour >= startHour || hour < endHour);
    }
}

//+------------------------------------------------------------------+
//| Vérifier si nous sommes dans une session autorisée                |
//+------------------------------------------------------------------+
bool IsInAllowedSession()
{
    if(!InpUseSessionFilter)
        return true;

    ENUM_TRADING_SESSION sess = GetCurrentSession();
    if(sess == SESSION_NONE)
        return false;

    switch(InpAllowedSessions)
    {
        case SESSION_ALL:    return true;
        case SESSION_ASIA:   return (sess == SESSION_ASIA);
        case SESSION_LONDON: return (sess == SESSION_LONDON);
        case SESSION_NY:     return (sess == SESSION_NY);
        default:             return false;
    }
}

//+------------------------------------------------------------------+
//| Obtenir le nom de la session                                      |
//+------------------------------------------------------------------+
string GetSessionName(ENUM_TRADING_SESSION session)
{
    switch(session)
    {
        case SESSION_ASIA:   return "ASIA";
        case SESSION_LONDON: return "LONDON";
        case SESSION_NY:     return "NEW YORK";
        case SESSION_ALL:    return "ALL";
        case SESSION_NONE:   return "NONE";
        default:             return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| Obtenir le facteur de volatilité de la session courante          |
//+------------------------------------------------------------------+
double GetCurrentVolatilityFactor()
{
    switch(currentSession)
    {
        case SESSION_ASIA:   return sessions[0].volatilityFactor;
        case SESSION_LONDON: return sessions[1].volatilityFactor;
        case SESSION_NY:     return sessions[2].volatilityFactor;
        default:             return 1.0;
    }
}

//+------------------------------------------------------------------+
//| Obtenir la session à un moment donné                              |
//+------------------------------------------------------------------+
ENUM_TRADING_SESSION GetSessionAtTime(datetime time)
{
    MqlDateTime ts;
    TimeToStruct(time, ts);
    int hour = ts.hour;

    if(IsHourInSession(hour, InpLondonStartHour, InpLondonEndHour))
        return SESSION_LONDON;
    if(IsHourInSession(hour, InpNYStartHour, InpNYEndHour))
        return SESSION_NY;
    if(IsHourInSession(hour, InpAsiaStartHour, InpAsiaEndHour))
        return SESSION_ASIA;
    return SESSION_NONE;
}

//+------------------------------------------------------------------+
//| Validation des paramètres d'entrée                                 |
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
    if(InpMAFastPeriod >= InpMASlowPeriod)
    {
        Print("Erreur: MA rapide doit être inférieure à MA lente");
        return false;
    }
    if(InpMaxSpread <= 0)
    {
        Print("Erreur: Spread maximum invalide: ", InpMaxSpread);
        return false;
    }
    if(InpRiskPercent <= 0 || InpRiskPercent > 100)
    {
        Print("Erreur: Pourcentage de risque invalide: ", InpRiskPercent);
        return false;
    }
    // Validation des heures de sessions
    if(InpAsiaStartHour < 0 || InpAsiaStartHour > 23 || InpAsiaEndHour < 0 || InpAsiaEndHour > 23)
    {
        Print("Erreur: Heures de session Asie invalides");
        return false;
    }
    if(InpLondonStartHour < 0 || InpLondonStartHour > 23 || InpLondonEndHour < 0 || InpLondonEndHour > 23)
    {
        Print("Erreur: Heures de session Londres invalides");
        return false;
    }
    if(InpNYStartHour < 0 || InpNYStartHour > 23 || InpNYEndHour < 0 || InpNYEndHour > 23)
    {
        Print("Erreur: Heures de session NY invalides");
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
//| Initialisation des indicateurs                                    |
//+------------------------------------------------------------------+
bool InitializeIndicators()
{
    // Indicateur Fractal
    fractalHandle = iFractals(_Symbol, InpTimeframe);
    if(fractalHandle == INVALID_HANDLE)
    {
        Print("Erreur création handle Fractal: ", GetLastError());
        return false;
    }

    // MA rapide
    maFastHandle = iMA(_Symbol, InpTimeframe, InpMAFastPeriod, 0, InpMAMethod, InpMAPrice);
    if(maFastHandle == INVALID_HANDLE)
    {
        Print("Erreur création handle MA rapide: ", GetLastError());
        return false;
    }

    // MA lente
    maSlowHandle = iMA(_Symbol, InpTimeframe, InpMASlowPeriod, 0, InpMAMethod, InpMAPrice);
    if(maSlowHandle == INVALID_HANDLE)
    {
        Print("Erreur création handle MA lente: ", GetLastError());
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Initialisation des arrays de fractals                             |
//+------------------------------------------------------------------+
void InitializeFractalArrays()
{
    for(int i = 0; i < 5; i++)
    {
        upperFractals[i].price      = 0;
        upperFractals[i].time       = 0;
        upperFractals[i].barIndex   = -1;
        upperFractals[i].isValid    = false;
        upperFractals[i].session    = SESSION_NONE;

        lowerFractals[i].price      = 0;
        lowerFractals[i].time       = 0;
        lowerFractals[i].barIndex   = -1;
        lowerFractals[i].isValid    = false;
        lowerFractals[i].session    = SESSION_NONE;
    }
}

//+------------------------------------------------------------------+
//| Détection d'une nouvelle barre                                    |
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
//| Mise à jour des données de marché                                 |
//+------------------------------------------------------------------+
void UpdateMarketData()
{
    // Copier les données des indicateurs
    if(CopyBuffer(fractalHandle, 0, 0, 50, fractalUpBuffer) <= 0)
    {
        Print("Erreur copie buffer fractal haut: ", GetLastError());
        return;
    }
    if(CopyBuffer(fractalHandle, 1, 0, 50, fractalDownBuffer) <= 0)
    {
        Print("Erreur copie buffer fractal bas: ", GetLastError());
        return;
    }
    if(CopyBuffer(maFastHandle, 0, 0, 10, maFastBuffer) <= 0)
    {
        Print("Erreur copie buffer MA rapide: ", GetLastError());
        return;
    }
    if(CopyBuffer(maSlowHandle, 0, 0, 10, maSlowBuffer) <= 0)
    {
        Print("Erreur copie buffer MA lente: ", GetLastError());
        return;
    }

    // Mettre à jour les fractals stockés
    UpdateFractals();
}

//+------------------------------------------------------------------+
//| Mise à jour des fractals stockés                                  |
//+------------------------------------------------------------------+
void UpdateFractals()
{
    // Rechercher de nouveaux fractals hauts
    for(int i = 2; i < 47; i++) // Commencer à 2 pour éviter les fractals trop récents
    {
        if(fractalUpBuffer[i] != 0 && fractalUpBuffer[i] != EMPTY_VALUE)
        {
            datetime fractalTime = iTime(_Symbol, InpTimeframe, i);
            if(!IsFractalAlreadyStored(fractalUpBuffer[i], fractalTime, true))
            {
                AddUpperFractal(fractalUpBuffer[i], fractalTime, i);
            }
        }
    }

    // Rechercher de nouveaux fractals bas
    for(int i = 2; i < 47; i++)
    {
        if(fractalDownBuffer[i] != 0 && fractalDownBuffer[i] != EMPTY_VALUE)
        {
            datetime fractalTime = iTime(_Symbol, InpTimeframe, i);
            if(!IsFractalAlreadyStored(fractalDownBuffer[i], fractalTime, false))
            {
                AddLowerFractal(fractalDownBuffer[i], fractalTime, i);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Vérifier si un fractal est déjà stocké                            |
//+------------------------------------------------------------------+
bool IsFractalAlreadyStored(double price, datetime time, bool isUpper)
{
    if(isUpper)
    {
        for(int i = 0; i < 5; i++)
        {
            if(upperFractals[i].isValid && upperFractals[i].time == time)
                return true;
        }
    }
    else
    {
        for(int i = 0; i < 5; i++)
        {
            if(lowerFractals[i].isValid && lowerFractals[i].time == time)
                return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Ajouter un fractal haut                                           |
//+------------------------------------------------------------------+
void AddUpperFractal(double price, datetime time, int barIndex)
{
    // Décaler les anciens fractals
    for(int i = 4; i > 0; i--)
    {
        upperFractals[i] = upperFractals[i-1];
    }

    // Déterminer la session du fractal
    ENUM_TRADING_SESSION fractalSession = GetSessionAtTime(time);

    // Ajouter le nouveau fractal
    upperFractals[0].price       = price;
    upperFractals[0].time        = time;
    upperFractals[0].barIndex    = barIndex;
    upperFractals[0].isValid     = true;
    upperFractals[0].session     = fractalSession;

    Print("Nouveau fractal haut ajouté: ", price,
          " à ", TimeToString(time),
          " (Session: ", GetSessionName(fractalSession), ")");
}

//+------------------------------------------------------------------+
//| Ajouter un fractal bas                                            |
//+------------------------------------------------------------------+
void AddLowerFractal(double price, datetime time, int barIndex)
{
    // Décaler les anciens fractals
    for(int i = 4; i > 0; i--)
    {
        lowerFractals[i] = lowerFractals[i-1];
    }

    // Déterminer la session du fractal
    ENUM_TRADING_SESSION fractalSession = GetSessionAtTime(time);

    // Ajouter le nouveau fractal
    lowerFractals[0].price       = price;
    lowerFractals[0].time        = time;
    lowerFractals[0].barIndex    = barIndex;
    lowerFractals[0].isValid     = true;
    lowerFractals[0].session     = fractalSession;

    Print("Nouveau fractal bas ajouté: ", price,
          " à ", TimeToString(time),
          " (Session: ", GetSessionName(fractalSession), ")");
}

//+------------------------------------------------------------------+
//| Analyse du marché et génération de signaux                        |
//+------------------------------------------------------------------+
void AnalyzeMarket()
{
    // Réinitialiser le signal
    lastSignal = 0;

    double currentPrice  = iClose(_Symbol, InpTimeframe, 0);
    double previousPrice = iClose(_Symbol, InpTimeframe, 1);
    double point         = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

    // Obtenir le facteur de volatilité pour la session courante
    double volatilityFactor = GetCurrentVolatilityFactor() * InpSessionVolatilityMultiplier;

    // Ajuster les seuils selon la session
    double breakoutPips   = InpBreakoutPips * volatilityFactor;
    double rejectionPips  = InpRejectionPips * volatilityFactor;

    // Bonus pour l'ouverture de session
    if(sessionJustOpened && InpBreakoutOnSessionOpen)
    {
        breakoutPips *= 0.7; // Réduire le seuil pour favoriser les cassures
        Print("Seuil de cassure réduit pour ouverture de session: ", breakoutPips, " pips");
    }

    // Vérifier la tendance avec les MA
    bool bullishTrend = (maFastBuffer[0] > maSlowBuffer[0]);
    bool bearishTrend = (maFastBuffer[0] < maSlowBuffer[0]);

    // Analyser les cassures de fractals hauts (résistances)
    for(int i = 0; i < 5; i++)
    {
        if(!upperFractals[i].isValid) continue;

        double resistanceLevel = upperFractals[i].price;
        double breakoutLevel   = resistanceLevel + (breakoutPips * point);
        double rejectionLevel  = resistanceLevel - (rejectionPips * point);

        // Cassure haussière confirmée
        if(previousPrice <= resistanceLevel && currentPrice >= breakoutLevel && bullishTrend)
        {
            lastSignal = 1; // Signal d'achat
            Print("Cassure haussière détectée au niveau: ", resistanceLevel);
            break;
        }

        // Rejet baissier confirmé
        if(previousPrice >= resistanceLevel && currentPrice <= rejectionLevel && bearishTrend)
        {
            lastSignal = -1; // Signal de vente
            Print("Rejet baissier détecté au niveau: ", resistanceLevel);
            break;
        }
    }

    // Analyser les cassures de fractals bas (supports) si aucun signal trouvé
    if(lastSignal == 0)
    {
        for(int i = 0; i < 5; i++)
        {
            if(!lowerFractals[i].isValid) continue;

            double supportLevel  = lowerFractals[i].price;
            double breakoutLevel = supportLevel - (breakoutPips * point);
            double rejectionLevel= supportLevel + (rejectionPips * point);

            // Cassure baissière confirmée
            if(previousPrice >= supportLevel && currentPrice <= breakoutLevel && bearishTrend)
            {
                lastSignal = -1; // Signal de vente
                Print("Cassure baissière détectée au niveau: ", supportLevel);
                break;
            }

            // Rejet haussier confirmé
            if(previousPrice <= supportLevel && currentPrice >= rejectionLevel && bullishTrend)
            {
                lastSignal = 1; // Signal d'achat
                Print("Rejet haussier détecté au niveau: ", supportLevel);
                break;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Gestion des positions existantes                                  |
//+------------------------------------------------------------------+
void ManagePositions()
{
    if(!HasOpenPositions())
        return;

    // Vérifier si on doit fermer des positions rentables
    if(InpMinProfitToClose > 0)
    {
        CheckProfitablePositions();
    }

    // Si signal contraire, fermer les positions
    if(lastSignal != 0)
    {
        ENUM_POSITION_TYPE currentPositionType = GetFirstPositionType();
        if((lastSignal == 1 && currentPositionType == POSITION_TYPE_SELL) ||
           (lastSignal == -1 && currentPositionType == POSITION_TYPE_BUY))
        {
            Print("Signal contraire détecté - Fermeture des positions");
            CloseAllPositions();
        }
    }
}

//+------------------------------------------------------------------+
//| Vérification des positions rentables à fermer                     |
//+------------------------------------------------------------------+
void CheckProfitablePositions()
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
            {
                double profit = positionInfo.Profit() + positionInfo.Swap() + positionInfo.Commission();
                if(profit >= InpMinProfitToClose)
                {
                    ulong ticket = positionInfo.Ticket();
                    if(trade.PositionClose(ticket))
                    {
                        Print("Position fermée pour profit minimum atteint. Ticket: ", ticket, " Profit: ", profit);
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Exécution des signaux de trading                                  |
//+------------------------------------------------------------------+
void ExecuteSignals()
{
    // Vérifier s'il y a de la place pour de nouvelles positions
    if(CountOpenPositions() >= InpMaxPositions)
        return;

    // Vérifier le nombre minimum de barres entre trades
    if(barsSinceLastTrade < InpMinBarsBetweenTrades)
        return;

    // Exécuter les signaux
    if(lastSignal == 1) // Signal d'achat
    {
        if(CanOpenBuy())
            OpenBuyPosition();
    }
    else if(lastSignal == -1) // Signal de vente
    {
        if(CanOpenSell())
            OpenSellPosition();
    }
}

//+------------------------------------------------------------------+
//| Vérification des conditions pour position d'achat                 |
//+------------------------------------------------------------------+
bool CanOpenBuy()
{
    // Vérifier le spread
    double spread   = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double maxSpread= InpMaxSpread * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if(spread > maxSpread)
    {
        Print("Spread trop élevé pour ouvrir position BUY: ", spread / SymbolInfoDouble(_Symbol, SYMBOL_POINT), " pips");
        return false;
    }

    // Vérifier la liquidité
    if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE))
    {
        Print("Trading non autorisé pour ce symbole");
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Vérification des conditions pour position de vente                |
//+------------------------------------------------------------------+
bool CanOpenSell()
{
    // Vérifier le spread
    double spread   = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double maxSpread= InpMaxSpread * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if(spread > maxSpread)
    {
        Print("Spread trop élevé pour ouvrir position SELL: ", spread / SymbolInfoDouble(_Symbol, SYMBOL_POINT), " pips");
        return false;
    }

    // Vérifier la liquidité
    if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE))
    {
        Print("Trading non autorisé pour ce symbole");
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Ouverture d'une position d'achat                                  |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
    double lotSize = InpLotSize;
    // Utiliser la gestion du risque si activée
    if(InpUseRiskManagement)
        lotSize = CalculateOptimalLotSize(InpRiskPercent);

    double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double sl    = (InpStopLoss > 0) ? price - InpStopLoss * SymbolInfoDouble(_Symbol, SYMBOL_POINT) : 0;
    double tp    = (InpTakeProfit > 0) ? price + InpTakeProfit * SymbolInfoDouble(_Symbol, SYMBOL_POINT) : 0;

    if(trade.Buy(lotSize, _Symbol, price, sl, tp, InpComment))
    {
        Print("Position BUY ouverte. Ticket: ", trade.ResultOrder(),
              " | Prix: ", price, " | Lot: ", lotSize);
        lastTradeTime       = TimeCurrent();
        barsSinceLastTrade  = 0;
    }
    else
    {
        Print("Erreur ouverture BUY: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Ouverture d'une position de vente                                 |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
    double lotSize = InpLotSize;
    // Utiliser la gestion du risque si activée
    if(InpUseRiskManagement)
        lotSize = CalculateOptimalLotSize(InpRiskPercent);

    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl    = (InpStopLoss > 0) ? price + InpStopLoss * SymbolInfoDouble(_Symbol, SYMBOL_POINT) : 0;
    double tp    = (InpTakeProfit > 0) ? price - InpTakeProfit * SymbolInfoDouble(_Symbol, SYMBOL_POINT) : 0;

    if(trade.Sell(lotSize, _Symbol, price, sl, tp, InpComment))
    {
        Print("Position SELL ouverte. Ticket: ", trade.ResultOrder(),
              " | Prix: ", price, " | Lot: ", lotSize);
        lastTradeTime       = TimeCurrent();
        barsSinceLastTrade  = 0;
    }
    else
    {
        Print("Erreur ouverture SELL: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Vérification de l'existence de positions ouvertes                 |
//+------------------------------------------------------------------+
bool HasOpenPositions()
{
    return (CountOpenPositions() > 0);
}

//+------------------------------------------------------------------+
//| Compter le nombre de positions ouvertes                           |
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
//| Obtenir le type de la première position trouvée                   |
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
//| Fermeture de toutes les positions                                 |
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
//| Fermeture d'une position spécifique par ticket                    |
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
//| Modification du Stop Loss et Take Profit d'une position           |
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
//| Fonction pour calculer la taille de lot optimale                  |
//+------------------------------------------------------------------+
double CalculateOptimalLotSize(double riskPercent = 2.0)
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount     = accountBalance * riskPercent / 100.0;

    double tickValue      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double stopLossPoints = InpStopLoss;

    if(stopLossPoints <= 0 || tickValue <= 0)
        return InpLotSize;

    double lotSize = riskAmount / (stopLossPoints * tickValue);

    // Normaliser la taille du lot selon les spécifications du symbole
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double stepLot= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    lotSize = MathMax(lotSize, minLot);
    lotSize = MathMin(lotSize, maxLot);
    lotSize = NormalizeDouble(lotSize / stepLot, 0) * stepLot;

    return lotSize;
}
