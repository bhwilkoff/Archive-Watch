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
    # RECONNECT on EOF: Roku DROPS the 8085 console when the channel
    # relaunches, so a reader connected once went silent for every step
    # after the first /launch/dev and the sweep reported NO TRACE (lesson 95).
    while not stop[0]:
        try:
            s=socket.create_connection((roku.HOST,8085),timeout=5); s.settimeout(1.0); buf=b""
            while not stop[0]:
                try: c=s.recv(4096)
                except socket.timeout: continue
                if not c: break
                buf+=c
                while b"\n" in buf:
                    l,buf=buf.split(b"\n",1); lines.append(l.decode(errors="replace").strip())
            s.close()
        except OSError:
            pass
        time.sleep(1.0)
stop = [False]
t = threading.Thread(target=reader, daemon=True); t.start()
time.sleep(1.5)

def mark(): return len(lines)
def since(m): return [l for l in lines[m:] if l.startswith("AW") or l.startswith("SCHED")]


def active_app():
    xml = roku.curl(f"{roku.ECP}/query/active-app")
    if 'id="dev"' in xml:
        return "dev"
    import re
    m = re.search(r'<app[^>]*>([^<]*)</app>', xml)
    return m.group(1) if m else "?"

def ensure_channel(what=""):
    """A sweep that runs against a channel which is not there reports every
    step as NO TRACE — indistinguishable from ten dead controls. That happened
    once; the device had been left on another app. Prove ours is foreground."""
    if active_app() == "dev":
        return True
    print(f"   [channel was not foreground ({active_app()}) — relaunching]")
    roku.curl("-X", "POST", f"{roku.ECP}/launch/dev")
    time.sleep(16)
    if active_app() != "dev":
        print("   [could not bring the channel to the foreground — the device is "
              "in use. Stopping rather than fighting for it.]")
        return False
    return True

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
    if not ensure_channel():
        break
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
