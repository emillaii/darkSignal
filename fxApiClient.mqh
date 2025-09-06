#property copyright "Your Name"
#property link      "https://example.com"
#property version   "1.00"

#include <Trade\Trade.mqh>  // Include CTrade for order placement

// Configuration
string SERVER_URL = "http://127.0.0.1:12300";  // API server URL (change to market server port if needed)
CTrade trade;  // Trading object for placing orders

// --- ATR-based SL/TP helpers ---

// Map timeframe string like "M1","M5","H1" to ENUM_TIMEFRAMES
ENUM_TIMEFRAMES TimeframeFromString(string tf)
{
   string s = StringToUpper(tf);
   if(s == "M1") return PERIOD_M1;
   if(s == "M2") return PERIOD_M2;
   if(s == "M3") return PERIOD_M3;
   if(s == "M4") return PERIOD_M4;
   if(s == "M5") return PERIOD_M5;
   if(s == "M6") return PERIOD_M6;
   if(s == "M10") return PERIOD_M10;
   if(s == "M12") return PERIOD_M12;
   if(s == "M15") return PERIOD_M15;
   if(s == "M20") return PERIOD_M20;
   if(s == "M30") return PERIOD_M30;
   if(s == "H1") return PERIOD_H1;
   if(s == "H2") return PERIOD_H2;
   if(s == "H3") return PERIOD_H3;
   if(s == "H4") return PERIOD_H4;
   if(s == "H6") return PERIOD_H6;
   if(s == "H8") return PERIOD_H8;
   if(s == "H12") return PERIOD_H12;
   if(s == "D1") return PERIOD_D1;
   if(s == "W1") return PERIOD_W1;
   if(s == "MN1") return PERIOD_MN1;
   return PERIOD_CURRENT;
}

// Compute ATR-based SL/TP for market orders; returns true if both computed
bool ComputeATRStops(string symbol, string order_type_str, string tf_str, int atr_period, double mult_sl, double mult_tp, double &out_sl, double &out_tp)
{
   if(atr_period <= 0 || (mult_sl <= 0 && mult_tp <= 0))
      return false;

   ENUM_TIMEFRAMES tf = TimeframeFromString(tf_str);
   int handle = iATR(symbol, tf, atr_period);
   if(handle == INVALID_HANDLE)
   {
      Print("iATR handle invalid for ", symbol, " ", tf_str, ", period ", atr_period, ". Error ", GetLastError());
      return false;
    }

   double buff[];
   ArraySetAsSeries(buff, true);
   if(CopyBuffer(handle, 0, 0, 1, buff) <= 0)
   {
      Print("CopyBuffer ATR failed. Error ", GetLastError());
      IndicatorRelease(handle);
      return false;
   }
   double atr = buff[0];
   IndicatorRelease(handle);
   if(atr <= 0)
      return false;

   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   int stops_level_points = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_stop = stops_level_points * point;

   double sl = 0.0, tp = 0.0;
   if(order_type_str == "BUY")
   {
      if(mult_sl > 0) sl = bid - atr * mult_sl;
      if(mult_tp > 0) tp = bid + atr * mult_tp;
   }
   else if(order_type_str == "SELL")
   {
      if(mult_sl > 0) sl = ask + atr * mult_sl;
      if(mult_tp > 0) tp = ask - atr * mult_tp;
   }
   else
   {
      return false; // only market orders supported here
   }

   // Enforce minimum stop distance if both prices present
   double open_price = (order_type_str == "BUY") ? ask : bid;
   if(sl > 0 && MathAbs(open_price - sl) < min_stop)
   {
      if(order_type_str == "BUY") sl = open_price - min_stop; else sl = open_price + min_stop;
   }
   if(tp > 0 && MathAbs(tp - open_price) < min_stop)
   {
      if(order_type_str == "BUY") tp = open_price + min_stop; else tp = open_price - min_stop;
   }

   if(sl > 0) sl = NormalizeDouble(sl, digits);
   if(tp > 0) tp = NormalizeDouble(tp, digits);

   out_sl = sl;
   out_tp = tp;
   return (sl > 0 || tp > 0);
}

// Helper function to extract string value between quotes from JSON
string ExtractValue(string text, string key)
{
   int start = StringFind(text, "\"" + key + "\":\"");
   if(start == -1) {
      Print("Key not found: ", key);
      return "";
   }
   start += StringLen(key) + 4;  // Skip key and quotes
   int end = StringFind(text, "\"", start);
   if(end == -1) {
      Print("Closing quote not found for key: ", key);
      return "";
   }
   string value = StringSubstr(text, start, end - start);
   Print("Extracted ", key, ": ", value);
   return value;
}

