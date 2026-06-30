#!/usr/bin/env python3
"""
build_catalog_index.py — emit a tiny, browser-friendly search index of the FULL
catalog for the public editorial tool (index.html "Browse the catalog").

The full catalog (~95 MB) lives on a GitHub Release and can't be fetched from a
browser (Release assets send no CORS header — verified). So we publish a slim
index to GitHub Pages (same-origin as the tool). To keep it small AND
git-delta-friendly (it's committed + refreshed on every DB update), each item is
a positional array, not an object:

    [archiveID, title, year, contentType, poster, pro, search]

`poster` is the designed-artwork URL (TMDb/Wikidata/commons/generated) or null;
the browser falls back to archive.org/services/img/{id} when null — so the web
viewer keeps the same visual dignity as the apps without shipping the 95 MB
catalog. (Schema 2; schema-1 consumers ignore the extra column.) Adult-collection items (featured.json.adultCollections)
are excluded — this index feeds a PUBLIC tool.

`search` (column 6, schema 6, Decision 046) is the web's flat-index analog of
the apps' FTS5 + keyword/studio join tables: a lowercased space-joined blob of
the rich-metadata search terms — keywords, alternative/original titles, writer,
and studios — so the client-side search box finds a film by a TMDb keyword,
a foreign re-title, its writer, or its studio without shipping the full catalog.
It is null on the ~65% of films with no TMDb/OMDb match (those cost nothing).
A top-level `facets` object ({keywords:[…], studios:[…]} — the most common
names) lets Browse offer keyword + studio filter chips; the filter itself runs
client-side against the `search` column (no per-row id map → the committed index
stays lean). Schema 6 is additive: older readers ignore column 6 + `facets`.

Reads ./catalog.json (fetch it first via catalog_release.py). Writes
./catalog-index.json at the repo root (served by Pages).
"""

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
FEATURED = REPO / "featured.json"
OUT = REPO / "catalog-index.json"


