#!/usr/bin/env python3
"""
test_social_media_gate.py — a URL is not offered to a platform until it
actually serves media, and a scheduled platform that refuses fails the run.

Instagram posts stopped on 2026-09-11 under a GREEN run. Nothing was wrong
with the file, the host or the credentials: Meta fetches the URL itself,
within a second or two, and archive.org accepts a PUT well before the object
is servable. The post raced the upload and lost — and because it usually wins,
the programme looked healthy on the 8th and the 10th.

Two rules come out of that, and this guards both:
  1. publish_media verifies the URL serves image/* or video/* before returning
     it. An unfetchable URL is withheld, not handed over.
  2. A platform that was scheduled, connected, and then refused FAILS the run.

Hermetic: the fetchability cases run against a local stub server, so this needs
no network and cannot flake.

Run: python3 tools/test_social_media_gate.py   (exit 0 = pass)
"""
import http.server, re, sys, threading, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import social_post as S

fails = []


def check(ok, what, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'}  {what}" + (f"  — {detail}" if detail and not ok else ""))
    if not ok:
        fails.append(what)


class Stub(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def do_GET(self):
        if self.path == "/good.jpg":
            body = b"\xff\xd8\xff\xe0" + b"x" * 400
            self.send_response(200); self.send_header("Content-Type", "image/jpeg")
        elif self.path == "/good.mp4":
            body = b"\x00\x00\x00\x18ftypmp42" + b"x" * 400
            self.send_response(200); self.send_header("Content-Type", "video/mp4")
        elif self.path == "/html":
            body = b"<html>not media</html>"
            self.send_response(200); self.send_header("Content-Type", "text/html; charset=utf-8")
        else:
            self.send_response(404); self.send_header("Content-Type", "text/plain")
            body = b"nope"
        self.send_header("Content-Length", str(len(body)))
        self.end_headers(); self.wfile.write(body)


srv = http.server.HTTPServer(("127.0.0.1", 0), Stub)
threading.Thread(target=srv.serve_forever, daemon=True).start()
base = f"http://127.0.0.1:{srv.server_address[1]}"

# NEGATIVE CONTROLS FIRST — a gate that cannot fail proves nothing.
ok, d = S.media_fetchable(f"{base}/missing.jpg", timeout=4)
check(ok is False, "a 404 is NOT fetchable", d)
ok, d = S.media_fetchable(f"{base}/html", timeout=4)
check(ok is False, "a 200 that serves HTML is NOT fetchable", d)

ok, d = S.media_fetchable(f"{base}/good.jpg", timeout=8)
check(ok is True and d.startswith("image/"), "a real image IS fetchable", d)
ok, d = S.media_fetchable(f"{base}/good.mp4", timeout=8)
check(ok is True and d.startswith("video/"), "a real video IS fetchable", d)

t = time.time()
S.media_fetchable(f"{base}/missing.jpg", timeout=4)
check(time.time() - t < 12, "an unfetchable URL gives up rather than hanging the run")

srv.shutdown()

# The two source rules. Comments are stripped: the block that fixed this NAMES
# the failure it replaced, and a checker that counts its own explanation is the
# trap this repo has hit before (tools/test_roku_legacy_syntax.py).
src = Path("tools/social_post.py").read_text()
code = "\n".join(re.sub(r"#.*$", "", ln) for ln in src.splitlines())
code = re.sub(r'"""(?:.|\n)*?"""', "", code)

check("media_fetchable(ia)" in code,
      "publish_media gates the archive.org URL on fetchability")
check(re.search(r"NOT fetchable after", src) is not None,
      "...and says so loudly when it never becomes fetchable")
check(re.search(r"if failures:(?:.|\n){0,900}?return 1", code) is not None
      and not re.search(r"if entries:\s*\n\s*print\(f\"::warning::\{len\(failures\)\}", code),
      "a scheduled platform that refused FAILS the run (no warning-and-pass)")
check("::error::" in src and "platform(s) refused" in src,
      "...and the refusal is an ::error:: annotation, not a ::warning::")

print(f"\n{len(fails)} failed" if fails else "\nall passed")
sys.exit(1 if fails else 0)
