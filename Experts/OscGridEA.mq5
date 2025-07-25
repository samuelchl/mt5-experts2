//+------------------------------------------------------------------+
//|                                           OscillatingGridEA.mq5 |
//|                                      Copyright 2025, Gemini |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Gemini"
#property version   "1.00"

#include <OscillatingGridManager.mqh>

// --- Paramètres de l'EA ---
input ulong  InpMagicNumber = 12345;      // Numéro Magique
input double InpLotSize = 0.01;           // Taille de lot
input int    InpGridStepPoints = 100;     // Écart de la grille en points (ex: 100 pour 10 pips)
input int    InpMaxOpenTrades = 5;        // Nombre max de trades ouverts

OscillatingGridManager *grid; // Pointeur vers notre gestionnaire

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Crée une instance de notre gestionnaire de grille
    grid = new OscillatingGridManager(InpMagicNumber, InpLotSize, InpGridStepPoints, InpMaxOpenTrades);
    
    // Démarre la grille
    grid.Start();
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Si la raison de l'arrêt est que l'utilisateur retire l'EA du graphique,
    // on nettoie les ordres et positions.
    if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE)
    {
        grid.Stop();
    }
    
    // Libère la mémoire
    delete grid;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Met à jour la grille (gère les ordres en attente)
    grid.Update();
}