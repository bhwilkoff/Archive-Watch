#!/usr/bin/env python3
"""
build_web_details.py — emit the web viewer's per-item DETAIL shards.

The slim catalog-index gives the browser browse/search rows, but Detail and
playback need what the pipeline already produced per item: the build-time
picked downloadURL, the curated synopsis, director, cast, runtime. The full
catalog can't ship to a browser (95 MB) and the archive.org metadata API is
an unreliable re-derivation (it hangs/404s for items we play fine — the
downloadURL is the truth). So we shard the display fields into 256 small
JSON files served by Pages (CORS), fetched one shard (~40-90 KB) per Detail
view:

    details/{00..ff}.json  →  { archiveID: [downloadURL, synopsis, director,
                                            castNames, genres, runtimeSeconds,
                                            backdropURL, captions, community,
                                            extras], ... }

Positional record indices (trailing nulls trimmed — APPEND new fields at the
end so existing indices never shift; keep watch.js `Details.get` in sync):
    0 downloadURL   3 cast      6 backdropURL   9 extras (Decision 046)
    1 synopsis      4 genres    7 captions      10 related (Decision 139)
    2 director      5 runtime   8 community
`extras` (index 9, Decision 046) is a compact object of the rich-metadata
fields — present keys only, the whole object omitted when empty so sparse
films cost nothing: {w:writer, st:studios[], fr:franchise, tg:tagline,
aw:awards, co:composer, ci:cinematographer, rd:releaseDate, ot:originalTitle,
ct:canonicalTitle}.
Each cast entry is ALWAYS a list: [name] | [name, profilePath] | [name, profilePath,
tmdbPersonID] (trailing nulls trimmed) — the personID (Decision 046) unblocks
person links.

Shard = FNV-1a 32-bit hash of the archiveID, low byte, hex — the JS side
(watch.js `Details.shardOf`) implements the SAME function; keep them in sync.
Adult/excluded filtering matches build_catalog_index.py (the index is the
gatekeeper; an item absent there is never requested here).

`related` (index 10, Decision 139) is More Like This as the pipeline ranked
it — archiveIDs, best first — read from `item_related` in ./catalog.sqlite,
which publish-db builds earlier in the same job. Omitted when absent.
Reads ./catalog.json (fetch via catalog_release.py first). Writes ./details/.
"""

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from build_sqlite import _is_adult, bundle_sources, series_cards  # noqa: E402  (Decisions 105, 166)
CATALOG = REPO / "catalog.json"
FEATURED = REPO / "featured.json"
OUT_DIR = REPO / "details"
# Fields only the generated film pages read (build_share_pages.py), kept out of
# details/ so the viewer, which fetches a details shard on every Detail, pays
# nothing for them. Same shard function and keys as details/.
PAGE_DIR = REPO / "page-extras"
COLLECTIONS = REPO / "ArchiveWatch" / "ArchiveWatch" / "collection_metadata.json"

SYNOPSIS_MAX = 500
PAGE_SYNOPSIS_MAX = 1500
SUBJECTS_MAX = 10

