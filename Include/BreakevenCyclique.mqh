#ifndef BREAKEVENCYCLIQUE_MQH
#define BREAKEVENCYCLIQUE_MQH

#include <Generic\HashMap.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <SamBotUtils.mqh>

// === Contexte pour stocker les paramètres du Breakeven Cyclique ===
struct BreakevenCycliqueContext
{
    ulong               magicNumber;
    string              symbol;
    ENUM_TIMEFRAMES     timeframe;
    int                 candlesAvant;
    bool                profitSeulement;
    int                 nbVerifications;
    CHashMap<ulong, datetime> lastCheckTime;   // objet, pas pointeur
    CHashMap<ulong, int>      candleCounter;   // objet, pas pointeur
};

// === Classe interne PositionInfo étendue ===
class BreakevenPositionInfo : public CPositionInfo
{
public:
    bool SelectByMagicNumber(const string symbol, ulong magic)
    {
        for (int i = 0; i < PositionsTotal(); i++)
        {
            ulong ticket = PositionGetTicket(i);
            if (SelectByTicket(ticket) && Symbol() == symbol && Magic() == magic)
            {
                return true;
            }
        }
        return false;
    }
};

// === Fonction d'initialisation du contexte Breakeven Cyclique ===
bool InitBreakevenCycliqueContext(BreakevenCycliqueContext &ctx,
                                  ulong magic,
                                  string symbol,
                                  ENUM_TIMEFRAMES timeframe,
                                  int candles,
                                  bool profitOnly,
                                  int nbVerif)
{
    ctx.magicNumber     = magic;
    ctx.symbol          = symbol;
    ctx.timeframe       = timeframe;
    ctx.candlesAvant    = candles;
    ctx.profitSeulement = profitOnly;
    ctx.nbVerifications = nbVerif;

    // Pas d'allocation dynamique nécessaire : les CHashMap sont des objets
    // On peut simplement vider les maps au cas où elles contiendraient quelque chose
    ctx.lastCheckTime.Clear();
    ctx.candleCounter.Clear();

    return true;
}

// === Fonction pour gérer le breakeven cyclique (appelée par l'EA à chaque tick) ===
void ManageBreakevenCyclique(BreakevenCycliqueContext &ctx)
{
    BreakevenPositionInfo positionInfo;
    if (positionInfo.SelectByMagicNumber(ctx.symbol, ctx.magicNumber))
    {
        ulong ticket          = positionInfo.Ticket();
        ENUM_POSITION_TYPE typePos       = (ENUM_POSITION_TYPE)positionInfo.Type();
        double prixOuverture  = positionInfo.PriceOpen();
        double slActuel       = positionInfo.StopLoss();
        double point          = SymbolInfoDouble(ctx.symbol, SYMBOL_POINT);
        double currentPrice   = (typePos == POSITION_TYPE_BUY)
                                ? SymbolInfoDouble(ctx.symbol, SYMBOL_ASK)
                                : SymbolInfoDouble(ctx.symbol, SYMBOL_BID);
        double profitPips     = (typePos == POSITION_TYPE_BUY)
                                ? (currentPrice - prixOuverture) / point
                                : (prixOuverture - currentPrice) / point;
        datetime currentBarTime = iTime(ctx.symbol, ctx.timeframe, 0);

        // Si la position n'a pas encore d'entrée dans les HashMaps, on la crée
        if (!ctx.lastCheckTime.ContainsKey(ticket))
        {
            ctx.lastCheckTime.Add(ticket, currentBarTime);
            ctx.candleCounter.Add(ticket, 0);
        }

        // On récupère les valeurs précédemment stockées
        datetime lastCheck;
        ctx.lastCheckTime.TryGetValue(ticket, lastCheck);
        int counter;
        ctx.candleCounter.TryGetValue(ticket, counter);

        // Une nouvelle bougie sur le timeframe de breakeven ?
        if (currentBarTime > lastCheck)
        {
            // Mise à jour du temps de dernière vérification
            ctx.lastCheckTime.TrySetValue(ticket, currentBarTime);
            // Incrémentation du compteur de bougies
            counter++;
            ctx.candleCounter.TrySetValue(ticket, counter);

            // Si on a atteint le nombre de bougiesAvant
            if (counter >= ctx.candlesAvant)
            {
                if (!ctx.profitSeulement || profitPips > 0)
                {
                    double prixBreakeven = (typePos == POSITION_TYPE_BUY)
                                           ? prixOuverture + point
                                           : prixOuverture - point;
                    bool slNonDefini    = (slActuel == 0);
                    bool besoinDeMove   = (typePos == POSITION_TYPE_BUY && slActuel < prixBreakeven)
                                          || (typePos == POSITION_TYPE_SELL && slActuel > prixBreakeven);

                    if (slNonDefini || besoinDeMove)
                    {
                        SamBotUtils::ModifierSL(ctx.symbol, ticket, prixBreakeven);
                        PrintFormat("BreakevenCyclique: SL mis au breakeven pour le ticket %llu après %d bougies", ticket, counter);
                        // Si tu veux qu'une seule mise au breakeven, tu peux désactiver le compteur ici
                        // ctx.candleCounter.TrySetValue(ticket, -1);
                    }
                }
            }
            else if (ctx.nbVerifications > 0)
            {
                int interval = ctx.candlesAvant / (ctx.nbVerifications + 1);
                if (interval > 0 && counter > 0 && (counter % interval) == 0)
                {
                    if (profitPips > 0)
                    {
                        double prixBreakeven = (typePos == POSITION_TYPE_BUY)
                                               ? prixOuverture + point
                                               : prixOuverture - point;
                        bool slNonDefini    = (slActuel == 0);
                        bool besoinDeMove   = (typePos == POSITION_TYPE_BUY && slActuel < prixBreakeven)
                                              || (typePos == POSITION_TYPE_SELL && slActuel > prixBreakeven);

                        if (slNonDefini || besoinDeMove)
                        {
                            SamBotUtils::ModifierSL(ctx.symbol, ticket, prixBreakeven);
                            PrintFormat("BreakevenCyclique: SL mis au breakeven anticipé pour le ticket %llu après %d bougies (vérification)", ticket, counter);
                            // ctx.candleCounter.TrySetValue(ticket, -1);
                        }
                    }
                }
            }
        }
    }
}

// === Fonction appelée lors du OnDeinit de l'EA ===
void DeinitBreakevenCycliqueContext(BreakevenCycliqueContext &ctx)
{
    // Plus besoin de delete, ce sont des objets automatiques
    ctx.lastCheckTime.Clear();
    ctx.candleCounter.Clear();
}

#endif // BREAKEVENCYCLIQUE_MQH
