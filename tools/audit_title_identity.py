#!/usr/bin/env python3
"""Catch a film matched to a DIFFERENT film that shares its title — and take
its captions with it.

The owner started "Man on the Run" (1949 British film noir) and got the poster
AND the subtitles of Morgan Neville's 2025 Paul McCartney documentary. Two
copies of the same 1949 film sat in the catalog; one carried the correct
tt0040566 / Lawrence Huntington, the other tt26931594 / Morgan Neville. The
wrong one had `matchVerified: True` — Decision 026's tiers all ABSTAINED
because the item's own Archive record offered nothing to contradict a
title-only match, and Decision 087's era check, which exists for exactly this,
was only ever wired for TV.

The signal here needs no network at all: two copies of the SAME film disagree
about which film they are. A title+year cluster whose members carry different
IMDb ids contains at least one wrong match, and the catalog already holds both
halves of the contradiction.

ACTING is deliberately narrower than DETECTING (the Decision 035/040/064 rule
— it is better to leave a wrong match visible than to clear a right one). We
only clear when the culprit is named unambiguously: a pre-1970 film whose
sibling carries an IMDb id in the modern registration range (>= 1,000,000)
while another carries a low one. Measured on the live catalog that decides 15
of 35 clusters; the remaining 20 are two LOW ids — genuinely distinct old works
that merely share a title (Chaplin's "Burlesque on Carmen" has two entries; the
1900 "Capture of Boer Battery" pair are adjacent ids) — and are reported only.

CAPTIONS RIDE WITH THE MATCH. free_subtitles.py searches by `imdbID`, so a
wrong id fetches a wrong film's subtitles, and clearing the poster alone would
leave the McCartney captions playing over the noir. Anything sourced from a
provider keyed on that id (subsource / subdl / opensubtitles) is dropped with
it; archive-native uploader captions belong to the ITEM, not the match, and are
kept.
"""
from __future__ import annotations
import argparse, collections, json, re, sys

MODERN_IMDB = 1_000_000      # tt ids at/above this are modern registrations
OLD_FILM_BEFORE = 1970       # a film older than this should carry a low tt id
NOT_FILM = ("tv-series", "tv-episode")
# Providers that search BY imdb id — their result is only as good as the match.
MATCH_KEYED_CAPTION_SOURCES = ("subsource", "subdl", "opensubtitles")

_STRIP = re.compile(r"\b(colorized|colourized|restored|hd|sd|720p|1080p|576p|"
                    r"480p|4k|movie|film|feature|complete|uncut)\b")


def norm_title(t: str | None) -> str:
    t = _STRIP.sub(" ", (t or "").lower())
    t = re.sub(r"[^a-z0-9]+", " ", t).strip()
    return re.sub(r"^(the|a|an) ", "", t)


def imdb_num(i: str | None) -> int:
    d = re.sub(r"\D", "", i or "")
    return int(d) if d else 0


def clusters(items):
    """Film-type items grouped by normalised title + year."""
    out = collections.defaultdict(list)
    for it in items:
        if it.get("contentType") in NOT_FILM:
            continue
        t, y = it.get("title"), it.get("year")
        if t and y:
            out[(norm_title(t), y)].append(it)
    return out


def conflicts(items):
    """Clusters whose members disagree about which film they are."""
    bad = []
    for (t, y), mem in clusters(items).items():
        ids = {i.get("imdbID") for i in mem if i.get("imdbID")}
        if len(ids) > 1:
            bad.append((t, y, mem))
    return bad


def wrong_members(year: int, mem: list) -> list:
    """The members this evidence can name as wrong — empty when it cannot.

    Only fires when an OLD film has members split across the modern/old id
    ranges. Both-low means two distinct old works sharing a title, which is not
    a fault; both-high means we cannot tell which is which.
    """
    if not year or year >= OLD_FILM_BEFORE:
        return []
    ided = [i for i in mem if i.get("imdbID")]
    modern = [i for i in ided if imdb_num(i.get("imdbID")) >= MODERN_IMDB]
    if not modern or len(modern) == len(ided):
        return []
    return modern


# EVIDENCE ALREADY IN THE BUILD names the wrong copy in the clusters the id
# ranges cannot decide (audit 2026-10-28: 25 of 25 open clusters were two LOW
# ids). Each test needs a POSITIVE alternative inside the cluster, not just a
# doubt about one member, so a surviving fragment of the right film (31 of
# Isn't Life Wonderful's 115 minutes) is never cleared:
#   runtime   its match's runtime contradicts its own file (<0.5x or >2x, at
#             least 5 minutes apart) while ANOTHER member's match runs within
#             25% of its file: Radio Ranch (69 min) wore The Phantom Empire
#             serial (245); "The Magician" (79 min) a 1-minute Méliès;
#             "Cinderella" (7 min) Kenneth Branagh's.
#   director  its own id or title names another member's director and not its
#             own: BRONCHOBILLYANDTHEGREASERG.M.Anderson... wore Raoul Walsh.
#   year      its match's release year (tmdb_verify_cache) is more than two
#             years from the cluster's, while another member's agrees.
# An upload that declared its own id (matchVerdict "verified") is never named.
SHORT, LONG, MIN_GAP, AGREE = 0.5, 2.0, 300, 0.25


def _load(path):
    try:
        d = json.loads(open(path, encoding="utf-8").read())
        return d.get("entries", d)
    except Exception:  # noqa: BLE001
        return {}


def _own_runtime(it):
    return it.get("trueRuntimeSeconds") or it.get("fileRuntimeSeconds") or (
        it.get("runtimeSeconds") if it.get("runtimeSource") in ("archive_file", "measured-ffprobe") else None)


