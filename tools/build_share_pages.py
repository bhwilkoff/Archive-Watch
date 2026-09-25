#!/usr/bin/env python3
"""
build_share_pages.py — a real page at every share URL, so a shared link looks
like the film.

THE DEFECT THIS FIXES. `archivewatch.org/item/<id>` is the canonical share URL
on every platform: the apps' share buttons, the Roku QR card, the social
programme, and the Universal / App Links that open the native apps. On GitHub
Pages nothing existed at that path, so it fell through to `404.html` — a page
carrying no per-film metadata at all, served with HTTP 404. Every link anyone
shared previewed as nothing, and several crawlers decline to preview a 404 at
all. A share is the only channel that scales with the audience rather than
with our own posting rate, and it was the one that looked broken.

WHY THIS IS NOT REPO BLOAT. Pages deploys from an ARTIFACT assembled in
deploy-pages.yml, not from the branch, so these ~27,000 files are generated at
deploy time and never committed — the same reasoning as Decision 018, which
kept the catalog out of git.

WHAT EACH PAGE IS (rewritten 2026-09-25, WEB-DESIGN §3.2a). The film's whole
Detail as HTML — synopsis with its source, credits, cast, genres, facts,
archive.org reviews, More Like This as links — with schema.org JSON-LD, Open
Graph tags, the iOS Smart App Banner and one primary "Watch now" into the
viewer. NO SCRIPT: the page used to forward humans with location.replace(),
and Google runs scripts, so it read all ~27,000 pages as redirects to the site
root (a hash is not a URL to a crawler) and indexed none of them. The owner
chose the page over the jump: "I'd love the full set of movies to be
searchable with all of the info on each page being a part of the search
index." No script is also no counter, so privacy.html needs no change.

It also writes sitemap.xml (an index of <=10,000-URL files), which robots.txt
names, so Google can find every page without a submission.

A NOTE ON RUNNING THIS LOCALLY. Two catalog ids differ only in case
(`macleanstoot` and `MacleansToot`), so a case-insensitive filesystem — macOS
by default — writes one over the other and the count comes out one short. The
Linux runner and GitHub Pages are both case-sensitive, so the deployed site is
correct. Do NOT "fix" this by folding case: the id IS the URL the apps emit.

Run:
  python tools/build_share_pages.py --out _site
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SITE = "https://archivewatch.org"
IOS_APP_ID = "6776697407"

# catalog-index.json schema 11, from its own `fields` array:
#   id title year contentType poster pro search backdrop playable documentary
#   rating10 votes director genres color
I_ID, I_TITLE, I_YEAR, I_TYPE, I_POSTER = 0, 1, 2, 3, 4
I_BACKDROP, I_DIRECTOR = 7, 12

# details/<shard>.json record order, documented in build_web_details.py.
# TRAILING NULLS ARE TRIMMED, so every read is length-guarded via at().
D_SYNOPSIS, D_DIRECTOR, D_RUNTIME, D_BACKDROP = 1, 2, 5, 6
D_CAST, D_GENRES, D_COMMUNITY, D_EXTRAS, D_RELATED = 3, 4, 8, 9, 10
I_GENRES = 13
SITEMAP_CHUNK = 10000

# The viewer's own provenance labels (watch.js, Detail), so a page and the
# app name a synopsis's source in the same words.
SOURCE = {"tmdb": "Synopsis from TMDb", "omdb": "Synopsis from OMDb",
          "wikipedia": "Synopsis from Wikipedia", "tvmaze": "Synopsis from TVmaze",
          "agent-reviewed": "Synopsis, reviewed"}
UPLOADER = "Uploader's description on archive.org"

KIND = {
    "feature-film": "Feature film", "silent-film": "Silent film",
    "short-film": "Short film", "animation": "Animation",
    "tv-series": "Classic TV series", "tv-special": "Television",
    "tv-episode": "Episode", "newsreel": "Newsreel",
    "documentary": "Documentary", "ephemeral": "Ephemeral film",
    "commercial": "Commercial",
}

SHARE_CSS = """:root{color-scheme:dark;--bg:#0B0B0C;--panel:#16161A;--text:#EBEBEB;
--muted:#9A9AA0;--line:#26262B;--primary:#FF5C35;--accent:#7FA3FF}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);
font:16px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
a{color:var(--accent)}
.top{padding:14px 16px;border-bottom:1px solid var(--line)}
.top a{color:var(--primary);font-weight:700;text-decoration:none;letter-spacing:.01em}
main{max-width:900px;margin:0 auto;padding:20px 16px 48px}
.hero{display:flex;flex-direction:column;gap:20px}
.hero img{width:180px;height:270px;object-fit:cover;border-radius:10px;background:var(--panel)}
h1{font-size:1.7rem;line-height:1.2;margin:0 0 6px}
h2{font-size:1.05rem;margin:32px 0 10px;color:var(--muted);font-weight:600;
text-transform:uppercase;letter-spacing:.06em}
.aka,.m,.src,.f{color:var(--muted);font-size:.95rem;margin:0 0 10px}
.tg{font-style:italic;margin:0 0 12px}
.src{font-size:.85rem}
.gen{display:flex;flex-wrap:wrap;gap:8px;margin:0 0 16px;padding:0;list-style:none}
.gen li{border:1px solid var(--line);border-radius:999px;padding:2px 12px;font-size:.9rem}
.acts{display:flex;flex-wrap:wrap;gap:12px;align-items:center;margin:4px 0 8px}
a.b{display:inline-block;background:var(--primary);color:var(--bg);font-weight:700;
text-decoration:none;padding:12px 24px;border-radius:999px}
dl{display:grid;grid-template-columns:minmax(0,1fr);gap:4px 16px;margin:0}
dt{color:var(--muted);font-size:.9rem}
dd{margin:0 0 10px}
.cast{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:12px 16px;
margin:0;padding:0;list-style:none}
.cast li{display:flex;align-items:center;gap:10px}
.cast img,.cast .ini{width:56px;height:56px;border-radius:50%;object-fit:cover;flex:none;
background:var(--panel)}
.cast .ini{display:grid;place-items:center;color:var(--muted);font-weight:700}
.cast .m{display:block;margin:0;font-size:.8rem}
.rv{border-top:1px solid var(--line);padding:12px 0}
.rv p{margin:4px 0}
.rel{display:grid;grid-template-columns:repeat(auto-fill,minmax(120px,1fr));gap:16px;
margin:0;padding:0;list-style:none}
.rel a{display:block;text-decoration:none;color:var(--text);font-size:.9rem}
.rel img,.rel .noart{display:block;width:100%;height:auto;aspect-ratio:2/3;object-fit:cover;
border-radius:8px;background:var(--panel);margin:0 0 6px}
.az{display:flex;flex-wrap:wrap;gap:6px 14px;margin:0 0 24px;padding:0;list-style:none}
.list{margin:0;padding:0;list-style:none}
.list li{padding:6px 0;border-bottom:1px solid var(--line)}
.list .m,.az .m{margin:0;font-size:.85rem}
footer{max-width:900px;margin:0 auto;padding:0 16px 40px;color:var(--muted);font-size:.85rem}
@media (min-width:640px){
.hero{flex-direction:row}
.hero img{width:220px;height:330px;flex:none}
dl{grid-template-columns:max-content minmax(0,1fr)}
dd{margin:0 0 6px}
}
"""

# X/Twitter falls back to Open Graph for title, description and image, so only
# the card TYPE needs a twitter: tag.
HEAD = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title_tag}</title>
<meta name="description" content="{desc}">
<link rel="canonical" href="{url}">
<meta name="apple-itunes-app" content="app-id={app_id}, app-argument={app_arg}">
<meta property="og:site_name" content="Archive Watch">
<meta property="og:type" content="{og_type}">
<meta property="og:title" content="{og_title}">
<meta property="og:description" content="{desc}">
<meta property="og:url" content="{url}">{image_tags}
<meta name="twitter:card" content="{tw_card}">
<link rel="stylesheet" href="/share.css">
<script type="application/ld+json">{ld}</script>
</head>
<body>
<header class="top"><a href="/">Archive Watch</a></header>
<main>
"""

FOOT = """</main>
<footer>Public domain, from the Internet Archive. Free to watch on Archive Watch
&mdash; no account, no ads. <a href="/films/">All films A&ndash;Z</a> &middot;
<a href="/privacy.html">Privacy</a></footer>
</body>
</html>
"""


def strip_html(s: str) -> str:
    s = re.sub(r"<br\s*/?>", " ", s or "")
    s = re.sub(r"<[^>]+>", "", s)
    s = (s.replace("&amp;", "&").replace("&quot;", '"').replace("&#39;", "'")
          .replace("&nbsp;", " ").replace("&lt;", "<").replace("&gt;", ">"))
    return re.sub(r"\s+", " ", s).strip()


def balance_quotes(s: str) -> str:
    """A synopsis here is often a quoted review, so clipping it mid-quote
    leaves an opening quotation mark with nothing to close it — which reads,
    in a link preview, as if the text had been truncated by accident. Drop the
    opener rather than invent a closer we cannot place."""
    opens = ('"', "“")
    closes = ('"', "”")
    if s[:1] in opens and sum(s.count(c) for c in set(opens + closes)) < 2:
        return s[1:].lstrip()
    return s


def clip(text: str, limit: int) -> str:
    text = strip_html(text)
    if len(text) <= limit:
        return balance_quotes(text)
    cut = text[:limit]
    i = cut.rfind(". ")
    if i > limit * 0.5:
        return balance_quotes(cut[: i + 1])
    i = cut.rfind(" ")
    return balance_quotes((cut[:i] if i > 0 else cut) + "…")


def at(row, i):
    """Positional read that tolerates a trimmed record."""
    return row[i] if row is not None and len(row) > i else None


def safe_segment(s: str):
    """An archiveID becomes a directory name, so anything that could escape
    the output tree is refused rather than written somewhere unexpected."""
    if not s or s in (".", "..") or "/" in s or "\\" in s or s.startswith("."):
        return None
    return s


def tmdb_at(url, width: int):
    """TMDb serves fixed widths; ask for the one the page draws at, never the
    full-size art (watch.js tmdbAtWidth's steps). Other hosts pass through."""
    if not url or "image.tmdb.org/t/p/" not in str(url):
        return url
    return re.sub(r"/t/p/(w\d+|original)/", f"/t/p/w{width}/", str(url))


def e(s) -> str:
    return html.escape(str(s), quote=True)


def title_key(s: str) -> str:
    """watch.js titleKey(): the same folding, so "also known as" appears on a
    page exactly when it appears in the viewer."""
    import unicodedata
    lig = {"œ": "oe", "Œ": "oe", "æ": "ae", "Æ": "ae", "ß": "ss", "ø": "o",
           "Ø": "o", "ł": "l", "Ł": "l", "đ": "d", "Đ": "d"}
    s = "".join(lig.get(c, c) for c in str(s or ""))
    s = "".join(c for c in unicodedata.normalize("NFD", s) if not unicodedata.combining(c))
    s = re.sub(r"\(.*?\)", " ", s.lower())
    s = re.sub(r"^(the|a|an)\s+", "", s)
    return re.sub(r"[^a-z0-9]+", "", s)


def also_known_as(title, canonical) -> str:
    canon = str(canonical or "").strip()
    if not canon:
        return ""
    a, b = title_key(canon), title_key(title)
    if not a or not b or a == b or a in b or b in a:
        return ""
    return canon


def as_list(v):
    if not v:
        return []
    if isinstance(v, (list, tuple)):
        return [str(x) for x in v if x]
    return [x.strip() for x in re.split(r"[|,]", str(v)) if x.strip()]


def build_page(*, url, app_arg, title_tag, og_title, desc, image, wide, og_type,
               body, ld) -> str:
    image_tags = ""
    if image:
        image_tags = (f'\n<meta property="og:image" content="{e(image)}">'
                      f'\n<meta property="og:image:alt" content="{e(og_title)}">')
    # "</" inside JSON-LD would end the script element early.
    ld_json = json.dumps(ld, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    return HEAD.format(
        title_tag=html.escape(title_tag), og_title=e(og_title), desc=e(desc),
        url=e(url), app_arg=e(app_arg), app_id=IOS_APP_ID, og_type=og_type,
        image_tags=image_tags, ld=ld_json,
        # A tall poster inside a wide card is letterboxed by every platform,
        # so a film with only a 2:3 poster gets the SMALL card (Decision 097).
        tw_card="summary_large_image" if wide else "summary") + body + FOOT


def page_body(*, h1, aka, meta, tagline, genres, viewer, source_url, poster,
              synopsis, synopsis_src, facts, cast, reviews, related, episodes=()) -> str:
    out = ['<section class="hero">']
    if poster:
        out.append(f'<img src="{e(poster)}" alt="Poster for {e(h1)}" width="220" '
                   f'height="330" loading="eager" decoding="async">')
    out.append("<div>")
    out.append(f"<h1>{html.escape(h1)}</h1>")
    if aka:
        out.append(f'<p class="aka">Also known as {html.escape(aka)}</p>')
    out.append(f'<p class="m">{html.escape(meta)}</p>')
    if tagline:
        out.append(f'<p class="tg">{html.escape(tagline)}</p>')
    if genres:
        out.append('<ul class="gen">' + "".join(f"<li>{html.escape(g)}</li>" for g in genres) + "</ul>")
    out.append(f'<div class="acts"><a class="b" href="{e(viewer)}">Watch now</a>')
    if source_url:
        out.append(f'<a href="{e(source_url)}" rel="noopener">On the Internet Archive</a>')
    out.append("</div></div></section>")
    if synopsis:
        out.append("<h2>Synopsis</h2>")
        out.append(f"<p>{html.escape(synopsis)}</p>")
        out.append(f'<p class="src">{html.escape(synopsis_src)}</p>')
    if facts:
        out.append("<h2>Details</h2><dl>")
        for k, v in facts:
            out.append(f"<dt>{html.escape(k)}</dt><dd>{html.escape(v)}</dd>")
        out.append("</dl>")
    if cast:
        # The viewer's cast row: director first, TMDb w185 photos, an initial
        # where there is none. Lazy, sized, so a long cast costs nothing above
        # the fold.
        li = []
        for name, role, photo in cast:
            pic = (f'<img src="{e(photo)}" alt="" width="56" height="56" loading="lazy" decoding="async">'
                   if photo else f'<span class="ini" aria-hidden="true">{html.escape(name[:1])}</span>')
            rl = f' <span class="m">{html.escape(role)}</span>' if role else ""
            li.append(f"<li>{pic}<span>{html.escape(name)}{rl}</span></li>")
        out.append('<h2>Cast &amp; crew</h2><ul class="cast">' + "".join(li) + "</ul>")
    if episodes:
        # A series page lists what can be watched; each episode opens in the
        # viewer, and its title is text a search can find.
        li = []
        for season, number, etitle, eyear, eurl in episodes:
            tag = (f"S{season}E{number} · " if season and number else
                   f"Episode {number} · " if number else "")
            yr = f' <span class="m">{eyear}</span>' if eyear else ""
            li.append(f'<li><a href="{e(eurl)}">{html.escape(tag + etitle)}</a>{yr}</li>')
        out.append(f"<h2>Episodes</h2><ul class=\"list\">{''.join(li)}</ul>")
    if reviews:
        out.append("<h2>Reviews on the Internet Archive</h2>")
        for stars, rtitle, rbody, who, when in reviews:
            head = " · ".join(x for x in [
                ("★" * int(stars)) if isinstance(stars, (int, float)) and stars else "",
                html.escape(str(rtitle or "")), html.escape(str(who or "")),
                html.escape(str(when or ""))[:10]] if x)
            out.append(f'<div class="rv"><p class="m">{head}</p>'
                       f"<p>{html.escape(strip_html(str(rbody or '')))}</p></div>")
    if related:
        tiles = []
        for u, t, pic in related:
            art = (f'<img src="{e(pic)}" alt="" width="150" height="225" loading="lazy" decoding="async">'
                   if pic else '<span class="noart" aria-hidden="true"></span>')
            tiles.append(f'<li><a href="{e(u)}">{art}<span>{html.escape(t)}</span></a></li>')
        out.append('<h2>More like this</h2><ul class="rel">' + "".join(tiles) + "</ul>")
    return "\n".join(out) + "\n"


LIST_LANDING = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>A shared playlist — Archive Watch</title>
  <meta property="og:title" content="A shared playlist on Archive Watch">
  <meta property="og:description" content="Someone put together a collection of public-domain films. Free to watch, no account.">
  <meta property="og:image" content="https://archivewatch.org/assets/app-icon/app-icon.png">
  <meta property="og:type" content="website">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="apple-itunes-app" content="app-id=6776697407">
  <script>
    (function () {
      // The playlist is in the FRAGMENT and has never left this browser. Hand
      // it to the viewer's router. A path form is accepted too, so a link
      // written either way opens the same collection.
      var blob = (location.hash || '').replace(/^#\\/?/, '');
      if (!blob) {
        var m = location.pathname.match(/^\\/list\\/(.+?)\\/?$/);
        blob = m ? m[1] : '';
      }
      location.replace(blob ? '/#/list/' + blob : '/');
    })();
  </script>
</head>
<body><p>Opening the playlist… <a href="/">Archive Watch</a></p></body>
</html>
"""


def write_directory(out: Path, entries) -> list:
    """/films/ and /films/<letter>/: every title, A to Z, as plain links.

    The viewer links by hash, which a crawler cannot follow, so without this a
    film page is reachable only from the sitemap and from other film pages. The
    viewer's footer links here, so every film is two links from the home page —
    for people browsing the whole collection as much as for Google. Sorted and
    grouped by the viewer's own title key, so "The General" is under G."""
    groups: dict = {}
    for key, headline, kind, url in entries:
        # title_key keeps a-z0-9 only, so a Greek or Cyrillic title has no
        # letter here; it joins the digits rather than minting a page per script.
        ch = key[:1].upper() if "a" <= key[:1] <= "z" else "0-9"
        groups.setdefault(ch, []).append((key, headline, kind, url))
    letters = sorted(groups, key=lambda c: (c != "0-9", c))
    nav = "".join(f'<li><a href="{SITE}/films/{c.lower()}/">{c}</a> '
                  f'<span class="m">{len(groups[c]):,}</span></li>' for c in letters)

    def page(title, desc, url, body):
        return (HEAD.format(title_tag=html.escape(title), og_title=e(title), desc=e(desc),
                            url=e(url), app_arg=e(f"{SITE}/"), app_id=IOS_APP_ID,
                            og_type="website", image_tags="", tw_card="summary",
                            ld=json.dumps({"@context": "https://schema.org",
                                           "@type": "CollectionPage", "name": title,
                                           "url": url}, separators=(",", ":")))
                + body + FOOT)

    written = []
    total = len(entries)
    d = out / "films"
    d.mkdir(parents=True, exist_ok=True)
    idx_url = f"{SITE}/films/"
    (d / "index.html").write_text(page(
        "Every film on Archive Watch, A to Z",
        f"All {total:,} public-domain films and series on Archive Watch, free to watch.",
        idx_url,
        f"<h1>Every film, A to Z</h1><p class=\"m\">{total:,} titles, all free to watch.</p>"
        f'<ul class="az">{nav}</ul>\n'), encoding="utf-8")
    written.append(idx_url)
    for c in letters:
        rows = sorted(groups[c])
        u = f"{SITE}/films/{c.lower()}/"
        items = "".join(f'<li><a href="{e(url)}">{html.escape(h)}</a> '
                        f'<span class="m">{html.escape(k)}</span></li>' for _, h, k, url in rows)
        (d / c.lower()).mkdir(exist_ok=True)
        (d / c.lower() / "index.html").write_text(page(
            f"Films starting with {c} — Archive Watch",
            f"{len(rows):,} public-domain titles starting with {c}, free to watch on Archive Watch.",
            u,
            f'<h1>Films: {c}</h1><ul class="az">{nav}</ul>'
            f'<ul class="list">{items}</ul>\n'), encoding="utf-8")
        written.append(u)
    return written


def write_sitemaps(out: Path, urls, lastmod: str) -> None:
    """sitemap.xml is an INDEX of files of at most SITEMAP_CHUNK URLs (Google
    takes 50,000; smaller files keep each fetch light). robots.txt names it."""
    pages = [f"{SITE}/"] + urls
    lm = f"<lastmod>{lastmod}</lastmod>" if re.match(r"\d{4}-\d{2}-\d{2}$", lastmod) else ""
    names = []
    for n, k in enumerate(range(0, len(pages), SITEMAP_CHUNK), 1):
        name = f"sitemap-{n}.xml"
        body = "".join(f"<url><loc>{html.escape(u)}</loc>{lm}</url>\n" for u in pages[k:k + SITEMAP_CHUNK])
        (out / name).write_text('<?xml version="1.0" encoding="UTF-8"?>\n'
                                '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
                                + body + "</urlset>\n", encoding="utf-8")
        names.append(name)
    (out / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        + "".join(f"<sitemap><loc>{SITE}/{n}</loc>{lm}</sitemap>\n" for n in names)
        + "</sitemapindex>\n", encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default="_site")
    ap.add_argument("--index", default=str(REPO / "catalog-index.json"))
    ap.add_argument("--details", default=str(REPO / "details"))
    ap.add_argument("--episodes", default=str(REPO / "episodes-index.json"))
    ap.add_argument("--limit", type=int, default=0, help="0 = every item")
    args = ap.parse_args()

    index_path = Path(args.index)
    if not index_path.exists():
        print(f"[share] no {index_path} — nothing to build", file=sys.stderr)
        return 0
    index = json.loads(index_path.read_text(encoding="utf-8"))
    rows = index["items"]
    if args.limit:
        rows = rows[: args.limit]

    details = {}
    dpath = Path(args.details)
    if dpath.exists():
        for sh in dpath.glob("*.json"):
            try:
                details.update(json.loads(sh.read_text(encoding="utf-8")))
            except Exception:  # noqa: BLE001
                continue

    episodes_by_slug: dict = {}
    epath = Path(args.episodes)
    if epath.exists():
        ei = json.loads(epath.read_text(encoding="utf-8"))
        f = {name: n for n, name in enumerate(ei.get("fields") or [])}
        for ep in ei.get("episodes") or []:
            aid_e, slug_e = ep[f["archiveID"]], ep[f["slug"]]
            if not aid_e or not slug_e:
                continue
            episodes_by_slug.setdefault(slug_e, []).append((
                ep[f["season"]], ep[f["episode"]], strip_html(str(ep[f["title"]] or aid_e)),
                ep[f["year"]], f"{SITE}/#/item/{aid_e}"))
        for v in episodes_by_slug.values():
            v.sort(key=lambda t: (t[0] is None, t[0] or 0, t[1] is None, t[1] or 0, t[2]))

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "share.css").write_text(SHARE_CSS, encoding="utf-8")

    names = {}
    for r in index["items"]:
        rid, rt, ry = at(r, I_ID), at(r, I_TITLE), at(r, I_YEAR)
        if rid and rt:
            names[str(rid)] = (strip_html(str(rt)) + (f" ({ry})" if ry else ""),
                               tmdb_at(at(r, I_POSTER), 185))

    def page_url(aid: str):
        if aid.startswith("series:"):
            slug = safe_segment(aid[len("series:"):])
            return (f"{SITE}/series/{slug}/", f"{SITE}/series/{slug}") if slug else (None, None)
        return (f"{SITE}/item/{aid}/", f"{SITE}/item/{aid}") if safe_segment(aid) else (None, None)

    urls = []
    directory = []
    made = skipped = 0
    for r in rows:
        aid = str(at(r, I_ID) or "")
        title = strip_html(str(at(r, I_TITLE) or aid))
        year = at(r, I_YEAR)
        ctype = at(r, I_TYPE)
        kind = KIND.get(ctype, "Film")
        d = details.get(aid)
        x = at(d, D_EXTRAS) or {}
        synopsis = strip_html(at(d, D_SYNOPSIS) or "")
        director = at(d, D_DIRECTOR) or at(r, I_DIRECTOR)
        runtime = at(d, D_RUNTIME)
        backdrop = at(d, D_BACKDROP) or at(r, I_BACKDROP)
        poster = at(r, I_POSTER)
        genres = as_list(at(d, D_GENRES)) or as_list(at(r, I_GENRES))

        url, app_arg = page_url(aid)
        if not url:
            skipped += 1
            continue
        if aid.startswith("series:"):
            slug = aid[len("series:"):]
            path = out / "series" / slug
            viewer, og_type, ld_type = f"{SITE}/#/series/{slug}", "video.tv_show", "TVSeries"
            source_url = None
        else:
            path = out / "item" / aid
            viewer, og_type, ld_type = f"{SITE}/#/item/{aid}", "video.movie", "Movie"
            source_url = f"https://archive.org/details/{aid}"

        mins = int(runtime) // 60 if runtime else 0
        bits = [str(year)] if year else []
        bits.append(kind)
        if mins:
            bits.append(f"{mins} min")
        if director:
            bits.append(f"dir. {director}")
        meta = "  ·  ".join(bits)
        headline = title + (f" ({year})" if year else "")

        desc = clip(synopsis, 180) if synopsis else meta
        if "free" not in desc.lower():
            desc = (desc.rstrip(" .") + ". ") if desc else ""
            desc += "Free to watch on Archive Watch — public domain."

        cast_rows = at(d, D_CAST) or []
        cast = [str(c[0] if isinstance(c, list) else c) for c in cast_rows if c][:40]

        def photo(pp):
            if not pp:
                return None
            return pp if str(pp).startswith("http") else f"https://image.tmdb.org/t/p/w185{pp}"
        people = ([(str(director), "Director", photo(x.get("dp")))] if director else [])
        people += [(str(c[0]), None, photo(c[1] if len(c) > 1 else None)) if isinstance(c, list)
                   else (str(c), None, None) for c in cast_rows if c][:40]
        facts = []
        for label, val in (("Director", director), ("Writer", x.get("w")),
                           ("Composer", x.get("co")), ("Cinematography", x.get("ci")),
                           ("Studio", ", ".join(as_list(x.get("st")))),
                           ("Released", x.get("rd")), ("Original title", x.get("ot")),
                           ("Series", x.get("fr")), ("Awards", x.get("aw")),
                           ("Running time", f"{mins} minutes" if mins else None)):
            if val:
                facts.append((label, strip_html(str(val))))
        comm = at(d, D_COMMUNITY) or {}
        reviews = [rv for rv in (comm.get("rv") or []) if isinstance(rv, list) and len(rv) >= 5]
        related = []
        for rid in (at(d, D_RELATED) or [])[:12]:
            ru, _ = page_url(str(rid))
            if ru and str(rid) in names:
                related.append((ru, *names[str(rid)]))

        ld = {"@context": "https://schema.org", "@type": ld_type, "name": title,
              "url": url, "isAccessibleForFree": True,
              "potentialAction": {"@type": "WatchAction", "target": viewer}}
        if synopsis:
            ld["description"] = clip(synopsis, 500)
        if poster or backdrop:
            ld["image"] = poster or backdrop
        if x.get("rd") or year:
            ld["datePublished"] = str(x.get("rd") or year)
        if mins and ld_type == "Movie":
            ld["duration"] = f"PT{mins}M"
        if genres:
            ld["genre"] = genres
        if director:
            ld["director"] = {"@type": "Person", "name": str(director)}
        if cast:
            ld["actor"] = [{"@type": "Person", "name": c} for c in cast[:15]]
        if x.get("st"):
            ld["productionCompany"] = [{"@type": "Organization", "name": n} for n in as_list(x["st"])]
        if source_url:
            ld["sameAs"] = source_url

        body = page_body(
            h1=headline, aka=also_known_as(title, x.get("ct")), meta=meta,
            tagline=strip_html(x.get("tg") or ""), genres=genres, viewer=viewer,
            source_url=source_url, poster=tmdb_at(poster or backdrop, 342), synopsis=synopsis,
            synopsis_src=SOURCE.get(str(x.get("ss") or "").lower(), UPLOADER),
            facts=facts, cast=people, reviews=reviews, related=related,
            episodes=episodes_by_slug.get(aid[len("series:"):], ()) if aid.startswith("series:") else ())
        path.mkdir(parents=True, exist_ok=True)
        (path / "index.html").write_text(build_page(
            url=url, app_arg=app_arg, title_tag=f"{headline} — free to watch on Archive Watch",
            og_title=headline, desc=desc, image=backdrop or poster, wide=bool(backdrop),
            og_type=og_type, body=body, ld=ld), encoding="utf-8")
        urls.append(url)
        directory.append((title_key(title) or title.lower(), headline, kind, url))
        made += 1

    urls += write_directory(out, directory)
    write_sitemaps(out, urls, str(index.get("updatedAt") or "")[:10])

    # ---- the shared-playlist landing page -----------------------------
    #
    # ONE static page at /list/, and the playlist itself never reaches it: a
    # share link is `/list/#<blob>`, so the list travels in the FRAGMENT, which
    # a browser does not send to any server. This page reads it back out and
    # hands it to the viewer's hash router.
    #
    # Why a real page rather than letting /list/ fall through to 404.html:
    #   * STATUS. GitHub Pages serves 404.html with an HTTP 404, and several
    #     crawlers decline to preview a 404 outright — the whole reason 26,000
    #     per-item share pages exist (see this file's header). A playlist link
    #     is made to be posted to Reddit and to social; it has to preview.
    #   * A PATH. Android intent filters match on the path and cannot see a
    #     fragment at all, so `/#/list/<blob>` can never open the Android app.
    #     `/list/` can. Apple can match either (AASA gained a "#" component in
    #     iOS 13), so the path form is the only one that serves both.
    # Together those give one link that previews, opens the native app once the
    # apps handle the route, and still keeps the playlist off our servers.
    #
    # The preview copy is generic ON PURPOSE — the contents are in a fragment
    # this generator never sees, which is exactly the property being preserved.
    (out / "list").mkdir(parents=True, exist_ok=True)
    (out / "list" / "index.html").write_text(LIST_LANDING, encoding="utf-8")

    note = f"; skipped {skipped} unsafe id(s)" if skipped else ""
    print(f"[share] wrote {made:,} share pages under {out}/item and "
          f"{out}/series{note}; plus the /list/ playlist landing page and "
          f"sitemap.xml ({len(urls) + 1:,} URLs)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
