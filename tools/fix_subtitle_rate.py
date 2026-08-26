#!/usr/bin/env python3
"""Repair subtitle files that DRIFT, by rescaling their timeline.

Companion to `audit_subtitle_rate.py`, which finds them. A file flagged
`rate` was authored against a different frame rate than the copy we stream —
almost always a PAL 25fps file laid over an NTSC 23.976fps transfer, or the
reverse — so its error GROWS with the runtime. Decisions 062/064 search for a
single constant offset and are structurally blind to this: no constant is
right for a file that is 0s off at the start and 200s off at the end.

The repair is arithmetic, and that is not a shortcut — it is measured. On
Earth vs. the Flying Saucers, rescaling every cue by 23.976/25 landed within
0.4s of the answer ffsubsync derived from the actual audio, at four points
spanning 50 minutes of film, checked against speech transcribed locally:

    spoken   published   rescaled   error      (ffsubsync's own error)
    1201.7s    1253.2s    1201.9s   +0.17s              +0.3s
    4302.0s    4485.7s    4302.0s   -0.03s               0.0s

So a whole fault class is repairable with NO film download, NO audio, and NO
speech models — which means it runs in CI, unlike Decision 064's sync sweep.

alass was evaluated and is the WRONG tool here: it models drift as a
staircase of splice shifts and pushed this film's last cue to 5176s on a
4818s film — 344s worse than doing nothing. Tool choice follows fault class;
see docs/research/captions-architecture-2026.md.

Every repair is gated on physics, not confidence: the rescaled file must end
INSIDE the film's runtime, start at or after zero, keep every cue, and stay
monotonic. A file that fails any of those is left exactly as published.

Usage:
  gh release download subtitle-assets -p subs.tar.gz && tar xzf subs.tar.gz
  python3 tools/audit_subtitle_rate.py --dry-run          # or use the CSV
  python3 tools/fix_subtitle_rate.py --subs subs --findings tools/subtitle_rate_findings.csv
  python3 tools/fix_subtitle_sync.py publish --subs subs  # one publish path
"""
import argparse, csv, re, shutil
from pathlib import Path
import sys as _sys
_sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_subtitle_assets import pace_vtt

TIMESTAMP = re.compile(r"(?P<h>\d+:)?(?P<m>\d{1,2}):(?P<s>\d{2})(?P<frac>[.,]\d{1,3})?")

# The telecine ratios. A file authored at 25fps and played at 23.976 runs
# LONG by 25/23.976; the reverse runs short by its inverse.
RATIOS = {"PAL->NTSC": 23.976 / 25}   # only the overrun case is provable

# The rescaled file must land inside the film. Credits and trailing silence
# mean a legitimate file can end well before the end, but never after it.
MAX_END_RATIO = 1.005
MIN_END_RATIO = 0.50


def stamp_to_seconds(text):
    m = TIMESTAMP.fullmatch(text.strip())
    if not m:
        return None
    hours = int((m.group("h") or "0:")[:-1] or 0)
    frac = float((m.group("frac") or "0").replace(",", ".")) if m.group("frac") else 0.0
    return hours * 3600 + int(m.group("m")) * 60 + int(m.group("s")) + frac


def seconds_to_stamp(value):
    value = max(value, 0.0)
    hours, rest = divmod(value, 3600)
    minutes, seconds = divmod(rest, 60)
    return f"{int(hours):02d}:{int(minutes):02d}:{seconds:06.3f}"


def rescale_vtt(body, factor):
    """Multiply every cue time by `factor`. Returns (text, times, ok)."""
    out, times = [], []
    for line in body.splitlines():
        if "-->" not in line:
            out.append(line)
            continue
        head, _, tail = line.partition("-->")
        parts = tail.strip().split(" ", 1)
        start, end = stamp_to_seconds(head.strip()), stamp_to_seconds(parts[0])
        if start is None or end is None:
            out.append(line)
            continue
        rest = (" " + parts[1]) if len(parts) > 1 else ""
        ns, ne = start * factor, end * factor
        times.append((ns, ne))
        out.append(f"{seconds_to_stamp(ns)} --> {seconds_to_stamp(ne)}{rest}")
    return "\n".join(out) + "\n", times


def validate(times, original_count, runtime):
    """Physics, not confidence. Any failure means we publish nothing."""
    if len(times) != original_count:
        return "cue count changed"
    if not times:
        return "no cues"
    if times[0][0] < -0.001:
        return "starts before zero"
    if any(b[0] < a[0] - 0.001 for a, b in zip(times, times[1:])):
        return "non-monotonic"
    end = times[-1][1]
    if end > runtime * MAX_END_RATIO:
        return f"still overruns ({end:.0f}s vs {runtime}s)"
    if end < runtime * MIN_END_RATIO:
        return f"ends far too early ({end:.0f}s vs {runtime}s)"
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--subs", default="subs", help="extracted subs/ directory")
    ap.add_argument("--findings", default="tools/subtitle_rate_findings.csv")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    subs = Path(args.subs)
    # Only files PROVEN mistimed (they end after the film) whose overrun is
    # explained by a telecine ratio. Everything else needs audio-based sync.
    rows = [r for r in csv.DictReader(open(args.findings))
            if r["verdict"] == "overruns" and r["cause"] in RATIOS]
    rows.sort(key=lambda r: -float(r.get("pop") or 0))
    if args.limit:
        rows = rows[: args.limit]
    print(f"{len(rows)} rate-mistimed files to repair")

    fixed = skipped = 0
    for r in rows:
        aid, cause, runtime = r["archiveID"], r["cause"], int(r["runtime"])
        vtt = subs / aid / "en.vtt"
        if not vtt.is_file():
            print(f"  SKIP {aid}: no local en.vtt (extract subs.tar.gz first)")
            skipped += 1
            continue
        factor = RATIOS.get(cause)
        if factor is None:
            print(f"  SKIP {aid}: unknown cause {cause!r}")
            skipped += 1
            continue
        body = vtt.read_text(encoding="utf-8", errors="replace")
        original_count = body.count("-->")
        new_body, times = rescale_vtt(body, factor)
        problem = validate(times, original_count, runtime)
        if problem:
            print(f"  REJECT {aid}: {problem}")
            skipped += 1
            continue
        before = float(r["lastCue"])
        print(f"  FIX  {aid[:44]:44} x{factor:.5f} ({cause})  "
              f"last {before:.0f}s -> {times[-1][1]:.0f}s  (runtime {runtime}s)")
        if not args.dry_run:
            shutil.copy2(vtt, vtt.with_suffix(".vtt.orig"))
            new_body, _paced = pace_vtt(new_body)   # D059 pacing on every mutation
            vtt.write_text(new_body, encoding="utf-8")
        fixed += 1

    print(f"\nrepaired {fixed} | skipped {skipped}")
    if fixed and not args.dry_run:
        print("publish with: python3 tools/fix_subtitle_sync.py publish --subs " + str(subs))


if __name__ == "__main__":
    main()
