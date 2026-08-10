#!/usr/bin/env python3
"""Central auto-captioning: pick films to caption, and publish what came back.

The in-app "Get subtitles" action can caption ONE film for ONE viewer at the
cost of downloading it. This does the same work once, on a macOS runner, so
every viewer on every platform gets the result — which is the only route to
"all films that can have subtitles, have them". Coverage is 16.6%; roughly
27,000 sound-era films have none.

The transcription itself is `tools/caption_gen_main.swift`, which compiles the
SHIPPED `AutoCaptions.swift` so the quality gate is literally the same code the
app uses. Measured: a 29-minute film -> 771 cues in 26 seconds, i.e. ~66x
realtime including the audio pull, so one runner clears ~690 films in a 5-hour
budget.

WHY THIS IS NOT DECISION 039a AGAIN. That was whisper.cpp, retired by 039b for
producing fluent, confident, WRONG dialogue on archival audio. Different engine
(SpeechTranscriber, macOS 26), every result passes CaptionQuality, and silent
films are excluded HERE — never offered to the recognizer at all, because
fabricating dialogue over a silent film is the worst outcome available and is
prevented by not running, not by inspecting afterwards.

    select   emit shard work lists of films worth captioning
    publish  validate returned VTTs, write /subs assets, wire the catalog

Usage:
    python3 tools/auto_captions.py select --shards 5 --limit 3000 --out work
    python3 tools/auto_captions.py publish --subs-in generated/ [--deltas-out d.json]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))

import build_subtitle_assets as B  # noqa: E402  (validate_vtt + hls_manifests + SUBS_DIR)

CATALOG = REPO / "catalog.json"
SOUND_ERA = 1930          # before this, a "film" is overwhelmingly silent
MIN_RUNTIME = 240         # a 4-minute clip is not worth a runner slot
LABEL = "English (auto-generated)"
SOURCE = "apple-speech"


def load_items():
    cat = json.load(open(CATALOG))
    return cat, (cat["items"] if isinstance(cat, dict) else cat)


def wants_captions(it) -> bool:
    """A film that could have subtitles and does not."""
    if it.get("excluded") or not it.get("downloadURL"):
        return False
    if it.get("captions") or it.get("subtitleHLS"):
        return False
    if it.get("autoCaptionTried"):            # attempted; don't burn a slot twice
        return False
    # Silent films are refused here, not detected later.
    if it.get("isSilentFilm") or it.get("contentType") == "silent-film":
        return False
    year = it.get("year")
    if year is not None and year < SOUND_ERA:
        return False
    if (it.get("runtimeSeconds") or 0) < MIN_RUNTIME:
        return False
    # TV series CARDS are not playable; their episodes are separate items.
    if it.get("contentType") == "tv-series":
        return False
    return True


def cmd_select(args) -> int:
    _, items = load_items()
    targets = [it for it in items if wants_captions(it)]
    targets.sort(key=lambda it: it.get("popularityScore") or 0, reverse=True)
    total = len(targets)
    if args.limit:
        targets = targets[:args.limit]

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    shards = max(1, args.shards)
    for s in range(shards):
        # Stride, don't slice: the list is popularity-ordered, so a contiguous
        # slice would hand one runner all the well-known films and another
        # nothing but the tail — and a partial run would then skew coverage.
        mine = targets[s::shards]
        payload = [{"id": it["archiveID"],
                    "url": it["downloadURL"],
                    "runtime": float(it.get("runtimeSeconds") or 0)}
                   for it in mine]
        (out / f"work-{s}.json").write_text(json.dumps(payload), encoding="utf-8")
        print(f"shard {s}: {len(payload)} films -> {out / f'work-{s}.json'}")
    print(f"[auto-captions] {len(targets)} selected of {total} eligible "
          f"({total - len(targets)} remain for later runs)")
    return 0


def cmd_publish(args) -> int:
    cat, items = load_items()
    by_id = {it.get("archiveID"): it for it in items}
    src = Path(args.subs_in)
    deltas, stats = {}, {"built": 0, "rejected": 0, "unknown": 0, "missing": 0}

    for vtt_path in sorted(src.glob("*/en.vtt")):
        aid = vtt_path.parent.name
        it = by_id.get(aid)
        if it is None:
            stats["unknown"] += 1
            continue
        vtt = vtt_path.read_text(encoding="utf-8", errors="replace")
        vtt, _paced = B.pace_vtt(vtt)   # no overlap; nothing too brief to read
        ok, why = B.validate_vtt(vtt, it.get("runtimeSeconds") or 0)
        if not ok:
            # The generator already gated this; a second look here catches a
            # truncated upload or a runtime we only learned later.
            print(f"  [auto-captions] {aid[:40]}: rejected ({why})")
            it["autoCaptionTried"] = True
            stats["rejected"] += 1
            continue

        sid = B.safe_dir(aid)
        out = B.SUBS_DIR / sid
        out.mkdir(parents=True, exist_ok=True)
        (out / "en.vtt").write_text(vtt, encoding="utf-8")
        base = f"{B.PAGES_BASE}/{sid}"
        langs = [("en", LABEL, "en.vtt")]
        master, video, subs = B.hls_manifests(it["downloadURL"],
                                              it.get("runtimeSeconds") or 0, langs)
        (out / "master.m3u8").write_text(master, encoding="utf-8")
        (out / "video.m3u8").write_text(video, encoding="utf-8")
        for lang, body in subs.items():
            (out / f"subs.{lang}.m3u8").write_text(body, encoding="utf-8")

        it["captions"] = [{"lang": "en", "label": LABEL, "format": "vtt",
                           "url": f"{base}/en.vtt", "vttURL": f"{base}/en.vtt",
                           "source": SOURCE}]
        it["subtitleHLS"] = f"{base}/master.m3u8"
        it["autoCaptionTried"] = True
        deltas[aid] = {"captions": it["captions"], "subtitleHLS": it["subtitleHLS"],
                       "autoCaptionTried": True}
        stats["built"] += 1

    # Films the generator attempted and refused never appear as a directory, so
    # mark them from the report — otherwise every run re-attempts the same
    # unusable audio forever.
    for rp in sorted(Path(args.subs_in).glob("report-*.json")):
        try:
            for r in json.loads(rp.read_text()):
                it = by_id.get(r.get("id"))
                if it is not None and not r.get("ok"):
                    it["autoCaptionTried"] = True
                    deltas.setdefault(r["id"], {})["autoCaptionTried"] = True
                    stats["missing"] += 1
        except (json.JSONDecodeError, OSError):
            continue

    if not args.dry_run:
        tmp = CATALOG.with_suffix(".json.tmp")
        json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
        tmp.replace(CATALOG)
    if args.deltas_out:
        Path(args.deltas_out).write_text(json.dumps(deltas), encoding="utf-8")

    print(f"[auto-captions] built={stats['built']} rejected={stats['rejected']} "
          f"attempted-but-unusable={stats['missing']} not-in-catalog={stats['unknown']}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("select")
    s.add_argument("--shards", type=int, default=5)
    s.add_argument("--limit", type=int, default=3000)
    s.add_argument("--out", default="work")
    s.set_defaults(fn=cmd_select)

    p = sub.add_parser("publish")
    p.add_argument("--subs-in", required=True)
    p.add_argument("--deltas-out")
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(fn=cmd_publish)

    args = ap.parse_args()
    if not CATALOG.exists():
        print("[auto-captions] no catalog.json (catalog_release.py fetch first)")
        return 2
    return args.fn(args)


if __name__ == "__main__":
    raise SystemExit(main())