def _surnames(names):
    out = set()
    for n in re.split(r",|&| and ", names or ""):
        w = re.sub(r"[^a-z ]", " ", n.lower()).split()
        if w and len(w[-1]) >= 4:
            out.add(w[-1])
    return out


def _own_text(it):
    t = f"{it.get('archiveID') or ''} {it.get('title') or ''}"
    return re.sub(r"[^a-z]", "", t.lower())


def evidenced_wrong(year, mem, omdb, verify):
    """[(member, reason)] the cluster's own evidence names as the wrong film."""
    ided = [i for i in mem if i.get("imdbID")]
    if len({i["imdbID"] for i in ided}) < 2:
        return []
    film_rt = {i["imdbID"]: ((omdb.get(i["imdbID"]) or {}).get("runtime_min") or 0) * 60 for i in ided}
    out = []
    for it in ided:
        if it.get("matchVerdict") == "verified":
            continue
        mine, others = it["imdbID"], {i["imdbID"] for i in ided} - {it["imdbID"]}
        own, rt = _own_runtime(it), film_rt.get(mine)
        if own and rt and (own / rt < SHORT or own / rt > LONG) and abs(own - rt) >= MIN_GAP:
            alt = [o for o in others if film_rt.get(o) and abs(own - film_rt[o]) <= AGREE * film_rt[o]]
            if alt:
                out.append((it, f"runtime {own // 60} min vs its match's {rt // 60}; "
                                f"{alt[0]} runs {film_rt[alt[0]] // 60}"))
                continue
        text = _own_text(it)
        mine_dir = _surnames(it.get("director"))
        other_dirs = set().union(*(_surnames(i.get("director")) for i in ided if i["imdbID"] in others)) - mine_dir
        if mine_dir and not any(s in text for s in mine_dir) and any(s in text for s in other_dirs):
            out.append((it, f"its own id/title names {sorted(s for s in other_dirs if s in text)[0]}, "
                            f"not {it.get('director')}"))
            continue
        my = (verify.get(str(it.get("tmdbID"))) or {}).get("year") if it.get("tmdbID") else None
        if isinstance(my, int) and year and abs(my - year) > 2:
            agree = [i for i in ided if i["imdbID"] in others and i.get("tmdbID")
                     and abs(((verify.get(str(i["tmdbID"])) or {}).get("year") or -99) - year) <= 2]
            if agree:
                out.append((it, f"its match was released {my}, the film {year}"))
    return out


def clear_match(it: dict) -> list[str]:
    """Strip a wrong external identity + everything derived from it."""
    cleared = []
    for k in ("imdbID", "tmdbID", "director", "imdbRating", "imdbVotes"):
        if it.get(k) not in (None, ""):
            it[k] = None
            cleared.append(k)
    # Artwork that came FROM the match. An archive.org thumb or a generated
    # frame cover belongs to the item itself (Decision 023) and stays.
    if it.get("artworkSource") in ("tmdb", "omdb", "external", "tvdb", "tvmaze"):
        it["posterURL"] = None
        it["backdropURL"] = None
        it["artworkSource"] = None
        it["hasRealArtwork"] = False
        cleared.append("artwork")
    caps = it.get("captions") or []
    keep = [c for c in caps if (c.get("source") or "") not in MATCH_KEYED_CAPTION_SOURCES]
    if len(keep) != len(caps):
        it["captions"] = keep
        cleared.append(f"captions(-{len(caps) - len(keep)})")
        if not keep:
            it.pop("subtitleHLS", None)
            cleared.append("subtitleHLS")
    it["matchVerified"] = False
    it["identityConflict"] = True
    return cleared


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", default="catalog.json")
    ap.add_argument("--omdb-cache", default="shared/editorial/omdb_cache.json")
    ap.add_argument("--verify-cache", default="shared/editorial/tmdb_verify_cache.json")
    ap.add_argument("--apply", action="store_true",
                    help="clear the matches this evidence can name (default: report only)")
    a = ap.parse_args()

    cat = json.loads(open(a.catalog, encoding="utf-8").read())
    items = cat["items"] if isinstance(cat, dict) else cat

    omdb, verify = _load(a.omdb_cache), _load(a.verify_cache)
    bad = conflicts(items)
    acted = ambiguous = 0
    for t, y, mem in bad:
        wrong = wrong_members(y, mem)
        if not wrong:
            named = evidenced_wrong(y, mem, omdb, verify)
            for it, why in named:
                print(f"  EVIDENCE {t[:36]:38} ({y})  {it['archiveID'][:40]}: {why}")
            wrong = [it for it, _ in named]
        if not wrong:
            ambiguous += 1
            ids = " | ".join(f"{i.get('imdbID')}/{(i.get('director') or '?')[:18]}" for i in mem)
            print(f"  REPORT   {t[:36]:38} ({y})  {ids[:92]}")
            continue
        for it in wrong:
            what = clear_match(it) if a.apply else ["(dry-run)"]
            acted += 1
            print(f"  {'CLEARED' if a.apply else 'WOULD':8} {t[:36]:38} ({y})  "
                  f"{it.get('imdbID') or '-'} {(it.get('director') or '?')[:20]} "
                  f"-> {','.join(what)}")

    print(f"\n{len(bad)} title+year clusters disagree about identity: "
          f"{acted} named by the evidence, {ambiguous} reported for review.")
    if a.apply:
        with open(a.catalog, "w", encoding="utf-8") as fh:
            json.dump(cat, fh, ensure_ascii=False)
        print(f"[identity] wrote {a.catalog}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
