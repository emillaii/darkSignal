//+------------------------------------------------------------------+
//|                      Dark Bands Example EA (MT5)                 |
//|     Converts MT4 script sample to an MT5 Expert Advisor          |
//+------------------------------------------------------------------+
#property copyright "Converted for MT5"
#property version   "1.00"
#property strict

// Indicator handle
int g_indicator_handle = INVALID_HANDLE;
// Trading helper
#include <Trade/Trade.mqh>
CTrade trade;

//--- Inputs
input string         InpIndicatorPath   = "Market\\Dark Bands MT5"; // Indicator path (MQL5/Indicators)
input ENUM_TIMEFRAMES InpTimeframe      = PERIOD_H1;                                    // Timeframe for indicator
input int            InpBufferIndex     = 2;                                            // 2 = Upper Band (per comment)
input int            InpLowerBufferIndex= 3;                                            // 3 = Lower Band (per comment)
input int            InpBuyBufferIndex  = 0;                                            // 0 = Buy arrow buffer
input int            InpSellBufferIndex = 1;                                            // 1 = Sell arrow buffer
input int            InpShift           = 1;                                            // 1 = last closed bar
input int            InpDrawBars        = 200;                                          // Bars to draw polylines

// Display options for info panel
input ENUM_BASE_CORNER InfoCorner       = CORNER_RIGHT_LOWER;                           // Corner for info panel
input int              InfoX            = 10;                                           // X offset
input int              InfoY            = 10;                                           // Y offset
input color            InfoTextColor    = clrWhite;                                     // Text color
input color            InfoBgColor      = clrBlack;                                     // Background color
input int              InfoFontSize     = 10;                                           // Font size

// Optional: TP buffers (set to -1 to disable buffer read)
input int            InpTP1BufferIndex  = -1;                                           // e.g., 4 if TP1 is a buffer
input int            InpTP2BufferIndex  = -1;                                           // e.g., 5 if TP2 is a buffer
input int            InpTP3BufferIndex  = -1;                                           // e.g., 6 if TP3 is a buffer
// Optional: TP object name keys (used if buffers are disabled)
input string         InpTP1ObjectKey    = "TP1";                                       // Substring to match TP1 object
input string         InpTP2ObjectKey    = "TP2";                                       // Substring to match TP2 object
input string         InpTP3ObjectKey    = "TP3";                                       // Substring to match TP3 object

// Optional: SL buffers (set to -1 to disable buffer read)
input int            InpSL1BufferIndex  = -1;                                           // e.g., 7 if SL1 is a buffer
input int            InpSL2BufferIndex  = -1;                                           // e.g., 8 if SL2 is a buffer
input int            InpSL3BufferIndex  = -1;                                           // e.g., 9 if SL3 is a buffer
// Optional: SL object name keys (used if buffers are disabled)
input string         InpSL1ObjectKey    = "SL1";                                       // Substring to match SL1 object
input string         InpSL2ObjectKey    = "SL2";                                       // Substring to match SL2 object
input string         InpSL3ObjectKey    = "SL3";                                       // Substring to match SL3 object

// NOTE: The inputs below map 1:1 to the indicator's parameters.
input int            MaxBars            = 1000;
input int            LineMethod         = 0;
input bool           ShowLines          = true;
input bool           ShowArrows         = true;
input int            VolatilityPeriod   = 30;
input string         s1                 = "";
input int            BandsPeriod        = 15;
input double         Multiplier         = 2.0;
input int            BandsShift         = 0;
input ENUM_MA_METHOD BandsMethod        = MODE_SMA;
input ENUM_APPLIED_PRICE BandsPrice     = PRICE_TYPICAL; // 5 per your set
input string         s2                 = "";
input int            LineWidth1         = 7;
input int            LineWidth2         = 3;
input int            LineWidth3         = 1;
input string         s3                 = "";
input bool           UseAlert           = true;
input bool           UseEmail           = false;
input bool           UseNotification    = false;
input bool           UseSound           = false;
input string         SoundName          = "alert.wav";
input string         s4                 = "";
input double         TP1e               = 0.8;
input double         TP2e               = 1.6;
input double         TP3e               = 3.2;
input double         SL1e               = 1.6;
input double         SL2e               = 3.2;
input double         SL3e               = 5.0;
input bool           AbleTP1            = true;
input bool           AbleTP2            = true;
input bool           AbleTP3            = true;
input bool           AbleSL1            = true;
input bool           AbleSL2            = true;
input bool           AbleSL3            = true;
input bool           ShowTPSL           = true;
input bool           ShowStatistics     = true;
input bool           CustomChart        = true; // last indicator input before buffers/shift

