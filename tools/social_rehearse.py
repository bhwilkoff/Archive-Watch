#!/usr/bin/env python3
"""
social_rehearse.py — run the programme forward N days and show the result.

A single sample is not evidence about a programme. The first CI run produced
one perfectly good card and one teaser that was nearly black; both looked
fine in isolation, and only a BATCH shows whether the week reads as a
repertory calendar or as a random-number generator with a poster attached.

Produces, for a date range, without posting anything:
  * every day's post spec, card and (optionally) teaser,
  * a CONTACT SHEET — all the cards on one image, in programme order,
  * a report: the slot mix, the decade spread, repeats, and any day the
    selector could not fill.

The ledger is simulated in memory, so a rehearsal never touches the real one
and never blocks a film from being posted for real later.

Run:
  python tools/social_rehearse.py --days 10
  python tools/social_rehearse.py --days 14 --clips --out /tmp/rehearsal
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LEDGER = REPO / "social" / "posted.json"

# print() is BLOCK-BUFFERED when stdout is not a terminal, so a long run in CI
# or a background shell shows nothing at all until it ends — recorded in this
# repo already (the macOS download audit sat silent for nine minutes with its
# verdicts in the buffer). A rehearsal is minutes long by design.
try:
    sys.stdout.reconfigure(line_buffering=True)
except AttributeError:  # pragma: no cover
    pass


def run(cmd: list, timeout: int = 900, env=None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                          env=env)


def contact_sheet(cards: list, out: Path, cols: int = 5) -> None:
    """All the cards on one image. Judging a programme means seeing it as a
    viewer would scrolling a profile grid — the failure this catches is
    sameness, which no single card can show you."""
    from PIL import Image, ImageDraw, ImageFont

    if not cards:
        return
    cell, pad, label_h = 340, 16, 34
    rows = (len(cards) + cols - 1) // cols
    W = cols * cell + pad * (cols + 1)
    H = rows * (cell + label_h) + pad * (rows + 1)
    sheet = Image.new("RGB", (W, H), (11, 11, 12))
    draw = ImageDraw.Draw(sheet)
    try:
        f = ImageFont.truetype(str(REPO / "roku" / "fonts" / "Inter-Regular.ttf"), 19)
    except OSError:
        f = ImageFont.load_default()

    for i, (path, caption) in enumerate(cards):
        r, c = divmod(i, cols)
        x = pad + c * (cell + pad)
        y = pad + r * (cell + label_h + pad)
        try:
            im = Image.open(path).convert("RGB")
        except Exception:  # noqa: BLE001
            continue
        im.thumbnail((cell, cell), Image.LANCZOS)
        sheet.paste(im, (x + (cell - im.width) // 2, y))
        text = caption if draw.textlength(caption, font=f) <= cell else caption
        while draw.textlength(text, font=f) > cell and len(text) > 4:
            text = text[:-2]
        draw.text((x, y + cell + 8), text, font=f, fill=(154, 154, 160))
    sheet.save(out, "JPEG", quality=88, optimize=True)
    print(f"[rehearse] contact sheet -> {out}  ({len(cards)} cards)")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--days", type=int, default=10)
    ap.add_argument("--start", default=None, help="YYYY-MM-DD (default: tomorrow)")
    ap.add_argument("--out", default="/tmp/aw-rehearsal")
    ap.add_argument("--clips", action="store_true", help="also cut the teasers")
    ap.add_argument("--index", default="/tmp/clips.sqlite")
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    # Fetch the 7 MB index ONCE. The selector accepts a local path, and a
    # ten-day rehearsal that downloads it ten times spends most of its wall
    # clock on the same file.
    cached = out / "catalog-index.json"
    if not cached.exists():
        import urllib.request
        print("[rehearse] fetching the catalog index once…")
        req = urllib.request.Request("https://archivewatch.org/catalog-index.json",
                                     headers={"User-Agent": "ArchiveWatch-Social/1.0"})
        with urllib.request.urlopen(req, timeout=180) as r:
            cached.write_bytes(r.read())
    start = (dt.date.fromisoformat(args.start) if args.start
             else dt.date.today() + dt.timedelta(days=1))

    # The real ledger is put aside for the run and restored in `finally`, so a
    # rehearsal can never burn a film the programme has not actually posted.
    saved = LEDGER.read_text(encoding="utf-8") if LEDGER.exists() else None
    sim = {"_": "rehearsal (in memory)", "posts": []}
    rows, cards = [], []
    try:
        for i in range(args.days):
            day = (start + dt.timedelta(days=i)).isoformat()
            LEDGER.write_text(json.dumps(sim), encoding="utf-8")
            spec_path = out / f"{day}.json"
            env = {**os.environ, "AW_SOCIAL_CACHE": str(out / "shards")}
            r = run([sys.executable, str(REPO / "tools" / "social_select.py"),
                     "--slot", "auto", "--date", day, "--out", str(spec_path),
                     "--index", str(cached)], env=env)
            if r.returncode != 0:
                rows.append({"date": day, "error": r.stderr.strip()[:90]})
                print(f"  {day}  COULD NOT FILL — {r.stderr.strip()[:70]}")
                continue
            spec = json.loads(spec_path.read_text(encoding="utf-8"))

            card = out / f"{day}-card.jpg"
            run([sys.executable, str(REPO / "tools" / "social_card.py"),
                 "--spec", str(spec_path), "--size", "square", "--out", str(card)])

            clip_note = ""
            if args.clips:
                clip = out / f"{day}-clip.mp4"
                rc = run([sys.executable, str(REPO / "tools" / "social_clip.py"),
                          "--spec", str(spec_path), "--index", args.index,
                          "--out", str(clip)])
                clip_note = ("clip" if rc.returncode == 0 and clip.exists()
                             else "no clip")

            has_review = any(f["kind"] == "review" for f in spec["fragments"])
            rows.append({"date": day, "dow": (start + dt.timedelta(days=i)).strftime("%a"),
                         "slot": spec["slot"], "title": spec["title"],
                         "year": spec["year"], "id": spec["id"],
                         "kind": spec["contentType"], "review": has_review,
                         "clip": clip_note})
            if card.exists():
                cards.append((card, f"{spec['title'][:30]} ({spec['year']})"))
            sim["posts"].append({"at": dt.datetime.now(dt.timezone.utc).isoformat(),
                                 "id": spec["id"], "title": spec["title"],
                                 "slot": spec["slot"], "platform": "rehearsal",
                                 "url": "rehearsal", "reviewer": spec.get("reviewer")})
            print(f"  {day} {rows[-1]['dow']}  {spec['slot']:16s} "
                  f"{spec['title'][:38]:38s} {str(spec['year']):5s} "
                  f"{'quote' if has_review else '     '} {clip_note}")
    finally:
        if saved is not None:
            LEDGER.write_text(saved, encoding="utf-8")

    good = [r for r in rows if "error" not in r]
    print("\n--- the programme, as a whole ---")
    print(f"days filled      : {len(good)} of {args.days}")
    ids = [r["id"] for r in good]
    print(f"unique films     : {len(set(ids))} of {len(ids)}"
          f"{'  ** REPEAT **' if len(set(ids)) != len(ids) else ''}")
    print(f"slots            : {dict(Counter(r['slot'] for r in good))}")
    print(f"kinds            : {dict(Counter(r['kind'] for r in good))}")
    decades = Counter((r["year"] // 10 * 10) for r in good if r["year"])
    print(f"decades          : {dict(sorted(decades.items()))}")
    print(f"with a quote     : {sum(1 for r in good if r['review'])}")
    if args.clips:
        print(f"with a teaser    : {sum(1 for r in good if r['clip'] == 'clip')}")
    # Sameness is the failure a batch exists to catch.
    top_kind = Counter(r["kind"] for r in good).most_common(1)
    if good and top_kind and top_kind[0][1] > len(good) * 0.6:
        print(f"\n!! {top_kind[0][0]} is {top_kind[0][1]}/{len(good)} of the run — "
              f"the programme reads as one note")
    if decades and max(decades.values()) > len(good) * 0.6:
        print("\n!! one decade dominates the run")

    contact_sheet(cards, out / "contact-sheet.jpg")
    (out / "report.json").write_text(json.dumps(rows, indent=1), encoding="utf-8")
    print(f"[rehearse] {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