# archive.org's language field is free text: ISO 639-1, 639-2 and English names
# all occur. Codes for "no speech" (zxx) and "unknown" (xx) are not a language.
LANGUAGES = {
    "en": "English", "eng": "English", "english": "English",
    "de": "German", "ger": "German", "deu": "German", "german": "German",
    "es": "Spanish", "spa": "Spanish", "spanish": "Spanish",
    "fr": "French", "fre": "French", "fra": "French", "french": "French",
    "it": "Italian", "ita": "Italian", "italian": "Italian",
    "ru": "Russian", "rus": "Russian", "russian": "Russian",
    "ja": "Japanese", "jpn": "Japanese", "japanese": "Japanese",
    "pt": "Portuguese", "por": "Portuguese", "portuguese": "Portuguese",
    "nl": "Dutch", "dut": "Dutch", "nld": "Dutch", "dutch": "Dutch",
    "sv": "Swedish", "swe": "Swedish", "swedish": "Swedish",
    "pl": "Polish", "pol": "Polish", "polish": "Polish",
    "cs": "Czech", "cze": "Czech", "ces": "Czech", "czech": "Czech",
    "zh": "Chinese", "chi": "Chinese", "zho": "Chinese", "chinese": "Chinese",
    "hi": "Hindi", "hin": "Hindi", "hindi": "Hindi",
    "hu": "Hungarian", "hun": "Hungarian", "hungarian": "Hungarian",
    "da": "Danish", "dan": "Danish", "danish": "Danish",
    "fi": "Finnish", "fin": "Finnish", "finnish": "Finnish",
    "no": "Norwegian", "nor": "Norwegian", "norwegian": "Norwegian",
    "el": "Greek", "gre": "Greek", "ell": "Greek", "greek": "Greek",
    "tr": "Turkish", "tur": "Turkish", "turkish": "Turkish",
    "ko": "Korean", "kor": "Korean", "korean": "Korean",
    "ar": "Arabic", "ara": "Arabic", "arabic": "Arabic",
}

# Uploaders tag items with search keywords ("old movies online", "free classic
# movie", "silent film streaming"): shown on a page, those read as keyword
# stuffing and say nothing about the film. A subject is kept only when it
# names something about THIS item — a place, a subject, a decade, a genre.
_SUBJECT_PROMO = re.compile(
    r"\b(online|on line|streaming|stream|free|download|watch|youtube|hd|"
    r"high definition|720p|1080p|dvd|blu-?ray|mp4|avi|full movie|full length|"
    r"public domain|classic|classics|need keyword|pdmovies|images)\b", re.I)
_SUBJECT_NOISE = re.compile(
    r"\b(archive|archives|rare|fine|good|best|old|vintage|movie|movies|film|films|"
    r"feature|short|motion pictures?|cinema|video|videos)\b", re.I)


def page_subjects(raw, skip) -> list:
    """archive.org subjects worth printing on a film page, in the uploader's
    order, at most SUBJECTS_MAX. `skip` holds lower-cased words already on the
    page (genres, collection slugs) so nothing is said twice."""
    out, seen = [], set(skip)
    if isinstance(raw, str):
        raw = re.split(r"[;,]", raw)
    for s in raw or []:
        if not isinstance(s, str):
            continue
        for part in s.split(";"):
            t = " ".join(part.split()).strip(" .-")
            k = t.lower()
            if not t or len(t) > 60 or k in seen or "--" in t or "." in k and " " not in k:
                continue
            words = re.findall(r"[a-z0-9']+", k)
            if _SUBJECT_PROMO.search(k):
                continue
            # Noise words alone ("classic movies", "old film") say nothing; a
            # phrase that names something besides them ("silent film" is a
            # kind, "Idaho" a place) keeps its place only if a word remains.
            if not words or not _SUBJECT_NOISE.sub("", k).strip(" -'&/"):
                continue
            if _SUBJECT_NOISE.search(k) and len(words) > 2:
                continue
            seen.add(k)
            out.append(t)
            if len(out) >= SUBJECTS_MAX:
                return out
    return out


def page_language(raw):
    if isinstance(raw, list):
        raw = next((x for x in raw if isinstance(x, str)), None)
    if not isinstance(raw, str):
        return None
    return LANGUAGES.get(raw.strip().lower())


