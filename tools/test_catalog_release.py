#!/usr/bin/env python3
"""catalog_release.publish against a fake release, in a temp dir; no gh, no network.

Cases: an unchanged catalog is not uploaded (only generatedAt differs); a
changed one is, and the uploaded gzip holds exactly the bytes that were
parsed; a release that moves AFTER the first check (while this run merges and
gzips) is merged onto again rather than clobbered; an item this run removed is
not resurrected by the merge; a removed item another writer changed since the
fetch is kept. Controls: a release that keeps moving is refused; a removal of
most of the catalog is refused.
"""
import gzip
import json
import sys
import tempfile
import types
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import catalog_release as C

ok = True


def check(name, cond):
    global ok
    ok &= bool(cond)
    print(f"  {'ok  ' if cond else 'FAIL'} {name}")


def doc(items, gen="2026-10-27T00:00:00Z"):
    return {"version": 1, "generatedAt": gen, "items": items}


def items(n=1200, **over):
    out = [{"archiveID": f"a{i}", "title": f"T{i}"} for i in range(n)]
    for k, v in over.items():
        out[int(k[1:])].update(v)
    return out


class Fake:
    """A release whose asset can be moved by 'another writer' on the Nth stamp read."""

    def __init__(self, d, tmp):
        self.doc, self.stamp_n, self.uploads, self.moves = d, 0, [], {}
        self.tmp = tmp

    def asset_stamp(self):
        self.stamp_n += 1
        if self.stamp_n in self.moves:
            self.doc = self.moves[self.stamp_n](self.doc)
            self.version = self.stamp_n
        return f"id|v{getattr(self, 'version', 0)}"

    def gh_net(self, *args):
        if args[:2] == ("release", "download"):
            with gzip.open(C.GZ, "wb") as fo:
                fo.write(json.dumps(self.doc).encode())
        elif args[:2] == ("release", "upload"):
            self.uploads.append(Path(args[3]).read_bytes())
        return types.SimpleNamespace(returncode=0, stdout="", stderr="")

    def swap_in(self, name):
        return "ok"


def setup(base_doc, mine_doc, moves=None):
    tmp = Path(tempfile.mkdtemp())
    C.REPO, C.CATALOG, C.GZ = tmp, tmp / "catalog.json", tmp / "catalog.json.gz"
    C.BASE, C.STAMP = tmp / ".base.gz", tmp / ".stamp"
    with gzip.open(C.BASE, "wb") as fo:
        fo.write(json.dumps(base_doc).encode())
    C.STAMP.write_text("id|v0")
    C.CATALOG.write_text(json.dumps(mine_doc))
    f = Fake(base_doc, tmp)
    f.moves = moves or {}
    C._asset_stamp = f.asset_stamp
    C._swap_in = f.swap_in
    C._gh_net = f.gh_net
    C._asset_size = lambda: 0
    C._release_state = lambda: "present"
    return f


def published(f):
    return json.loads(gzip.decompress(f.uploads[-1]))


# 1. unchanged (only generatedAt moved): nothing uploaded
f = setup(doc(items()), doc(items(), gen="2026-10-28T00:00:00Z"))
check("an unchanged catalog is not uploaded", C.publish() == 0 and not f.uploads)

# 2. changed: uploaded, and the gzip is the bytes on disk
f = setup(doc(items()), doc(items(a5={"title": "Fixed"})))
C.CATALOG.write_text(json.dumps(doc(items(a5={"title": "Fixed"})), indent=1))
raw = C.CATALOG.read_bytes()
check("a changed catalog is uploaded, the same bytes it parsed",
      C.publish() == 0 and len(f.uploads) == 1 and gzip.decompress(f.uploads[0]) == raw)

# 3. the release moves between the first check and the upload
def other_writer(d):
    d = json.loads(json.dumps(d))
    d["items"][7]["synopsis"] = "from another writer"
    return d
f = setup(doc(items()), doc(items(a5={"title": "Fixed"})), moves={2: other_writer})
rc = C.publish()
p = published(f) if f.uploads else {"items": []}
by = {i["archiveID"]: i for i in p["items"]}
check("a release that moves during the publish is merged onto, not clobbered",
      rc == 0 and len(f.uploads) == 1 and by.get("a7", {}).get("synopsis") == "from another writer"
      and by.get("a5", {}).get("title") == "Fixed")

# 4. a removed item is not resurrected by the merge; one changed since stays
mine = [i for i in items() if i["archiveID"] not in ("a3", "a4")]
def touch_a4(d):
    d = json.loads(json.dumps(d))
    d["items"][4]["synopsis"] = "enriched meanwhile"
    d["items"][9]["title"] = "theirs"
    return d
f = setup(doc(items()), doc(mine), moves={1: touch_a4})
rc = C.publish()
ids = {i["archiveID"]: i for i in published(f)["items"]} if f.uploads else {}
check("an item this run removed stays removed after the merge", rc == 0 and "a3" not in ids)
check("a removed item another writer changed since the fetch is kept", "a4" in ids)
check("the other writer's change survives the merge", ids.get("a9", {}).get("title") == "theirs")