// Helper function to extract number from JSON (double or integer)
double ExtractNumber(string text, string key)
{
   int start = StringFind(text, "\"" + key + "\":");
   if(start == -1) {
      Print("Key not found: ", key);
      return 0.0;
   }
   start += StringLen(key) + 3;  // Skip key and colon
   int end = StringFind(text, ",", start);
   if(end == -1) end = StringFind(text, "}", start);
   if(end == -1) {
      Print("End of number not found for key: ", key);
      return 0.0;
   }
   string value = StringSubstr(text, start, end - start);
   double number = StringToDouble(value);
   Print("Extracted ", key, ": ", number);
   return number;
}

// Parse JSON order data from server response
bool ParseOrderResponse(string json, string &symbol, string &order_type_str, double &volume, double &price, double &sl, double &tp, string &order_id, string &comment, long &magic_number)
{
   if(json == "") {
      Print("Empty JSON response");
      return false;
   }
   
   Print("Parsing JSON: ", json);
   
   symbol = ExtractValue(json, "symbol");
   order_type_str = ExtractValue(json, "order_type");
   volume = ExtractNumber(json, "volume");
   price = ExtractNumber(json, "price"); // may be 0 for market orders
   sl = ExtractNumber(json, "sl");
   tp = ExtractNumber(json, "tp");
   order_id = ExtractValue(json, "order_id");
   comment = ExtractValue(json, "comment");
   magic_number = (long)ExtractNumber(json, "magic_number");
   
   if(symbol == "" || volume <= 0 || order_id == "") {
      Print("Invalid order parameters: symbol=", symbol, ", volume=", volume, ", order_id=", order_id);
      return false;
   }
   
   // Validate symbol in Market Watch
   if(!SymbolExists(symbol)) {
      Print("Symbol not found in Market Watch: ", symbol);
      return false;
   }
   
   // Ensure magic_number is positive
   if(magic_number <= 0) {
      magic_number = 123456;  // Default magic number
      Print("Invalid magic_number, using default: ", magic_number);
   }
   
   Print("Parsed order: symbol=", symbol, ", order_type=", order_type_str, ", volume=", volume, ", price=", price, ", sl=", sl, ", tp=", tp, ", order_id=", order_id, ", comment=", comment, ", magic_number=", magic_number);
   return true;
}

// Process and place order in MT5
bool ProcessOrder(string json)
{
   string symbol, order_type_str, order_id, comment;
   double volume, price, sl, tp;
   long magic_number;
   
   if(!ParseOrderResponse(json, symbol, order_type_str, volume, price, sl, tp, order_id, comment, magic_number)) {
      SendOrderResult(false, "", "", 0, 0, 0, 0, 0, order_id, "", 0, "Invalid order parameters");
      return false;
   }
   
   // Handle market orders (BUY/SELL) and pending orders
   trade.SetExpertMagicNumber(magic_number);

   if(order_type_str == "BUY" || order_type_str == "SELL") {
      // Optional ATR-based SL/TP
      string sltp_mode = ExtractValue(json, "sl_tp_mode");
      int atr_period = (int)ExtractNumber(json, "atr_period");
      double atr_mult_sl = ExtractNumber(json, "atr_mult_sl");
      double atr_mult_tp = ExtractNumber(json, "atr_mult_tp");
      string tf_str = ExtractValue(json, "timeframe");
      if(StringToUpper(sltp_mode) == "ATR")
      {
         double atr_sl = 0.0, atr_tp = 0.0;
         if(ComputeATRStops(symbol, order_type_str, tf_str, atr_period, atr_mult_sl, atr_mult_tp, atr_sl, atr_tp))
         {
            if(atr_sl > 0) sl = atr_sl;
            if(atr_tp > 0) tp = atr_tp;
            Print("Using ATR-based SL/TP: ", sl, " / ", tp, " (period=", atr_period, ", mults=", atr_mult_sl, ",", atr_mult_tp, ", tf=", tf_str, ")");
         }
      }

      bool success;
      if(order_type_str == "BUY")
         success = trade.Buy(volume, symbol, 0.0, sl, tp, comment);
      else
         success = trade.Sell(volume, symbol, 0.0, sl, tp, comment);

      if(!success) {
         string error_msg = "Market order failed: " + trade.ResultComment() + ", Code: " + IntegerToString(trade.ResultRetcode());
         Print(error_msg);
         SendOrderResult(false, symbol, order_type_str, volume, 0.0, sl, tp, 0, order_id, comment, magic_number, error_msg);
         return false;
      }

      ulong ticket = trade.ResultOrder();
      Print("Market order placed, ticket: ", ticket);
      SendOrderResult(true, symbol, order_type_str, volume, 0.0, sl, tp, ticket, order_id, comment, magic_number, "");
      return true;
   } else {
      // Map order type to MT5 ENUM_ORDER_TYPE (pending orders require price > 0)
      ENUM_ORDER_TYPE order_type;
      if(order_type_str == "BUY_LIMIT") order_type = ORDER_TYPE_BUY_LIMIT;
      else if(order_type_str == "SELL_LIMIT") order_type = ORDER_TYPE_SELL_LIMIT;
      else if(order_type_str == "BUY_STOP") order_type = ORDER_TYPE_BUY_STOP;
      else if(order_type_str == "SELL_STOP") order_type = ORDER_TYPE_SELL_STOP;
      else {
         Print("Invalid order type: ", order_type_str);
         SendOrderResult(false, symbol, order_type_str, volume, price, sl, tp, 0, order_id, comment, magic_number, "Invalid order type");
         return false;
      }

      if(price <= 0) {
         Print("Invalid price for pending order: ", price);
         SendOrderResult(false, symbol, order_type_str, volume, price, sl, tp, 0, order_id, comment, magic_number, "Invalid price for pending order");
         return false;
      }

      bool success = trade.OrderOpen(symbol, order_type, volume, 0, price, sl, tp, ORDER_TIME_GTC, 0, comment);
      if(!success) {
         string error_msg = "OrderOpen failed: " + trade.ResultComment() + ", Code: " + IntegerToString(trade.ResultRetcode());
         Print(error_msg);
         SendOrderResult(false, symbol, order_type_str, volume, price, sl, tp, 0, order_id, comment, magic_number, error_msg);
         return false;
      }

      ulong ticket = trade.ResultOrder();
      Print("Pending order placed, ticket: ", ticket);
      SendOrderResult(true, symbol, order_type_str, volume, price, sl, tp, ticket, order_id, comment, magic_number, "");
      return true;
   }
}

