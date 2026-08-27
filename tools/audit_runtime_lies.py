#!/usr/bin/env python3
"""Find films whose catalog runtimeSeconds LIES, and the mistimed subtitles hiding behind it.

The Maggie (2026-08-27): its subsource file was PAL-scaled (0.960) and ran
33s late on the glass — and audit_subtitle_rate's overrun detector never
flagged it, because the catalog's runtime (5520s) was inflated by the SAME
4% PAL factor as the file. A file cannot "end past the runtime" when the
runtime lies by the ratio the file does. The only cure is measuring: ffprobe
the served copy's real duration (moov header only — cheap on faststart
files), compare, and re-run the cue-span physics against the MEASURED number.

Emits CSV: archiveID, catalogRuntime, measuredRuntime, ratio, lastCue,
cueVsMeasured, verdict. Verdicts:
  RUNTIME-LIE            catalog vs measured off by > 2%
  SUBS-OVERRUN-HIDDEN    file's cues end past the MEASURED runtime (the
                         Maggie class — retime with ffsubsync)
  OK / PROBE-FAIL

Usage:
  python3 tools/audit_runtime_lies.py [--limit N] [--workers 8]
      [--out tools/runtime_lie_audit.csv]
Targets claimed films only (that is where a lie hides a bad subtitle file).
"""
import argparse, csv, re, sqlite3, subprocess, sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

CUE_END = re.compile(r"-->\s*(\d+):(\d\d):(\d\d)[.,](\d\d\d)")


def probe_duration(url):
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "csv=p=0", url],
            capture_output=True, text=True, timeout=45)
        s = out.stdout.strip()
        return float(s) if s else None
    except Exception:
        return None


def last_cue_end(vtt_path):
    try:
        ends = [int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000
                for h, m, s, ms in CUE_END.findall(Path(vtt_path).read_text(errors="replace"))]
        return max(ends) if ends else None
    except OSError:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="/tmp/catalog-fresh.sqlite")
    ap.add_argument("--subs", default="/tmp/impact-fix/work/subs")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--out", default="tools/runtime_lie_audit.csv")
    args = ap.parse_args()

    db = sqlite3.connect(args.db)
    rows = db.execute("""
        SELECT archiveID, json_extract(json,'$.downloadURL'),
               json_extract(json,'$.runtimeSeconds')
        FROM item_json
        WHERE json_extract(json,'$.subtitleHLS') IS NOT NULL
          AND json_extract(json,'$.downloadURL') IS NOT NULL
          AND json_extract(json,'$.runtimeSeconds') > 600
        ORDER BY json_extract(json,'$.popularityScore') DESC""").fetchall()
    if args.limit:
        rows = rows[:args.limit]
    print(f"{len(rows)} claimed films to probe", flush=True)

    results = []
    done = 0

    def work(row):
        aid, url, cat = row
        measured = probe_duration(url)
        cue = last_cue_end(Path(args.subs) / aid / "en.vtt")
        return aid, cat, measured, cue

    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futures = [ex.submit(work, r) for r in rows]
        for f in as_completed(futures):
            aid, cat, measured, cue = f.result()
            done += 1
            if done % 200 == 0:
                print(f"  ...{done}/{len(rows)}", flush=True)
            if measured is None or measured < 60:
                results.append((aid, cat, "", "", cue or "", "", "PROBE-FAIL"))
                continue
            ratio = cat / measured if measured else 0
            lie = abs(ratio - 1.0) > 0.02
            over = cue is not None and cue > measured * 1.01
            verdict = ("SUBS-OVERRUN-HIDDEN" if over else
                       "RUNTIME-LIE" if lie else "OK")
            results.append((aid, cat, f"{measured:.0f}", f"{ratio:.3f}",
                            f"{cue:.0f}" if cue else "", f"{(cue / measured):.3f}" if cue else "",
                            verdict))

    with open(args.out, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["archiveID", "catalogRuntime", "measuredRuntime", "ratio",
                    "lastCue", "cueVsMeasured", "verdict"])
        w.writerows(results)
    from collections import Counter
    counts = Counter(r[-1] for r in results)
    print("verdicts:", dict(counts), flush=True)
    for r in results:
        if r[-1] == "SUBS-OVERRUN-HIDDEN":
            print("  RETIME:", r[0], f"cat={r[1]} meas={r[2]} cue={r[4]}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
