#!/usr/bin/env python3
"""
build_roku_search_feed.py — the Roku Search feed: every film Roku may list in
its own search results, deep linking into the Archive Watch channel.

WHY. Roku Search sits in the Roku home menu, and a channel that publishes a
search feed has its titles listed there when somebody types or says a film's
name — with a free "watch" option that installs the channel if it is missing
and deep links straight into playback (Roku: "Implementing Roku Search",
"Roku Search feed (JSON)"). That is the one discovery channel where the
viewer arrives already wanting a specific film we hold. Every other route
depends on our own posting rate.

WHAT GOES IN, and why the gates are the ones they are:

  * The item must be in catalog-index.json. The index is the public
    gatekeeper the Roku channel itself reads (Decision 105): an id absent
    there cannot be resolved on the device, so a deep link to it would land on
    a Detail screen with a reason and no film. Being in the index already
    means not `excluded`, not mature, and verified playable.
  * The rights bucket must be a KEEP bucket of audit_rights (Decision 027) —
    safe_pd_age, safe_gov, safe_archive_license, safe_cc, presumed_pd. The
    REPORT buckets (renewal_zone, 1964-77 with no confirmation either way) and
    the CONFIRM bucket are left out: the owner keeps them visible in the app
    under a stated policy, but a feed is a list of films we hand to a third
    party to advertise as free, and "not yet judged" is not a claim we make
    there. `--tier strict` narrows further to pre-1930 / government /
    licensed evidence only — and is what the deploy runs (owner, 2026-09-10:
    "only include items with professional posters ... as well as ones that
    are fully guaranteed to be public domain"), with `--art professional`.
  * TELEVISION IS OUT. Episodes live in series/*.json, never in catalog.json,
    and have never passed the rights audit (SCRATCHPAD: OPEN — OWNER
    DECISION). tv-series cards and orphan tv-episode rows are skipped with
    them. Standalone tv-special items DID pass the film audit and are
    included — as "movie"/"shortform" by duration until the channel that
    honours a tvSpecial deep link is the one in the store (`--tv-specials`).
  * Commercials are out. They are kept off Home in every app for a reason
    (Decision: commercials own surface); 800 brand ads in Roku Search would
    be noise against the films.
  * A poster, a year and a runtime are required by Roku, so an item lacking
    any of them is skipped and COUNTED, never invented.

WHAT EACH ASSET IS. Roku's schema, filled from the catalog: title (never
decorated with the year — Roku matches on it), short/long descriptions
clipped at sentence boundaries with the share pages' quote balancing, the
release date when the catalog holds a real one, genres mapped onto Roku's
fixed vocabulary, credits, an MPAA/USA_PR advisory rating (Roku requires one;
Hays-era "Approved"/"Passed" and no rating at all are honestly "UR"), a main
poster and an optional background, the duration, and one free play option
whose playId IS the archiveID — exactly what the channel's deep-link handler
takes as contentId.

IMDb IDS ARE OFF BY DEFAULT. The spec's prose lists IMDB as an externalIds
source, but Roku's published JSON schema (github.com/rokudev/search-feed-json)
enumerates only tms/ref/gsd/partner_*/gracenote_station_id, and a feed
validated against that schema here fails on every IMDb entry. Roku's own
validator is the authority; `--imdb` emits them for a validator run, and the
default flips only once that run passes.

THE ASSET ID IS NOT ALWAYS THE ARCHIVE ID. Roku caps `id` at 50 characters
and makes it immutable; 2,710 archive ids are longer. Those get a stable
derived id (prefix + hash). The playId is still the archiveID, which is the
only thing the channel needs.

IMAGES MUST ANSWER 200 AT THE URL GIVEN. Roku's validator does not follow a
redirect: the first live run rejected 7,557 assets with IMAGE_DOWNLOAD_ERROR,
every sampled one an archive.org cover (302 to a storage node) — with Commons
`Special:FilePath` (302 to upload.wikimedia.org) in the same pile. So the
generator RESOLVES: one HEAD learns the storage node all our covers live on
(they are files of ONE archive.org item), and the Commons imageinfo API answers
50 titles per call with a direct thumbnail URL at 500px, which also turns
svg/tiff/webp originals — formats Roku refuses — into a jpg/png rendition.
A URL that could not be resolved stays as it was and is counted, never
invented. Roku also refused 343 assets under 60 seconds and 40 with an
implausible year, so both are gates now.

A MAIN IMAGE MUST BE 2:3 OR 16:9. The validator refused 907 posters as
IMAGE_INVALID_MAIN — 300x229, 300x300, 300x400, 500x663, 997x678 — so the
spec's "4:3, 3:4, 1:1 also supported" is not what it enforces. Nothing in the
catalog records an image's size; `tools/measure_image_dims.py` builds that
record in ops/image-dims.json (committed by publish-db). An image measured
off-aspect is replaced by the item's 16:9 TMDb backdrop when it has one, or
the asset is dropped and counted (`image_aspect`). Unmeasured images ship
as-is and Roku judges them — the feed never waits on the cache.

SIZE. ~22,000 assets is ~27 MB, and Roku asks for pagination at 20 MB. Pages
of --page-size assets are chained with nextPageUrl. Generated into the Pages
artifact at deploy time, never committed (Decision 018's reasoning).

Run:
  python tools/catalog_release.py fetch
  python tools/build_roku_search_feed.py --out _site
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import hashlib
import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from audit_rights import bucket, year_contradicted as _audit_year_contradicted  # noqa: E402
from build_share_pages import balance_quotes, strip_html  # noqa: E402

SITE = "https://archivewatch.org"
FEED_DIR = "roku-search"
PAGE_SIZE = 4000
SHORTFORM_MAX_SECONDS = 15 * 60  # Roku: shortform is 15 minutes or less
MIN_SECONDS = 60          # Roku: ASSET_DURATION_SHORT under this (measured)
# 1900, not 1888: Roku's validator answered ASSET_ALL_RELEASE_REMOVED for every
# 1894-1899 film in the first live run (Lumière, Paul, Guy, the 1899
# Cinderella) and then rejected the asset for having no release. The 1890s
# are real cinema and stay in the app; they cannot be stated to Roku.
MIN_YEAR, MAX_YEAR = 1900, dt.date.today().year + 1
COVERS_ITEM = "archivewatch-covers"
COVERS_URL = f"https://archive.org/download/{COVERS_ITEM}/"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"
USER_AGENT = "ArchiveWatch/1.0 (https://archivewatch.org; ben@learningischange.com)"
IMAGE_EXT_RE = re.compile(r"\.(jpe?g|png|gif)(\?.*)?$", re.I)
DIMS_CACHE = REPO / "ops" / "image-dims.json"
# Assets Roku has refused MORE THAN ONCE for something we cannot reproduce —
# an image that answers 200 with the right shape from here and still comes
# back IMAGE_DOWNLOAD_ERROR there. One asset is not worth an unexplained
# rejection in a feed we are asking Roku to publish; the reason travels with
# the id so the next reader can retest it rather than inherit a mystery.
DENYLIST = REPO / "ops" / "roku-feed-denylist.json"
# Measured against Roku's own ingestion, 2026-09-11: it is GENEROUS about a
# portrait poster and STRICT about a landscape one. 500x781 (3.97% off 2:3)
# was approved, while 500x292 (3.68% off 16:9) was refused — the only
# landscape main in the feed that sits above 1%. The other four landscape
# mains (0.09%, 0.15%, 0.97%, 0.97%) were all approved. So the tolerances
# are not symmetric, and neither is the evidence.
# Measured against Roku's own ingestion, 2026-09-11: it is GENEROUS about a
# portrait poster and STRICT about a landscape one. It approved 500x781
# (3.97% off 2:3) and refused 500x292 (3.68% off 16:9), while the other four
# landscape mains — 0.09%, 0.15%, 0.97%, 0.97% — all passed.
#
# These were briefly cut to 1% both ways in pursuit of a 100% ingestion
# report, and the experiment DISPROVED its own premise: removing the 203
# assets outside 1% changed the reported error count by exactly zero
# (job 3: 3,106 assets / 54 errors -> job 4: 2,903 assets / 54 errors). The
# 54 are carried-forward records for assets no longer in the feed at all —
# none of the ids appear in it — so the tail was never the cause and the
# films are restored. The standalone validator, which scores only the FILE,
# is the honest oracle here.
ASPECT_TOLERANCE = {2 / 3: 0.04, 16 / 9: 0.015}

KEEP_BUCKETS = {"safe_pd_age", "safe_gov", "safe_archive_license", "safe_cc",
                "presumed_pd"}
STRICT_BUCKETS = {"safe_pd_age", "safe_gov", "safe_archive_license", "safe_cc"}
# "Fully guaranteed" (owner, 2026-09-10) is narrower than the audit's STRICT
# set: measured on the strict feed, 107 post-1963 items rode in on an
# uploader's CC mark (A Bridge Too Far, Cross of Iron), a CC0 dedication on a
# studio cartoon (Jonny Quest, The Simpsons pilot) or a government-collection
# membership (a 2021 feature). Only age cannot be argued: pre-1930 US works.
GUARANTEED_BUCKETS = {"safe_pd_age"}
TIERS = {"catalog": KEEP_BUCKETS, "strict": STRICT_BUCKETS, "guaranteed": GUARANTEED_BUCKETS}
SKIP_TYPES = {"tv-series", "tv-episode", "commercial"}
# Sources whose art is a DESIGNED poster or still, never a frame grab. The
# generated covers (Decision 023) are honest placeholders in the apps; in a
# feed that advertises films to Roku's search they are the weakest image on
# offer and the one Roku's fetcher fails on. `--art professional` (the
# deployed default) keeps only these.
PROFESSIONAL_ART = {"tmdb", "omdb", "tvdb", "fanart", "tvmaze", "commons",
                    "wikidata", "external"}

# Catalog genre vocabulary (TMDb, OMDb, Wikidata descriptors) -> Roku's fixed
# genre enum. Anything not listed is dropped; a film with nothing left falls
# back by content type. Never guess "drama" for an unknown label.
GENRE_MAP = {
    "drama": "drama", "comedy": "comedy", "animation": "animated",
    "crime": "crime", "romance": "romance", "thriller": "thriller",
    "action": "action", "mystery": "mystery", "horror": "horror",
    "western": "western", "b western": "western", "documentary": "documentary",
    "adventure": "adventure", "war": "war", "fantasy": "fantasy",
    "music": "music", "science fiction": "science fiction",
    "sci-fi": "science fiction", "family": "children", "film noir": "crime drama",
    "history": "history", "musical": "musical", "musical film": "musical",
    "musical comedy": "musical comedy", "tv movie": "drama",
    "romantic comedy": "romantic comedy", "comedy drama": "comedy drama",
    "comedy-drama": "comedy drama", "monster film": "horror",
    "biography": "biography", "biographical film": "biography",
    "spy film": "thriller", "heist film": "crime",
    "crime thriller film": "thriller", "crime drama film": "crime drama",
    "swashbuckler film": "adventure", "historical film": "historical drama",
    "historical drama": "historical drama", "vampire film": "horror",
    "christmas film": "holiday", "comedy horror film": "horror",
    "propaganda film": "history", "war film": "war", "sport": "sports",
    "sports": "sports", "news": "news", "newsreel": "news",
    "educational": "educational", "nature": "nature", "travel": "travel",
    "religious": "religious", "dance": "dance", "opera": "opera",
    "anime": "anime", "suspense": "suspense", "dark comedy": "dark comedy",
    "docudrama": "docudrama", "military": "military", "politics": "politics",
    "science": "science", "art": "art", "children": "children",
    "kids": "children", "aviation": "aviation", "medical": "medical",
    "reality": "reality", "variety": "variety", "talk": "talk",
    "game show": "game show", "cooking": "cooking", "how-to": "how-to",
    "health": "health", "technology": "technology", "environment": "environment",
    "agriculture": "agriculture", "animals": "animals", "boxing": "boxing",
    "baseball": "baseball", "football": "football", "wrestling": "wrestling",
    "golf": "golf", "tennis": "tennis", "hockey": "hockey",
    "basketball": "basketball", "soccer": "soccer", "auto racing": "auto racing",
    "fashion": "fashion", "paranormal": "paranormal", "holiday": "holiday",
    "standup": "standup", "stand-up": "standup", "sitcom": "sitcom",
    "anthology": "anthology", "miniseries": "miniseries",
}
TYPE_FALLBACK_GENRE = {
    "newsreel": "news", "documentary": "documentary", "ephemeral": "educational",
    "animation": "animated", "home-movie": "documentary",
}
DEFAULT_GENRE = "entertainment"

KIND = {
    "feature-film": "Feature film", "silent-film": "Silent film",
    "short-film": "Short film", "animation": "Animated film",
    "tv-special": "Television special", "newsreel": "Newsreel",
    "documentary": "Documentary", "ephemeral": "Ephemeral film",
    "home-movie": "Home movie",
}

MPAA = {"G", "PG", "PG-13", "R", "NC-17"}
USA_PR = {"TV-Y", "TV-Y7", "TV-G", "TV-PG", "TV-14", "TV-MA"}

_NAME_SUFFIXES = {"jr.", "jr", "sr.", "sr", "ii", "iii", "iv"}

# A period after one of these is not the end of a sentence. The share pages'
# clipper cut Caligari's synopsis to "...where they meet Dr." — a sentence
# boundary that was really an honorific.
_ABBREV = ("dr", "mr", "mrs", "ms", "st", "jr", "sr", "vs", "no", "mt", "lt",
           "col", "gen", "capt", "sgt", "prof", "rev", "inc", "co", "u.s", "d.c")


def ulen(s: str) -> int:
    """Roku counts UTF-16 code units: the one description it refused measured
    194 characters here and 208 there (emoji are two units each)."""
    return len(s.encode("utf-16-le")) // 2


def clip(text: str, limit: int) -> str:
    """Clip at a sentence end where one exists past the halfway mark and is
    not an abbreviation; otherwise at a word, with an ellipsis. `limit` is
    in UTF-16 code units, which is how Roku measures."""
    text = strip_html(text)
    if ulen(text) <= limit:
        return balance_quotes(text)
    cut = text[:limit]
    while ulen(cut) > limit:
        cut = cut[:-1]
    i = cut.rfind(". ")
    while i > limit * 0.5:
        before = cut[:i].rstrip()
        last = before.split()[-1].lower().rstrip(".") if before.split() else ""
        if last not in _ABBREV and not (len(last) == 1 and last.isalpha()):
            return balance_quotes(cut[: i + 1])
        i = cut.rfind(". ", 0, i)
    i = cut.rfind(" ")
    return balance_quotes((cut[:i] if i > 0 else cut) + "\u2026")


# An 11-character YouTube video id at the end of the archive id — mixed
# case, at least one digit, and at least five class switches, which is what
# separates "neJjrOjM7uE" and "Qgb5M7HLg4Q" from "Impact_1949". A film that
# arrived as a YouTube rip with the video id still attached is, in this
# catalog, a modern capture wearing an old film's match (My Little Pony as
# "The Doctor", a 2019 talk as "Valencia (1927)"); a real PD film uploaded
# from YouTube is named for the film, not for the video id.
def id_is_youtube_capture(archive_id: str) -> bool:
    aid = archive_id or ""
    # The id must be SET OFF by a separator: CamelCase titles with a year
    # ("TheWizardOfOz1925", "EyesOfYouthPd19") switch class just as often as
    # a video id does, and were 20 of 51 hits without this (measured).
    if len(aid) <= 12 or aid[-12] not in "-_":
        return False
    t = aid[-11:]
    if not re.fullmatch(r"[A-Za-z0-9]{11}", t):     # a separator inside is a word boundary, not an id
        return False
    if not (re.search(r"[a-z]", t) and re.search(r"[A-Z]", t) and re.search(r"\d", t)):
        return False
    cls = ["d" if c.isdigit() else "u" if c.isupper() else "l" for c in t]
    return sum(1 for a, b in zip(cls, cls[1:]) if a != b) >= 5


def year_contradicted(item: dict) -> bool:
    """The audit's own rule (audit_rights.year_contradicted): a year >= 1978
    in the archive id of a "pre-1964" item whose title words are absent from
    that id. One predicate for the apps and the feed."""
    y = item.get("year")
    if not isinstance(y, int) or y >= 1964:
        return False
    return _audit_year_contradicted(item, y)


# --------------------------------------------------------------------------
# pure helpers (tested in tools/test_roku_search_feed.py)

def asset_id(archive_id: str) -> str:
    """Roku caps `id` at 50 chars and never lets it change; a long archive id
    gets a stable derived one. The playId is always the archive id."""
    if len(archive_id) <= 50:
        return archive_id
    h = hashlib.sha1(archive_id.encode("utf-8")).hexdigest()[:20]
    return archive_id[:29] + "~" + h


def roku_type(item: dict, tv_specials: bool = False) -> str:
    rt = int(item.get("runtimeSeconds") or 0)
    # Casing follows the schema Roku links from the spec
    # (github.com/rokudev/search-feed-json): "shortForm"/"tvSpecial", the same
    # spelling as the deep-link mediaTypes. The spec's inline copy is
    # lowercase and its own two examples disagree with each other.
    if item.get("contentType") == "tv-special" and tv_specials:
        return "tvSpecial"
    return "movie" if rt > SHORTFORM_MAX_SECONDS else "shortForm"


def roku_genres(item: dict) -> list:
    out = []
    for g in item.get("genres") or []:
        if not isinstance(g, str):
            continue
        m = GENRE_MAP.get(g.strip().lower())
        if m and m not in out:
            out.append(m)
    if not out:
        out = [TYPE_FALLBACK_GENRE.get(item.get("contentType") or "", DEFAULT_GENRE)]
    return out[:6]


def advisory_rating(content_rating) -> dict:
    r = (content_rating or "").strip().upper().replace("PG13", "PG-13")
    if r in MPAA:
        return {"source": "MPAA", "value": r}
    if r in USA_PR:
        return {"source": "USA_PR", "value": r}
    return {"source": "MPAA", "value": "UR"}


def image_url(url: str, kind: str = "poster") -> str | None:
    """Roku downloads the image and applies a 1920x1080 ceiling. TMDb w780
    posters are 780x1170, and a Commons original can be anything, so every
    source that offers a sized rendition is asked for one that fits."""
    if not url or not url.startswith("http"):
        return None
    u = url.strip()
    if "image.tmdb.org/t/p/" in u:
        size = "w1280" if kind == "background" else "w500"
        u = re.sub(r"/t/p/(original|w\d+)/", f"/t/p/{size}/", u)
    elif "commons.wikimedia.org/wiki/Special:FilePath/" in u:
        # Left for the resolver (Roku will not follow its redirect); the
        # width hint is dropped so the title is exactly the file name.
        u = re.sub(r"\?width=\d+$", "", u)
    return u


def commons_title(url: str) -> str | None:
    m = re.match(r"^https://commons\.wikimedia\.org/wiki/Special:FilePath/([^?#]+)", url)
    return urllib.parse.unquote(m.group(1)) if m else None


_UPLOAD_RE = re.compile(r"^https://upload\.wikimedia\.org/wikipedia/(commons|[a-z]{2,3})/(?:thumb/)?[0-9a-f]/[0-9a-f]{2}/([^/?#]+)")


def wiki_file(url: str):
    """(api host, file name) for an upload.wikimedia.org original. Roku's
    fetcher is refused by upload.wikimedia.org (101 of 103 image failures on
    2026-09-10 were that host, every one answering 200 from a browser), while
    the thumb.wikimedia.org renditions the imageinfo API hands out pass."""
    m = _UPLOAD_RE.match(url or "")
    if not m:
        return None
    wiki, name = m.group(1), urllib.parse.unquote(m.group(2))
    host = "commons.wikimedia.org" if wiki == "commons" else f"{wiki}.wikipedia.org"
    return host, name


class ImageResolver:
    """Turns redirecting image URLs into ones that answer 200 directly.

    archive.org covers: every cover is a file of ONE item, so a single HEAD
    reveals the storage node prefix for all of them. Commons: the imageinfo
    API, 50 titles a call, answers a direct thumbnail URL (and a jpg/png
    rendition for svg/tiff/webp originals). Both are best-effort — a failure
    leaves the URL untouched and is counted in `unresolved`."""

    def __init__(self, network: bool = True, width: int = 500,
                 covers_dir: "Path | None" = None):
        self.network = network
        self.width = width
        # A cover file present here is served from archivewatch.org itself:
        # archive.org refuses the download to datacenter fetchers, and Roku's
        # validator is one (tools/publish_roku_covers.py, deploy-pages.yml).
        self.covers_dir = covers_dir
        self.covers_local = 0
        self.node_prefix: str | None = None
        self.commons: dict = {}
        self.unresolved = 0
        self.notes: list = []

    # -- archive.org covers
    def _learn_node(self, sample: str) -> None:
        if not self.network or self.node_prefix is not None:
            return
        try:
            req = urllib.request.Request(sample, method="HEAD",
                                         headers={"User-Agent": USER_AGENT})

            class NoRedirect(urllib.request.HTTPRedirectHandler):
                def redirect_request(self, *a, **k):
                    return None
            opener = urllib.request.build_opener(NoRedirect)
            try:
                opener.open(req, timeout=20)
            except urllib.error.HTTPError as e:
                loc = e.headers.get("Location") if e.code in (301, 302, 303, 307, 308) else None
                if loc and f"/items/{COVERS_ITEM}/" in loc:
                    self.node_prefix = loc.split(f"/items/{COVERS_ITEM}/")[0] + f"/items/{COVERS_ITEM}/"
                    self.notes.append(f"covers node {self.node_prefix}")
                    return
                raise
        except Exception as e:  # noqa: BLE001
            self.notes.append(f"covers node unresolved: {e}")
        if self.node_prefix is None:
            self.node_prefix = ""      # tried once; keep the archive.org URL

    def _covers(self, url: str) -> str:
        name = url[len(COVERS_URL):]
        if self.covers_dir and (self.covers_dir / name).is_file():
            self.covers_local += 1
            return f"{SITE}/{FEED_DIR}/covers/{name}"
        self._learn_node(url)
        if self.node_prefix:
            return self.node_prefix + url[len(COVERS_URL):]
        self.unresolved += 1
        return url

    # -- Commons
    def prefetch_commons(self, urls: list) -> None:
        by_host: dict = {}
        for u in urls:
            t = commons_title(u)
            if t:
                by_host.setdefault("commons.wikimedia.org", set()).add(t)
                continue
            wf = wiki_file(u)
            if wf:
                by_host.setdefault(wf[0], set()).add(wf[1])
        if not self.network:
            return
        for host, titles in by_host.items():
            self._prefetch_host(host, sorted(titles))

    def _prefetch_host(self, host: str, titles: list) -> None:
        for i in range(0, len(titles), 50):
            batch = titles[i:i + 50]
            q = urllib.parse.urlencode({
                "action": "query", "prop": "imageinfo", "iiprop": "url|mime",
                "iiurlwidth": str(self.width), "format": "json",
                "titles": "|".join("File:" + t for t in batch),
            })
            try:
                req = urllib.request.Request(f"https://{host}/w/api.php?{q}",
                                             headers={"User-Agent": USER_AGENT})
                with urllib.request.urlopen(req, timeout=30) as r:
                    data = json.loads(r.read().decode("utf-8"))
                norm = {}
                for n in data.get("query", {}).get("normalized", []):
                    norm[n["to"]] = n["from"]
                for page in data.get("query", {}).get("pages", {}).values():
                    info = (page.get("imageinfo") or [{}])[0]
                    thumb = (info.get("thumburl") or info.get("url") or "").split("?")[0]
                    title = page.get("title", "")
                    orig = norm.get(title, title)
                    key = orig[5:] if orig.startswith("File:") else orig
                    if thumb and IMAGE_EXT_RE.search(thumb):
                        self.commons[(host, key)] = thumb
                        self.commons[(host, key.replace("_", " "))] = thumb
            except Exception as e:  # noqa: BLE001
                self.notes.append(f"{host} batch {i // 50} failed: {e}")

    def _lookup(self, host: str, name: str):
        return self.commons.get((host, name)) or self.commons.get((host, name.replace("_", " ")))

    def _commons(self, url: str) -> str:
        t = commons_title(url)
        hit = self._lookup("commons.wikimedia.org", t or "")
        if hit:
            return hit
        self.unresolved += 1
        return url

    def _upload(self, url: str) -> str:
        wf = wiki_file(url)
        hit = self._lookup(*wf) if wf else None
        if hit:
            return hit
        self.unresolved += 1
        return url

    def resolve(self, url: str | None) -> str | None:
        if not url:
            return url
        if url.startswith(COVERS_URL):
            return self._covers(url)
        if "commons.wikimedia.org/wiki/Special:FilePath/" in url:
            return self._commons(url)
        if url.startswith("https://upload.wikimedia.org/wikipedia/"):
            return self._upload(url)
        return url


def aspect_ok(w: int, h: int) -> bool:
    if not w or not h:
        return False
    r = w / h
    return any(abs(r - a) / a <= tol for a, tol in ASPECT_TOLERANCE.items())


def image_verdict(url: str | None, dims: dict) -> str:
    """'ok' | 'bad' | 'unknown' for a resolved image URL against the cache.
    Generated covers are 600x900 by construction and TMDb backdrops are 16:9
    by TMDb's rule, so both are ok without a measurement."""
    if not url:
        return "bad"
    if ("/items/archivewatch-covers/" in url or f"/{FEED_DIR}/covers/" in url
            or ("image.tmdb.org" in url and "/w1280/" in url)):
        return "ok"
    d = dims.get(url)
    if d is None:
        return "unknown"
    if d == 0:
        return "bad"
    return "ok" if aspect_ok(d[0], d[1]) else "bad"


