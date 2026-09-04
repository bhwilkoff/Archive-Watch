#!/usr/bin/env python3
"""End-to-end functional audit of the Roku channel, on the device.

The tvOS twin of this (FunctionalAudit.swift, AW_UI_AUDIT=1) exists because a
screen that DRAWS is not a screen that WORKS: this build has shipped a Library
showing its empty state beside its own "2 in progress" line, a Browse grid
frozen under a changed sort label, and shelves whose queries returned zero for
weeks. Every assertion here therefore checks CONTENT — how many rows and items
a surface is actually showing — not that a screenshot was non-black.

Three oracles, none of them the app's own opinion of itself:
  * `selftest:report`  — every visible list and its real content counts
  * `selftest:layout`  — overlapping or off-screen Labels, by sceneBoundingRect
  * `selftest:store`   — a round trip over the registry, restoring what it found

Run:  python3 tools/roku_audit.py
Exit status is non-zero if any assertion fails, so it can gate a release.
"""
import os, re, socket, sys, threading, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import roku  # noqa: E402

# surface -> (minimum rows, minimum total items). A floor, not an exact count:
# the catalog changes daily and an audit that has to be edited every publish is
# an audit nobody runs.
SURFACES = [
    ("home",        "rows", 8, 60),
    ("movies",      "grid", 1, 20),
    ("tv",          "grid", 1, 10),
    ("collections", "rows", 6, 40),
    ("surprise",    "grid", 1, 13),
    ("search",      None,   0, 0),
    ("library",     None,   0, 0),
    ("channels",    "chList", 10, 10),
]


class Console(threading.Thread):
    def __init__(self):
        super().__init__(daemon=True)
        self.lines, self.lock, self.stop, self.ok = [], threading.Lock(), False, False

    def run(self):
        try:
            s = socket.create_connection((roku.HOST, 8085), timeout=5)
        except OSError:
            return
        self.ok = True
        s.settimeout(1)
        buf = ""
        while not self.stop:
            try:
                chunk = s.recv(65536)
            except socket.timeout:
                continue
            except OSError:
                break
            if not chunk:
                break
            buf += chunk.decode(errors="replace")
            *whole, buf = buf.split("\n")
            with self.lock:
                self.lines.extend(l.strip() for l in whole)
        s.close()

    def mark(self):
        with self.lock:
            return len(self.lines)

    def since(self, m):
        with self.lock:
            return self.lines[m:]

    def wait_for(self, mark, prefix, timeout=20):
        end = time.time() + timeout
        while time.time() < end:
            for l in self.since(mark):
                if l.startswith(prefix):
                    return l
            time.sleep(0.4)
        return None


def link(what):
    roku.curl("-X", "POST", f"{roku.ECP}/input?contentId={what}")