# controls
f = setup(doc(items()), doc(items(a5={"title": "Fixed"})),
          moves={2: other_writer, 3: other_writer, 4: other_writer, 5: other_writer})
check("control: a release that keeps moving is refused", C.publish() == 3 and not f.uploads)
f = setup(doc(items(5000)), doc(items(1200)), moves={1: other_writer})
check("control: a merge that would remove most of the catalog is refused",
      C.publish() == 3 and not f.uploads)


# The swap: a release that is never without its catalog.
import importlib
importlib.reload(C)
NS = types.SimpleNamespace


class Assets:
    def __init__(self, names):
        self.a = {n: (str(i), "2026-11-04T00:00:00Z") for i, n in enumerate(names, 1)}
        self.log, self.deny, self.gaps = [], set(), 0

    def net(self, *args):
        if args[0] != "api":
            return NS(returncode=0, stdout="", stderr="")
        if "-X" not in args:
            return NS(returncode=0, stderr="", stdout="".join(
                f"{i} {c} {n}\n" for n, (i, c) in self.a.items()))
        aid = args[3].rsplit("/", 1)[1]
        name = next((n for n, v in self.a.items() if v[0] == aid), None)
        if args[2] == "DELETE":
            self.a.pop(name, None)
            self.log.append("delete")
            return NS(returncode=0, stdout="", stderr="")
        to = args[5].split("=", 1)[1]
        if name is None or to in self.deny or to in self.a:
            self.deny.discard(to)
            return NS(returncode=1, stdout="", stderr="HTTP 422")
        self.a[to] = self.a.pop(name)
        self.log.append("rename")
        if C.ASSET not in self.a:
            self.gaps += 1
        return NS(returncode=0, stdout="", stderr="")


s = Assets([C.ASSET, C.ASSET + ".next-1"])
C._gh_net = s.net
check("a swap succeeds", C._swap_in(C.ASSET + ".next-1") == "ok")
check("the new bytes hold the name", s.a[C.ASSET][0] == "2")
check("nothing else is left on the release", list(s.a) == [C.ASSET])
check("nothing is deleted until the new catalog is in place", s.log == ["rename", "rename", "delete"])
s = Assets([C.ASSET, C.ASSET + ".next-1"])
s.deny = {C.ASSET}
C._gh_net = s.net
check("a lost race reports itself", C._swap_in(C.ASSET + ".next-1") == "raced")
check("and the old catalog is put back", s.a.get(C.ASSET, ("",))[0] == "1")
s = Assets([C.ASSET])
C._gh_net = s.net
check("an upload that is not there changes nothing",
      C._swap_in(C.ASSET + ".next-9") == "failed" and list(s.a) == [C.ASSET])
s = Assets([C.ASSET, C.ASSET + ".next-1", C.ASSET + ".old-7"])
s.a[C.ASSET + ".old-7"] = ("3", "2020-01-01T00:00:00Z")
C._gh_net = s.net
C._swap_in(C.ASSET + ".next-1")
check("a leftover of a killed run is cleared", list(s.a) == [C.ASSET])
s = Assets([C.ASSET, C.ASSET + ".next-1", C.ASSET + ".next-2"])
s.a[C.ASSET + ".next-2"] = ("3", "2999-01-01T00:00:00Z")
C._gh_net = s.net
C._swap_in(C.ASSET + ".next-1")
check("CONTROL: another run's fresh upload is left alone", C.ASSET + ".next-2" in s.a)

# Fetch: a missing asset is a publish mid-swap, never a first run.
class Release:
    def __init__(self, appears_after):
        self.left, self.downloads = appears_after, 0

    def net(self, *args):
        self.downloads += 1
        if self.left > 0:
            self.left -= 1
            return NS(returncode=1, stdout="", stderr="no assets match the file pattern")
        with gzip.open(C.GZ, "wb") as fo:
            fo.write(json.dumps(doc(items(3))).encode())
        return NS(returncode=0, stdout="", stderr="")

    def gh(self, *args, **kw):
        return NS(returncode=0, stderr="", stdout=C.ASSET if self.left == 0 else "other.bin")


def fetch_case(appears_after, **kw):
    tmp = Path(tempfile.mkdtemp())
    C.REPO, C.CATALOG, C.GZ = tmp, tmp / "catalog.json", tmp / "catalog.json.gz"
    C.BASE, C.STAMP = tmp / ".base.gz", tmp / ".stamp"
    r = Release(appears_after)
    C._gh_net, C._gh = r.net, r.gh
    C._release_state = lambda: "present"
    C._asset_stamp = lambda: "id|v1"
    C.time.sleep = lambda s: None
    return C.fetch(**kw), C.CATALOG.exists()


check("a catalog mid-swap is waited for", fetch_case(2) == (0, True))
check("a catalog that never returns fails the run", fetch_case(99) == (1, False))
check("a person may still seed a new release", fetch_case(99, bootstrap=True) == (0, False))

print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
