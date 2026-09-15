#!/usr/bin/env python3
"""
audit_title_wants.py — judge every catalog item that Decision 032's wants hunt
resolved BY TITLE against the Archive item's OWN title and date.

Why this exists (2026-09-14). The owner saw "a slideshow of Minnie Mouse
stills" in Party Play. The catalog had it as the 1922 silent feature *Minnie*
— year, IMDb id, cast, Commons poster — because `resolve_title` gave a
one-word want a full word-overlap score against ANY upload containing that
word, and the gallery carried no year so the wrong-year penalty never fired.
`remediate_catalog` then ADOPTED the match's canonical title over the
uploader's, so in the catalog the wrong match reads as an exact one: a
Ukrainian war video is titled "Civilian Clothes", a Holocaust-denial video
"The Denial", a Duran Duran edit "New Moon". Nothing in the catalog can judge
these any more; only archive.org can (Decision 026: the item's own signals).

What it does: for every want with status=ingested and resolvedVia=title,
fetch /metadata/<id>/metadata, keep title/date/collection/mediatype in a
committed cache (resumable; the fetch is the expensive part), and file a
verdict:

  wrong   a want word is missing from the Archive title; OR the Archive title
          carries stray words (not the want, not a benign token like a year
          or "restored") and either has no date or a date outside the want's
          year +-2; OR the Archive date itself contradicts the want year by
          more than 2 (a 1938 "Sex Madness aka Human Wreckage" is not the
          1923 Human Wreckage); OR the title matches the clip/compilation noise
          pattern.
  keep    everything else — an exact title, or extras with a matching date
          ("The Leatherneck (1929) Reels Two & Five ...").

`--apply` sets `excluded=True` + `wrongMatchTitle={...}` on the catalog for
`wrong`, records `archiveTitle` on every audited item so the next judge needs
no fetch, and audit_rights.bucket() hides on the marker every build.
Report-first: without --apply nothing but the cache changes.

Usage:
    python3 tools/audit_title_wants.py            # fetch + report
    python3 tools/audit_title_wants.py --apply    # also mark the catalog
    python3 tools/audit_title_wants.py --limit 200 --rate 2
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import archive_lib as A  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
QUEUE = REPO / "shared/editorial/discovery_candidates.json"
CACHE = REPO / "shared/editorial/want_match_audit.json"

STOP = {"the", "a", "an", "of", "and", "in", "on", "le", "la", "les", "der", "die",
        "das", "el", "los", "las", "de", "du", "et", "il", "un", "une", "ein", "to",
        "for", "at", "by", "with", "or"}
# Words an honest upload title adds to a film's name.
BENIGN = re.compile(
    r"^(\d{4}|restored|restoration|hd|4k|1080p|720p|480p|film|movie|full|silent|"
    r"complete|version|remastered|colorized|colorised|dvd|bluray|blu|ray|vhs|rip|"
    r"x264|h264|h|264|mp4|avi|mkv|part|reel|reels|pt|s|the|a|an|usa|uk|us|aka|"
    r"feature|talkie|sound|edition|print|copy|archive|public|domain|pd|classic|"
    r"vintage|rare|old|original|english|subtitles|subtitled|subs|3gp|ia|ep|epi)$")
NOISE = re.compile(
    r"\b(gallery|slideshow|tribute|fan ?(art|made|film|edit)|compilation|amv|"
    r"reaction|unboxing|podcast|vlog|trailer|teaser|lyrics|karaoke|remix|mashup|"
    r"highlights|gameplay|walkthrough|playthrough|tas|speedrun|asmr|live ?stream|"
    r"episode \d+|s\d+ ?e\d+|\d+x\d+)\b", re.I)


def words(t):
    return [w for w in re.sub(r"[^a-z0-9 ]", " ", (t or "").lower()).split() if w not in STOP]


def year_of(md):
    """The year the Archive item says its FILM is from. `year` and a year in
    the title are that; `date` is very often the UPLOAD date ("The Devil's
    Holiday (1930)" carries date 2025), so a 2000+ date is no evidence at all
    — the ingest already refuses `date` for the same reason."""
    m = re.search(r"(1[89]\d\d|20\d\d)", str(md.get("year") or ""))
    if m:
        return int(m.group(1))
    t = md.get("title") if isinstance(md.get("title"), str) else " ".join(md.get("title") or [])
    m = re.search(r"\b(1[89]\d\d|19\d\d)\b", t or "")
    if m:
        return int(m.group(1))
    m = re.search(r"(1[89]\d\d)", str(md.get("date") or ""))
    return int(m.group(1)) if m else None


def judge(want_title, want_year, md):
    """(verdict, reason) from the Archive item's own metadata."""
    at = md.get("title") if isinstance(md.get("title"), str) else " ".join(md.get("title") or [])
    ww, aw = words(want_title), words(at)
    if not aw:
        return "keep", "archive title empty — unjudgeable"
    if NOISE.search(at or ""):
        return "wrong", f"noise title: {at[:80]!r}"
    missing = [w for w in ww if w not in set(aw)]
    if missing:
        return "wrong", f"want word(s) {missing} absent from archive title {at[:80]!r}"
    extra = [w for w in aw if w not in set(ww) and not BENIGN.match(w)]
    ay = year_of(md)
    if want_year and ay and abs(ay - want_year) > 2:
        return "wrong", f"archive date {ay} vs want year {want_year}: {at[:80]!r}"
    if extra:
        if want_year and ay and abs(ay - want_year) <= 2:
            return "keep", f"extras {extra[:4]} but archive date {ay} agrees"
        if len(extra) >= 2 or len(ww) <= 2:
            return "wrong", f"stray words {extra[:6]} and no agreeing date: {at[:80]!r}"
    return "keep", "title agrees"


def fetch(iaid, sess):
    r = sess.get(A.ARCHIVE_META + iaid + "/metadata", headers={"User-Agent": A.UA}, timeout=40)
    if r.status_code == 404:
        return {"_missing": True}
    r.raise_for_status()
    md = (r.json() or {}).get("result") or {}
    keep = {k: md.get(k) for k in ("title", "date", "year", "mediatype", "collection", "publicdate")}
    return keep


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--rate", type=float, default=2.0, help="fetches per second (main host — be polite)")
    ap.add_argument("--workers", type=int, default=3)
    args = ap.parse_args()

    q = json.loads(QUEUE.read_text())["candidates"]
    cat = json.loads(CATALOG.read_text())
    items = {x["archiveID"]: x for x in cat["items"]}
    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {"version": 1, "entries": {}}
    entries = cache["entries"]

    wants = [w for w in q if w.get("status") == "ingested" and w.get("resolvedVia") == "title"
             and w.get("iaid") in items]
    todo = [w for w in wants if w["iaid"] not in entries]
    if args.limit:
        todo = todo[: args.limit]
    print(f"title-resolved wants in catalog: {len(wants)}  cached: {len(wants) - len(todo)}  to fetch: {len(todo)}")

    sess = requests.Session()
    gap = 1.0 / max(args.rate, 0.1)
    last = [0.0]

    def one(w):
        # Global throttle: the metadata API is archive.org's MAIN host, and a
        # storm there rate-limits the whole IP (Creation Studio's -1004).
        now = time.time()
        wait = last[0] + gap - now
        if wait > 0:
            time.sleep(wait)
        last[0] = time.time()
        try:
            return w, fetch(w["iaid"], sess)
        except Exception as e:  # noqa: BLE001
            return w, {"_error": str(e)[:120]}

    done = 0
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        for w, md in (f.result() for f in as_completed([ex.submit(one, w) for w in todo])):
            if "_error" in md:
                print(f"  ! {w['iaid']}: {md['_error']}")
                continue
            entries[w["iaid"]] = {"want": w["title"], "wantYear": w.get("year"), "archive": md,
                                  "fetched_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
            done += 1
            if done % 100 == 0:
                CACHE.write_text(json.dumps(cache, indent=1, ensure_ascii=False))
                print(f"  fetched {done}/{len(todo)}")
    CACHE.write_text(json.dumps(cache, indent=1, ensure_ascii=False))

    verdicts = {}
    for w in wants:
        e = entries.get(w["iaid"])
        if not e:
            continue
        md = e["archive"]
        if md.get("_missing"):
            verdicts[w["iaid"]] = ("wrong", "archive item gone")
            continue
        verdicts[w["iaid"]] = judge(e["want"], e.get("wantYear"), md)

    wrong = {k: v for k, v in verdicts.items() if v[0] == "wrong"}
    visible_wrong = [k for k in wrong if not items[k].get("excluded")]
    print(f"judged: {len(verdicts)}  wrong: {len(wrong)}  of which visible today: {len(visible_wrong)}")
    for k in sorted(visible_wrong)[:40]:
        print(f"  {k[:46]:46} want={entries[k]['want'][:28]!r:30} {wrong[k][1][:90]}")

    if not args.apply:
        print("(report only — pass --apply to mark the catalog)")
        return
    changed = 0
    for k, (v, reason) in verdicts.items():
        it = items[k]
        md = entries[k]["archive"]
        if isinstance(md.get("title"), str):
            it["archiveTitle"] = md["title"]
        if v == "wrong":
            if not it.get("excluded") or not it.get("wrongMatchTitle"):
                changed += 1
            it["excluded"] = True
            it["wrongMatchTitle"] = {"want": entries[k]["want"], "reason": reason[:160],
                                    "judged_at": time.strftime("%Y-%m-%d")}
        elif it.get("wrongMatchTitle"):
            del it["wrongMatchTitle"]
    CATALOG.write_text(json.dumps(cat, ensure_ascii=False, separators=(",", ":")))
    print(f"applied: {changed} newly marked wrongMatchTitle (+excluded); archiveTitle recorded on {len(verdicts)} items")


if __name__ == "__main__":
    main()