def main():
    con = Console()
    con.start()
    time.sleep(1.5)
    if not con.ok:
        print("cannot read the debug console on 8085 — this audit is built on it")
        return 1

    # Roku allows ONE client on 8085. A `roku.py log` left running elsewhere
    # takes the socket and this audit then sees nothing — which it reported as
    # eleven separate assertion failures, none of them true. Prove the stream
    # is actually ours before asserting anything on it.
    roku.curl("-X", "POST", f"{roku.ECP}/input?contentId=selftest%3Areport")
    if con.wait_for(0, "AWREPORT", timeout=12) is None:
        roku.curl("-X", "POST", f"{roku.ECP}/launch/dev")
        if con.wait_for(0, "AW", timeout=45) is None:
            print("attached to 8085 but no channel output arrived.")
            print("Another client is probably holding the console — check for a")
            print("running `roku.py log` and stop it, then re-run.")
            return 1

    results = []

    def check(name, ok, detail=""):
        results.append((name, ok, detail))
        print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"   {detail}" if detail else ""))

    print("Roku end-to-end audit\n")
    # A COLD start, deliberately. `/launch` on a channel that is already in the
    # foreground answers 204 and changes nothing, so launching without exiting
    # first asserts nothing at all — and the cold path is the one worth
    # measuring anyway, since it is the one every viewer takes.
    roku.curl("-X", "POST", f"{roku.ECP}/keypress/Home")
    # WAIT for the channel to actually be gone rather than assuming a fixed
    # sleep is enough. Two audits back to back produced 19/19 and then 0/11
    # from identical code, because the second launched into a device still
    # tearing the first one down — a harness that is flaky is a harness whose
    # failures nobody believes.
    for _ in range(20):
        if "Archive Watch" not in roku.curl(f"{roku.ECP}/query/active-app"):
            break
        time.sleep(1)
    time.sleep(2)
    m = con.mark()
    t0 = time.time()
    roku.curl("-X", "POST", f"{roku.ECP}/launch/dev")
    ready = con.wait_for(m, "AWSVC ready", timeout=90)
    boot = round(time.time() - t0, 1)
    check(f"catalog parses on a cold start ({boot}s)", ready is not None, ready or "")

    print("\nsurfaces")
    for name, listid, minrows, minitems in SURFACES:
        link(f"go%3A{name}")
        time.sleep(9)
        m = con.mark()
        link("selftest%3Areport")
        rep = con.wait_for(m, "AWREPORT", timeout=15)
        if rep is None:
            check(f"{name}: reports", False, "no report")
            continue
        route_ok = f"route={name}" in rep or (name in ("movies", "tv") and "route=browse" in rep)
        detail = rep.replace("AWREPORT ", "")
        if listid:
            mm = re.search(rf"\b{listid}=(\d+)/(\d+)", rep)
            if not mm:
                check(f"{name}: {listid} present", False, detail)
                continue
            rows, items = int(mm.group(1)), int(mm.group(2))
            check(f"{name}: {rows} rows / {items} items", route_ok and rows >= minrows and items >= minitems, detail)
        else:
            check(f"{name}: reached", route_ok, detail)

        m = con.mark()
        link("selftest%3Alayout")
        lay = con.wait_for(m, "AWLAYOUT", timeout=15)
        if lay:
            n = re.search(r"(\d+) findings", lay)
            check(f"{name}: no overlapping text", bool(n) and n.group(1) == "0", lay.split(": ", 1)[-1])

    print("\nresponsiveness")
    # Roku requires a response to a remote press within 250ms. Measure KEY
    # RECEIPT, not the end of a focus animation: `rowItemFocused` fires when
    # the animation settles, which measured 545ms and says nothing about
    # whether the app reacted promptly. BrowseScreen prints on receipt.
    link("go%3Amovies")
    time.sleep(9)
    lat = []
    for i in range(10):
        mk = con.mark()
        t0 = time.time()
        roku.curl("-X", "POST", f"{roku.ECP}/keypress/{'Right' if i % 2 == 0 else 'Left'}")
        deadline = t0 + 3
        while time.time() < deadline:
            hit = None
            for l in con.since(mk):
                if l.startswith("AWBROWSE key="):
                    hit = (time.time() - t0) * 1000
                    break
            if hit is not None:
                lat.append(hit)
                break
            time.sleep(0.005)
        time.sleep(0.6)
    if lat:
        lat.sort()
        worst = lat[-1]
        med = lat[len(lat) // 2]
        # The ECP POST alone is ~99ms of this, so the bar is met with room.
        check(f"remote response (median {med:.0f} ms, worst {worst:.0f} ms)", worst < 250,
              "Roku requires under 250 ms; the ECP round trip is ~99 ms of the measurement")
    else:
        check("remote response", False, "no key traces observed")

    # ---------------------------------------------------------------- controls
    #
    # Everything above drives the app through DEEP LINKS, which is why the
    # audit sat at 20/20 while OK on the More button did nothing at all: no
    # assertion had ever pressed Select on a control. (And `roku.py keys OK`
    # could not have — the ECP key is `Select`, and Roku answers 200 for a name
    # it does not know.) These press real buttons and assert the app ACTED.
    print("\nlive controls")

    def key(name, settle=0.9):
        roku.press(name, settle=settle)

    # Home opens ON the hero, which pages and then scrolls away.
    m = con.mark()
    link("go%3Ahome")
    time.sleep(3)
    key("right")
    hero = con.wait_for(m, "AWHERO index=", timeout=8)
    check("hero pages on Right", bool(hero), hero or "no AWHERO index trace")

    m = con.mark()
    key("down")
    zone = con.wait_for(m, "AWHERO zone=rows", timeout=8)
    check("hero scrolls away on Down", bool(zone), zone or "hero never yielded to the shelves")

    m = con.mark()
    key("up")
    zone = con.wait_for(m, "AWHERO zone=hero", timeout=8)
    check("shelves return to the hero on Up", bool(zone), zone or "no way back to the hero")

    # A tile opens Detail on a real Select.
    m = con.mark()
    key("down")
    time.sleep(0.6)
    key("select")
    det = con.wait_for(m, "AWROKU detail ok", timeout=15)
    check("Select on a tile opens Detail", bool(det), det or "Select did nothing")

    # The More button is a control, not a label.
    m = con.mark()
    key("right"); key("right"); key("select")
    panel = con.wait_for(m, "AWPANEL open more", timeout=10)
    check("Select on More opens the menu", bool(panel), panel or "More is inert")

    # ... and its actions reach the screen.
    m = con.mark()
    for _ in range(4):
        key("down", settle=0.6)
    key("select")
    tst = con.wait_for(m, "AWTOAST", timeout=10)
    check("a More action reports back", bool(tst), tst or "no toast rendered")
    key("back", settle=1.2)

    # Browse -> TV must reach SERIES SPINES, not standalone TV uploads.
    m = con.mark()
    link("go%3Atv")
    time.sleep(4)
    key("down")
    time.sleep(0.6)
    key("select")
    ser = con.wait_for(m, "AWSER ", timeout=20)
    check("Browse to TV opens a series spine", bool(ser), ser or "TV browse opened a film, not a spine")

    print("\nstate")
    m = con.mark()
    link("selftest%3Astore")
    st = con.wait_for(m, "AWPL selftest", timeout=20)
    check("registry round trip", bool(st) and "PASS" in st, st or "")

    m = con.mark()
    link("go%3Achannels")
    time.sleep(9)
    sch = None
    for l in con.since(0):
        if l.startswith("SCHED selftest"):
            sch = l
    check("channel schedule matches the other platforms", bool(sch) and "PASS" in sch, sch or "not run")

    roku.curl("-X", "POST", f"{roku.ECP}/keypress/Home")
    con.stop = True

    ok = sum(1 for _, o, _ in results if o)
    print(f"\n{ok}/{len(results)} assertions passed")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
