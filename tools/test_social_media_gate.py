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
ok, d = S.media_probe(f"{base}/missing.jpg")
check(ok is False, "a 404 is NOT fetchable", d)
ok, d = S.media_probe(f"{base}/html")
check(ok is False, "a 200 that serves HTML is NOT fetchable", d)

ok, d = S.media_probe(f"{base}/good.jpg")
check(ok is True and d.startswith("image/"), "a real image IS fetchable", d)
ok, d = S.media_probe(f"{base}/good.mp4")
check(ok is True and d.startswith("video/"), "a real video IS fetchable", d)

# ONE DEADLINE FOR ALL THE MEDIA, not one each. Waiting per file is what lost
# Instagram and Threads: three uploads were polled to their own timeouts in
# sequence, so the run burned 450s and gave the later files no head start.
good = S.await_media([f"{base}/good.jpg", f"{base}/good.mp4"], timeout=8)
check(good == {}, "everything fetchable comes back clean", str(good))

t = time.time()
bad = S.await_media([f"{base}/missing.jpg", f"{base}/nope.mp4"], timeout=4)
elapsed = time.time() - t
check(set(bad) == {f"{base}/missing.jpg", f"{base}/nope.mp4"},
      "the ones that never came good are named", str(bad))
check(elapsed < 10, "...and two bad URLs share ONE deadline, not one each",
      f"{elapsed:.1f}s")

mixed = S.await_media([f"{base}/good.jpg", f"{base}/missing.jpg"], timeout=4)
check(set(mixed) == {f"{base}/missing.jpg"},
      "a good file is not held back by a bad sibling", str(mixed))

srv.shutdown()

src = Path("tools/social_post.py").read_text()
code = "\n".join(re.sub(r"#.*$", "", ln) for ln in src.splitlines())
code = re.sub(r'"""(?:.|\n)*?"""', "", code)

# THE CLASSIFICATION — the rule that actually broke.
#
# This file already asserted "a scheduled platform that refused FAILS the run"
# and was GREEN through six runs that lost Instagram and Threads, because it
# checked the CONSEQUENCE (`if failures: return 1`) and never the thing that
# decides what enters `failures`. An unfetchable media URL took the quiet
# `(skipped — ...)` branch, so the list it was asserting about stayed empty.
check(S.BENIGN_SKIPS == {"not connected", "no teaser for this film"},
      "only a missing credential or a missing teaser is a QUIET skip",
      str(S.BENIGN_SKIPS))

# Any skip reason written as a bare literal must be one of those two. A new
# reason therefore has to be classified deliberately rather than inheriting
# silence — which is exactly what "no public media URL" did.
literals = set(re.findall(r'return None,\s*"([^"]+)"', src))
check(literals <= S.BENIGN_SKIPS,
      "every literal skip reason is declared benign on purpose",
      f"unclassified: {sorted(literals - S.BENIGN_SKIPS)}")

check(re.search(r"if skip in BENIGN_SKIPS:(?:.|\n){0,400}?failures\.append", code) is not None,
      "a non-benign skip is appended to failures, not printed and forgotten")

# The two source rules. Comments are stripped: the block that fixed this NAMES
# the failure it replaced, and a checker that counts its own explanation is the
# trap this repo has hit before (tools/test_roku_legacy_syntax.py).
check("await_media(" in code,
      "the run waits for its media before handing any URL to a platform")
check(re.search(r"NOT fetchable after", src) is not None,
      "...and says so loudly when it never becomes fetchable")
check(re.search(r"if failures:(?:.|\n){0,900}?return 1", code) is not None
      and not re.search(r"if entries:\s*\n\s*print\(f\"::warning::\{len\(failures\)\}", code),
      "a scheduled platform that refused FAILS the run (no warning-and-pass)")
check("::error::" in src and "platform(s) refused" in src,
      "...and the refusal is an ::error:: annotation, not a ::warning::")

print(f"\n{len(fails)} failed" if fails else "\nall passed")
sys.exit(1 if fails else 0)