// Draw trade signals
input bool           DrawSignals        = true;                                         // Draw Buy/Sell arrows when present

// Trading settings
input bool           EnableTrading      = false;                                        // Enable live trading
input double         Lots               = 0.10;                                         // Order volume
input int            DeviationPoints    = 20;                                           // Max slippage (points)
input long           MagicNumber        = 86015001;                                     // Magic number
input bool           StrictTPValidation = false;                                        // If true, skip orders when TP/SL invalid
input bool           AutoAdjustStops    = true;                                         // If true, adjust TP/SL to meet broker min
input bool           DebugTradingLogs   = false;                                        // Extra logs for trading decisions
// Logging controls
input bool           VerboseTPSLSourceLogs = false;                                     // Print TP/SL source object/buffer logs
input bool           PreserveStopsRelative = true;                                      // Shift all SLs to keep spacing when constrained

// Internal state to avoid duplicate orders per bar
datetime g_last_buy_bar_time = 0;
datetime g_last_sell_bar_time = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Create the custom indicator handle (MT5 requires CopyBuffer afterwards)
   ResetLastError();
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(DeviationPoints);
   g_indicator_handle = iCustom(
      _Symbol,
      InpTimeframe,
      InpIndicatorPath,
      MaxBars,
      LineMethod,
      ShowLines,
      ShowArrows,
      VolatilityPeriod,
      s1,
      BandsPeriod,
      Multiplier,
      BandsShift,
      BandsMethod,
      BandsPrice,
      s2,
      LineWidth1,
      LineWidth2,
      LineWidth3,
      s3,
      UseAlert,
      UseEmail,
      UseNotification,
      UseSound,
      SoundName,
      s4,
      TP1e,
      TP2e,
      TP3e,
      SL1e,
      SL2e,
      SL3e,
      AbleTP1,
      AbleTP2,
      AbleTP3,
      AbleSL1,
      AbleSL2,
      AbleSL3,
      ShowTPSL,
      ShowStatistics,
      CustomChart
   );

   if(g_indicator_handle == INVALID_HANDLE)
   {
      int err = GetLastError();
      Print("Failed to create indicator handle. Error: ", err,
            ". Ensure MT5 version exists at MQL5/Indicators/", InpIndicatorPath);
      return INIT_FAILED;
   }
   Print("Indicator handle created: ", g_indicator_handle);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_indicator_handle != INVALID_HANDLE)
   {
      IndicatorRelease(g_indicator_handle);
      g_indicator_handle = INVALID_HANDLE;
   }

   // Remove drawn objects
   ObjectDelete(0, "DarkBands_Upper_Line");
   ObjectDelete(0, "DarkBands_Lower_Line");
   ObjectDelete(0, "DarkBands_Upper_Point");
   ObjectDelete(0, "DarkBands_Lower_Point");
   ObjectDelete(0, "DarkBands_InfoLabel");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(g_indicator_handle == INVALID_HANDLE)
      return;

   double val_up[1];
   double val_lo[1];
   double val_buy[1];
   double val_sell[1];
   double buy_edge[2];   // [0]=current bar, [1]=prev bar
   double sell_edge[2];  // [0]=current bar, [1]=prev bar
   double upper = EMPTY_VALUE;
   double lower = EMPTY_VALUE;
   double buy   = EMPTY_VALUE;
   double sell  = EMPTY_VALUE;
   ResetLastError();
   int copied_up = CopyBuffer(g_indicator_handle, InpBufferIndex, InpShift, 1, val_up);
   int copied_lo = CopyBuffer(g_indicator_handle, InpLowerBufferIndex, InpShift, 1, val_lo);
   int copied_buy = CopyBuffer(g_indicator_handle, InpBuyBufferIndex, InpShift, 1, val_buy);
   int copied_sell= CopyBuffer(g_indicator_handle, InpSellBufferIndex, InpShift, 1, val_sell);
   int edge_buy   = CopyBuffer(g_indicator_handle, InpBuyBufferIndex, 0, 2, buy_edge);
   int edge_sell  = CopyBuffer(g_indicator_handle, InpSellBufferIndex, 0, 2, sell_edge);

   if(copied_up <= 0)
   {
      int err = GetLastError();
      Print("CopyBuffer failed for Upper (buf=", InpBufferIndex, ", shift=", InpShift, ") err=", err);
   }

   if(copied_lo <= 0)
   {
      int err2 = GetLastError();
      Print("CopyBuffer failed for Lower (buf=", InpLowerBufferIndex, ", shift=", InpShift, ") err=", err2);
   }
   if(copied_buy <= 0)
   {
      int err3 = GetLastError();
      Print("CopyBuffer failed for Buy (buf=", InpBuyBufferIndex, ", shift=", InpShift, ") err=", err3);
   }
   if(copied_sell <= 0)
   {
      int err4 = GetLastError();
      Print("CopyBuffer failed for Sell (buf=", InpSellBufferIndex, ", shift=", InpShift, ") err=", err4);
   }

   string comment_text = "";
   // Compute rising-edge triggers on current bar: from 0.0 -> >0.0
   bool buy_trigger=false, sell_trigger=false;
   if(edge_buy==2)
      buy_trigger  = (buy_edge[0] > 0.0) && (buy_edge[1] <= 0.0 || buy_edge[1] == EMPTY_VALUE);
   if(edge_sell==2)
      sell_trigger = (sell_edge[0] > 0.0) && (sell_edge[1] <= 0.0 || sell_edge[1] == EMPTY_VALUE);
   if(copied_up > 0 || copied_lo > 0 || copied_buy > 0 || copied_sell > 0)
   {
      upper = (copied_up > 0) ? val_up[0] : EMPTY_VALUE;
      lower = (copied_lo > 0) ? val_lo[0] : EMPTY_VALUE;
      buy   = (copied_buy > 0) ? val_buy[0] : EMPTY_VALUE;
      sell  = (copied_sell> 0) ? val_sell[0] : EMPTY_VALUE;

      string up_s   = (upper==EMPTY_VALUE ? "EMPTY" : DoubleToString(upper, _Digits));
      string lo_s   = (lower==EMPTY_VALUE ? "EMPTY" : DoubleToString(lower, _Digits));
      string buy_s  = (buy  ==EMPTY_VALUE ? "EMPTY" : DoubleToString(buy, _Digits));
      string sell_s = (sell ==EMPTY_VALUE ? "EMPTY" : DoubleToString(sell, _Digits));

      Print("Bands/Arrows[", InpShift, "] Upper=", up_s, " Lower=", lo_s,
            " Buy=", buy_s, " Sell=", sell_s);
      comment_text = StringFormat("Upper[%d]: %s\nLower[%d]: %s\nBuy[%d]: %s\nSell[%d]: %s",
                                  InpShift, up_s, InpShift, lo_s, InpShift, buy_s, InpShift, sell_s);
   }

   // --- Try to read TP1/TP2/TP3 levels ---
   double tp1 = EMPTY_VALUE, tp2 = EMPTY_VALUE, tp3 = EMPTY_VALUE;

   // Prefer buffers if configured
   bool tp1_from_buf=false, tp2_from_buf=false, tp3_from_buf=false;
   if(InpTP1BufferIndex >= 0)
   {
      double b1[1];
      if(CopyBuffer(g_indicator_handle, InpTP1BufferIndex, InpShift, 1, b1) > 0)
      {  tp1 = b1[0]; tp1_from_buf=true; }
   }
   if(InpTP2BufferIndex >= 0)
   {
      double b2[1];
      if(CopyBuffer(g_indicator_handle, InpTP2BufferIndex, InpShift, 1, b2) > 0)
      {  tp2 = b2[0]; tp2_from_buf=true; }
   }
   if(InpTP3BufferIndex >= 0)
   {
      double b3[1];
      if(CopyBuffer(g_indicator_handle, InpTP3BufferIndex, InpShift, 1, b3) > 0)
      {  tp3 = b3[0]; tp3_from_buf=true; }
   }

   // If buffers not set/found, try to locate the latest "Reverse TP* <date> <time>" set
   if(tp1==EMPTY_VALUE || tp2==EMPTY_VALUE || tp3==EMPTY_VALUE)
   {
      double lt1=EMPTY_VALUE, lt2=EMPTY_VALUE, lt3=EMPTY_VALUE;
      string ln1="", ln2="", ln3="";
      FindLatestReverseTPSet("Reverse", InpTP1ObjectKey, InpTP2ObjectKey, InpTP3ObjectKey, lt1, lt2, lt3, ln1, ln2, ln3);
      if(tp1==EMPTY_VALUE) tp1 = lt1;
      if(tp2==EMPTY_VALUE) tp2 = lt2;
      if(tp3==EMPTY_VALUE) tp3 = lt3;
      // Append object source names to log (optional)
      if(VerboseTPSLSourceLogs)
      {
         if(lt1!=EMPTY_VALUE && !tp1_from_buf) Print("TP1 from object: ", ln1);
         if(lt2!=EMPTY_VALUE && !tp2_from_buf) Print("TP2 from object: ", ln2);
         if(lt3!=EMPTY_VALUE && !tp3_from_buf) Print("TP3 from object: ", ln3);
         if(tp1_from_buf) Print("TP1 from buffer index ", InpTP1BufferIndex);
         if(tp2_from_buf) Print("TP2 from buffer index ", InpTP2BufferIndex);
         if(tp3_from_buf) Print("TP3 from buffer index ", InpTP3BufferIndex);
      }
   }

   // Log TP levels when any are found
   if(tp1!=EMPTY_VALUE || tp2!=EMPTY_VALUE || tp3!=EMPTY_VALUE)
   {
      string tp1_s = (tp1==EMPTY_VALUE? "EMPTY" : DoubleToString(tp1, _Digits));
      string tp2_s = (tp2==EMPTY_VALUE? "EMPTY" : DoubleToString(tp2, _Digits));
      string tp3_s = (tp3==EMPTY_VALUE? "EMPTY" : DoubleToString(tp3, _Digits));
      Print("TP Levels: TP1=", tp1_s, " TP2=", tp2_s, " TP3=", tp3_s);
      string tp_line = StringFormat("\nTP1: %s  TP2: %s  TP3: %s", tp1_s, tp2_s, tp3_s);
      comment_text = (StringLen(comment_text)>0 ? comment_text + tp_line : tp_line);
   }

   // --- Try to read SL1/SL2/SL3 levels ---
   double sl1 = EMPTY_VALUE, sl2 = EMPTY_VALUE, sl3 = EMPTY_VALUE;

   bool sl1_from_buf=false, sl2_from_buf=false, sl3_from_buf=false;
   if(InpSL1BufferIndex >= 0)
   {
      double s1[1];
      if(CopyBuffer(g_indicator_handle, InpSL1BufferIndex, InpShift, 1, s1) > 0)
      {  sl1 = s1[0]; sl1_from_buf=true; }
   }
   if(InpSL2BufferIndex >= 0)
   {
      double s2[1];
      if(CopyBuffer(g_indicator_handle, InpSL2BufferIndex, InpShift, 1, s2) > 0)
      {  sl2 = s2[0]; sl2_from_buf=true; }
   }
   if(InpSL3BufferIndex >= 0)
   {
      double s3[1];
      if(CopyBuffer(g_indicator_handle, InpSL3BufferIndex, InpShift, 1, s3) > 0)
      {  sl3 = s3[0]; sl3_from_buf=true; }
   }

   if(sl1==EMPTY_VALUE || sl2==EMPTY_VALUE || sl3==EMPTY_VALUE)
   {
      double ls1=EMPTY_VALUE, ls2=EMPTY_VALUE, ls3=EMPTY_VALUE;
      string lnS1="", lnS2="", lnS3="";
      FindLatestReverseTPSet("Reverse", InpSL1ObjectKey, InpSL2ObjectKey, InpSL3ObjectKey, ls1, ls2, ls3, lnS1, lnS2, lnS3);
      if(sl1==EMPTY_VALUE) sl1 = ls1;
      if(sl2==EMPTY_VALUE) sl2 = ls2;
      if(sl3==EMPTY_VALUE) sl3 = ls3;
      if(VerboseTPSLSourceLogs)
      {
         if(ls1!=EMPTY_VALUE && !sl1_from_buf) Print("SL1 from object: ", lnS1);
         if(ls2!=EMPTY_VALUE && !sl2_from_buf) Print("SL2 from object: ", lnS2);
         if(ls3!=EMPTY_VALUE && !sl3_from_buf) Print("SL3 from object: ", lnS3);
         if(sl1_from_buf) Print("SL1 from buffer index ", InpSL1BufferIndex);
         if(sl2_from_buf) Print("SL2 from buffer index ", InpSL2BufferIndex);
         if(sl3_from_buf) Print("SL3 from buffer index ", InpSL3BufferIndex);
      }
   }

   if(sl1!=EMPTY_VALUE || sl2!=EMPTY_VALUE || sl3!=EMPTY_VALUE)
   {
      string sl1_s = (sl1==EMPTY_VALUE? "EMPTY" : DoubleToString(sl1, _Digits));
      string sl2_s = (sl2==EMPTY_VALUE? "EMPTY" : DoubleToString(sl2, _Digits));
      string sl3_s = (sl3==EMPTY_VALUE? "EMPTY" : DoubleToString(sl3, _Digits));
      Print("SL Levels: SL1=", sl1_s, " SL2=", sl2_s, " SL3=", sl3_s);
      string sl_line = StringFormat("\nSL1: %s  SL2: %s  SL3: %s", sl1_s, sl2_s, sl3_s);
      comment_text = (StringLen(comment_text)>0 ? comment_text + sl_line : sl_line);
   }

   if(StringLen(comment_text)>0)
      UpdateInfoLabel(comment_text);
   else
   {
      string tf = EnumToString(InpTimeframe);
      UpdateInfoLabel(StringFormat("%s %s\nWaiting for indicator data...", _Symbol, tf));
   }

   // Draw a single point (arrow) at the band levels for the selected bar
   datetime bt[];
   datetime bt_curr[];
   bool have_bt_shift = (CopyTime(_Symbol, InpTimeframe, InpShift, 1, bt) > 0);
   bool have_bt_curr  = (CopyTime(_Symbol, InpTimeframe, 0,        1, bt_curr) > 0);
   if(have_bt_shift)
   {
      // Use unique names per bar time so historical points remain
      string suffix = IntegerToString((long)bt[0]);
      string up_p = "DarkBands_Upper_Point_" + suffix;
      string lo_p = "DarkBands_Lower_Point_" + suffix;
      string buy_p  = "DarkBands_Buy_Signal_"  + suffix;
      string sell_p = "DarkBands_Sell_Signal_" + suffix;

      if(upper!=EMPTY_VALUE)
      {
         if(ObjectFind(0, up_p) < 0)
            ObjectCreate(0, up_p, OBJ_ARROW, 0, bt[0], upper);
         ObjectSetInteger(0, up_p, OBJPROP_ARROWCODE, 159);
         ObjectSetInteger(0, up_p, OBJPROP_COLOR, clrBlue);
         ObjectSetInteger(0, up_p, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, up_p, OBJPROP_BACK, false);
      }
      if(lower!=EMPTY_VALUE)
      {
         if(ObjectFind(0, lo_p) < 0)
            ObjectCreate(0, lo_p, OBJ_ARROW, 0, bt[0], lower);
         ObjectSetInteger(0, lo_p, OBJPROP_ARROWCODE, 159);
         ObjectSetInteger(0, lo_p, OBJPROP_COLOR, clrPink);
         ObjectSetInteger(0, lo_p, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, lo_p, OBJPROP_BACK, false);
      }
      // Draw Buy/Sell signals if enabled
      if(DrawSignals)
      {
         if(buy!=EMPTY_VALUE)
         {
            if(ObjectFind(0, buy_p) < 0)
               ObjectCreate(0, buy_p, OBJ_ARROW, 0, bt[0], buy);
            ObjectSetInteger(0, buy_p, OBJPROP_ARROWCODE, 241);
            ObjectSetInteger(0, buy_p, OBJPROP_COLOR, clrLime);
            ObjectSetInteger(0, buy_p, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, buy_p, OBJPROP_BACK, false);
         }
         if(sell!=EMPTY_VALUE)
         {
            if(ObjectFind(0, sell_p) < 0)
               ObjectCreate(0, sell_p, OBJ_ARROW, 0, bt[0], sell);
            ObjectSetInteger(0, sell_p, OBJPROP_ARROWCODE, 242);
            ObjectSetInteger(0, sell_p, OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, sell_p, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, sell_p, OBJPROP_BACK, false);
         }
      }
      // Place market orders per TP/SL set once per signal bar using rising-edge trigger
      if(EnableTrading && have_bt_curr)
      {
         string tstamp = TimeToString(bt_curr[0], TIME_DATE|TIME_MINUTES);
         double ask = 0, bid = 0;
         SymbolInfoDouble(_Symbol, SYMBOL_ASK, ask);
         SymbolInfoDouble(_Symbol, SYMBOL_BID, bid);
         // Compute broker constraints
         double point=0, tick_size=0; long stops_level=0; int digits=(int)_Digits;
         SymbolInfoDouble(_Symbol, SYMBOL_POINT, point);
         SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE, tick_size);
         if(tick_size<=0) tick_size=point;
         SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL, stops_level);
         double min_dist = stops_level * point;
         // Snap helper moved to function SnapPrice()

         // Optionally shift SLs together to preserve spacing when all are under/over constraint
         double adj_sl1=sl1, adj_sl2=sl2, adj_sl3=sl3;
         if(AutoAdjustStops && PreserveStopsRelative)
         {
            // For BUY: SL must be <= bid - min_dist
            if(buy_trigger)
            {
               double maxAllowedSL = bid - min_dist;
               // Compute max of provided SLs
               double maxSL = -1.0e100; bool any=false;
               if(adj_sl1!=EMPTY_VALUE){ maxSL = MathMax(maxSL, adj_sl1); any=true; }
               if(adj_sl2!=EMPTY_VALUE){ maxSL = MathMax(maxSL, adj_sl2); any=true; }
               if(adj_sl3!=EMPTY_VALUE){ maxSL = MathMax(maxSL, adj_sl3); any=true; }
               if(any && maxSL > maxAllowedSL)
               {
                  double shift = maxSL - maxAllowedSL + tick_size; // push down
                  if(adj_sl1!=EMPTY_VALUE) adj_sl1 = SnapPrice(adj_sl1 - shift, tick_size, digits);
                  if(adj_sl2!=EMPTY_VALUE) adj_sl2 = SnapPrice(adj_sl2 - shift, tick_size, digits);
                  if(adj_sl3!=EMPTY_VALUE) adj_sl3 = SnapPrice(adj_sl3 - shift, tick_size, digits);
               }
            }
            // For SELL: SL must be >= ask + min_dist
            if(sell_trigger)
            {
               double minAllowedSL = ask + min_dist;
               // Compute max of provided SLs (closest to validity boundary)
               double maxSL = -1.0e100; bool any=false;
               if(adj_sl1!=EMPTY_VALUE){ maxSL = MathMax(maxSL, adj_sl1); any=true; }
               if(adj_sl2!=EMPTY_VALUE){ maxSL = MathMax(maxSL, adj_sl2); any=true; }
               if(adj_sl3!=EMPTY_VALUE){ maxSL = MathMax(maxSL, adj_sl3); any=true; }
               if(any && maxSL < minAllowedSL)
               {
                  double shift = minAllowedSL - maxSL; // push up
                  if(adj_sl1!=EMPTY_VALUE) adj_sl1 = SnapPrice(adj_sl1 + shift, tick_size, digits);
                  if(adj_sl2!=EMPTY_VALUE) adj_sl2 = SnapPrice(adj_sl2 + shift, tick_size, digits);
                  if(adj_sl3!=EMPTY_VALUE) adj_sl3 = SnapPrice(adj_sl3 + shift, tick_size, digits);
               }
            }
         }
         // BUY side
         if(buy_trigger && bt_curr[0] != g_last_buy_bar_time)
         {
            if(tp1!=EMPTY_VALUE && adj_sl1!=EMPTY_VALUE) TryPlaceOrder(ORDER_TYPE_BUY, ask, tp1, adj_sl1, StringFormat("TP1 %s", tstamp));
            if(tp2!=EMPTY_VALUE && adj_sl2!=EMPTY_VALUE) TryPlaceOrder(ORDER_TYPE_BUY, ask, tp2, adj_sl2, StringFormat("TP2 %s", tstamp));
            if(tp3!=EMPTY_VALUE && adj_sl3!=EMPTY_VALUE) TryPlaceOrder(ORDER_TYPE_BUY, ask, tp3, adj_sl3, StringFormat("TP3 %s", tstamp));
            g_last_buy_bar_time = bt_curr[0];
         }
         // SELL side
         if(sell_trigger && bt_curr[0] != g_last_sell_bar_time)
         {
            if(tp1!=EMPTY_VALUE && adj_sl1!=EMPTY_VALUE) TryPlaceOrder(ORDER_TYPE_SELL, bid, tp1, adj_sl1, StringFormat("TP1 %s", tstamp));
            if(tp2!=EMPTY_VALUE && adj_sl2!=EMPTY_VALUE) TryPlaceOrder(ORDER_TYPE_SELL, bid, tp2, adj_sl2, StringFormat("TP2 %s", tstamp));
            if(tp3!=EMPTY_VALUE && adj_sl3!=EMPTY_VALUE) TryPlaceOrder(ORDER_TYPE_SELL, bid, tp3, adj_sl3, StringFormat("TP3 %s", tstamp));
            g_last_sell_bar_time = bt_curr[0];
         }
      }
      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