def quality(item: dict) -> str:
    vf = item.get("videoFile") or {}
    hint = " ".join(str(x) for x in (vf.get("name") if isinstance(vf, dict) else "",
                                     item.get("archiveID"), item.get("title")) if x)
    m = re.search(r"(?<!\d)(2160|1080|720|480|360|240)p", hint, re.I)
    if not m:
        return "sd"
    h = int(m.group(1))
    if h >= 2160:
        return "uhd"
    if h >= 1080:
        return "fhd"
    if h >= 720:
        return "hd"
    return "sd"


def split_people(s) -> list:
    """'Otto Brower, Edwin H. Knopf' -> two people; 'Florenz Ziegfeld, Jr.' -> one."""
    if isinstance(s, list):
        names = []
        for x in s:
            names += split_people(x)
        return names
    if not isinstance(s, str) or not s.strip():
        return []
    parts = [p.strip() for p in s.split(",")]
    out = []
    for p in parts:
        if out and p.lower() in _NAME_SUFFIXES:
            out[-1] = out[-1] + ", " + p
        elif p:
            out.append(p)
    return out


def credits(item: dict) -> list:
    out, seen = [], set()

    def add(name, role):
        if not isinstance(name, str):
            return
        n = re.sub(r"\s+", " ", name).strip()
        if not n or (n, role) in seen or len(n) > 100:
            return
        seen.add((n, role))
        out.append({"name": n, "role": role})

    for d in split_people(item.get("director")):
        add(d, "director")
    for w in split_people(item.get("writer")):
        add(w, "screenwriter")
    for c in (item.get("cast") or [])[:10]:
        if isinstance(c, dict):
            add(c.get("name"), "actor")
        elif isinstance(c, str):
            add(c, "actor")
    return out[:20]


