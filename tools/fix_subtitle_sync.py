#!/usr/bin/env python3
"""Correct published subtitle files that are out of sync with their own film.

The app checks this per viewer, per playback, and only on Apple platforms
(Decision 062). Fixing the FILE fixes it once for everyone — web and Android
included, and neither of those can transcribe on device, so this is the only
route by which they get correct subtitles at all.

Three stages, each runnable on its own:

  work     build a work list, popularity-first, from the published subs
  apply    read verdicts and rewrite the files
  publish  repack subs.tar.gz, upload it, and redeploy Pages

The listening between `work` and `apply` is done by tools/subtitle_sync_main.swift,
which must run on a machine that HAS speech models — a hosted runner does not and
cannot get them (Decision 060).

What `apply` does with each verdict:

  keep      nothing
  shift     rewrite every cue time in the VTT by the measured offset
  mismatch  REPORTED ONLY unless --drop-mismatched is passed. Deleting a
            subtitle set is destructive and irreversible from here, and the
            mismatch threshold has not been validated at this scale — the same
            precision-over-recall rule that governs hiding items (Decisions
            027/035/044). A shift, by contrast, is a pure rewrite that a later
            re-run corrects if it was wrong.
  unheard / no-verdict / error
            nothing. A film we could not hear is not a film with bad
            subtitles, and treating silence as evidence would delete good files.

Usage:
  python3 tools/fix_subtitle_sync.py work  --subs /tmp/subsfix/subs --out work.json [--limit N]
  python3 tools/fix_subtitle_sync.py apply --subs /tmp/subsfix/subs --verdicts verdicts.jsonl
        [--catalog catalog.json] [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PAGES = "https://archivewatch.org"

# A shift smaller than this is inside cue-boundary noise and not worth
# rewriting a published file for.
MIN_SHIFT = 1.0

TIMESTAMP = re.compile(
    r"(?P<h>\d+:)?(?P<m>\d{1,2}):(?P<s>\d{2})(?P<frac>[.,]\d{1,3})?"
)


def shard_of(archive_id: str) -> str:
    """FNV-1a low byte — the same sharding the web detail files use."""
    h = 2166136261
    for byte in archive_id.encode():
        h ^= byte
        h = (h * 16777619) & 0xFFFFFFFF
    return "%02x" % (h & 0xFF)


def stamp_to_seconds(text: str) -> float | None:
    m = TIMESTAMP.fullmatch(text.strip())
    if not m:
        return None
    hours = int((m.group("h") or "0:")[:-1] or 0)
    frac = float((m.group("frac") or "0").replace(",", ".")) if m.group("frac") else 0.0
    return hours * 3600 + int(m.group("m")) * 60 + int(m.group("s")) + frac


def seconds_to_stamp(value: float) -> str:
    value = max(value, 0.0)
    hours, rest = divmod(value, 3600)
    minutes, seconds = divmod(rest, 60)
    return f"{int(hours):02d}:{int(minutes):02d}:{seconds:06.3f}"


def shift_vtt(body: str, by: float) -> tuple[str, int]:
    """Move every cue time by `by` seconds. Returns (text, cues moved)."""
    out, moved = [], 0
    for line in body.splitlines():
        if "-->" in line:
            head, _, tail = line.partition("-->")
            # A cue line can carry positioning settings after the end stamp;
            # keep whatever follows untouched.
            tail_parts = tail.strip().split(" ", 1)
            start = stamp_to_seconds(head.strip())
            end = stamp_to_seconds(tail_parts[0])
            if start is None or end is None:
                out.append(line)
                continue
            rest = (" " + tail_parts[1]) if len(tail_parts) > 1 else ""
            out.append(
                f"{seconds_to_stamp(start + by)} --> {seconds_to_stamp(end + by)}{rest}"
            )
            moved += 1
        else:
            out.append(line)
    return "\n".join(out) + "\n", moved


def detail_url(archive_id: str, cache: dict) -> str | None:
    """The playable MP4, from the web detail shards."""
    shard = shard_of(archive_id)
    if shard not in cache:
        try:
            with urllib.request.urlopen(f"{PAGES}/details/{shard}.json", timeout=60) as r:
                cache[shard] = json.load(r)
        except Exception:
            cache[shard] = {}
    record = cache[shard].get(archive_id)
    return record[0] if record and record[0] else None


def cmd_work(args: argparse.Namespace) -> int:
    subs = Path(args.subs)
    ids = sorted(d.name for d in subs.iterdir() if (d / "en.vtt").is_file())
    print(f"[work] {len(ids)} films have a published English track")

    # Popularity-first: a mistimed file on a film nobody opens matters less than
    # one on the front page. The index is ordered by popularity already.
    order: dict[str, int] = {}
    try:
        with urllib.request.urlopen(f"{PAGES}/catalog-index.json", timeout=120) as r:
            index = json.load(r)
        rows = index.get("items") or index.get("rows") or []
        for rank, row in enumerate(rows):
            key = row[0] if isinstance(row, list) else row.get("id")
            if isinstance(key, str):
                order.setdefault(key, rank)
        print(f"[work] popularity known for {len(order)} catalog items")
    except Exception as exc:  # the sweep still works unordered
        print(f"[work] no popularity order ({exc}); using alphabetical")

    ids.sort(key=lambda i: (order.get(i, 10**9), i))
    if args.limit:
        ids = ids[: args.limit]

    cache: dict = {}
    jobs, skipped = [], 0
    for archive_id in ids:
        url = detail_url(archive_id, cache)
        if not url:
            skipped += 1
            continue
        jobs.append(
            {"id": archive_id, "mp4": url, "vtt": f"{PAGES}/subs/{archive_id}/en.vtt"}
        )
    Path(args.out).write_text(json.dumps(jobs, indent=1))
    print(f"[work] wrote {len(jobs)} jobs to {args.out} ({skipped} had no playable URL)")
    return 0


def cmd_apply(args: argparse.Namespace) -> int:
    subs = Path(args.subs)
    verdicts = []
    for line in Path(args.verdicts).read_text().splitlines():
        line = line.strip()
        if line:
            verdicts.append(json.loads(line))
    print(f"[apply] {len(verdicts)} verdicts")

    counts: dict[str, int] = {}
    for verdict in verdicts:
        counts[verdict.get("choice", "?")] = counts.get(verdict.get("choice", "?"), 0) + 1
    print("[apply] " + " · ".join(f"{k} {v}" for k, v in sorted(counts.items())))

    shifted, dropped, cues_moved = [], [], 0
    for verdict in verdicts:
        archive_id = verdict["id"]
        choice = verdict.get("choice")
        folder = subs / archive_id

        if choice == "shift":
            by = float(verdict.get("shift", 0))
            if abs(by) < MIN_SHIFT:
                continue
            vtt = folder / "en.vtt"
            if not vtt.is_file():
                continue
            body, moved = shift_vtt(vtt.read_text(encoding="utf-8", errors="replace"), by)
            if moved == 0:
                print(f"  ! {archive_id}: no cue lines parsed — left alone")
                continue
            if not args.dry_run:
                vtt.write_text(body, encoding="utf-8")
            shifted.append((archive_id, by, moved))
            cues_moved += moved

        elif choice == "mismatch":
            dropped.append(archive_id)
            if args.drop_mismatched and not args.dry_run and folder.is_dir():
                for child in folder.iterdir():
                    child.unlink()
                folder.rmdir()

    print(f"\n[apply] shifted {len(shifted)} files ({cues_moved} cues moved)")
    for archive_id, by, moved in shifted[:15]:
        print(f"    {by:+7.1f}s  {moved:5d} cues  {archive_id}")
    if len(shifted) > 15:
        print(f"    … and {len(shifted) - 15} more")
    verb = "removed" if args.drop_mismatched else "FLAGGED (not removed)"
    print(f"[apply] {verb} {len(dropped)} subtitle sets that look like another film")
    for archive_id in dropped[:10]:
        print(f"    {archive_id}")

    if dropped and args.catalog and args.drop_mismatched:
        clear_catalog_captions(Path(args.catalog), set(dropped), args.dry_run)

    if args.dry_run:
        print("\n[apply] DRY RUN — nothing written")
    return 0


def clear_catalog_captions(catalog_path: Path, ids: set[str], dry_run: bool) -> None:
    """Stop advertising subtitles that turned out to be the wrong film's.

    Leaving the assets deleted but the item still claiming `subtitleHLS` would
    give every client a 404 where subtitles used to be — worse than no claim.
    """
    if not catalog_path.is_file():
        print(f"[apply] no catalog at {catalog_path}; skipped clearing the claims")
        return
    catalog = json.loads(catalog_path.read_text())
    items = catalog.get("items", catalog if isinstance(catalog, list) else [])
    cleared = 0
    for item in items:
        if item.get("archiveID") in ids:
            if item.pop("subtitleHLS", None) is not None:
                cleared += 1
            item.pop("captions", None)
            item["subtitlesMismatched"] = True
    print(f"[apply] cleared subtitle claims on {cleared} catalog items")
    if not dry_run and cleared:
        catalog_path.write_text(json.dumps(catalog))


def cmd_publish(args: argparse.Namespace) -> int:
    """Repack the corrected subtitles and put them where every platform reads.

    The published set lives in ONE place — subs.tar.gz on the subtitle-assets
    release — which deploy-pages restores into the site. So a correction here
    reaches web, Android and every Apple platform at once, without an app build.
    """
    import subprocess

    subs = Path(args.subs)
    count = sum(1 for _ in subs.rglob("*.vtt"))
    if count < args.min_files:
        print(f"[publish] REFUSING: only {count} vtt files, expected at least "
              f"{args.min_files}. A shrunken set means something went wrong "
              f"upstream, and republishing it would delete subtitles wholesale.")
        return 1
    print(f"[publish] {count} vtt files")

    tarball = subs.parent / "subs.tar.gz"
    if not args.dry_run:
        subprocess.run(["tar", "czf", str(tarball), "-C", str(subs.parent), subs.name],
                       check=True)
        size = tarball.stat().st_size
        print(f"[publish] packed {size/1e6:.0f} MB")
        subprocess.run(["gh", "release", "upload", "subtitle-assets", str(tarball),
                        "--clobber"], cwd=str(REPO), check=True)
        print("[publish] uploaded to the subtitle-assets release")
        subprocess.run(["gh", "workflow", "run", "deploy-pages.yml"], cwd=str(REPO),
                       check=False)
        print("[publish] deploy-pages dispatched")
    else:
        print("[publish] DRY RUN — nothing packed or uploaded")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)

    w = sub.add_parser("work")
    w.add_argument("--subs", required=True)
    w.add_argument("--out", required=True)
    w.add_argument("--limit", type=int, default=0)
    w.set_defaults(func=cmd_work)

    a = sub.add_parser("apply")
    a.add_argument("--subs", required=True)
    a.add_argument("--verdicts", required=True)
    a.add_argument("--catalog", default="")
    a.add_argument("--dry-run", action="store_true")
    a.add_argument("--drop-mismatched", action="store_true",
                   help="also DELETE subtitle sets judged to be another film's")
    a.set_defaults(func=cmd_apply)

    p = sub.add_parser("publish")
    p.add_argument("--subs", required=True)
    p.add_argument("--min-files", type=int, default=7000,
                   help="floor below which the set is assumed damaged")
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(func=cmd_publish)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
