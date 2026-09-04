#!/usr/bin/env python3
"""Level TWO of the Select sweep: options panels, playlists, versions, the
channel guide, the player and Back.

roku_sweep.py proves the first control on each surface is connected. This
walks INTO what that control opens. It found: Detail keeping its focused
button for the life of the channel (so Select meant to play a film opened the
options menu instead), three panels with no trace at all, and a search hint
promising a gesture the platform does not deliver.
"""
import sys, time, threading, socket
sys.path.insert(0, "tools")
import roku

lines=[]; stop=[False]
def reader():
    s=socket.create_connection((roku.HOST,8085),timeout=5); s.settimeout(1.0); buf=b""
    while not stop[0]:
        try: c=s.recv(4096)
        except socket.timeout: continue
        except OSError: break
        if not c: break
        buf+=c
        while b"\n" in buf:
            l,buf=buf.split(b"\n",1); lines.append(l.decode(errors="replace").strip())
    s.close()
threading.Thread(target=reader,daemon=True).start(); time.sleep(1.5)

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

def link(w): roku.curl("-X","POST",f"{roku.ECP}/input?contentId={w}")
def k(*keys, settle=1.0):
    for x in keys: roku.press(x, settle=settle)

def step(name, setup, keys, settle=2.5):
    if not ensure_channel():
        raise SystemExit(1)
    setup()
    m=mark()
    for x in keys: roku.press(x, settle=1.0)
    time.sleep(settle)
    ev=since(m)
    print(f"\n=== {name}")
    if not ev: print("   NO TRACE")
    for l in ev[-7:]: print("   ", l)

FILM="el-candidato-1959"

# 1. More -> Add to playlist
step("Detail > More > Add to playlist",
     lambda: (link(FILM), time.sleep(7)),
     ["right","right","select","down","down","select"])
k("back", settle=1.5)

# 2. More -> Choose a different copy
step("Detail > More > Choose a different copy",
     lambda: (link(FILM), time.sleep(6)),
     ["right","right","select","down","down","down","select"])
k("back", settle=1.5)

# 3. More -> Mark as watched
step("Detail > More > Mark as watched",
     lambda: (link(FILM), time.sleep(6)),
     ["right","right","select","select"])

# 4. Library options via * (Info)
step("Library > Options (*)",
     lambda: (link("go%3Alibrary"), time.sleep(5)),
     ["info"])
k("back", settle=1.5)

# 5. Channels: move to the guide column and select a programme
step("Channels > guide column",
     lambda: (link("go%3Achannels"), time.sleep(6)),
     ["right","down","select"])
k("back", settle=2.0)

# 6. Surprise doors: second door
step("Surprise > second door",
     lambda: (link("go%3Asurprise"), time.sleep(5)),
     ["right","select"])

# 7. Player -> Back returns
step("Player > Back returns to the referrer",
     lambda: (link(FILM), time.sleep(6)),
     ["select"], settle=8)
step("   (back out)", lambda: None, ["back"], settle=3)

# 8. Search chips
step("Search > Right into results > filters",
     lambda: (link("go%3Asearch"), time.sleep(4), [roku.press("Lit_"+c, settle=0.35) for c in "noir"], time.sleep(3)),
     ["right","up","select"])

# 9. Browse chips cycle
step("Browse > chip cycles the query",
     lambda: (link("go%3Amovies"), time.sleep(5)),
     ["select"])

stop[0]=True; time.sleep(0.4)