def synopsis_text(item: dict) -> str:
    s = item.get("synopsis")
    if isinstance(s, list):
        s = " ".join(x for x in s if isinstance(x, str))
    return strip_html(s or "") if s else ""


def descriptions(item: dict) -> tuple[str, str | None]:
    text = synopsis_text(item)
    if text:
        # Five under Roku's limits: the validator refused one description that
        # measured exactly 200 here, so however it counts, stay clear of it.
        return clip(text, 195), clip(text, 495)
    kind = KIND.get(item.get("contentType") or "", "Film")
    y = item.get("year")
    d = item.get("director")
    who = f" by {d}" if isinstance(d, str) and d.strip() and len(d) < 60 else ""
    return f"{kind} from {y}{who}, preserved by the Internet Archive.", None


def release(item: dict) -> dict:
    rd = item.get("releaseDate")
    y = item.get("year")
    if isinstance(rd, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", rd) \
            and isinstance(y, int) and rd[:4] == str(y):
        return {"releaseDate": rd}
    return {"releaseYear": int(y)}


def tags(item: dict, b: str) -> list:
    t = []
    y = item.get("year")
    if isinstance(y, int):
        t.append(f"{y // 10 * 10}s")
    t.append("creative commons" if b == "safe_cc"
             or item.get("rightsStatus") == "creative_commons" else "public domain")
    if item.get("isSilentFilm"):
        t.append("silent film")
    if item.get("colorMode") == "bw":
        t.append("black and white")
    t.append("internet archive")
    return [x for x in t if len(x) <= 20]


def eligibility(item: dict, index_ids: set, tier: str, art: str = "any") -> str | None:
    """None when the item belongs in the feed, else the reason it does not."""
    if item.get("excluded"):
        return "excluded"
    if item.get("contentType") in SKIP_TYPES:
        return "tv_or_commercial"
    if item.get("archiveID") not in index_ids:
        return "not_in_public_index"
    b, _ = bucket(item)
    allowed = TIERS[tier]
    if b not in allowed:
        return f"rights:{b}"
    if not isinstance(item.get("year"), int):
        return "no_year"
    if not (MIN_YEAR <= item["year"] <= MAX_YEAR):
        return "implausible_year"
    if year_contradicted(item):
        return "year_contradicted_by_id"
    if id_is_youtube_capture(item.get("archiveID", "")):
        return "youtube_capture_id"
    if not item.get("runtimeSeconds"):
        return "no_runtime"
    if int(item["runtimeSeconds"]) < MIN_SECONDS:
        return "under_60s"
    if not item.get("hasRealArtwork") or not image_url(item.get("posterURL")):
        return "no_poster"
    if art == "professional" and (item.get("artworkSource") or "") not in PROFESSIONAL_ART:
        return "art_not_professional"
    if not (item.get("title") or "").strip():
        return "no_title"
    return None


def build_asset(item: dict, tv_specials: bool = False, imdb: bool = False,
                resolver: "ImageResolver | None" = None,
                dims: dict | None = None) -> "dict | None":
    """The Roku asset, or None when its only images are known-bad."""
    b, _ = bucket(item)
    title = strip_html(item.get("title") or "")[:200]
    short, long_ = descriptions(item)
    a = {
        "id": asset_id(item["archiveID"]),
        "type": roku_type(item, tv_specials),
        "titles": [{"value": title}],
        "shortDescriptions": [{"value": short}],
    }
    if long_ and long_ != short:
        a["longDescriptions"] = [{"value": long_}]
    a.update(release(item))
    a["genres"] = roku_genres(item)
    a["tags"] = tags(item, b)
    cr = credits(item)
    if cr:
        a["credits"] = cr
    a["advisoryRatings"] = [advisory_rating(item.get("contentRating"))]
    main = image_url(item.get("posterURL"))
    bg = image_url(item.get("backdropURL"), "background")
    if resolver:
        main, bg = resolver.resolve(main), resolver.resolve(bg)
    dims = dims or {}
    mv, bv = image_verdict(main, dims), image_verdict(bg, dims) if bg else "bad"
    # UNKNOWN is not OK. An unmeasured image is an unverified claim, and Roku
    # rejects the asset when it turns out off-aspect: on 2026-09-11 the feed
    # validated at 97%, and every enumerated failure was a Wikimedia still
    # (4:3, panorama, 500x1106) that had shipped unmeasured because the dims
    # cache held the PRE-resolution URL. We choose what goes in this feed, so
    # anything we cannot prove is the right shape does not go in.
    if mv != "ok":
        if bv == "ok":
            main, bg = bg, None      # a 16:9 backdrop is a valid main image
        else:
            return None
    images = [{"type": "main", "url": main}]
    if bg and bv != "bad":
        images.append({"type": "background", "url": bg})
    a["images"] = images
    a["durationInSeconds"] = int(item["runtimeSeconds"])
    if imdb and isinstance(item.get("imdbID"), str) and re.fullmatch(r"tt\d{5,9}", item["imdbID"]):
        a["externalIds"] = [{"source": "IMDB", "id": item["imdbID"]}]
    a["content"] = {"playOptions": [{
        "license": "free",
        "quality": quality(item),
        "playId": item["archiveID"],
    }]}
    return a


def validate_asset(a: dict) -> list:
    """The spec's hard limits, checked before Roku checks them."""
    errs = []
    if not (1 <= len(a["id"]) <= 50):
        errs.append("id length")
    if a["type"] not in ("movie", "tvSpecial", "shortForm"):
        errs.append("type")
    if not a["titles"][0]["value"] or ulen(a["titles"][0]["value"]) > 200:
        errs.append("title length")
    if ulen(a["shortDescriptions"][0]["value"]) > 200:
        errs.append("short description")
    if any(ulen(d["value"]) > 500 for d in a.get("longDescriptions", [])):
        errs.append("long description")
    if not a.get("genres"):
        errs.append("genres")
    if any(len(t) > 20 for t in a.get("tags", [])):
        errs.append("tag length")
    if not any(i["type"] == "main" for i in a["images"]):
        errs.append("main image")
    if any(not IMAGE_EXT_RE.search(i["url"]) for i in a["images"]):
        errs.append("image format (jpg/png/gif only)")
    if any("/wiki/Special:FilePath/" in i["url"] or i["url"].startswith("https://upload.wikimedia.org/")
           for i in a["images"]):
        errs.append("image Roku cannot fetch (unresolved Wikimedia)")
    if a["durationInSeconds"] <= 0:
        errs.append("duration")
    if not a["content"]["playOptions"][0]["playId"]:
        errs.append("playId")
    if "releaseDate" not in a and "releaseYear" not in a:
        errs.append("release")
    return errs


def paginate(assets: list, page_size: int, base_url: str, stamp: str = "") -> list:
    """Root feed + chained pages. Page 1 is feed.json; page N is feed-N.json.

    `stamp` is part of every continuation page's NAME: GitHub Pages sits
    behind a CDN with a 600 s cache that IGNORES the query string (measured:
    a random ?g= answered x-cache HIT), and Roku's fourth validation run read
    page 1 fresh and pages 2-4 from the cache — the previous build, still
    pointing covers at archive.org — so 4,082 assets re-failed a fix that
    was live. The stamp is a hash of the page set, so an unchanged feed keeps
    its names (and its cache) and a changed one gets names the CDN has never
    served. The root stays feed.json — the URL Roku is registered with."""
    pages = []
    q = f"-{stamp}" if stamp else ""
    n = max(1, (len(assets) + page_size - 1) // page_size)
    for p in range(n):
        chunk = assets[p * page_size:(p + 1) * page_size]
        doc = {
            "version": "1",
            "defaultLanguage": "en",
            "defaultAvailabilityCountries": ["us"],
            "assets": chunk,
        }
        if p + 1 < n:
            doc["nextPageUrl"] = f"{base_url}/feed-{p + 2}{q}.json"
        pages.append(("feed.json" if p == 0 else f"feed-{p + 1}{q}.json", doc))
    return pages


def keep_live_chain(out: Path, base_url: str, new_names: set) -> int:
    """Copy the currently-live continuation pages into `out` when their names
    differ from this build's. Best effort: any failure keeps nothing."""
    kept = 0
    url = f"{base_url}/feed.json"
    try:
        for _ in range(20):
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=30) as r:
                body = r.read()
            doc = json.loads(body.decode("utf-8"))
            nxt = doc.get("nextPageUrl")
            if not nxt:
                break
            name = nxt.rsplit("/", 1)[-1].split("?")[0]
            if name in new_names or not re.fullmatch(r"feed-\d+(-[0-9a-f]+)?\.json", name):
                break
            req = urllib.request.Request(nxt, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=60) as r:
                page = r.read()
            (out / name).write_bytes(page)
            kept += 1
            url = nxt
    except Exception:  # noqa: BLE001
        pass
    return kept


# --------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", default=str(REPO / "catalog.json"))
    ap.add_argument("--index", default=str(REPO / "catalog-index.json"))
    ap.add_argument("--out", default=str(REPO / "_site"))
    ap.add_argument("--base-url", default=f"{SITE}/{FEED_DIR}")
    ap.add_argument("--page-size", type=int, default=PAGE_SIZE)
    ap.add_argument("--tier", choices=("catalog", "strict", "guaranteed"), default="catalog")
    ap.add_argument("--art", choices=("any", "professional"), default="any",
                    help="professional: designed posters/stills only, no frame covers")
    ap.add_argument("--tv-specials", action="store_true",
                    help="emit tv-special items as Roku 'tvspecial' (needs the "
                         "channel build that autoplays a tvSpecial deep link)")
    ap.add_argument("--imdb", action="store_true",
                    help="emit IMDb ids as externalIds (not in Roku's published "
                         "schema; try on the dashboard validator first)")
    ap.add_argument("--limit", type=int, default=0,
                    help="cap the asset count (a test feed)")
    ap.add_argument("--no-network", action="store_true",
                    help="skip image URL resolution (offline / tests)")
    args = ap.parse_args()

    cat_path, idx_path = Path(args.catalog), Path(args.index)
    if not cat_path.exists():
        print("[roku-feed] no catalog.json — run tools/catalog_release.py fetch first",
              file=sys.stderr)
        return 1
    catalog = json.loads(cat_path.read_text(encoding="utf-8"))
    index = json.loads(idx_path.read_text(encoding="utf-8"))
    index_ids = {row[0] for row in index.get("items", [])}

    reasons = collections.Counter()
    assets, invalid = [], collections.Counter()
    seen_ids = set()
    eligible = []
    for item in catalog.get("items", []):
        why = eligibility(item, index_ids, args.tier, args.art)
        if why:
            reasons[why.split(":")[0] if why.startswith("rights:") and args.tier == "catalog"
                    and not why.endswith(("renewal_zone", "renewal_zone_bw",
                                          "modern_copyright_unconfirmed", "unknown_year"))
                    else why] += 1
            continue
        eligible.append(item)

    resolver = ImageResolver(network=not args.no_network,
                             covers_dir=Path(args.out) / FEED_DIR / "covers")
    resolver.prefetch_commons([image_url(it.get("posterURL")) or "" for it in eligible]
                              + [image_url(it.get("backdropURL"), "background") or "" for it in eligible])
    dims = json.loads(DIMS_CACHE.read_text(encoding="utf-8")) if DIMS_CACHE.exists() else {}
    denied = json.loads(DENYLIST.read_text(encoding="utf-8")) if DENYLIST.exists() else {}
    unmeasured = 0
    for item in eligible:
        if item["archiveID"] in denied:
            reasons["roku_denylist"] += 1
            continue
        a = build_asset(item, args.tv_specials, imdb=args.imdb, resolver=resolver, dims=dims)
        if a is None:
            reasons["image_unverified"] += 1
            continue
        if image_verdict(a["images"][0]["url"], dims) == "unknown":
            unmeasured += 1          # can no longer happen; kept as a tripwire
        errs = validate_asset(a)
        if errs:
            for e in errs:
                invalid[e] += 1
            continue
        if a["id"] in seen_ids:
            invalid["duplicate id"] += 1
            continue
        seen_ids.add(a["id"])
        assets.append(a)

    # Popular first, so a truncated test feed and Roku's own ingestion order
    # both start with the films people actually search for.
    pop = {it["archiveID"]: (it.get("popularityScore") or 0) for it in catalog["items"]}
    assets.sort(key=lambda a: -pop.get(a["content"]["playOptions"][0]["playId"], 0))
    if args.limit:
        assets = assets[:args.limit]

    out = Path(args.out) / FEED_DIR
    out.mkdir(parents=True, exist_ok=True)
    stamp = hashlib.sha1(json.dumps(assets, sort_keys=True, ensure_ascii=False)
                         .encode("utf-8")).hexdigest()[:10]
    pages = paginate(assets, args.page_size, args.base_url, stamp)
    total_bytes = 0
    for name, doc in pages:
        data = json.dumps(doc, ensure_ascii=False, separators=(",", ":"))
        (out / name).write_text(data, encoding="utf-8")
        total_bytes += len(data.encode("utf-8"))

    # The root feed.json the CDN is still serving may be the PREVIOUS build's
    # for up to ten minutes, naming continuation pages this artifact would
    # otherwise no longer carry. Keep that chain alive alongside the new one,
    # so a Roku ingestion that lands in the window never hits a 404 mid-feed.
    kept = keep_live_chain(out, args.base_url, {n for n, _ in pages}) if not args.no_network else 0

    # One asset per Roku type, as the implementation guide asks for a test
    # feed with a single entry per content type. Popular first, so the test
    # films are recognisable.
    test, seen_types = [], set()
    for a in assets:
        if a["type"] not in seen_types:
            seen_types.add(a["type"])
            test.append(a)
    test_doc = paginate(test, len(test) or 1, args.base_url)[0][1]
    (out / "test-feed.json").write_text(
        json.dumps(test_doc, ensure_ascii=False, indent=1), encoding="utf-8")

    by_type = collections.Counter(a["type"] for a in assets)
    manifest = {
        "generated": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "tier": args.tier,
        "art": args.art,
        "assets": len(assets),
        "byType": dict(by_type),
        "pages": [n for n, _ in pages],
        "previousChainKept": kept,
        "bytes": total_bytes,
        "withImdb": sum(1 for a in assets if a.get("externalIds")),
        "withBackground": sum(1 for a in assets if len(a["images"]) > 1),
        "withLongDescription": sum(1 for a in assets if a.get("longDescriptions")),
        "skipped": dict(reasons),
        "invalid": dict(invalid),
        "imagesUnresolved": resolver.unresolved,
        "coversServedLocally": resolver.covers_local,
        "imagesUnmeasured": unmeasured,
        "imageDimsCached": len(dims),
        "imageNotes": resolver.notes,
        "imageHosts": dict(collections.Counter(
            a["images"][0]["url"].split("/")[2] for a in assets)),
        "test": [a["content"]["playOptions"][0]["playId"] for a in test],
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1), encoding="utf-8")

    print(f"[roku-feed] {len(assets)} assets ({total_bytes/1e6:.1f} MB over "
          f"{len(pages)} page(s)) tier={args.tier} art={args.art} types={dict(by_type)}")
    print(f"[roku-feed] skipped: {dict(reasons)}")
    if invalid:
        print(f"[roku-feed] invalid (dropped): {dict(invalid)}")
    print(f"[roku-feed] images: hosts={manifest['imageHosts']} unresolved={resolver.unresolved} "
          f"unmeasured={unmeasured} dims-cached={len(dims)} notes={resolver.notes}")
    print(f"[roku-feed] test feed: {manifest['test']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
