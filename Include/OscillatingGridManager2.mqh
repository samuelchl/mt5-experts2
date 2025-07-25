//+------------------------------------------------------------------+
//|                                     OscillatingGridManager.mqh |
//|                      Copyright 2025, Gemini (Concept by User) |
//|                                                                  |
//|  Grille bidirectionnelle avec filtre de tendance optionnel.      |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

class OscillatingGridManager
{
private:
    CTrade      m_trade;
    ulong       m_magic_number;
    double      m_lot_size;
    int         m_grid_step_points;
    int         m_max_open_trades;
    double      m_anchor_price;
    double      m_point_value;
    string      m_symbol;
    MqlTick     m_last_tick;
    
    // --- Paramètres des filtres internes à la classe ---
    bool        m_use_trend_filter;
    int         m_trend_filter_ma_period;
    

public:
    // --- Constructeur mis à jour avec les paramètres de trailing stop ---
    OscillatingGridManager(ulong magic, double lots, int step_points, int max_trades, 
                          bool use_trend_filter, int ma_period)
    {
        m_magic_number = magic;
        m_lot_size = lots;
        m_grid_step_points = step_points;
        m_max_open_trades = max_trades;
        m_symbol = _Symbol;
        m_point_value = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        m_anchor_price = 0;
        
        m_use_trend_filter = use_trend_filter;
        m_trend_filter_ma_period = ma_period;
        


        m_trade.SetExpertMagicNumber(m_magic_number);
        m_trade.SetMarginMode();
        m_trade.SetTypeFillingBySymbol(m_symbol);
    }

    ~OscillatingGridManager() {}

    void Start()
    {
        if (m_anchor_price == 0)
        {
            SymbolInfoTick(m_symbol, m_last_tick);
            m_anchor_price = m_last_tick.bid;
            Print("OscillatingGridManager démarré. Ancrage à ", m_anchor_price);
            Update();
        }
    }

    void Update()
    {
        if (m_anchor_price == 0) return;
        CleanUpOldPendingOrders();
        PlacePendingOrders();
        
    }
    
    void Stop()
    {
        CancelPendingOrders();
        // Ferme les positions ouvertes
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if(PositionGetInteger(POSITION_MAGIC) == m_magic_number && PositionGetString(POSITION_SYMBOL) == m_symbol)
            {
                m_trade.PositionClose(PositionGetTicket(i));
            }
        }
        Print("OscillatingGridManager arrêté et nettoyé.");
    }
    
    // --- Nouvelle méthode pour annuler uniquement les ordres en attente ---
    void CancelPendingOrders()
    {
        for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
            ulong ticket = OrderGetTicket(i);
            if(OrderGetInteger(ORDER_MAGIC) == m_magic_number && OrderGetString(ORDER_SYMBOL) == m_symbol)
            {
                m_trade.OrderDelete(ticket);
            }
        }
    }

private:
    

    // --- Mettre à jour la fonction PlacePendingOrders ---
    void PlacePendingOrders()
    {
        if(CountOpenPositions() >= m_max_open_trades) return;

        MqlTick current_tick;
        SymbolInfoTick(m_symbol, current_tick);

        double lower_line = GetLowerGridLine(current_tick.bid);
        double upper_line = lower_line + m_grid_step_points * m_point_value;

        // --- Logique des filtres ---
        bool allow_buys = true;
        bool allow_sells = true;

        if (m_use_trend_filter)
        {
            // --- NOUVELLE FAÇON CORRECTE DE LIRE LA VALEUR DE L'INDICATEUR EN MQL5 ---

            // 1. Obtenir le "handle" (le lien) vers l'indicateur MA
            int ma_handle = iMA(m_symbol, _Period, m_trend_filter_ma_period, 0, MODE_EMA, PRICE_CLOSE);
            if(ma_handle == INVALID_HANDLE)
            {
                Print("Erreur lors de la création du handle pour iMA. Code d'erreur : ", GetLastError());
                return; // On ne peut pas continuer si l'indicateur ne peut pas être créé
            }

            // 2. Préparer un tableau pour recevoir les données et le copier
            double ma_buffer[]; // Tableau pour les valeurs de la MA
            ArraySetAsSeries(ma_buffer, true); // On met le tableau en mode "série chronologique" (indice 0 = barre actuelle)

            // On copie 2 valeurs depuis le début de la dernière barre (shift 0)
            if(CopyBuffer(ma_handle, 0, 0, 2, ma_buffer) < 2)
            {
                Print("Erreur lors de la copie du buffer de iMA. Code d'erreur : ", GetLastError());
                return; // On ne peut pas continuer si on n'arrive pas à lire les valeurs
            }

            // 3. On utilise la valeur de la dernière barre CLÔTURÉE (indice 1) pour la stabilité
            double ma_value = ma_buffer[1]; 
            
            //--- FIN DE LA CORRECTION ---

            if (current_tick.ask > ma_value)
            {
                allow_sells = false; // Tendance haussière, on bloque les ventes
            }
            else
            {
                allow_buys = false; // Tendance baissière, on bloque les achats
            }
        }

        if (allow_buys && !HasPendingOrderAt(upper_line, ORDER_TYPE_BUY_STOP))
        {
            double tp = upper_line + m_grid_step_points * m_point_value;
            double sl = lower_line;
            m_trade.BuyStop(m_lot_size, upper_line, m_symbol, sl, tp);
        }

        if (allow_sells && !HasPendingOrderAt(lower_line, ORDER_TYPE_SELL_STOP))
        {
            double tp = lower_line - m_grid_step_points * m_point_value;
            double sl = upper_line;
            m_trade.SellStop(m_lot_size, lower_line, m_symbol, sl, tp);
        }
    }
    
    // --- Les autres fonctions privées restent identiques ---
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
                if(order_type == ORDER_TYPE_BUY_STOP && NormalizeDouble(order_price, _Digits) != NormalizeDouble(upper_line, _Digits))
                {
                    m_trade.OrderDelete(ticket);
                }
                else if(order_type == ORDER_TYPE_SELL_STOP && NormalizeDouble(order_price, _Digits) != NormalizeDouble(lower_line, _Digits))
                {
                    m_trade.OrderDelete(ticket);
                }
            }
        }
    }
    
    double GetLowerGridLine(double price)
    {
        double step_value = m_grid_step_points * m_point_value;
        double price_from_anchor = price - m_anchor_price;
        int steps_count = (int)floor(price_from_anchor / step_value);
        return m_anchor_price + steps_count * step_value;
    }
    
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