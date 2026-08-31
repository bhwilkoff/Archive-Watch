"""Cooperative leases so two agent sessions can share one bench of test devices.

The problem, named by the owner: two Claude Code sessions were driving the SAME
physical devices from different repos. Each kept finding the other's app in the
foreground, each force-stopped the other's app as part of its own "reset to a clean
state", and each diagnosed it as a bug in its own product. The Fire TV and the
Android TV changed hands mid-run repeatedly, and this harness spent four rounds of
fixes making its recovery smarter at fighting a peer it did not know existed.

No shared memory is needed to fix it — only a shared filesystem and an agreed
convention:

    ~/.device-lease/<device>.json   {"owner", "pid", "task", "acquired", "expires"}

Rules, deliberately few enough that any other tool can implement them in an hour:

  * Take a lease BEFORE touching a device; release it after.
  * A lease has a TTL. A crashed session must not hold a device forever, and no
    session should have to ask a human to break a lock.
  * Never steal a live lease. Wait, or skip the device and SAY the run did not
    cover it — a skipped device reported honestly beats a contended device
    reported as a product failure.
  * Reading a foreign lease tells you WHO has it, so a message names a peer
    instead of blaming the app.

    with lease("firetv", task="tidbits live join"):
        ...                       # the device is yours for the duration

    ok, holder = try_lease("firetv")
    if not ok:  print(f"skipping firetv — held by {holder}")

ORIGIN: this file is a VERBATIM copy of Tidbits-Trivia's tools/devlease.py, which
authored the protocol. Only DEVICE_LEASE_OWNER's default differs. Do not "improve"
it here — the lease dir, the filename, the JSON fields and the DEVICE KEYS are a
contract between two repos, and a unilateral change silently stops the interlock
rather than failing loudly. Canonical keys (from Tidbits' tools/adb_run.py):

    firetv     10.0.0.139:5555      androidtv  10.0.0.55:5555
    pixel      (mDNS serial)        windows

    python3 tools/devlease.py              # who holds what
    python3 tools/devlease.py release-all  # release only OUR leases
"""
import contextlib
import json
import os
import time
from pathlib import Path

DIR = Path(os.environ.get("DEVICE_LEASE_DIR", Path.home() / ".device-lease"))
DEFAULT_TTL = 900          # 15 min: longer than any single run here, short enough
                           # that a crashed session frees the bench on its own.
OWNER = os.environ.get("DEVICE_LEASE_OWNER", "archive-watch")


def _path(dev):
    DIR.mkdir(parents=True, exist_ok=True)
    return DIR / f"{dev}.json"


def read(dev):
    """The current lease, or None when free/expired."""
    p = _path(dev)
    try:
        d = json.loads(p.read_text())
    except (OSError, ValueError):
        return None
    if d.get("expires", 0) < time.time():
        return None                     # expired: treated as free, not stolen
    return d


def try_lease(dev, task="", ttl=DEFAULT_TTL):
    """Take `dev` if it is free. Returns (ok, holder_description)."""
    held = read(dev)
    if held and held.get("pid") != os.getpid():
        who = held.get("owner", "?")
        what = held.get("task") or "unnamed work"
        left = int(held.get("expires", 0) - time.time())
        return False, f"{who} (pid {held.get('pid')}) — {what}, {left}s left"

    rec = {"owner": OWNER, "pid": os.getpid(), "task": task,
           "acquired": time.time(), "expires": time.time() + ttl}
    # O_EXCL so two processes racing for a free device cannot both win. Losing the
    # race is not an error — it means someone else got there first, which is the
    # whole point.
    tmp = _path(dev).with_suffix(".tmp")
    try:
        with open(tmp, "w") as f:
            json.dump(rec, f)
        os.replace(tmp, _path(dev))
    except OSError as e:
        return False, f"could not write lease: {e}"
    back = read(dev)
    if not back or back.get("pid") != os.getpid():
        return False, "lost the race to another session"
    return True, ""


def release(dev):
    held = read(dev)
    if held and held.get("pid") != os.getpid():
        return False                    # never release someone else's
    with contextlib.suppress(OSError):
        _path(dev).unlink()
    return True


def renew(dev, ttl=DEFAULT_TTL):
    """Extend our own lease. A long run must not expire mid-flight."""
    held = read(dev)
    if not held or held.get("pid") != os.getpid():
        return False
    held["expires"] = time.time() + ttl
    _path(dev).write_text(json.dumps(held))
    return True


@contextlib.contextmanager
def lease(dev, task="", ttl=DEFAULT_TTL, wait=0):
    """Hold `dev` for the block. Raises if it cannot be had within `wait` seconds."""
    deadline = time.time() + wait
    while True:
        ok, holder = try_lease(dev, task, ttl)
        if ok:
            break
        if time.time() >= deadline:
            raise RuntimeError(f"{dev} is leased by {holder}")
        time.sleep(3)
    try:
        yield
    finally:
        release(dev)


def status():
    DIR.mkdir(parents=True, exist_ok=True)
    rows = []
    for p in sorted(DIR.glob("*.json")):
        dev = p.stem
        d = read(dev)
        rows.append((dev, d))
    return rows


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "release-all":
        for dev, _ in status():
            print(f"  released {dev}" if release(dev) else f"  {dev} is not ours")
    else:
        for dev, d in status():
            if d is None:
                print(f"  {dev:12} free")
            else:
                left = int(d["expires"] - time.time())
                print(f"  {dev:12} {d['owner']} (pid {d['pid']}) — "
                      f"{d.get('task') or 'unnamed'}, {left}s left")
        if not status():
            print("  (no leases: the whole bench is free)")
