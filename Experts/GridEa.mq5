//+------------------------------------------------------------------+
//|                                                       GridEa.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

input bool toto = true;

#include <GridManager.mqh>
GridManager *buy_grid;
GridManager *sell_grid;

int OnInit()
  {
   buy_grid = new GridManager(GRID_BUY, 0.01, 100, 1);
   buy_grid.SetGridMagicNumber(100);
   buy_grid.SetGridMultiplier(1);
   buy_grid.SetGridMaxDD(0.5);
   
   //sell_grid = new GridManager(GRID_SELL, 0.01, 100, 1);
   //sell_grid.SetGridMagicNumber(200);
   //sell_grid.SetGridMultiplier(1);
   //sell_grid.SetGridMaxDD(0.5);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   delete buy_grid;
   delete sell_grid;
  }

void OnTick(void)
  {
   bool buy_condition=true;
   if(buy_condition)
      buy_grid.Start();
   buy_grid.Update();
   
   // bool sell_condition=true;
   //if(sell_condition)
   //   sell_grid.Start();
   //sell_grid.Update();
  }
