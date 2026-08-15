#!/usr/bin/env python3
"""Range-capable HTTP server with a token-bucket bandwidth cap.

The adverse-conditions gate the harness lacked: every caption/playback fix
through build 925 was validated when archive.org happened to be fast, and
the ones that only held at 40+ Mbps shipped and broke at 10. Serve a local
copy of a film through this at --mbps 10 and a scenario reproduces a bad
archive.org morning ON DEMAND.

  python3 tools/throttled_range_server.py --port 8899 --mbps 10 --dir /tmp

NOTE: python's stock http.server ignores Range and serves byte-zero garbage
that AVFoundation reports as "media damaged" — hence this server.
"""
import argparse, http.server, os, re, socketserver, threading, time

class Bucket:
    def __init__(self, mbps):
        self.rate = mbps * 1_000_000 / 8       # bytes/sec, shared across conns
        self.tokens = self.rate
        self.last = time.monotonic()
        self.lock = threading.Lock()
    def take(self, n):
        while True:
            with self.lock:
                now = time.monotonic()
                self.tokens = min(self.rate, self.tokens + (now - self.last) * self.rate)
                self.last = now
                if self.tokens >= n:
                    self.tokens -= n
                    return
                need = (n - self.tokens) / self.rate
            time.sleep(min(need, 0.25))

BUCKET = None

class H(http.server.SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def do_GET(self):
        path = self.translate_path(self.path)
        if not os.path.isfile(path):
            self.send_error(404); return
        size = os.path.getsize(path)
        rng = self.headers.get("Range")
        lo, hi, code = 0, size - 1, 200
        if rng and (m := re.match(r"bytes=(\d+)-(\d*)", rng)):
            lo = int(m.group(1))
            hi = int(m.group(2)) if m.group(2) else size - 1
            hi = min(hi, size - 1)
            if lo >= size:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.send_header("Content-Length", "0")
                self.end_headers(); return
            code = 206
        self.send_response(code)
        if code == 206:
            self.send_header("Content-Range", f"bytes {lo}-{hi}/{size}")
        self.send_header("Content-Length", str(hi - lo + 1))
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        with open(path, "rb") as f:
            f.seek(lo)
            remaining = hi - lo + 1
            while remaining > 0:
                chunk = f.read(min(256 * 1024, remaining))
                if not chunk: break
                if BUCKET: BUCKET.take(len(chunk))
                try: self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError): return
                remaining -= len(chunk)
    def log_message(self, *a): pass

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8899)
    ap.add_argument("--mbps", type=float, default=0, help="0 = unthrottled")
    ap.add_argument("--dir", default="/tmp")
    args = ap.parse_args()
    if args.mbps: BUCKET = Bucket(args.mbps)
    os.chdir(args.dir)
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    print(f"serving {args.dir} on :{args.port} at "
          f"{args.mbps or 'unlimited'} Mbps")
    socketserver.ThreadingTCPServer(("", args.port), H).serve_forever()
