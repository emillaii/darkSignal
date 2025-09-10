//+------------------------------------------------------------------+
//|                    Dark Bands Example script for EA building.mq4 |
//|                        Copyright 2021, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2021, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
  {
  
//buffer 0 buy arrow
//buffer 1 sell arrow
//buffer 2 upper band
//buffer 3 lower band

double UpperBand = iCustom(
  _Symbol,PERIOD_H1,
  "Nuovi Indicatori\\Dark Bands\\Dark Bands.ex4",
  1000,0,true,true,30,"",15,2.0,0,MODE_SMA,PRICE_MEDIAN,"",7,3,1,"",false,false,false,false,"alert.wav","",0.8,1.6,3.2,1.6,3.2,5.0,true,true,true,true,true,true,true,true,false,2,1);




Print("value: ",UpperBand);
Comment("value: ",UpperBand);
   
  }
//+------------------------------------------------------------------+
