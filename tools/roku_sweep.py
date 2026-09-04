#!/usr/bin/env python3
"""Press Select on every surface and report what the app actually did.

Deep links prove a screen RENDERS. This proves it is CONNECTED. It found, in
one pass: Select on an empty Library starting a channel, the Home hero
rotating behind every other surface, and Browse -> TV opening a film rather
than a series spine — none of which thirty ticks of screenshots had caught.

Read the output: a surface reporting NO TRACE, or a trace naming a DIFFERENT
surface than the one under test, is a dead or mis-routed control.
"""
import sys, time, threading, socket
sys.path.insert(0, "tools")
import roku

lines = []
def reader():
    s = socket.create_connection((roku.HOST, 8085), timeout=5)
    s.settimeout(1.0)
    buf = b""
    while not stop[0]:
        try:
            c = s.recv(4096)
        except socket.timeout:
            continue
        except OSError:
            break
        if not c: break
        buf += c
        while b"\n" in buf:
            l, buf = buf.split(b"\n", 1)
            lines.append(l.decode(errors="replace").strip())
    s.close()

stop = [False]
t = threading.Thread(target=reader, daemon=True); t.start()
time.sleep(1.5)

def mark(): return len(lines)
def since(m): return [l for l in lines[m:] if l.startswith("AW") or l.startswith("SCHED")]

def link(w):
    roku.curl("-X", "POST", f"{roku.ECP}/input?contentId={w}")

SURFACES = [
    ("Movies",      "go%3Amovies",     ["down", "select"]),
    ("TV",          "go%3Atv",         ["down", "select"]),
    ("Collections", "go%3Acollections",["select"]),
    ("Channels",    "go%3Achannels",   ["select"]),
    ("Library",     "go%3Alibrary",    ["select"]),
    ("Search",      "go%3Asearch",     ["select"]),
    ("Surprise",    "go%3Asurprise",   ["select"]),
]

for name, dl, keys in SURFACES:
    link(dl); time.sleep(4.5)
    m = mark()
    for k in keys:
        roku.press(k, settle=1.2)
    time.sleep(2.5)
    ev = since(m)
    print(f"\n=== {name}  (keys: {' '.join(keys)})")
    if not ev:
        print("   NO TRACE — the control did nothing")
    for l in ev[-8:]:
        print("   ", l)

stop[0] = True
time.sleep(0.5)