// Send order result back to server
void SendOrderResult(bool success, string symbol, string order_type, double volume, double price, double sl, double tp, ulong ticket, string order_id, string comment, long magic_number, string error)
{
   string headers = "Content-Type: application/json";
   string url = SERVER_URL + "/submit_result";
   
   // Format result JSON with all order details
   string json = StringFormat(
      "{\"success\":%s,\"symbol\":\"%s\",\"order_type\":\"%s\",\"volume\":%.2f,\"price\":%.5f,\"sl\":%.5f,\"tp\":%.5f,\"ticket\":%I64u,\"order_id\":\"%s\",\"comment\":\"%s\",\"magic_number\":%I64d,\"error\":\"%s\"}",
      success ? "true" : "false", symbol, order_type, volume, price, sl, tp, ticket, order_id, comment, magic_number, error
   );
   
   char data[], result[];
   StringToCharArray(json, data);
   
   Print("Sending result to ", url, ": ", json);
   int res = WebRequest("POST", url, headers, NULL, 5000, data, ArraySize(data), result, headers);
   if(res == -1) {
      Print("Failed to send result to ", url, ": ", GetLastError());
   } else {
      Print("Result sent, Response code: ", res, ", Response: ", CharArrayToString(result));
   }
}

// EA initialization
int OnInit()
{
   EventSetTimer(1);  // Poll server every 1 second
   Print("EA initialized, polling ", SERVER_URL, "/get_order");
   return(INIT_SUCCEEDED);
}

// EA deinitialization
void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("EA deinitialized, reason: ", reason);
}

// Poll server for new orders
void OnTimer()
{
   string headers = "";  // No headers needed for GET
   string url = SERVER_URL + "/get_order";
   char data[], result[];
   string response;
   
   //Print("Attempting to fetch order from ", url);
   int res = WebRequest("GET", url, headers, NULL, 5000, data, 0, result, headers);
   if(res == -1) {
      Print("Failed to fetch order from ", url, ": ", GetLastError());
      return;
   }
   
   if(res == 204) {
      //Print("No orders available (HTTP 204)");
      return;
   }
   
   if(res == 200) {
      response = CharArrayToString(result);
      Print("Received order: ", response);
      if(ProcessOrder(response)) {
         Print("Order processed successfully");
      }
   } else {
      Print("Unexpected response code: ", res, ", Response: ", CharArrayToString(result));
   }
}

// Check if symbol exists in Market Watch
bool SymbolExists(string symbol)
{
   return SymbolInfoDouble(symbol, SYMBOL_BID) > 0;
}
