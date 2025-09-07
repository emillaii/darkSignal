//+------------------------------------------------------------------+
//|                      Dark Bands Example EA (MT4)                 |
//|     MT4 Expert Advisor reading Dark Bands via iCustom           |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

//--- Inputs
input string          InpIndicatorPath   = "Nuovi Indicatori\\Dark Bands\\Dark Bands.ex4"; // MQL4/Indicators path
input ENUM_TIMEFRAMES InpTimeframe       = PERIOD_H1;                                       // Indicator timeframe
input int             InpBufferIndex     = 2;                                               // 2 = Upper Band (per comment)
input int             InpShift           = 1;                                               // 1 = last closed bar
input int             InpBuyBufferIndex  = 0;                                               // 0 = Buy arrow buffer
input int             InpSellBufferIndex = 1;                                               // 1 = Sell arrow buffer

// NOTE: The inputs below must match the Dark Bands indicator's inputs exactly.
// They mirror the original MT4 script call, with buffer & shift appended by this EA.
input int             InpBarsLimit       = 1000;
input int             InpShiftOffset     = 0;
input bool            InpShowArrowsBuy   = true;
input bool            InpShowArrowsSell  = true;
input int             InpATRPeriod       = 30;
input string          InpLabel1          = "";
input int             InpMAPeriod        = 15;
input double          InpMADeviation     = 2.0;
input int             InpMAPriceShift    = 0;
input ENUM_MA_METHOD  InpMAMethod        = MODE_SMA;
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_MEDIAN;
input string          InpLabel2          = "";
input int             InpFastMAPeriod    = 7;
input int             InpMidMAPeriod     = 3;
input int             InpSlowMAPeriod    = 1;
input string          InpLabel3          = "";
input bool            InpAlertsOn        = false;
input bool            InpPushOn          = false;
input bool            InpEmailOn         = false;
input bool            InpSoundOn         = false;
input string          InpAlertSound      = "alert.wav";
input string          InpLabel4          = "";
input double          InpBandMult1       = 0.8;
input double          InpBandMult2       = 1.6;
input double          InpBandMult3       = 3.2;
input double          InpBandMult4       = 1.6;
input double          InpBandMult5       = 3.2;
input double          InpBandMult6       = 5.0;
input bool            InpOpt1            = true;
input bool            InpOpt2            = true;
input bool            InpOpt3            = true;
input bool            InpOpt4            = true;
input bool            InpOpt5            = true;
input bool            InpOpt6            = true;
input bool            InpOpt7            = true;
input bool            InpOpt8            = true;
input bool            InpOpt9            = false; // last indicator input before (buffer,shift)

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Dark Bands MT4 EA initialized on ", _Symbol, " ", EnumToString(InpTimeframe));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit()
{
   Comment("");
}

//+------------------------------------------------------------------+
//| Helper: read indicator buffer value (MT4)                        |
//+------------------------------------------------------------------+
double ReadIndicatorValue(int buffer_index, int shift)
{
   ResetLastError();
   double v = iCustom(
      _Symbol,
      InpTimeframe,
      InpIndicatorPath,
      InpBarsLimit,
      InpShiftOffset,
      InpShowArrowsBuy,
      InpShowArrowsSell,
      InpATRPeriod,
      InpLabel1,
      InpMAPeriod,
      InpMADeviation,
      InpMAPriceShift,
      InpMAMethod,
      InpAppliedPrice,
      InpLabel2,
      InpFastMAPeriod,
      InpMidMAPeriod,
      InpSlowMAPeriod,
      InpLabel3,
      InpAlertsOn,
      InpPushOn,
      InpEmailOn,
      InpSoundOn,
      InpAlertSound,
      InpLabel4,
      InpBandMult1,
      InpBandMult2,
      InpBandMult3,
      InpBandMult4,
      InpBandMult5,
      InpBandMult6,
      InpOpt1,
      InpOpt2,
      InpOpt3,
      InpOpt4,
      InpOpt5,
      InpOpt6,
      InpOpt7,
      InpOpt8,
      InpOpt9,
      buffer_index,
      shift
   );
   // If indicator or history isn't ready, EMPTY_VALUE can be returned
   return v;
}

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   // Ensure enough history on the requested timeframe
   if(iBars(_Symbol, InpTimeframe) < 100)
   {
      // Wait for more data to load
      return;
   }

   double upper = ReadIndicatorValue(InpBufferIndex, InpShift);
   double lower = ReadIndicatorValue(3, InpShift);
   double buy   = ReadIndicatorValue(InpBuyBufferIndex, InpShift);
   double sell  = ReadIndicatorValue(InpSellBufferIndex, InpShift);
   if(upper == EMPTY_VALUE)
   {
      int err = GetLastError();
      if(err != 0)
         Print("iCustom returned EMPTY_VALUE. LastError=", err);
   }
   string up_s   = (upper==EMPTY_VALUE ? "EMPTY" : DoubleToString(upper, Digits));
   string lo_s   = (lower==EMPTY_VALUE ? "EMPTY" : DoubleToString(lower, Digits));
   string buy_s  = (buy  ==EMPTY_VALUE ? "EMPTY" : DoubleToString(buy, Digits));
   string sell_s = (sell ==EMPTY_VALUE ? "EMPTY" : DoubleToString(sell, Digits));

   Comment("Upper[", InpShift, "]: ", up_s,
           "\nLower[", InpShift, "]: ", lo_s,
           "\nBuy[",   InpShift, "]: ", buy_s,
           "\nSell[",  InpShift, "]: ", sell_s);
   Print("Bands/Arrows[", InpShift, "] Upper=", up_s,
         " Lower=", lo_s, " Buy=", buy_s, " Sell=", sell_s);
}

//+------------------------------------------------------------------+
