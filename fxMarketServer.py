import http.server
import socketserver
import json
import threading
import queue
import time
import os
from typing import Optional, Dict, Any

# Local signal parser/tailer
import signal_monitor as sm

def load_dotenv(path: str = ".env") -> None:
    """Minimal .env loader: KEY=VALUE per line, supports quotes and comments.
    Does not overwrite existing env values.
    """
    try:
        with open(path, "r", encoding="utf-8") as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith('#'):
                    continue
                if '=' not in line:
                    continue
                key, val = line.split('=', 1)
                key = key.strip()
                val = val.strip().strip('"').strip("'")
                os.environ.setdefault(key, val)
    except FileNotFoundError:
        pass

# Load .env before reading configuration
load_dotenv()

# Configuration (can be overridden by .env)
PORT = int(os.environ.get("FX_MARKET_PORT", "12301"))
LOG_PATH = os.environ.get("FX_LOG_PATH", "20250906.log")
DEFAULT_VOLUME = float(os.environ.get("FX_DEFAULT_VOLUME", "0.01"))
MAGIC_NUMBER = int(os.environ.get("FX_MAGIC_NUMBER", "987654"))
ATR_MODE = os.environ.get("FX_ATR_MODE", "on").lower() in ("1","true","on","yes")
ATR_PERIOD = int(os.environ.get("FX_ATR_PERIOD", "14"))
ATR_MULT_SL = float(os.environ.get("FX_ATR_MULT_SL", "2.0"))
ATR_MULT_TP = float(os.environ.get("FX_ATR_MULT_TP", "3.0"))
SYMBOL_FILTER = None
if os.environ.get("FX_SYMBOLS"):
    SYMBOL_FILTER = {s.strip().upper() for s in os.environ["FX_SYMBOLS"].split(',') if s.strip()}

order_queue: "queue.Queue[Dict[str, Any]]" = queue.Queue()
order_results: Dict[str, Any] = {}


def enqueue_from_signal(sig: Dict[str, Any]):
    side = sig.get("side", "").lower()
    symbol = sig.get("symbol", "").upper()
    if not symbol or side not in ("buy", "sell"):
        return
    if SYMBOL_FILTER and symbol not in SYMBOL_FILTER:
        return

    order_id = sig.get("id") or str(int(time.time() * 1000))
    order_type = "BUY" if side == "buy" else "SELL"
    comment = f"{sig.get('type','sig')} {sig.get('timeframe','')} {sig.get('source','')} {sig.get('signal_time', sig.get('signal_datetime',''))}".strip()

    order = {
        "symbol": symbol,
        "order_type": order_type,  # MARKET order for EA
        "volume": DEFAULT_VOLUME,
        "price": 0.0,              # Ignored for market orders by EA
        "sl": 0.0,
        "tp": 0.0,
        "order_id": order_id,
        "comment": comment,
        "magic_number": MAGIC_NUMBER,
    }

    # Include ATR-based SL/TP parameters for EA to compute
    if ATR_MODE:
        order["sl_tp_mode"] = "ATR"
        order["atr_period"] = ATR_PERIOD
        order["atr_mult_sl"] = ATR_MULT_SL
        order["atr_mult_tp"] = ATR_MULT_TP
        order["timeframe"] = sig.get("timeframe") or ""

    order_queue.put(order)
    order_results[order_id] = {"status": "pending"}
    print(f"Enqueued market order from signal: {order}")


def tail_log_and_enqueue():
    print(f"Tailing log for signals: {LOG_PATH}")
    try:
        for raw_line in sm.follow_utf16(LOG_PATH, from_beginning=False):
            parts = raw_line.split("\t")
            sig = sm.parse_signal(parts)
            if not sig:
                continue
            enqueue_from_signal(sig)
    except Exception as e:
        print(f"Signal tailer error: {e}")


class RequestHandler(http.server.BaseHTTPRequestHandler):
    def log_request(self, code='-', size='-'):
        print(f"Request: {self.requestline}, Code: {code}, Client: {self.client_address}")

    def do_GET(self):
        if self.path == "/get_order":
            try:
                order = order_queue.get_nowait()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(order, separators=(',', ':')).encode())
                print(f"Sent order to MT5: {order}")
            except queue.Empty:
                self.send_response(204)
                self.end_headers()
        elif self.path.startswith("/order_status/"):
            order_id = self.path.split("/")[-1]
            result = order_results.get(order_id, {"error": "Order not found"})
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(result, separators=(',', ':')).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == "/submit_result":
            length = int(self.headers.get('Content-Length', '0'))
            body = self.rfile.read(length)
            try:
                result = json.loads(body.decode('utf-8'))
            except json.JSONDecodeError:
                self.send_response(400)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": "Invalid JSON"}).encode())
                return

            order_id = result.get("order_id")
            if not order_id:
                self.send_response(400)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": "Missing order_id"}).encode())
                return

            order_results[order_id] = result
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "result received"}).encode())
        else:
            self.send_response(404)
            self.end_headers()


def start_server():
    with socketserver.TCPServer(("", PORT), RequestHandler) as httpd:
        print(f"Market server running on port {PORT}")
        httpd.serve_forever()


if __name__ == "__main__":
    # Start signal tailer thread
    t = threading.Thread(target=tail_log_and_enqueue, daemon=True)
    t.start()

    # Start HTTP server (main thread)
    try:
        start_server()
    except KeyboardInterrupt:
        print("Shutting down market server")
