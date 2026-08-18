#!/usr/bin/env python3
"""Stamp the ACTUAL video codec on catalog items and fix the undecodables.

Owner report 2026-08-17: "Can't play this title — this copy's video is AV1"
on the Apple TV. The pipeline's playback verifier runs on a Mac, which CAN
decode AV1, so an uploader original labeled "MPEG4" sailed through every
gate and reached a device that renders it as audio over black. The label is
not the codec; only ffprobe is.

Targets: visible playable items whose videoFile.format does NOT already
guarantee h.264 ("h.264*" labels are archive-generated derivatives;
"512Kb/256Kb MPEG4" are the classic mp4v derives, which Apple decodes).
Everything else — bare "MPEG4", "QuickTime", "Matroska", "3gp", "HiRes" —
gets a real ffprobe (moov read only, a few hundred KB).

Writes `videoCodec` (additive; re-runs skip stamped items). For av1/vp9:
  1. swap downloadURL to a same-item archive-generated h.264 derivative
     (keeps the archiveID and everything keyed to it), else
  2. reversible `excluded=true` + `codecUnsupported` — and Decision 040's
     dedup then surfaces a same-imdb sibling copy as its own card on the
     next build, which is how The Oregon Trail-class films come back with
     a playable copy where one exists.

Usage (inside the fetch/publish wrap):
  python tools/catalog_release.py fetch
  python tools/audit_codecs.py [--limit N] [--workers 6] [--dry-run]
  python tools/catalog_release.py publish
"""
import argparse, json, subprocess, time, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor

CATALOG = "catalog.json"
SAFE_FORMAT_TOKENS = ("264",)          # "h.264", "h.264 IA", ... = derived h264
SAFE_FORMATS = {"512Kb MPEG4", "256Kb MPEG4"}   # classic mp4v derives, decodable
APPLE_OK = {"h264", "hevc", "mpeg4", "mjpeg", "prores"}
UA = {"User-Agent": "ArchiveWatch-pipeline (codec audit; contact ben@learningischange.com)"}


def needs_probe(item):
    if item.get("excluded") or not item.get("downloadURL"):
        return False
    if item.get("videoCodec"):
        return False
    fmt = (item.get("videoFile") or {}).get("format", "")
    if any(t in fmt for t in SAFE_FORMAT_TOKENS) or fmt in SAFE_FORMATS:
        return False
    return True


def probe(url):
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "v:0",
             "-show_entries", "stream=codec_name", "-of", "csv=p=0", url],
            capture_output=True, text=True, timeout=90)
        codec = out.stdout.strip().splitlines()[0].strip() if out.stdout.strip() else ""
        return codec or None
    except Exception:
        return None


def h264_derivative(item_id, current_name):
    try:
        req = urllib.request.Request(
            f"https://archive.org/metadata/{item_id}", headers=UA)
        with urllib.request.urlopen(req, timeout=20) as r:
            meta = json.load(r)
    except Exception:
        return None
    best = None
    for f in meta.get("files", []):
        name = f.get("name", "")
        if (not name.lower().endswith(".mp4") or name == current_name
                or f.get("source") != "derivative"
                or "264" not in (f.get("format") or "")):
            continue
        try:
            size = int(f.get("size", 0))
        except (TypeError, ValueError):
            continue
        if best is None or size > best[1]:
            best = (f, size)
    if not best:
        return None
    f = best[0]
    url = (f"https://archive.org/download/{item_id}/"
           + urllib.parse.quote(f["name"]))
    return {"name": f["name"], "format": f.get("format", "h.264"),
            "sizeBytes": best[1], "url": url}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--max-minutes", type=float, default=0,
                    help="stop probing after N minutes and RETURN so the caller "
                         "still publishes. A job killed by timeout-minutes never "
                         "reaches its publish step, so its work is lost outright "
                         "— which is exactly what happened to the 5.5-hour run "
                         "on 2026-08-17 (Decision 057's rule, applied to myself).")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(CATALOG) as f:
        catalog = json.load(f)
    targets = [i for i in catalog["items"] if needs_probe(i)]
    targets.sort(key=lambda i: -(i.get("popularityScore") or 0))
    if args.limit:
        targets = targets[: args.limit]
    print(f"probing {len(targets)} items", flush=True)

    stamped = bad = swapped = excluded = 0
    started = time.monotonic()
    budget = args.max_minutes * 60 if args.max_minutes else None
    stopped_early = False
    def work(item):
        return item, probe(item["downloadURL"])

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        for n, (item, codec) in enumerate(pool.map(work, targets)):
            if budget and time.monotonic() - started > budget:
                stopped_early = True
                print(f"  budget reached at {n}/{len(targets)} — stopping so the "
                      f"caller can publish", flush=True)
                break
            if codec is None:
                continue           # transient — never condemn on a failed probe
            stamped += 1
            item["videoCodec"] = codec
            if codec in APPLE_OK:
                pass
            else:
                bad += 1
                fix = h264_derivative(item["archiveID"],
                                      urllib.parse.unquote(
                                          item["downloadURL"].rsplit("/", 1)[-1]))
                if fix:
                    print(f"  SWAP {item['archiveID']}: {codec} -> {fix['format']} "
                          f"({fix['sizeBytes']//1_000_000}MB)", flush=True)
                    if not args.dry_run:
                        item["downloadURL"] = fix["url"]
                        item["videoFile"] = {"name": fix["name"],
                                             "format": fix["format"],
                                             "sizeBytes": fix["sizeBytes"],
                                             "tier": 2}
                        item["videoCodec"] = "h264"
                        item["codecSwapped"] = codec
                    swapped += 1
                else:
                    print(f"  EXCLUDE {item['archiveID']}: {codec}, no h264 derivative", flush=True)
                    if not args.dry_run:
                        item["excluded"] = True
                        item["codecUnsupported"] = codec
                    excluded += 1
            if n % 100 == 99:
                print(f"  ... {n+1}/{len(targets)} probed, {bad} bad "
                      f"({swapped} swapped, {excluded} excluded)", flush=True)
                # CHECKPOINT. This wrote only at the very end once, and a run
                # stopped at 4,700 of 9,101 items lost every probe it had
                # made — on a sweep whose whole design is "resumable via the
                # videoCodec stamp". A long sweep that cannot be interrupted
                # is not resumable, it just looks it.
                if not args.dry_run:
                    with open(CATALOG, "w") as f:
                        json.dump(catalog, f, separators=(",", ":"))

    print(f"stamped {stamped} | undecodable {bad} | swapped {swapped} | excluded {excluded}"
          + (" | STOPPED EARLY (budget)" if stopped_early else ""))
    if not args.dry_run and stamped:
        with open(CATALOG, "w") as f:
            json.dump(catalog, f, separators=(",", ":"))
        print("catalog written")


if __name__ == "__main__":
    main()
