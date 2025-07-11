//+------------------------------------------------------------------+
//|                                     OscillatingGridManager.mqh |
//|                      Copyright 2025, Gemini (Concept by User) |
//|                                                                  |
//|  Une grille bidirectionnelle qui accompagne le prix avec des   |
//|  ordres en attente pour trader les oscillations.               |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

class OscillatingGridManager
{
private:
    CTrade      m_trade;                // Objet pour le trading
    ulong       m_magic_number;         // Numéro magique pour identifier les ordres
    double      m_lot_size;             // Taille de lot pour chaque trade
    int         m_grid_step_points;     // Écart en points entre chaque ligne de la grille
    int         m_max_open_trades;      // Nombre maximum de trades ouverts en même temps
    double      m_anchor_price;         // Prix de référence pour aligner la grille
    double      m_point_value;          // Valeur d'un point pour le symbole actuel
    string      m_symbol;               // Symbole sur lequel le grid opère
    MqlTick     m_last_tick;            // <-- AJOUT : Déclaration de la variable pour le tick

public:
    // --- Constructeur ---
    OscillatingGridManager(ulong magic, double lots, int step_points, int max_trades)
    {
        m_magic_number = magic;
        m_lot_size = lots;
        m_grid_step_points = step_points;
        m_max_open_trades = max_trades;
        m_symbol = _Symbol;
        m_point_value = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        m_anchor_price = 0; // Sera défini au démarrage
        m_trade.SetExpertMagicNumber(m_magic_number);
        m_trade.SetMarginMode(); // Utilise le mode de calcul de marge par défaut du compte
        m_trade.SetTypeFillingBySymbol(m_symbol); // Adapte le type d'exécution au symbole
    }

    // --- Destructeur ---
    ~OscillatingGridManager() {}

    // --- Méthode pour démarrer la grille ---
    void Start()
    {
        // Si l'ancre n'est pas définie, on la fixe au prix actuel et on place les premiers ordres
        if (m_anchor_price == 0)
        {
            SymbolInfoTick(m_symbol, m_last_tick);
            m_anchor_price = m_last_tick.bid; // On ancre la grille sur le prix actuel
            Print("OscillatingGridManager démarré. Ancrage à ", m_anchor_price);
            Update(); // Place les premiers ordres en attente
        }
    }

    // --- Méthode principale à appeler dans OnTick() ---
    void Update()
    {
        if (m_anchor_price == 0) return; // Ne rien faire si non démarré

        // 1. Nettoyer les anciens ordres en attente qui ne sont plus pertinents
        CleanUpOldPendingOrders();

        // 2. S'assurer que les nouveaux ordres en attente sont en place
        PlacePendingOrders();
    }
    
    // --- Méthode pour tout arrêter et nettoyer ---
    void Stop()
    {
        // Ferme toutes les positions ouvertes par cette grille
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(PositionGetInteger(POSITION_MAGIC) == m_magic_number && PositionGetString(POSITION_SYMBOL) == m_symbol)
            {
                m_trade.PositionClose(ticket);
            }
        }
        
        // Annule tous les ordres en attente
        for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
            ulong ticket = OrderGetTicket(i);
            if(OrderGetInteger(ORDER_MAGIC) == m_magic_number && OrderGetString(ORDER_SYMBOL) == m_symbol)
            {
                m_trade.OrderDelete(ticket);
            }
        }
        Print("OscillatingGridManager arrêté et nettoyé.");
    }


private:
    // --- Placer les ordres en attente autour du prix actuel ---
    void PlacePendingOrders()
    {
        // On ne place pas de nouveaux ordres si on a atteint la limite de trades ouverts
        if(CountOpenPositions() >= m_max_open_trades) return;
    
        MqlTick current_tick;
        SymbolInfoTick(m_symbol, current_tick);

        double lower_line = GetLowerGridLine(current_tick.bid);
        double upper_line = lower_line + m_grid_step_points * m_point_value;

        // Placer un BUY STOP sur la ligne supérieure s'il n'y en a pas déjà un
        if (!HasPendingOrderAt(upper_line, ORDER_TYPE_BUY_STOP))
        {
            double tp = upper_line + m_grid_step_points * m_point_value;
            double sl = lower_line; // Stop Loss sur la ligne précédente
            m_trade.BuyStop(m_lot_size, upper_line, m_symbol, sl, tp);
        }

        // Placer un SELL STOP sur la ligne inférieure s'il n'y en a pas déjà un
        if (!HasPendingOrderAt(lower_line, ORDER_TYPE_SELL_STOP))
        {
            double tp = lower_line - m_grid_step_points * m_point_value;
            double sl = upper_line; // Stop Loss sur la ligne suivante
            m_trade.SellStop(m_lot_size, lower_line, m_symbol, sl, tp);
        }
    }
    
    // --- Nettoie les ordres en attente qui ne sont plus autour du prix ---
    void CleanUpOldPendingOrders()
    {
        MqlTick current_tick;
        SymbolInfoTick(m_symbol, current_tick);

        double lower_line = GetLowerGridLine(current_tick.bid);
        double upper_line = lower_line + m_grid_step_points * m_point_value;

        for (int i = OrdersTotal() - 1; i >= 0; i--)
        {
            ulong ticket = OrderGetTicket(i);
            if (OrderGetInteger(ORDER_MAGIC) == m_magic_number && OrderGetString(ORDER_SYMBOL) == m_symbol)
            {
                double order_price = OrderGetDouble(ORDER_PRICE_OPEN);
                long order_type = OrderGetInteger(ORDER_TYPE);

                // Si c'est un ordre BUY STOP qui n'est pas sur la ligne haute, on le supprime
                if(order_type == ORDER_TYPE_BUY_STOP && NormalizeDouble(order_price, _Digits) != NormalizeDouble(upper_line, _Digits))
                {
                    m_trade.OrderDelete(ticket);
                }
                // Si c'est un ordre SELL STOP qui n'est pas sur la ligne basse, on le supprime
                else if(order_type == ORDER_TYPE_SELL_STOP && NormalizeDouble(order_price, _Digits) != NormalizeDouble(lower_line, _Digits))
                {
                    m_trade.OrderDelete(ticket);
                }
            }
        }
    }

    // --- Calcule la ligne de grille immédiatement inférieure au prix donné ---
    double GetLowerGridLine(double price)
    {
        double step_value = m_grid_step_points * m_point_value;
        double price_from_anchor = price - m_anchor_price;
        int steps_count = (int)floor(price_from_anchor / step_value);
        return m_anchor_price + steps_count * step_value;
    }

    // --- Vérifie s'il existe déjà un ordre en attente à un prix donné ---
    bool HasPendingOrderAt(double price, ENUM_ORDER_TYPE type)
    {
        for (int i = 0; i < OrdersTotal(); i++)
        {
            ulong ticket = OrderGetTicket(i);
            if (OrderGetInteger(ORDER_MAGIC) == m_magic_number && OrderGetString(ORDER_SYMBOL) == m_symbol && OrderGetInteger(ORDER_TYPE) == type)
            {
                if (NormalizeDouble(OrderGetDouble(ORDER_PRICE_OPEN), _Digits) == NormalizeDouble(price, _Digits))
                {
                    return true;
                }
            }
        }
        return false;
    }
    
    // --- Compte le nombre de positions ouvertes par cette grille ---
    int CountOpenPositions()
    {
        int count = 0;
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if(PositionGetInteger(POSITION_MAGIC) == m_magic_number && PositionGetString(POSITION_SYMBOL) == m_symbol)
            {
                count++;
            }
        }
        return count;
    }
};