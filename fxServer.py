import http.server
import socketserver
import json
import threading
import queue
import time

# Configuration
PORT = 12300  # Server port, matching your setup at 192.168.1.8:3000
order_queue = queue.Queue()  # Queue to hold pending orders for MT5
order_results = {}  # Dictionary to store order results by order_id

# HTTP request handler for API endpoints
class RequestHandler(http.server.BaseHTTPRequestHandler):
    # Log incoming requests with method, path, and client IP
    def log_request(self, code='-', size='-'):
        print(f"Request: {self.requestline}, Code: {code}, Client: {self.client_address}")

    # Handle POST requests (/place_order, /submit_result)
    def do_POST(self):
        print(f"POST request received: {self.path} from {self.client_address}")
        if self.path == "/place_order":
            # Process new order submission from client
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            try:
                order_data = json.loads(post_data.decode('utf-8'))
                # Support both single order (dict) and array of orders (list)
                orders = order_data if isinstance(order_data, list) else [order_data]
                
                # Required fields for each order (allow ATR mode without sl/tp)
                required_fields = ["symbol", "order_type", "volume", "price"]
                order_ids = []
                
                for order in orders:
                    if not all(field in order for field in required_fields):
                        self.send_response(400)
                        self.send_header("Content-Type", "application/json")
                        self.end_headers()
                        self.wfile.write(json.dumps({"error": "Missing required fields in order"}).encode())
                        print(f"Missing required fields in order: {order}")
                        return
                    # If ATR mode is requested, allow sl/tp omission; EA will compute
                    sltp_mode = str(order.get("sl_tp_mode", "")).upper()
                    if sltp_mode != "ATR":
                        if "sl" not in order or "tp" not in order:
                            self.send_response(400)
                            self.send_header("Content-Type", "application/json")
                            self.end_headers()
                            self.wfile.write(json.dumps({"error": "Missing sl/tp; or set sl_tp_mode=ATR"}).encode())
                            print(f"Missing sl/tp for non-ATR order: {order}")
                            return
                    
                    # Assign order ID if not provided
                    order_id = order.get("order_id", str(int(time.time() * 1000)))
                    order["order_id"] = order_id
                    # Ensure comment and magic_number are included
                    order["comment"] = order.get("comment", "API Order")
                    order["magic_number"] = order.get("magic_number", 123456)
                    order_queue.put(order)
                    order_results[order_id] = {"status": "pending"}
                    order_ids.append(order_id)
                    print(f"Order queued: {order}")

                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"status": "orders submitted", "order_ids": order_ids}).encode())
            except json.JSONDecodeError:
                self.send_response(400)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": "Invalid JSON"}).encode())
                print("Invalid JSON")

        elif self.path == "/submit_result":
            # Process order result from MT5
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            try:
                result_data = json.loads(post_data.decode('utf-8'))
                order_id = result_data.get("order_id")
                if not order_id:
                    self.send_response(400)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({"error": "Missing order_id"}).encode())
                    print("Missing order_id")
                    return
                
                order_results[order_id] = result_data
                print(f"Received order result from MT5: {result_data}")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"status": "result received"}).encode())
            except json.JSONDecodeError:
                self.send_response(400)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": "Invalid JSON"}).encode())
                print("Invalid JSON")
        else:
            self.send_response(404)
            self.end_headers()
            print("404 Not Found")

    # Handle GET requests (/get_order, /order_status/)
    def do_GET(self):
        print(f"GET request received: {self.path} from {self.client_address}")
        if self.path == "/get_order":
            # Send next order to MT5
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
                print("No orders available (204)")
        elif self.path.startswith("/order_status/"):
            # Return status for a specific order_id
            order_id = self.path.split("/")[-1]
            result = order_results.get(order_id, {"error": "Order not found"})
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(result, separators=(',', ':')).encode())
            print(f"Sent order status for {order_id}: {result}")
        else:
            self.send_response(404)
            self.end_headers()
            print("404 Not Found")

# Start the HTTP server in a separate thread
def start_server():
    with socketserver.TCPServer(("", PORT), RequestHandler) as httpd:
        print(f"Server running on port {PORT}")
        httpd.serve_forever()

if __name__ == "__main__":
    server_thread = threading.Thread(target=start_server, daemon=True)
    server_thread.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("Shutting down server")
