//+------------------------------------------------------------------+
//|                                      LogReturn_ZScore_Indicator.mq5 |
//|                    Indicateur Log Return avec Z-Score et Signaux   |
//|                         Affichage visuel pour analyse graphique    |
//+------------------------------------------------------------------+
#property copyright "LogReturn ZScore Indicator"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 6
#property indicator_plots   4

// Paramètres d'affichage
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDeepSkyBlue
#property indicator_width1  2
#property indicator_label1  "LogReturn/ZScore"

#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_width2  1
#property indicator_style2  STYLE_DOT
#property indicator_label2  "Seuil Haut"

#property indicator_type3   DRAW_LINE
#property indicator_color3  clrRed
#property indicator_width3  1
#property indicator_style3  STYLE_DOT
#property indicator_label3  "Seuil Bas"

#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrLime
#property indicator_width4  3
#property indicator_label4  "Signaux BUY"

// Paramètres d'entrée
input ENUM_APPLIED_PRICE InpPrice = PRICE_CLOSE;       // Prix utilisé pour le calcul
input int InpShiftPeriod = 1;                          // Période de décalage pour log return
input bool InpUseZScore = true;                        // Afficher Z-Score (sinon Log Return brut)
input int InpLookbackPeriod = 50;                      // Période pour calcul du z-score
input double InpThreshold = 2.0;                       // Seuil pour signaux
input bool InpShowSignals = true;                      // Afficher les flèches de signaux
input bool InpShowThresholds = true;                   // Afficher les lignes de seuil
input color InpBuySignalColor = clrLime;               // Couleur signaux BUY
input color InpSellSignalColor = clrRed;               // Couleur signaux SELL

// Buffers d'indicateur
double MainBuffer[];           // Buffer principal (LogReturn ou ZScore)
double UpperThresholdBuffer[]; // Seuil supérieur
double LowerThresholdBuffer[]; // Seuil inférieur
double SignalBuffer[];         // Buffer pour les signaux (flèches)
double LogReturnBuffer[];      // Buffer interne pour log returns
double WorkBuffer[];           // Buffer de travail

