#!/usr/bin/env python3
"""No-cache static server for TV / PWA development.

Why this exists: `python3 -m http.server` sends no cache headers, so Chrome
holds onto tv.js / tv.css / watch.js across reloads and you end up testing a
STALE build while believing you fixed something. Combined with the app's own
service worker, an edit can be invisible for the whole session.

This serves everything with `Cache-Control: no-store` and refuses to serve
sw.js, so a dev session can never be shadowed by a cached shell.

    python3 tools/devserve.py [port]      # default 8099
"""
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class NoCacheHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def do_GET(self):
        # Never serve the service worker in dev — a registered SW caches the
        # shell and silently shadows every later edit.
        if self.path.split("?")[0].rstrip("/").endswith("sw.js"):
            self.send_error(404, "sw.js withheld in dev (tools/devserve.py)")
            return
        super().do_GET()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
    print(f"no-cache dev server on http://localhost:{port}  (sw.js withheld)")
    ThreadingHTTPServer(("", port), NoCacheHandler).serve_forever()