def main():
    if not CATALOG.exists():
        print("[index] no catalog.json — run tools/catalog_release.py fetch first", file=sys.stderr)
        return 1
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    items = catalog.get("items", catalog if isinstance(catalog, list) else [])

    # Curated collection ids (collection_metadata.json) → membership map, so
    # the web viewer can render the Collections surface (schema 5, additive).
    curated_collections = []
    cm = REPO / "ArchiveWatch" / "ArchiveWatch" / "collection_metadata.json"
    if cm.exists():
        try:
            curated_collections = [c["id"] for c in
                                   json.loads(cm.read_text()).get("collections", [])]
        except Exception:  # noqa: BLE001
            curated_collections = []
    curated_lower = {c.lower(): c for c in curated_collections}

    adult = set()
    if FEATURED.exists():
        try:
            adult = {c.lower() for c in json.loads(FEATURED.read_text())
                     .get("adultCollections", [])}
        except Exception:  # noqa: BLE001
            adult = set()

    _FILM = {"feature-film", "short-film", "silent-film", "animation", "documentary", "feature"}
    rows = []
    shelf_members: dict[str, list[tuple]] = {}
    collection_members: dict[str, list[tuple]] = {}
    community: dict[str, list[tuple]] = {"watching-now": [], "community-favorites": [], "most-discussed": []}
    # Facet frequency (Decision 046) — most-common keyword/studio names for the
    # Browse filter chips; the filter runs client-side against the search column.
    keyword_freq: dict[str, int] = {}
    studio_freq: dict[str, int] = {}
    for it in items:
        if it.get("excluded"):          # rights audit (Decision 027)
            continue
        if it.get("isAdult"):           # item-level flag (Decision 012) — the
            continue                    # apps' isAdult column ORs this in too
        cols = {c.lower() for c in (it.get("collections") or [])}
        if adult & cols:
            continue
        aid = it.get("archiveID")
        if not aid:
            continue
        poster = it.get("posterURL")
        if poster and "archive.org/services/img" in poster:
            poster = None          # derivable from the id; don't bloat the index
        # Professional art only (the apps' hasProfessionalArtwork): a designed
        # poster from TMDb/TVDB/Wikidata/etc — NOT a generated frame cover
        # (Decision 023) and not an archive thumb. Home shows pro art only.
        pro = 1 if (poster and it.get("artworkSource")
                    not in (None, "archive", "generated")) else 0
        # Searchable rich-metadata blob (Decision 046): keywords + AKA/original
        # title + writer + studios, lowercased + space-joined. Null when empty.
        keywords = [k for k in (it.get("keywords") or []) if k]
        studios = [s for s in (it.get("studios") or []) if s]
        search_parts = list(keywords)
        search_parts += [a for a in (it.get("akaTitles") or []) if a]
        if it.get("originalTitle"):
            search_parts.append(it["originalTitle"])
        if it.get("writer"):
            search_parts.append(it["writer"])
        search_parts += studios
        search = " ".join(search_parts).lower() or None
        # Wide backdrop (column 7, schema 7) — the web hero uses it so it shows well-composed wide
        # art, never a cropped 2:3 poster (owner 2026-06-29). Only a real designed backdrop; null
        # otherwise. Older consumers ignore the extra column (additive).
        backdrop = it.get("backdropURL") if pro else None
        rows.append([aid, it.get("title") or aid, it.get("year"),
                     it.get("contentType") or "", poster, pro, search, backdrop])
        for k in keywords:
            keyword_freq[k] = keyword_freq.get(k, 0) + 1
        for s in studios:
            studio_freq[s] = studio_freq.get(s, 0) + 1
        # Editorial shelf membership (the item_shelves analog) — so the web
        # viewer composes Home from the SAME curated assignments as the apps
        # instead of live scrape (which bypasses the rights/adult pipeline).
        designed = 1 if poster else 0
        pop_score = it.get("popularityScore") or 0
        for shelf_id in (it.get("shelves") or []):
            shelf_members.setdefault(shelf_id, []).append((designed, pop_score, aid))
        for c in cols:
            if (canon := curated_lower.get(c)):
                collection_members.setdefault(canon, []).append((designed, pop_score, aid))
        # Community shelves — vote-floored to recognized films (apps' parity): raw
        # counts are dominated by un-IMDb'd foreign edge cases, which have no votes.
        if pro and (it.get("imdbVotes") or 0) >= 1000 and it.get("contentType") in _FILM:
            if (it.get("views30d") or 0) > 0:
                community["watching-now"].append((it["views30d"], aid))
            if (it.get("numFavorites") or 0) > 0:
                community["community-favorites"].append((it["numFavorites"], aid))
            if (it.get("numReviews") or 0) > 0:
                community["most-discussed"].append((it["numReviews"], aid))

    # Sort by popularity so the most useful titles search/scroll first.
    pop = {it.get("archiveID"): (it.get("popularityScore") or 0) for it in items}
    rows.sort(key=lambda r: pop.get(r[0], 0), reverse=True)

    # Designed art leads each shelf, then popularity; cap keeps the file slim.
    shelves = {
        sid: [aid for _, _, aid in sorted(members, reverse=True)[:60]]
        for sid, members in sorted(shelf_members.items())
    }
    # Community shelves: sorted by their signal (views / favorites / reviews).
    for sid, members in community.items():
        if members:
            shelves[sid] = [aid for _, aid in sorted(members, reverse=True)[:60]]

    collections = {
        cid: [aid for _, _, aid in sorted(members, reverse=True)[:120]]
        for cid, members in sorted(collection_members.items())
    }

    # Facet chip lists (Decision 046) — most-common names only (the long tail is
    # still reachable via free-text search over the search column).
    facets = {
        "keywords": [k for k, _ in sorted(keyword_freq.items(),
                                          key=lambda kv: kv[1], reverse=True)[:60]],
        "studios": [s for s, _ in sorted(studio_freq.items(),
                                         key=lambda kv: kv[1], reverse=True)[:40]],
    }

    out = {
        "schema": 7,
        "updatedAt": catalog.get("updatedAt") or "",
        "count": len(rows),
        "fields": ["id", "title", "year", "contentType", "poster", "pro", "search", "backdrop"],
        "facets": facets,
        "shelves": shelves,
        "collections": collections,
        "items": rows,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    mb = OUT.stat().st_size / 1_000_000
    print(f"[index] wrote {OUT.name}: {len(rows):,} items, "
          f"{len(shelves)} shelves, {len(collections)} collections, {mb:.1f} MB", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