def fnv1a32(s: str) -> int:
    h = 0x811C9DC5
    for b in s.encode("utf-8"):
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def main():
    if not CATALOG.exists():
        print("[details] no catalog.json — run tools/catalog_release.py fetch first",
              file=sys.stderr)
        return 1
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    items = catalog.get("items", catalog if isinstance(catalog, list) else [])

    related = {}
    db_path = REPO / "catalog.sqlite"
    if db_path.exists():
        import sqlite3
        try:
            con = sqlite3.connect(db_path)
            related = {a: r.split("\t") for a, r in con.execute("SELECT archiveID, related FROM item_related")}
            con.close()
        except sqlite3.Error as e:
            print(f"[details] no related table ({e}) — shards ship without it", flush=True)
    print(f"[details] {len(related):,} films carry a pipeline related list", flush=True)

    shards: dict[str, dict] = {f"{i:02x}": {} for i in range(256)}
    page_shards: dict[str, dict] = {f"{i:02x}": {} for i in range(256)}
    # Only collections with a display title are named: a raw archive.org slug
    # ("fav-islanddisco") is never shown to a person (collection_metadata.json).
    coll_titles = {}
    try:
        coll_titles = {c["id"]: c["title"] for c in
                       json.loads(COLLECTIONS.read_text(encoding="utf-8"))["collections"]
                       if c.get("id") and c.get("title") and not c["id"].startswith("series-")}
    except (OSError, ValueError, KeyError) as e:
        print(f"[details] no collection titles ({e}) — pages name no collection", flush=True)
    kept = 0
    bundled = bundle_sources(series_cards(items))
    for it in items:
        # ONE mature predicate (Decision 105). This file carried its own
        # looser copy — the item flag plus the adult-collection list — and
        # two title-marker films the apps hide ("...Porno...") sat in the
        # shards, reachable by a direct /item/<id> link (measured 2026-09-10).
        if it.get("excluded") or _is_adult(it) or it.get("archiveID") in bundled:
            continue
        aid = it.get("archiveID")
        if not aid:
            continue
        raw_syn = it.get("synopsis")
        if isinstance(raw_syn, list):      # Archive metadata quirk: list-typed
            raw_syn = next((x for x in raw_syn if isinstance(x, str)), "")
        synopsis = (raw_syn or "").strip()
        if len(synopsis) > SYNOPSIS_MAX:
            synopsis = synopsis[:SYNOPSIS_MAX].rsplit(" ", 1)[0] + "…"
        cast = []
        for c in (it.get("cast") or [])[:8]:
            name = c.get("name")
            if not name:
                continue
            path = c.get("profilePath")
            pid = c.get("tmdbPersonID")
            entry = [name, path or None, pid or None]
            while len(entry) > 1 and entry[-1] is None:  # [name] | [name,path] | [name,path,pid]
                entry.pop()
            # ALWAYS a list, never the bare name. This line used to unwrap a
            # single-element entry into a string, contradicting the docstring
            # above — and the Roku channel, which trusted that docstring, calls
            # `c.Count()` on each entry. A String has no Count(), so opening
            # the Detail screen of any film with a profile-less cast member
            # crashed the channel: 2,798 such entries across 1,716 films, 16
            # crashes in the first two days on the store (2026-09-11).
            cast.append(entry)
        # Subtitle tracks for the web <track> element — the Pages-hosted VTT
        # (CORS-OK; archive.org's SRT is not). [lang, label, vttURL] each.
        captions = [[c.get("lang"), c.get("label"), c.get("vttURL")]
                    for c in (it.get("captions") or []) if c.get("vttURL")]
        # A caption entry without a vttURL is dropped above — several carry only
        # an .srt on archive.org, which the web player cannot use. But the item
        # may still have a PUBLISHED track: `subtitleHLS` is a separate field,
        # and the apps read it while this shard never did. Measured 2026-09-11
        # across 31,832 visible items: 26 films where every app showed subtitles
        # and the web showed none — The Grapes of Wrath among them. Derive the
        # same sibling `en.vtt` the Swift `publishedVTTURL` falls back to, so
        # both planes answer the same question the same way.
        if not captions and it.get("subtitleHLS"):
            hls = it["subtitleHLS"]
            if hls.endswith(".m3u8"):
                captions = [["en", "English", hls.rsplit("/", 1)[0] + "/en.vtt"]]
        # archive.org community signals + pipeline-filtered reviews (Decision P2).
        # [stars, title, body, reviewer, date] per review; community is null unless
        # there's a stat or a review (trailing-null trim then drops it).
        rv = [[r.get("stars"), r.get("title"), r.get("body"), r.get("reviewer"), r.get("date")]
              for r in (it.get("reviews") or [])[:6]]
        community = None
        if it.get("avgRating") or it.get("numFavorites") or it.get("viewsAllTime") or rv:
            community = {
                "r": it.get("avgRating"),
                "v": it.get("viewsAllTime") or it.get("downloads"),
                "f": it.get("numFavorites"),
                "rv": rv or None,
            }
        # Rich-metadata extras (Decision 046) — present keys only, omitted whole
        # when empty so the ~59% of films without a TMDb/OMDb match cost nothing.
        extras = {}
        for key, field in (("w", "writer"), ("fr", "franchise"), ("tg", "tagline"),
                           ("aw", "awards"), ("co", "composer"),
                           ("ci", "cinematographer"), ("rd", "releaseDate"),
                           ("ot", "originalTitle"),
                           # The film's primary title per the external match.
                           # `title` is the ARCHIVE uploader's, and when the two
                           # disagree the page reads as a wrong match — it is
                           # usually one film under several release titles
                           # (Decision 100). Emitted raw; watch.js decides
                           # whether it differs enough to show.
                           ("ct", "canonicalTitle"),
                           # Where the synopsis came from (synopsis_provenance.py):
                           # the clients say "Uploader's description" when it is
                           # "archive" and name the API otherwise (2026-09-16).
                           ("ss", "synopsisSource")):
            val = it.get(field)
            if isinstance(val, str):
                val = val.strip()
            if val:
                extras[key] = val
        studios = [s for s in (it.get("studios") or []) if s][:6]
        if studios:
            extras["st"] = studios
        if it.get("directorProfilePath"):
            extras["dp"] = it["directorProfilePath"]   # director photo for Detail's first chip
        record = [
            it.get("downloadURL"),
            synopsis or None,
            it.get("director"),
            cast or None,
            (it.get("genres") or [])[:3] or None,
            it.get("runtimeSeconds"),
            it.get("backdropURL"),
            captions or None,
            community,
            extras or None,
            related.get(aid) or None,
        ]
        # Trim trailing nulls so empty tails cost nothing on the wire.
        while record and record[-1] is None:
            record.pop()
        if not record:
            continue
        shard = f"{fnv1a32(aid) & 0xFF:02x}"
        shards[shard][aid] = record
        kept += 1

        page = {}
        full = (raw_syn or "").strip()
        if len(full) > SYNOPSIS_MAX:
            page["sy"] = (full if len(full) <= PAGE_SYNOPSIS_MAX
                          else full[:PAGE_SYNOPSIS_MAX].rsplit(" ", 1)[0] + "…")
        colls = it.get("collections") or []
        titles = []
        for cid in colls if isinstance(colls, list) else []:
            t = coll_titles.get(cid)
            if t and t not in titles:
                titles.append(t)
        if titles:
            page["cl"] = titles[:3]
        skip = {str(g).lower() for g in (it.get("genres") or [])}
        skip |= {str(c).lower() for c in (colls if isinstance(colls, list) else [])}
        skip |= {t.lower() for t in titles}
        subjects = page_subjects(it.get("subjects"), skip)
        if subjects:
            page["su"] = subjects
        lang = page_language(it.get("language"))
        if lang:
            page["lg"] = lang
        if page:
            page_shards[shard][aid] = page

    OUT_DIR.mkdir(exist_ok=True)
    total = 0
    for name, data in shards.items():
        p = OUT_DIR / f"{name}.json"
        p.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")),
                     encoding="utf-8")
        total += p.stat().st_size
    print(f"[details] wrote {kept:,} items into 256 shards, "
          f"{total/1_000_000:.1f} MB total "
          f"(avg {total/256/1000:.0f} KB/shard)", flush=True)

    PAGE_DIR.mkdir(exist_ok=True)
    ptotal = pitems = 0
    for name, data in page_shards.items():
        p = PAGE_DIR / f"{name}.json"
        p.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":"), sort_keys=True),
                     encoding="utf-8")
        ptotal += p.stat().st_size
        pitems += len(data)
    print(f"[details] page extras for {pitems:,} items, {ptotal/1_000_000:.1f} MB "
          f"(film pages only; the viewer never fetches them)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
