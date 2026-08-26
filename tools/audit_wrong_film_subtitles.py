#!/usr/bin/env python3
"""Compare a local transcript of each film against its PUBLISHED subtitle file.

The doa_ipod lesson (2026-08-26): a published file can belong to a DIFFERENT
FILM entirely and pass every physics gate — its cue span fit the runtime at
1.013. Content agreement is the only true detector, and vocabulary overlap
is decisive: same-film pairs measure 0.8-1.0, the wrong-film pair measured
0.02, wrong-language files 0.00-0.06. The transcripts come from
tools/caption_gen_main.swift (the shipped on-device engine, quality-gated);
an imperfect ASR transcript still shares most CONTENT words with a correct
subtitle file, which is all the metric needs.

Usage:
  python3 tools/audit_wrong_film_subtitles.py --transcripts /tmp/wrongfilm-out \
      [--subs /tmp/impact-fix/work/subs] [--threshold 0.25]

Verdicts: OK (>= threshold), WRONG-FILM candidate (< threshold), SKIP (no
transcript / file). A candidate is a REPORT, not an action — adjudicate by
reading both files before touching any claim (Decision 084: record the
evidence, not just the verdict).
"""
import argparse, csv, re, sys
from pathlib import Path

STAMP = re.compile(r"-->|^\d+$|^WEBVTT|^X-TIMESTAMP|::cue|[{}]")


def vocab(path):
    words = set()
    try:
        for line in open(path, errors="replace"):
            if STAMP.search(line):
                continue
            for w in re.findall(r"[a-z']{4,}", line.lower()):
                words.add(w)
    except OSError:
        return set()
    return words


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--transcripts", required=True)
    ap.add_argument("--subs", default="/tmp/impact-fix/work/subs")
    ap.add_argument("--threshold", type=float, default=0.25)
    ap.add_argument("--out", default="tools/wrong_film_audit.csv")
    args = ap.parse_args()

    rows = []
    for tdir in sorted(Path(args.transcripts).iterdir()):
        if not tdir.is_dir():
            continue
        aid = tdir.name
        tv = vocab(tdir / "en.vtt")
        pv = vocab(Path(args.subs) / aid / "en.vtt")
        if len(tv) < 50 or len(pv) < 50:
            rows.append((aid, "", "SKIP", len(tv), len(pv)))
            continue
        ov = len(tv & pv) / min(len(tv), len(pv))
        verdict = "OK" if ov >= args.threshold else "WRONG-FILM?"
        rows.append((aid, f"{ov:.2f}", verdict, len(tv), len(pv)))

    with open(args.out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["archiveID", "overlap", "verdict", "transcriptWords", "fileWords"])
        w.writerows(rows)
    bad = [r for r in rows if r[2] == "WRONG-FILM?"]
    print(f"{len(rows)} judged -> {len(bad)} wrong-film candidates "
          f"({sum(1 for r in rows if r[2] == 'SKIP')} skipped)")
    for r in sorted(bad, key=lambda r: r[1]):
        print(f"  {r[1]}  {r[0]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