//| Helper: draw/update info label in upper-right corner            |
//+------------------------------------------------------------------+
void UpdateInfoLabel(const string text)
{
   string name = "DarkBands_InfoLabel";
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   }
   ObjectSetInteger(0, name, OBJPROP_CORNER, InfoCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InfoX);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InfoY);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InfoFontSize);
   ObjectSetString (0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_COLOR, InfoTextColor);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Helper: place a market order with validation                    |
//+------------------------------------------------------------------+
double SnapPrice(const double price, const double tick_size, const int digits)
{
   if(tick_size<=0.0)
      return NormalizeDouble(price, digits);
   double snapped = MathRound(price/tick_size)*tick_size;
   return NormalizeDouble(snapped, digits);
}

//+------------------------------------------------------------------+
//| Helper: place a market order with validation                    |
//+------------------------------------------------------------------+
bool TryPlaceOrder(ENUM_ORDER_TYPE type, double mkt_price, double tp, double sl, const string note)
{
   // Normalize prices
   int digits = (int)_Digits;
   double ntp = NormalizeDouble(tp, digits);
   double nsl = NormalizeDouble(sl, digits);

   double ask=0, bid=0;
   SymbolInfoDouble(_Symbol, SYMBOL_ASK, ask);
   SymbolInfoDouble(_Symbol, SYMBOL_BID, bid);
   double point=0, tick_size=0; long stops_level=0;
   SymbolInfoDouble(_Symbol, SYMBOL_POINT, point);
   SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL, stops_level);
   SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE, tick_size);
   if(tick_size<=0) tick_size=point;
   double min_dist = stops_level * point;

   if(type==ORDER_TYPE_BUY)
   {
      // Validate and optionally adjust
      if(!(ntp>ask && nsl<ask))
      {
         if(DebugTradingLogs) Print("BUY validation failed: tp<=ask or sl>=ask (tp=",ntp,", sl=",nsl,", ask=",ask,")");
         if(StrictTPValidation) return false;
      }
      if(AutoAdjustStops)
      {
         if(ntp <= ask + min_dist) ntp = NormalizeDouble(ask + min_dist, digits);
         if(nsl >= bid - min_dist) nsl = NormalizeDouble(bid - min_dist, digits);
         // snap to tick size
         ntp = MathRound(ntp/tick_size)*tick_size;
         nsl = MathRound(nsl/tick_size)*tick_size;
      }
      bool ok = trade.Buy(Lots, _Symbol, 0.0, nsl, ntp, note);
      if(DebugTradingLogs)
      {
         Print("Buy attempt: lots=", Lots, " sl=", nsl, " tp=", ntp, " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      }
      if(!ok) Print("Buy failed: ", _LastError);
      else    Print("Buy opened: ", Lots, " TP=", ntp, " SL=", nsl, " ", note);
      return ok;
   }
   else if(type==ORDER_TYPE_SELL)
   {
      if(!(ntp<bid && nsl>bid))
      {
         if(DebugTradingLogs) Print("SELL validation failed: tp>=bid or sl<=bid (tp=",ntp,", sl=",nsl,", bid=",bid,")");
         if(StrictTPValidation) return false;
      }
      if(AutoAdjustStops)
      {
         if(ntp >= bid - min_dist) ntp = NormalizeDouble(bid - min_dist, digits);
         if(nsl <= ask + min_dist) nsl = NormalizeDouble(ask + min_dist, digits);
         ntp = MathRound(ntp/tick_size)*tick_size;
         nsl = MathRound(nsl/tick_size)*tick_size;
      }
      bool ok = trade.Sell(Lots, _Symbol, 0.0, nsl, ntp, note);
      if(DebugTradingLogs)
      {
         Print("Sell attempt: lots=", Lots, " sl=", nsl, " tp=", ntp, " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      }
      if(!ok) Print("Sell failed: ", _LastError);
      else    Print("Sell opened: ", Lots, " TP=", ntp, " SL=", nsl, " ", note);
      return ok;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Helper: find TP price from chart objects by substring key       |
//+------------------------------------------------------------------+
double FindTpObjectPrice(const string key)
{
   if(StringLen(key)==0)
      return EMPTY_VALUE;
   int total = ObjectsTotal(0,  -1, -1); // all objects in the chart (all subwindows)
   for(int i=0; i<total; ++i)
   {
      string name = ObjectName(0, i, -1);
      if(name==NULL || name=="")
         continue;
      string name_lower = name; StringToLower(name_lower);
      string key_lower  = key;  StringToLower(key_lower);
      if(StringFind(name_lower, key_lower) < 0)
         continue;

      long type = ObjectGetInteger(0, name, OBJPROP_TYPE);
      // Prefer horizontal lines; if trendline, read first anchor price
      if(type == OBJ_HLINE)
      {
         double price = ObjectGetDouble(0, name, OBJPROP_PRICE);
         if(price>0) return price;
      }
      else if(type == OBJ_TREND || type == OBJ_TRENDBYANGLE)
      {
         double p1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
         if(p1>0) return p1;
      }
      else if(type == OBJ_ARROW)
      {
         double p = ObjectGetDouble(0, name, OBJPROP_PRICE);
         if(p>0) return p;
      }
      // As a fallback, try generic price property
      double pgen = ObjectGetDouble(0, name, OBJPROP_PRICE);
      if(pgen>0) return pgen;
   }
   return EMPTY_VALUE;
}

//+------------------------------------------------------------------+
//| Parse datetime from object name tail: "YYYY.MM.DD HH:MM"        |
//+------------------------------------------------------------------+
bool ParseNameDateTime(const string name, datetime &out_dt)
{
   out_dt = 0;
   string parts[]; int n = StringSplit(name, ' ', parts);
   if(n < 2) return false;
   string date_s = parts[n-2];
   string time_s = parts[n-1];

   string d[]; int dn = StringSplit(date_s, '.', d);
   string t[]; int tn = StringSplit(time_s, ':', t);
   if(dn < 3 || tn < 2) return false;
   int Y = (int)StringToInteger(d[0]);
   int M = (int)StringToInteger(d[1]);
   int D = (int)StringToInteger(d[2]);
   int h = (int)StringToInteger(t[0]);
   int m = (int)StringToInteger(t[1]);
   MqlDateTime md; md.year=Y; md.mon=M; md.day=D; md.hour=h; md.min=m; md.sec=0;
   out_dt = StructToTime(md);
   return (out_dt>0);
}

//+------------------------------------------------------------------+
//| Find latest Reverse TP set and return TP1/TP2/TP3 prices        |
//+------------------------------------------------------------------+
void FindLatestReverseTPSet(const string prefix,
                            const string tp1Key,
                            const string tp2Key,
                            const string tp3Key,
                            double &tp1,
                            double &tp2,
                            double &tp3,
                            string &tp1Name,
                            string &tp2Name,
                            string &tp3Name)
{
   tp1 = tp2 = tp3 = EMPTY_VALUE;
   tp1Name = tp2Name = tp3Name = "";
   datetime latest = 0;

   int total = ObjectsTotal(0, -1, -1);
   for(int i=0; i<total; ++i)
   {
      string name = ObjectName(0, i, -1);
      if(name==NULL || name=="") continue;

      string lower_name = name; StringToLower(lower_name);
      string lower_prefix = prefix; StringToLower(lower_prefix);
      if(StringFind(lower_name, lower_prefix) < 0) continue;
      // Ensure it's a TP object
      string tp1k = tp1Key; StringToLower(tp1k);
      string tp2k = tp2Key; StringToLower(tp2k);
      string tp3k = tp3Key; StringToLower(tp3k);
      bool is_tp1 = (StringFind(lower_name, tp1k) >= 0);
      bool is_tp2 = (StringFind(lower_name, tp2k) >= 0);
      bool is_tp3 = (StringFind(lower_name, tp3k) >= 0);
      if(!(is_tp1 || is_tp2 || is_tp3)) continue;

      datetime dt;
      if(!ParseNameDateTime(name, dt))
         continue;

      // If newer timestamp seen, reset collected TPs for this latest set
      if(dt > latest)
      {
         latest = dt;
         tp1 = tp2 = tp3 = EMPTY_VALUE;
      }
      if(dt == latest)
      {
         long type = ObjectGetInteger(0, name, OBJPROP_TYPE);
         double price = EMPTY_VALUE;
         if(type == OBJ_HLINE)
            price = ObjectGetDouble(0, name, OBJPROP_PRICE);
         else if(type == OBJ_TREND || type == OBJ_TRENDBYANGLE)
            price = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
         else
            price = ObjectGetDouble(0, name, OBJPROP_PRICE);

         if(price>0)
         {
            if(is_tp1){ tp1 = price; tp1Name = name; }
            if(is_tp2){ tp2 = price; tp2Name = name; }
            if(is_tp3){ tp3 = price; tp3Name = name; }
         }
      }
   }
}

//+------------------------------------------------------------------+
