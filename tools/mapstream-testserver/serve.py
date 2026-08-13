#!/usr/bin/env python3
# Static map server with fault modes for testing the SwiftGibs map streamer.
# usage: serve.py <dir> <port> [ok|missing|corrupt|truncate|stall]
import http.server, socketserver, sys, time, os
root, port, mode = sys.argv[1], int(sys.argv[2]), (sys.argv[3] if len(sys.argv) > 3 else "ok")
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        p = os.path.join(root, os.path.basename(self.path))
        if mode == "missing" or not os.path.isfile(p):
            self.send_error(404); return
        data = open(p, "rb").read()
        if mode == "corrupt": data = b"X" + data[1:]
        # truncate: close early with a short body. stall: hold the connection open
        # past a short body so the client is genuinely still waiting on bytes when
        # the test issues /mapstreamcancel - a stall that sent the whole body up
        # front, then slept, would let the client finish before ever noticing.
        n = len(data) // 2 if mode in ("truncate", "stall") else len(data)
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))   # full length even when truncating/stalling
        self.end_headers()
        try:
            self.wfile.write(data[:n])
            if mode == "stall": time.sleep(120)
        except BrokenPipeError: pass
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("127.0.0.1", port), H) as s: s.serve_forever()
