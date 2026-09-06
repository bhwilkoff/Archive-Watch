#!/usr/bin/env python3
"""
build_catalog_index.py — emit a tiny, browser-friendly search index of the FULL
catalog for the public editorial tool (index.html "Browse the catalog").

The full catalog (~95 MB) lives on a GitHub Release and can't be fetched from a
browser (Release assets send no CORS header — verified). So we publish a slim
index to GitHub Pages (same-origin as the tool). To keep it small AND
git-delta-friendly (it's committed + refreshed on every DB update), each item is
a positional array, not an object:

    [archiveID, title, year, contentType, poster, pro, search, backdrop, playable, docs]

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
import sys as _sys
_sys.path.insert(0, str(__import__('pathlib').Path(__file__).resolve().parent))
from build_sqlite import _is_adult  # noqa: E402  (Decision 105: one adult predicate)

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
FEATURED = REPO / "featured.json"
OUT = REPO / "catalog-index.json"


def _spine_exists(archive_id) -> bool:
    """A `series:<slug>` card is only real if its spine file is still there.

    The cards live in catalog.json, but the EPISODES live in series/*.json,
    and the rights sweep deletes a spine outright. Without this a removed show
    kept its card on every platform and opened onto an empty page — the card
    and the content have two different sources, so removing one has to check
    the other. Applies to the app database and the web index alike, because
    both build their cards from catalog.json.
    """
    aid = str(archive_id or "")
    if not aid.startswith("series:"):
        return True
    slug = aid[len("series:"):]
    if not slug or "/" in slug or "\\" in slug:
        return False
    return (REPO / "series" / f"{slug}.json").exists()


def main():
    if not CATALOG.exists():
        print("[index] no catalog.json — run tools/catalog_release.py fetch first", file=sys.stderr)
        return 1
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    items = catalog.get("items", catalog if isinstance(catalog, list) else [])

    # The SAME dedup the app DB gets (build_sqlite: best copy per IMDb id, then
    # same-film re-upload merge). The web read catalog.json raw and showed every
    # duplicate upload as its own card — five visible copies of Till the Clouds
    # Roll By while the apps showed one (Decision 040's merge never applied
    # here). Import rather than reimplement so the two surfaces cannot drift.
    from build_sqlite import dedupe_by_imdb, merge_film_duplicates
    before = len(items)
    items = merge_film_duplicates(dedupe_by_imdb(items))
    print(f"[index] dedup: {before:,} -> {len(items):,} items", flush=True)

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
        # Decision 105 — ONE predicate. The apps hide mature titles behind a
        # default-off setting computed by build_sqlite._is_adult (item flag +
        # explicit title markers + collection-name markers as SUBSTRINGS); the
        # index has no toggle, so what it DROPS must be exactly what that
        # setting hides. This used to be a looser copy (exact collection names,
        # no title markers), and the two drifted: a title the Apple TV hid was
        # on the Roku's and the web's screens.
        if _is_adult(it):
            continue
        cols = {c.lower() for c in (it.get("collections") or [])}
        aid = it.get("archiveID")
        if not aid:
            continue
        # A series CARD whose spine was deleted opens onto nothing.
        if not _spine_exists(aid):
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
        # Playability (column 8, schema 8) — verified from the video's own BYTES
        # by tools/check_liveness.py, not from metadata. The web hero uses it so
        # it never marquees a title that turns out not to play, matching the
        # apps (ticks 10/12/22). 0 = not probed yet, NOT a failure: items that
        # fail are excluded upstream. Older consumers ignore the extra column.
        playable = 1 if it.get("playbackVerified") is True else 0
        # Documentary flag (column 9, schema 9). The Documentary CATEGORY
        # resolves by GENRE, not contentType (only ~8 items are typed
        # documentary vs 1,109 carrying the genre) — same as the apps. A cartoon
        # carrying the tag (Betty Boop) is not a documentary, so animation is
        # excluded. One bit per row; older consumers ignore the extra column.
        docs = 1 if ("Documentary" in (it.get("genres") or [])
                     and (it.get("contentType") or "") != "animation") else 0
        # Columns 10-12 (schema 10). The apps read these from the SQLite
        # catalog; the web plane had no equivalent, which left Top Rated,
        # director shelves and genre facets unbuildable on web AND Roku — the
        # only two clients that read this index. Additive, so every existing
        # consumer ignores them (Decision 020).
        #
        # rating is x10 as an INTEGER: 7.4 becomes 74. A float per row costs
        # more bytes in JSON than the precision is worth on a 27,000-row index.
        r = it.get("imdbRating")
        try:
            rating = int(round(float(r) * 10)) if r else None
        except (TypeError, ValueError):
            rating = None
        votes = it.get("imdbVotes")
        try:
            votes = int(votes) if votes else None
        except (TypeError, ValueError):
            votes = None
        director = it.get("director") or None
        genres = it.get("genres") or None
        if genres:
            # Joined, not a nested array: three short strings per row as one
            # string is materially smaller than three JSON arrays.
            genres = "|".join(g for g in genres if g)[:80] or None
        # Column 14 (schema 11): colour, one character. "c" colour, "b" black
        # and white, null unknown. Decision 025 classifies this from the video
        # itself and Decision 084 records how often the reading is a coin flip,
        # so consumers must treat it as a PREFERENCE and never a filter that
        # hides films — Party Play leans colour, it does not require it.
        cm = (it.get("colorMode") or "")[:1] or None
        rows.append([aid, it.get("title") or aid, it.get("year"),
                     it.get("contentType") or "", poster, pro, search, backdrop,
                     playable, docs, rating, votes, director, genres, cm])
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

    # Hidden Gems — read from the BUILT DB's computed flag so the web uses the
    # SAME membership as the apps. The web previously rendered its own "Hidden
    # Gems" by shuffling the popularity tail, which is "random obscure", not
    # "high craft, low traffic": no quality signal took part at all.
    if (gems := _hidden_gem_ids()):
        shelves["hidden-gems"] = gems

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
        "schema": 11,
        "updatedAt": catalog.get("updatedAt") or "",
        "count": len(rows),
        # Must list EVERY column. Rows carry 10 entries at schema 9 and this
        # stopped at 8, so a client that located a column by name instead of by
        # position could not find `playable` or `documentary` at all — they
        # were shipping, undeclared, for two schema bumps.
        "fields": ["id", "title", "year", "contentType", "poster", "pro", "search",
                   "backdrop", "playable", "documentary", "rating10", "votes",
                   "director", "genres", "color"],
        "facets": facets,
        "shelves": shelves,
        "collections": collections,
        "items": rows,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    mb = OUT.stat().st_size / 1_000_000
    print(f"[index] wrote {OUT.name}: {len(rows):,} items, "
          f"{len(shelves)} shelves, {len(collections)} collections, {mb:.1f} MB", flush=True)

    write_topshelf_feed()
    return 0


# ---------------------------------------------------------------------------
# tvOS Top Shelf feed
# ---------------------------------------------------------------------------
# The Top Shelf extension is a separate, out-of-process, memory-constrained
# process that cannot reach the app's SwiftData store or catalog, so it fetches
# THIS small public feed over the network. Continue Watching comes from the App
# Group snapshot the app writes; the two MERGE in the extension (tvOS-DESIGN
# §15.6) — the feed is the editorial backbone, and it populates even before the
# user's first launch.
#
# SCHEMA 2 (tvOS-DESIGN §15.3): we publish `rows` — a POOL of ~30 candidates per
# named row, and more rows than fit — because a feed of exactly what to show,
# ordered deterministically, renders the same titles forever. (Measured: the v1
# feed's 2 rows / 15 titles were byte-identical across three weeks of publishes,
# which is what the owner saw as "the Top Shelf never changes.") The extension
# rotates over these pools on a time bucket, so the surface changes between
# sittings without the pipeline republishing.
#
# `sections` is kept as a v1-shaped digest so already-shipped builds keep working.
TOPSHELF_OUT = REPO / "topshelf.json"
CATALOG_DB = REPO / "catalog.sqlite"

# A designed poster in the built DB: hasRealArtwork and a source that isn't the
# Archive thumbnail or a generated frame cover.
_DESIGNED = ("i.hasRealArtwork = 1 "
             "AND COALESCE(i.artworkSource,'') NOT IN ('','archive','generated') "
             "AND COALESCE(i.posterURL,'') <> '' "
             "AND i.posterURL NOT LIKE '%archive.org/services/img%'")
_NOT_TV_COMM = "i.isAdult = 0 AND i.contentType NOT IN ('tv-series','tv-special','tv-episode','commercial')"
# §15.7: a Top Shelf tile is the most visible surface the app has — it must play.
# `playable = 1` is check_liveness's byte-verified flag; the rights clause mirrors
# CatalogDB.homeAnd so the system Home screen can never show a modern title whose
# rights we can't vouch for.
_PLAYS = "i.playable = 1"
_RIGHTS = ("(i.rightsStatus IN ('public_domain','creative_commons') "
           "OR (i.year BETWEEN 1888 AND 1977))")
_TS_GATE = f"{_DESIGNED} AND {_NOT_TV_COMM} AND {_PLAYS} AND {_RIGHTS}"

# One row per named reason (§15.2 — never "For You"). Ordered by how strongly each
# earns a slot: earlier rows get first pick of a title, since pools are made
# disjoint so a rotation can't show the same film twice under two headings.
POOL_SIZE = 30          # candidates published per row; the extension shows 8
MIN_ROW = 6             # a row thinner than this reads as broken — drop it


def _shelf_sql(shelf_ids, order="s.position"):
    ids = ",".join(f"'{s}'" for s in shelf_ids)
    return f"""
        SELECT i.archiveID, i.title, i.year, i.posterURL, i.imdbID
        FROM items i JOIN item_shelves s USING(archiveID)
        WHERE s.shelfID IN ({ids}) AND {_TS_GATE}
        ORDER BY {order} LIMIT 400"""


def _signal_sql(where, order):
    return f"""
        SELECT i.archiveID, i.title, i.year, i.posterURL, i.imdbID FROM items i
        WHERE {where} AND {_TS_GATE} AND i.year IS NOT NULL
        ORDER BY {order} LIMIT 400"""


def _topshelf_rows(pd_year):
    """(row id, display title, SQL, min items) in priority order. `pd_year` is the
    film year that entered the US public domain most recently (current year - 95)."""
    votes = "COALESCE(i.imdbVotes,0) >= 1000"
    return [
        # Curated, so it leads and is allowed to be short — only 3 of the 7 picks
        # have designed art (the rest are frame covers, excluded by §15.7).
        ("editors-picks", "Editor's Picks",
         _shelf_sql(["editors-picks"], "i.popularityScore DESC"), 3),
        ("top-rated", "Top Rated",
         _signal_sql(f"i.imdbRating IS NOT NULL AND {votes}",
                     "i.imdbRating DESC, i.imdbVotes DESC"), MIN_ROW),
        ("watching-now", "Watching Now on the Archive",
         _signal_sql(f"COALESCE(i.views30d,0) > 0 AND {votes}", "i.views30d DESC"), MIN_ROW),
        ("community-favorites", "Community Favorites",
         _signal_sql(f"COALESCE(i.numFavorites,0) > 0 AND {votes}", "i.numFavorites DESC"), MIN_ROW),
        # The build-time flag, not a threshold restated here (see _mark_hidden_gems).
        ("hidden-gems", "Hidden Gems",
         _signal_sql("i.hiddenGem = 1", "i.imdbRating DESC, i.imdbVotes DESC"), MIN_ROW),
        ("public-domain-day", f"Public Domain Day — {pd_year}",
         _signal_sql(f"i.year = {pd_year}", "i.popularityScore DESC"), MIN_ROW),
        ("film-noir", "Film Noir", _shelf_sql(["film-noir"]), MIN_ROW),
        ("silent-era", "Silent Era", _shelf_sql(["silent-era", "silent-hall-of-fame"]), MIN_ROW),
        ("scifi-horror", "Sci-Fi & Horror", _shelf_sql(["scifi-horror"]), MIN_ROW),
        ("animation", "Animation",
         _shelf_sql(["vintage-cartoons", "classic-cartoons", "animation-all"]), MIN_ROW),
        ("comedy", "Comedy", _shelf_sql(["comedy"]), MIN_ROW),
        ("melies", "Early Cinema", _shelf_sql(["melies"]), MIN_ROW),
        ("most-discussed", "Most Discussed",
         _signal_sql(f"COALESCE(i.numReviews,0) > 0 AND {votes}", "i.numReviews DESC"), MIN_ROW),
        ("prelinger", "The Prelinger Archives", _shelf_sql(["prelinger"]), MIN_ROW),
        ("nasa", "From the NASA Archive", _shelf_sql(["nasa"]), MIN_ROW),
        ("newsreels", "Newsreels", _shelf_sql(["newsreels"]), MIN_ROW),
    ]


def _hidden_gem_ids(limit: int = 60) -> list:
    """archiveIDs flagged `hiddenGem` by build_sqlite (which runs before this).

    ONE definition of the shelf, in the pipeline, consumed by every platform —
    the arrangement this shelf lacked when it silently emptied everywhere at
    once. Returns [] if the DB isn't built yet; the caller then omits the shelf
    and the viewer falls back."""
    if not CATALOG_DB.exists():
        return []
    import sqlite3
    db = sqlite3.connect(CATALOG_DB)
    try:
        db.execute("SELECT hiddenGem FROM items LIMIT 1")
    except sqlite3.OperationalError:
        db.close()
        return []                                   # DB predates the column
    rows = [r[0] for r in db.execute(
        "SELECT archiveID FROM items WHERE hiddenGem = 1 "
        "ORDER BY imdbRating DESC, imdbVotes DESC LIMIT ?", (limit,))]
    db.close()
    print(f"[index] hidden-gems shelf: {len(rows)} items", flush=True)
    return rows


def write_topshelf_feed() -> None:
    # Read the BUILT DB (already deduped + rights-gated by build_sqlite, which
    # runs before this) so the feed is exactly the app's own data — not the raw
    # catalog.json, which still carries excluded/duplicate rows.
    if not CATALOG_DB.exists():
        print("[topshelf] no catalog.sqlite yet — skipped", flush=True)
        return
    import datetime
    import sqlite3
    db = sqlite3.connect(CATALOG_DB)
    pd_year = datetime.date.today().year - 95   # rolling US PD-by-age cutoff

    seen_ids: set[str] = set()
    seen_imdb: set[str] = set()

    def pool(sql):
        """Up to POOL_SIZE cards, skipping anything an earlier row already took
        and collapsing imdb duplicates (foreign re-titles of one film)."""
        out = []
        for aid, title, year, poster, imdb in db.execute(sql):
            if aid in seen_ids or (imdb and imdb in seen_imdb):
                continue
            seen_ids.add(aid)
            if imdb:
                seen_imdb.add(imdb)
            out.append({"id": aid, "title": title or aid, "year": year, "poster": poster})
            if len(out) >= POOL_SIZE:
                break
        return out

    rows = []
    for row_id, title, sql, minimum in _topshelf_rows(pd_year):
        try:
            items = pool(sql)
        except sqlite3.OperationalError as e:
            # A row whose SQL references a column this DB predates must not take
            # the whole feed down with it.
            print(f"[topshelf] row '{row_id}' skipped: {e}", flush=True)
            continue
        if len(items) >= minimum:
            rows.append({"id": row_id, "title": title, "items": items})
        else:
            print(f"[topshelf] row '{row_id}' has {len(items)} items — dropped", flush=True)
    db.close()

    # v1-shaped digest for already-shipped extensions (they read `sections` and
    # take the first 12 of each). Two rows, exactly as before.
    sections = [{"title": r["title"], "items": r["items"][:12]} for r in rows[:2]]

    feed = {"version": 2, "rows": rows, "sections": sections}
    TOPSHELF_OUT.write_text(json.dumps(feed, ensure_ascii=False, separators=(",", ":")),
                            encoding="utf-8")
    total = sum(len(r["items"]) for r in rows)
    kb = TOPSHELF_OUT.stat().st_size / 1000
    print(f"[topshelf] wrote {TOPSHELF_OUT.name}: {len(rows)} rows, {total} items, "
          f"{kb:.0f} KB", flush=True)


if __name__ == "__main__":
    sys.exit(main())