// Variables globales
int barsCalculated = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                          |
//+------------------------------------------------------------------+
int OnInit()
{
    // Mapping des buffers
    SetIndexBuffer(0, MainBuffer, INDICATOR_DATA);
    SetIndexBuffer(1, UpperThresholdBuffer, INDICATOR_DATA);
    SetIndexBuffer(2, LowerThresholdBuffer, INDICATOR_DATA);
    SetIndexBuffer(3, SignalBuffer, INDICATOR_DATA);
    SetIndexBuffer(4, LogReturnBuffer, INDICATOR_CALCULATIONS);
    SetIndexBuffer(5, WorkBuffer, INDICATOR_CALCULATIONS);
    
    // Configuration des flèches pour les signaux
    PlotIndexSetInteger(3, PLOT_ARROW, 233);  // Code flèche
    
    // Configuration des labels
    string mode = InpUseZScore ? "Z-Score" : "LogReturn";
    string indicatorName = StringFormat("LogReturn %s (Période=%d, Seuil=%.2f)", 
                                       mode, InpLookbackPeriod, InpThreshold);
    IndicatorSetString(INDICATOR_SHORTNAME, indicatorName);
    
    PlotIndexSetString(0, PLOT_LABEL, mode);
    PlotIndexSetString(1, PLOT_LABEL, "Seuil +" + DoubleToString(InpThreshold, 2));
    PlotIndexSetString(2, PLOT_LABEL, "Seuil -" + DoubleToString(InpThreshold, 2));
    PlotIndexSetString(3, PLOT_LABEL, "Signaux");
    
    // Configuration des couleurs
    PlotIndexSetInteger(3, PLOT_LINE_COLOR, InpBuySignalColor);
    
    // Masquer les seuils si non souhaités
    if(!InpShowThresholds)
    {
        PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_NONE);
        PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_NONE);
    }
    
    // Masquer les signaux si non souhaités
    if(!InpShowSignals)
    {
        PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_NONE);
    }
    
    // Définir les arrays comme séries temporelles
    ArraySetAsSeries(MainBuffer, true);
    ArraySetAsSeries(UpperThresholdBuffer, true);
    ArraySetAsSeries(LowerThresholdBuffer, true);
    ArraySetAsSeries(SignalBuffer, true);
    ArraySetAsSeries(LogReturnBuffer, true);
    ArraySetAsSeries(WorkBuffer, true);
    
    // Validation des paramètres
    if(InpLookbackPeriod <= InpShiftPeriod)
    {
        Print("Erreur: Période lookback doit être > période shift");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    if(InpThreshold <= 0)
    {
        Print("Erreur: Seuil doit être positif");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    Print("Indicateur LogReturn/ZScore initialisé - Mode: ", mode);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Obtenir le prix selon le type spécifié                         |
//+------------------------------------------------------------------+
double GetPriceValue(int index, 
                     ENUM_APPLIED_PRICE priceType,
                     const double &open[],
                     const double &high[],
                     const double &low[],
                     const double &close[])
{
    switch(priceType)
    {
        case PRICE_OPEN:     return open[index];
        case PRICE_HIGH:     return high[index];
        case PRICE_LOW:      return low[index];
        case PRICE_CLOSE:    return close[index];
        case PRICE_MEDIAN:   return (high[index] + low[index]) / 2.0;
        case PRICE_TYPICAL:  return (high[index] + low[index] + close[index]) / 3.0;
        case PRICE_WEIGHTED: return (high[index] + low[index] + 2 * close[index]) / 4.0;
        default:             return close[index];
    }
}

//+------------------------------------------------------------------+
//| Calcul du Z-Score                                               |
//+------------------------------------------------------------------+
double CalculateZScore(int index, int rates_total)
{
    if(index + InpLookbackPeriod >= rates_total)
        return 0.0;
    
    // Calculer la moyenne des log returns sur la période lookback
    double sum = 0.0;
    int validPoints = 0;
    
    for(int i = index + 1; i <= index + InpLookbackPeriod && i < rates_total; i++)
    {
        sum += LogReturnBuffer[i];
        validPoints++;
    }
    
    if(validPoints < InpLookbackPeriod / 2) // Au moins la moitié des points requis
        return 0.0;
    
    double mean = sum / validPoints;
    
    // Calculer l'écart-type
    double sumSquares = 0.0;
    for(int i = index + 1; i <= index + InpLookbackPeriod && i < rates_total; i++)
    {
        double diff = LogReturnBuffer[i] - mean;
        sumSquares += diff * diff;
    }
    
    double variance = sumSquares / validPoints;
    double stdDev = MathSqrt(variance);
    
    if(stdDev == 0.0)
        return 0.0;
    
    // Calculer le z-score du log return actuel
    double zScore = (LogReturnBuffer[index] - mean) / stdDev;
    
    return zScore;
}

//+------------------------------------------------------------------+
//| Détection des signaux de trading                                |
//+------------------------------------------------------------------+
int DetectSignal(double value, double previousValue)
{
    // Signal d'achat : valeur passe sous le seuil bas
    if(value < -InpThreshold && previousValue >= -InpThreshold)
        return 1; // Signal BUY
    
    // Signal de vente : valeur passe au-dessus du seuil haut
    if(value > InpThreshold && previousValue <= InpThreshold)
        return -1; // Signal SELL
    
    return 0; // Pas de signal
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                               |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    // Vérifier qu'on a assez de barres
    if(rates_total <= InpShiftPeriod + InpLookbackPeriod)
        return 0;
    
    // Déterminer la position de début pour le calcul
    int start = prev_calculated;
    if(start == 0)
        start = InpShiftPeriod;
    else
        start = prev_calculated - 1;
    
    // Calculer les log returns d'abord
    for(int i = start; i < rates_total; i++)
    {
        if(i < InpShiftPeriod)
        {
            LogReturnBuffer[i] = 0.0;
            continue;
        }
        
        double priceCurrent = GetPriceValue(i, InpPrice, open, high, low, close);
        double pricePrevious = GetPriceValue(i - InpShiftPeriod, InpPrice, open, high, low, close);
        
        if(priceCurrent > 0.0 && pricePrevious > 0.0)
        {
            LogReturnBuffer[i] = MathLog(priceCurrent / pricePrevious);
        }
        else
        {
            LogReturnBuffer[i] = 0.0;
        }
    }
    
    // Calculer le buffer principal (ZScore ou LogReturn)
    for(int i = start; i < rates_total; i++)
    {
        if(InpUseZScore)
        {
            // Mode Z-Score
            MainBuffer[i] = CalculateZScore(i, rates_total);
            
            // Seuils fixes pour z-score
            UpperThresholdBuffer[i] = InpThreshold;
            LowerThresholdBuffer[i] = -InpThreshold;
        }
        else
        {
            // Mode Log Return brut
            MainBuffer[i] = LogReturnBuffer[i];
            
            // Seuils adaptatifs pour log return (basés sur le seuil z-score converti)
            double adaptiveThreshold = InpThreshold * 0.01; // Conversion approximative
            UpperThresholdBuffer[i] = adaptiveThreshold;
            LowerThresholdBuffer[i] = -adaptiveThreshold;
        }
        
        // Initialiser le buffer de signaux
        SignalBuffer[i] = EMPTY_VALUE;
    }
    
    // Détecter et afficher les signaux
    if(InpShowSignals)
    {
        for(int i = start + 1; i < rates_total; i++)
        {
            double currentValue = MainBuffer[i];
            double previousValue = MainBuffer[i - 1];
            
            int signal = DetectSignal(currentValue, previousValue);
            
            if(signal == 1) // Signal BUY
            {
                SignalBuffer[i] = LowerThresholdBuffer[i] - (InpUseZScore ? 0.5 : 0.005);
                // Changer la couleur pour les signaux BUY
                PlotIndexSetInteger(3, PLOT_LINE_COLOR, InpBuySignalColor);
            }
            else if(signal == -1) // Signal SELL
            {
                SignalBuffer[i] = UpperThresholdBuffer[i] + (InpUseZScore ? 0.5 : 0.005);
                // Changer la couleur pour les signaux SELL
                PlotIndexSetInteger(3, PLOT_LINE_COLOR, InpSellSignalColor);
            }
        }
    }
    
    barsCalculated = rates_total;
    return(rates_total);
}

//+------------------------------------------------------------------+
//| Fonction pour obtenir la valeur actuelle (utile pour EA)        |
//+------------------------------------------------------------------+
double GetCurrentValue()
{
    return MainBuffer[0];
}

//+------------------------------------------------------------------+
//| Fonction pour obtenir le dernier signal (utile pour EA)         |
//+------------------------------------------------------------------+
int GetLastSignal()
{
    if(SignalBuffer[0] != EMPTY_VALUE)
    {
        if(SignalBuffer[0] < 0)
            return 1; // Signal BUY
        else
            return -1; // Signal SELL
    }
    return 0; // Pas de signal
}

//+------------------------------------------------------------------+
//| Fonction d'information sur l'indicateur                         |
//+------------------------------------------------------------------+
void PrintIndicatorInfo()
{
    string mode = InpUseZScore ? "Z-Score" : "LogReturn";
    Print("=== LogReturn Indicator Info ===");
    Print("Mode: ", mode);
    Print("Période Lookback: ", InpLookbackPeriod);
    Print("Seuil: ", InpThreshold);
    Print("Valeur actuelle: ", DoubleToString(MainBuffer[0], InpUseZScore ? 4 : 6));
    Print("Dernier signal: ", GetLastSignal());
}