import http.server
import socketserver
import json
import threading
import queue
import time
import os
from typing import Optional, Dict, Any

# Local signal parser/tailer

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

# Import after .env so signal monitor can read encoding overrides
import signal_monitor as sm

# Configuration (can be overridden by .env)
PORT = int(os.environ.get("FX_MARKET_PORT", "12301"))
LOG_PATH = os.environ.get("FX_LOG_PATH", "20250906.log")
DEFAULT_VOLUME = float(os.environ.get("FX_DEFAULT_VOLUME", "0.01"))
MAGIC_NUMBER = int(os.environ.get("FX_MAGIC_NUMBER", "987654"))
ATR_MODE = os.environ.get("FX_ATR_MODE", "on").lower() in ("1","true","on","yes")
ATR_PERIOD = int(os.environ.get("FX_ATR_PERIOD", "14"))
ATR_MULT_SL = float(os.environ.get("FX_ATR_MULT_SL", "2.0"))
ATR_MULT_TP = float(os.environ.get("FX_ATR_MULT_TP", "3.0"))
DEBUG = os.environ.get("FX_DEBUG", "off").lower() in ("1","true","on","yes")
TAIL_FROM_BEGINNING = os.environ.get("FX_TAIL_FROM_BEGINNING", "off").lower() in ("1","true","on","yes")
PROBE_ON_START = os.environ.get("FX_PROBE_ON_START", "on").lower() in ("1","true","on","yes")
TAIL_VIA_COMMAND = os.environ.get("FX_TAIL_VIA_COMMAND", "off").lower() in ("1","true","on","yes")
TAIL_CMD = os.environ.get("FX_TAIL_CMD", "").strip() or None


def probe_file(path: str):
    try:
        exists = os.path.exists(path)
        print(f"[PROBE] exists={exists}")
        if not exists:
            return
        st = os.stat(path)
        print(f"[PROBE] size={st.st_size} mtime={st.st_mtime}")
        # Try shared open via signal_monitor
        try:
            raw, text = sm._open_shared_text(path)  # type: ignore[attr-defined]
            try:
                # Peek raw
                head = raw.read(64)
                print("[PROBE] raw head:", head[:64].hex(' '))
                # Reset and read first line decoded
                raw.seek(0)
                line = text.readline()
                print("[PROBE] decoded first line:", repr(line))
            finally:
                try:
                    text.detach()
                except Exception:
                    pass
                try:
                    raw.close()
                except Exception:
                    pass
        except Exception as e:
            print(f"[PROBE] shared-open failed: {e}")
    except Exception as e:
        print(f"[PROBE] error: {e}")


def _ps_encoding_for(enc: str) -> str:
    enc_l = enc.lower()
    if enc_l in ("utf-8", "utf8", "utf-8-sig", "utf8sig"):
        return "UTF8"
    if enc_l in ("utf-16", "utf16", "utf-16-le", "utf16le"):
        return "Unicode"
    if enc_l in ("utf-16-be", "utf16be"):
        return "BigEndianUnicode"
    if enc_l in ("mbcs", "ansi", "oem"):
        return "OEM"
    # Fallback to Default (Windows current code page)
    return "Default"


def iter_tail_lines_command(path: str, log_enc: str):
    import subprocess, time
    ps_enc = _ps_encoding_for(log_enc)
    while True:
        try:
            if TAIL_CMD:
                cmd = TAIL_CMD
            else:
                # Force UTF-8 stdout so Python decodes reliably
                lit = path.replace("'", "''")
                cmd = (
                    f"[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; "
                    f"Get-Content -LiteralPath '{lit}' -Tail 0 -Wait -Encoding {ps_enc}"
                )
            args = [
                "powershell",
                "-NoProfile",
                "-ExecutionPolicy","Bypass",
                "-Command",
                cmd,
            ]
            if DEBUG:
                print(f"[TAILCMD] {' '.join(args)}")
            proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    bufsize=1, text=True, encoding="utf-8", errors="ignore")
            # Stream lines
            assert proc.stdout is not None
            for line in proc.stdout:
                yield line.rstrip("\r\n")
            rc = proc.wait()
            if DEBUG:
                err = b""
                try:
                    err = proc.stderr.read() if proc.stderr else b""
                except Exception:
                    pass
                print(f"[TAILCMD] exited rc={rc} err={err}")
            time.sleep(0.5)
        except Exception as e:
            print(f"[TAILCMD] error: {e}")
            time.sleep(1.0)
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
    enc = os.environ.get('FX_LOG_ENCODING') or ('utf-16' if os.name == 'nt' else 'utf-16-le')
    mode = 'command' if TAIL_VIA_COMMAND else 'native'
    print(f"Tailing log for signals: {LOG_PATH} (encoding={enc}, from_beginning={TAIL_FROM_BEGINNING}, mode={mode})")
    if PROBE_ON_START:
        probe_file(LOG_PATH)
    try:
        line_iter = (
            iter_tail_lines_command(LOG_PATH, enc)
            if TAIL_VIA_COMMAND else
            sm.follow_utf16(LOG_PATH, from_beginning=TAIL_FROM_BEGINNING)
        )
        for raw_line in line_iter:
            if DEBUG:
                print(f"[TAIL] {raw_line}")
            parts = raw_line.split("\t")
            sig = sm.parse_signal(parts)
            if not sig:
                if DEBUG:
                    print("[PARSE] no match")
                continue
            if DEBUG:
                try:
                    print(f"[PARSE] {json.dumps(sig, ensure_ascii=False)}")
                except Exception:
                    print(f"[PARSE] {sig}")
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
