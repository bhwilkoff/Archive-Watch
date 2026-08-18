#!/usr/bin/env python3
"""Clear subtitle tracks the app advertises but cannot load.

A film carrying `subtitleHLS` promises captions: tvOS fetches the VTT and
renders it as an overlay (Decision 070), and web/Android side-load it. When
that file 404s the promise fails silently — no captions, no error, on a title
whose Detail screen says it has them.

Measured 2026-08-18 on a 300-film sample of the 4,003 advertising a track:
1.7% dead, including films as popular as crisscross1949 and TheManFromUtah.
Small, but it is the app telling the viewer something untrue.

Costs nothing to check: the VTTs are on Pages, so this touches archive.org not
at all and can run beside anything.

NEVER condemns on a transient. Only 404/410 — a definitive "not here" — clears
the track; a timeout, a 429 or a 5xx leaves the film exactly as it was, the
same rule the poster validator follows (Decision 044). A guard that acts on a
throttle deletes real data on a bad afternoon.

Usage (inside the fetch/publish wrap):
  python tools/catalog_release.py fetch
  python tools/audit_dead_subtitles.py [--limit N] [--workers 8] [--apply]
  python tools/catalog_release.py publish
"""
import argparse, json, urllib.error, urllib.request
from concurrent.futures import ThreadPoolExecutor

CATALOG = "catalog.json"
UA = {"User-Agent": "ArchiveWatch-pipeline (dead subtitle audit)"}


def vtt_url(item):
    hls = item.get("subtitleHLS")
    return hls.rsplit("/", 1)[0] + "/en.vtt" if hls else None


def probe(item):
    url = vtt_url(item)
    if not url:
        return item, None
    try:
        req = urllib.request.Request(url, method="HEAD", headers=UA)
        with urllib.request.urlopen(req, timeout=20) as resp:
            return item, resp.status
    except urllib.error.HTTPError as e:
        return item, e.code
    except Exception:
        return item, None          # transient — never condemn


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--apply", action="store_true",
                    help="clear the dead tracks (default is report-only)")
    args = ap.parse_args()

    with open(CATALOG) as f:
        catalog = json.load(f)
    targets = [i for i in catalog["items"]
               if i.get("subtitleHLS") and not i.get("excluded")]
    targets.sort(key=lambda i: -(i.get("popularityScore") or 0))
    if args.limit:
        targets = targets[: args.limit]
    print(f"checking {len(targets)} advertised subtitle tracks", flush=True)

    live = dead = transient = 0
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        for n, (item, code) in enumerate(pool.map(probe, targets)):
            if code == 200:
                live += 1
            elif code in (404, 410):
                dead += 1
                print(f"  DEAD {item['archiveID'][:52]:52} HTTP {code}", flush=True)
                if args.apply:
                    # Reversible and additive: the track can be re-published by
                    # the subtitle pipeline, and `subtitleDead` records why it
                    # went so a later run does not re-advertise a 404.
                    item.pop("subtitleHLS", None)
                    item["captions"] = [c for c in (item.get("captions") or [])
                                        if c.get("source") not in (None, "published")]
                    item["subtitleDead"] = code
            else:
                transient += 1
            if n % 250 == 249:
                print(f"  ... {n+1}/{len(targets)} — {dead} dead", flush=True)

    print(f"\nlive {live} | dead {dead} | transient {transient}")
    if dead and live:
        print(f"dead rate among answered: {dead * 100 / (live + dead):.1f}%")
    if args.apply and dead:
        with open(CATALOG, "w") as f:
            json.dump(catalog, f, separators=(",", ":"))
        print(f"cleared {dead} dead tracks")
    elif dead:
        print("report-only; pass --apply to clear them")


if __name__ == "__main__":
    main()
