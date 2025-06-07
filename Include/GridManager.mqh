//+------------------------------------------------------------------+
//|                                                      GridManager |
//|                                  Copyright 2024, Yashar Seyyedin |
//|                    https://www.mql5.com/en/users/yashar.seyyedin |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
enum ENUM_GRID_DIRECTION {GRID_BUY, GRID_SELL};

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class GridManager
  {
private:
   CTrade            trade;
   ulong             grid_magic;
   ENUM_GRID_DIRECTION grid_direction;
   int               grid_gap_points;
   double            grid_initial_lot_size;
   double            grid_lotsize_multiplier;
   double            grid_profit_percent;
   double            grid_max_dd_percent;

public:
                     GridManager(ENUM_GRID_DIRECTION direction, double grid_initial_lot_size, int grid_gap_points, double grid_profit_percent);
                    ~GridManager() {};
   void              SetGridMagicNumber(ulong magic);
   void              SetGridMaxDD(double max_dd_percent);
   void              SetGridMultiplier(double lot_multiplier);
   void              Start(void);
   void              Update(void);
   void              CloseGrid();
   double            GridPnL();
   int               CountPositions();
private:
   double            HighestSell();
   double            LowestBuy();
   double            DealComission(ulong ticket);
   void              EntryBuy();
   void              EntrySell();
   double            NextLotSize();
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void GridManager::GridManager(ENUM_GRID_DIRECTION direction, double initial_lot_size, int gap_points, double profit_percent)
  {
   grid_magic=0;
   grid_direction=direction;
   grid_initial_lot_size=initial_lot_size;
   grid_lotsize_multiplier=1;
   grid_gap_points=gap_points;
   grid_profit_percent=profit_percent;
   grid_max_dd_percent=0;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void GridManager::Start(void)
  {
   if(CountPositions()>0)
      return;
   if(grid_direction == GRID_BUY)
      EntryBuy();
   if(grid_direction == GRID_SELL)
      EntrySell();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void GridManager::Update(void)
  {
   if(CountPositions()==0)
      return;
   if(grid_direction == GRID_BUY)
      EntryBuy();
   if(grid_direction == GRID_SELL)
      EntrySell();
   if(grid_profit_percent!=0)
      if(GridPnL()>AccountInfoDouble(ACCOUNT_BALANCE)*0.01*grid_profit_percent)
         CloseGrid();
   if(grid_max_dd_percent!=0)
      if(GridPnL()<-1*AccountInfoDouble(ACCOUNT_BALANCE)*0.01*grid_max_dd_percent)
         CloseGrid();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void GridManager::SetGridMagicNumber(ulong magic)
  {
   grid_magic=magic;
   trade.SetExpertMagicNumber(grid_magic);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void GridManager::SetGridMaxDD(double max_dd)
  {
   grid_max_dd_percent=max_dd;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void GridManager::SetGridMultiplier(double lot_multiplier)
  {
   grid_lotsize_multiplier=lot_multiplier;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GridManager::GridPnL()
  {
   double pnl=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(grid_direction == GRID_BUY && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY
         && PositionGetInteger(POSITION_MAGIC)==grid_magic)
         pnl+=(PositionGetDouble(POSITION_PROFIT)+
               PositionGetDouble(POSITION_SWAP) +
               +2*DealComission(PositionGetInteger(POSITION_TICKET)));
      else
         if(grid_direction == GRID_SELL && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL
            && PositionGetInteger(POSITION_MAGIC)==grid_magic)
            pnl+=(PositionGetDouble(POSITION_PROFIT)+
                  PositionGetDouble(POSITION_SWAP) +
                  2*DealComission(PositionGetInteger(POSITION_TICKET)));
     }
   return pnl;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GridManager::DealComission(ulong ticket)
  {
   if(HistorySelectByPosition(ticket)==true)
   {
      for(int i=HistoryDealsTotal()-1;i>=0;i--)
        {
         ulong ticket=HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
            return HistoryDealGetDouble(ticket, DEAL_COMMISSION);
        }
   }
   return 0;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GridManager::HighestSell()
  {
   double price=-DBL_MAX;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && PositionGetInteger(POSITION_MAGIC)==grid_magic)
         price = MathMax(PositionGetDouble(POSITION_PRICE_OPEN), price);
     }
   return price;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GridManager::LowestBuy()
  {
   double price=DBL_MAX;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && PositionGetInteger(POSITION_MAGIC)==grid_magic)
         price = MathMin(PositionGetDouble(POSITION_PRICE_OPEN), price);
     }
   return price;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GridManager::NextLotSize()
  {
   int count = CountPositions();
   double lots=MathPow(grid_lotsize_multiplier, count)*grid_initial_lot_size;
   double vol_step_=SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots=int(lots / vol_step_)*vol_step_;
   lots = MathMin(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
   lots = MathMax(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
   return lots;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void GridManager::EntryBuy(void)
  {
   double lowest = LowestBuy();
   double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(Ask<lowest-grid_gap_points*_Point)
     {
      double lot = NextLotSize();
      trade.Buy(lot, _Symbol, Ask, 0, 0, NULL);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void GridManager::EntrySell(void)
  {
   double highest = HighestSell();
   double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(Bid>highest+grid_gap_points*_Point)
     {
      double lot = NextLotSize();
      trade.Sell(lot, _Symbol, Bid, 0, 0, NULL);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void GridManager::CloseGrid(void)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(grid_direction == GRID_BUY && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY
         && PositionGetInteger(POSITION_MAGIC)==grid_magic)
         trade.PositionClose(ticket);
      else
         if(grid_direction == GRID_SELL && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL
            && PositionGetInteger(POSITION_MAGIC)==grid_magic)
            trade.PositionClose(ticket);
     }
   if(CountPositions()>0)
      CloseGrid();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int GridManager::CountPositions()
  {
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=  PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC)!=grid_magic)
         continue;
      if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY && grid_direction == GRID_BUY)
         count++;
      if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL && grid_direction == GRID_SELL)
         count++;
     }
   return count;
  }

//+------------------------------------------------------------------+