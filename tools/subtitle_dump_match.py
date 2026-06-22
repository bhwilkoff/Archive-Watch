#!/usr/bin/env python3
"""
subtitle_dump_match.py — match a one-time OpenSubtitles BULK DUMP to our catalog,
on a Mac, for $0 (Decision 039 Phase 3, the dump path that replaces the now-paid
OpenSubtitles.com API).

WHY a dump instead of an API: OpenSubtitles.com's API is effectively paid / capped
at ~20 free downloads/day, which can't backfill ~30k films. The full OpenSubtitles
library is published as a one-time dump of REAL .srt files with native timing
(milahu/opensubtitles-scraper -> archive.org `opensubs.db`), indexed to IMDb by the
free `subtitles_all.txt.gz` metadata export. Our films are public domain, so shipping
only the MATCHED subset is clean (attribution stays on the About screen). Sourcing was
the only problem; a local dump solves it with no rate limit.

THREE inputs (you download these once to an external SSD):
  1. subtitles_all.txt.gz   — 294 MB, the IMDb<->subtitle-id INDEX (the join key).
       https://dl.opensubtitles.org/addons/export/subtitles_all.txt.gz
  2. opensubs.db            — ~127 GB, the actual .srt blobs (extract phase only).
       https://archive.org/details/opensubtitles.org.Actually.Open.Edition.2022.07.25
  3. catalog.json           — our catalog (catalog_release.py fetch).

THREE modes — run them in order:

  # A. COVERAGE GATE (small, decisive — do this BEFORE downloading the 127 GB DB):
  python tools/subtitle_dump_match.py coverage --index subtitles_all.txt.gz
      -> prints "N of our films have an English sub in the dump" and writes
         shared/editorial/subtitle_dump_targets.csv (archiveID, imdbID, runtime,
         best sub id, all candidate ids). If coverage is low, stop here.

  # B. INSPECT the big DB once (so we NEVER guess its schema):
  python tools/subtitle_dump_match.py inspect --db opensubs.db
      -> prints tables/columns + a sample row so you can confirm the id + blob
         columns, then pass them to extract via --table/--id-col/--blob-col.

  # C. EXTRACT + sync-guard + write assets:
  python tools/subtitle_dump_match.py extract --index subtitles_all.txt.gz
      --db opensubs.db [--table subz --id-col idsubtitle --blob-col data] --limit 500
      -> for each matched film: pull the best .srt from the DB, decode, SYNC-GUARD
         against our runtime, write the same subs/<id>/ (VTT+HLS) the other phases
         emit, stamp captions:[{source:"opensubtitles-dump"}]. Resumable.

Publish like the other phases: tar subs -> subtitle-assets release -> catalog
publish -> deploy-pages -> publish-db.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import json
import re
import sqlite3
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_subtitle_assets import srt_to_vtt, hls_manifests, safe_dir, PAGES_BASE, SUBS_DIR  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
EDITORIAL = REPO / "shared" / "editorial"
TARGETS_CSV = EDITORIAL / "subtitle_dump_targets.csv"

# Per OpenSubtitles' terms (non-commercial + attribution); we already link them on About.
ATTRIBUTION = "opensubtitles.org"


# ----- imdb normalization (catalog stores "tt0017136"; export stores "17136") -----
def norm_imdb(v) -> str | None:
    if v is None:
        return None
    s = str(v).strip().lower()
    if s.startswith("tt"):
        s = s[2:]
    s = s.lstrip("0")
    return s or None  # numeric, zero-stripped; "0" -> None (no id)


def _last_cue_seconds(srt_text: str):
    """End time (s) of the LAST cue in an SRT, or None. Drives the sync guard."""
    times = re.findall(r"-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{3})", srt_text)
    if not times:
        return None
    h, m, s, ms = times[-1]
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000


def _cue_count(srt_text: str) -> int:
    return srt_text.count("-->")


# ----- the metadata index: stream subtitles_all.txt.gz -> {imdb: [candidates]} -----
def _open_index(path: Path):
    return gzip.open(path, "rt", encoding="utf-8", errors="replace")


def _map_columns(header: list[str]) -> dict:
    """Header-fuzzy column map so we never hardcode positions (the export's column
    order has drifted across years)."""
    idx = {}
    for i, h in enumerate(header):
        k = h.strip().lower().replace(" ", "").replace("_", "")
        if "idsubtitle" in k and "id" not in idx:
            idx["id"] = i
        elif k == "imdbid" or k == "idmovieimdb" or ("imdb" in k and "series" not in k and "imdb" not in idx):
            idx["imdb"] = i
        elif k in ("iso639", "subnameiso639", "languagename") and "lang" not in idx:
            idx["lang"] = i
        elif "subformat" in k and "fmt" not in idx:
            idx["fmt"] = i
        elif "moviekind" in k and "kind" not in idx:
            idx["kind"] = i
        elif ("downloadscnt" in k or "sumcd" in k or "downloadcount" in k) and "dl" not in idx:
            idx["dl"] = i
        elif "moviereleasename" in k and "release" not in idx:
            idx["release"] = i
    return idx


def load_index(path: Path, want_lang="en"):
    """Stream the export; keep only English MOVIE rows. Returns
    {imdb_numeric: [ {id, fmt, dl, release} ... ]} keeping memory small."""
    by_imdb: dict[str, list] = defaultdict(list)
    n = kept = 0
    with _open_index(path) as f:
        first = f.readline()
        delim = "\t" if first.count("\t") >= first.count(",") else ","
        header = first.rstrip("\n").split(delim)
        cols = _map_columns(header)
        if "id" not in cols or "imdb" not in cols:
            print(f"[dump] could not map id/imdb columns from header: {header[:8]}...")
            print("[dump] pass a different export, or fix _map_columns()")
            return by_imdb
        li, ii = cols["id"], cols["imdb"]
        lang_i, kind_i = cols.get("lang"), cols.get("kind")
        fmt_i, dl_i, rel_i = cols.get("fmt"), cols.get("dl"), cols.get("release")
        ncol = len(header)
        for line in f:
            n += 1
            if n % 1_000_000 == 0:
                print(f"[dump] scanned {n:,} index rows, kept {kept:,} en-movie subs", flush=True)
            row = line.rstrip("\n").split(delim)
            if len(row) < ncol:
                continue
            if lang_i is not None:
                lv = row[lang_i].strip().lower()
                if lv not in (want_lang, "english", "eng"):
                    continue
            if kind_i is not None and row[kind_i].strip().lower() in ("tv", "episode"):
                continue
            imdb = norm_imdb(row[ii])
            if not imdb:
                continue
            try:
                dl = int(row[dl_i]) if dl_i is not None and row[dl_i].strip().isdigit() else 0
            except (ValueError, IndexError):
                dl = 0
            by_imdb[imdb].append({
                "id": row[li].strip(),
                "fmt": (row[fmt_i].strip().lower() if fmt_i is not None and fmt_i < len(row) else ""),
                "dl": dl,
                "release": (row[rel_i].strip() if rel_i is not None and rel_i < len(row) else ""),
            })
            kept += 1
    print(f"[dump] index: {n:,} rows scanned, {kept:,} en-movie subs across {len(by_imdb):,} imdb ids", flush=True)
    return by_imdb


def _rank_candidates(cands: list) -> list:
    """Best first: prefer .srt format, then higher download count."""
    return sorted(cands, key=lambda c: (c["fmt"] == "srt", c["dl"]), reverse=True)


def _catalog_items():
    if not CATALOG.exists():
        print("[dump] no catalog.json (catalog_release.py fetch first)")
        return None, None
    cat = json.load(open(CATALOG))
    return cat, (cat["items"] if isinstance(cat, dict) else cat)


def _is_film(it) -> bool:
    return bool(it.get("downloadURL")) and not it.get("excluded") \
        and it.get("contentType") not in ("tv-series", "silent-film")


# ---------------------------------- modes ----------------------------------
def mode_coverage(args) -> int:
    by_imdb = load_index(Path(args.index))
    if not by_imdb:
        return 2
    cat, items = _catalog_items()
    if items is None:
        return 2
    EDITORIAL.mkdir(parents=True, exist_ok=True)
    tally = Counter()
    rows = []
    for it in items:
        if not _is_film(it):
            continue
        tally["films"] += 1
        imdb = norm_imdb(it.get("imdbID"))
        if not imdb:
            tally["no-imdb"] += 1
            continue
        tally["with-imdb"] += 1
        cands = by_imdb.get(imdb)
        if not cands:
            tally["no-sub-in-dump"] += 1
            continue
        if it.get("captions"):
            tally["already-captioned"] += 1
        tally["MATCH"] += 1
        ranked = _rank_candidates(cands)
        rows.append({
            "archiveID": it["archiveID"],
            "imdbID": it.get("imdbID") or "",
            "runtimeSeconds": it.get("runtimeSeconds") or 0,
            "already_captioned": int(bool(it.get("captions"))),
            "best_sub_id": ranked[0]["id"],
            "candidate_ids": "|".join(c["id"] for c in ranked[:8]),
        })
    rows.sort(key=lambda r: r["runtimeSeconds"], reverse=True)
    with open(TARGETS_CSV, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()) if rows else
                           ["archiveID", "imdbID", "runtimeSeconds", "already_captioned",
                            "best_sub_id", "candidate_ids"])
        w.writeheader()
        w.writerows(rows)
    print("\n[dump] COVERAGE")
    for k in ("films", "with-imdb", "no-imdb", "MATCH", "already-captioned", "no-sub-in-dump"):
        print(f"   {k:18} {tally[k]:>7,}")
    uncaptioned_matches = tally["MATCH"] - tally["already-captioned"]
    print(f"   {'NEW (uncaptioned)':18} {uncaptioned_matches:>7,}")
    print(f"\n[dump] wrote {len(rows):,} targets -> {TARGETS_CSV}")
    print("[dump] if MATCH is worth it, download opensubs.db and run `inspect` then `extract`.")
    return 0


def mode_inspect(args) -> int:
    con = sqlite3.connect(args.db)
    con.text_factory = bytes
    tables = [r[0].decode() for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")]
    print(f"[dump] {args.db}\n[dump] tables: {tables}\n")
    for t in tables:
        cols = con.execute(f"PRAGMA table_info('{t}')").fetchall()
        print(f"  TABLE {t}")
        for c in cols:
            print(f"    {c[1].decode():20} {c[2].decode()}")
        try:
            sample = con.execute(f"SELECT * FROM '{t}' LIMIT 1").fetchone()
            if sample:
                preview = [(v[:60] + b"...") if isinstance(v, bytes) and len(v) > 60 else v for v in sample]
                print(f"    sample: {preview}")
            cnt = con.execute(f"SELECT COUNT(*) FROM '{t}'").fetchone()[0]
            print(f"    rows: {cnt:,}")
        except sqlite3.Error as e:
            print(f"    (sample failed: {e})")
        print()
    print("[dump] pass --table/--id-col/--blob-col to extract based on the above.")
    return 0


def _decode_blob(b) -> str | None:
    if b is None:
        return None
    if isinstance(b, str):
        return b
    for enc in ("utf-8", "windows-1252", "iso-8859-1"):
        try:
            return b.decode(enc)
        except UnicodeDecodeError:
            continue
    return b.decode("utf-8", "replace")


def _find_schema(con):
    """Auto-detect (table, id-col, blob-col) when not given explicitly. Picks the
    table with an integer id-like col + a large text/blob col."""
    tables = [r[0].decode() for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")]
    for t in tables:
        cols = con.execute(f"PRAGMA table_info('{t}')").fetchall()
        names = [c[1].decode() for c in cols]
        types = [c[2].decode().upper() for c in cols]
        id_col = next((n for n in names if "idsub" in n.lower() or n.lower() in ("id", "subid")), None)
        blob_col = next((names[i] for i, ty in enumerate(types)
                         if ty in ("BLOB", "TEXT") and "id" not in names[i].lower()), None)
        if id_col and blob_col:
            return t, id_col, blob_col
    return None, None, None


def write_assets(item, srt_text):
    """SRT -> subs/<id>/ (VTT + HLS) + record captions. Mirrors the other phases."""
    sid = safe_dir(item["archiveID"])
    out = SUBS_DIR / sid
    out.mkdir(parents=True, exist_ok=True)
    (out / "en.vtt").write_text(srt_to_vtt(srt_text), encoding="utf-8")
    base = f"{PAGES_BASE}/{sid}"
    master, video, subs = hls_manifests(item["downloadURL"], item.get("runtimeSeconds") or 0,
                                         [("en", "English", "en.vtt")])
    (out / "master.m3u8").write_text(master, encoding="utf-8")
    (out / "video.m3u8").write_text(video, encoding="utf-8")
    (out / "subs.en.m3u8").write_text(subs["en"], encoding="utf-8")
    url = f"{base}/en.vtt"
    item["captions"] = [{"lang": "en", "label": "English", "format": "vtt",
                         "url": url, "vttURL": url, "source": "opensubtitles-dump",
                         "attribution": ATTRIBUTION}]
    item["subtitleHLS"] = f"{base}/master.m3u8"
    item["captionsChecked"] = True
    item.pop("whisperGenerated", None)


def mode_extract(args) -> int:
    by_imdb = load_index(Path(args.index))
    if not by_imdb:
        return 2
    cat, items = _catalog_items()
    if items is None:
        return 2
    con = sqlite3.connect(args.db)
    con.text_factory = bytes
    table, id_col, blob_col = args.table, args.id_col, args.blob_col
    if not (table and id_col and blob_col):
        table, id_col, blob_col = _find_schema(con)
        if not table:
            print("[dump] could not auto-detect DB schema; run `inspect` and pass "
                  "--table/--id-col/--blob-col")
            return 2
        print(f"[dump] auto-detected: table={table} id={id_col} blob={blob_col} "
              "(verify with `inspect` if results look wrong)")

    def fetch_srt(sub_id):
        try:
            row = con.execute(f"SELECT \"{blob_col}\" FROM \"{table}\" WHERE \"{id_col}\"=?",
                              (sub_id,)).fetchone()
        except sqlite3.Error:
            return None
        return _decode_blob(row[0]) if row else None

    targets = []
    for it in items:
        if not _is_film(it):
            continue
        if it.get("captions") and not args.upgrade:
            continue
        imdb = norm_imdb(it.get("imdbID"))
        if not imdb or imdb not in by_imdb:
            continue
        if args.upgrade and it.get("captions"):
            if not all(c.get("source") in ("whisper", "archive-asr") for c in it["captions"]):
                continue
        targets.append((it, _rank_candidates(by_imdb[imdb])))
    targets.sort(key=lambda t: t[0].get("popularityScore") or 0, reverse=True)
    if args.limit:
        targets = targets[:args.limit]
    print(f"[dump] {len(targets):,} films to extract", flush=True)

    def flush():
        tmp = CATALOG.with_suffix(".json.tmp")
        json.dump(cat, open(tmp, "w"), ensure_ascii=False, separators=(",", ":"))
        tmp.replace(CATALOG)

    tally = Counter()
    for n, (it, cands) in enumerate(targets, 1):
        rt = it.get("runtimeSeconds") or 0
        wrote = False
        for c in cands[:8]:  # walk candidates until one passes the sync guard
            srt = fetch_srt(c["id"])
            if not srt or _cue_count(srt) < 20:
                tally["empty/short"] += 1
                continue
            last = _last_cue_seconds(srt)
            if rt and last and abs(last - rt) / rt > 0.10:
                tally["sync-reject"] += 1
                continue
            write_assets(it, srt)
            tally["built"] += 1
            wrote = True
            print(f"[{n}] {it['archiveID']}: built (sub {c['id']}, {c['fmt']}, dl={c['dl']})", flush=True)
            break
        if not wrote:
            tally["no-good-sub"] += 1
        if n % 50 == 0:
            flush()
    flush()
    print(f"[dump] done: {dict(tally)}", flush=True)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="mode", required=True)

    c = sub.add_parser("coverage", help="metadata-only: how many films are covered")
    c.add_argument("--index", required=True, help="path to subtitles_all.txt.gz")
    c.set_defaults(fn=mode_coverage)

    i = sub.add_parser("inspect", help="print opensubs.db schema + a sample row")
    i.add_argument("--db", required=True)
    i.set_defaults(fn=mode_inspect)

    e = sub.add_parser("extract", help="pull best sub per film, sync-guard, write assets")
    e.add_argument("--index", required=True)
    e.add_argument("--db", required=True)
    e.add_argument("--table"); e.add_argument("--id-col"); e.add_argument("--blob-col")
    e.add_argument("--limit", type=int, default=0)
    e.add_argument("--upgrade", action="store_true",
                   help="also replace machine (whisper/asr) captions")
    e.set_defaults(fn=mode_extract)

    args = ap.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    raise SystemExit(main())
