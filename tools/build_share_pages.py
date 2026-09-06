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

WHAT EACH PAGE IS. Open Graph tags built from the catalog, the iOS Smart App
Banner, real visible content for anything that renders it, and a script that
forwards a human into the viewer. Crawlers do not run scripts, so they read
the metadata and stop.

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

KIND = {
    "feature-film": "Feature film", "silent-film": "Silent film",
    "short-film": "Short film", "animation": "Animation",
    "tv-series": "Classic TV series", "tv-special": "Television",
    "tv-episode": "Episode", "newsreel": "Newsreel",
    "documentary": "Documentary", "ephemeral": "Ephemeral film",
    "commercial": "Commercial",
}

SHARE_CSS = """:root{color-scheme:dark}
body{margin:0;background:#0B0B0C;color:#EBEBEB;
font:16px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
display:flex;min-height:100vh;align-items:center;justify-content:center;padding:24px}
.w{max-width:620px;display:flex;gap:24px;flex-wrap:wrap}
.w img{width:200px;border-radius:10px;background:#16161A}
.t{flex:1;min-width:260px}
h1{font-size:1.6rem;margin:0 0 6px}
.m{color:#9A9AA0;font-size:.95rem;margin:0 0 14px}
p{margin:0 0 14px}
a.b{display:inline-block;background:#FF5C35;color:#0B0B0C;font-weight:600;
text-decoration:none;padding:10px 20px;border-radius:999px}
.f{color:#9A9AA0;font-size:.85rem;margin-top:18px}
"""

# X/Twitter falls back to Open Graph for title, description and image, so only
# the card TYPE needs a twitter: tag. Three duplicated strings per page across
# 26,740 pages is the whole reason to care.
PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title_tag}</title>
<meta name="description" content="{desc}">
<link rel="canonical" href="{url}">
<meta name="apple-itunes-app" content="app-id={app_id}, app-argument={url}">
<meta property="og:site_name" content="Archive Watch">
<meta property="og:type" content="{og_type}">
<meta property="og:title" content="{og_title}">
<meta property="og:description" content="{desc}">
<meta property="og:url" content="{url}">{image_tags}
<meta name="twitter:card" content="{tw_card}">
<link rel="stylesheet" href="/share.css">
</head>
<body>
<div class="w">
{poster_img}<div class="t">
<h1>{h1}</h1>
<p class="m">{meta}</p>
<p>{blurb}</p>
<a class="b" href="{viewer}">Watch it free</a>
<p class="f">Free to watch on Archive Watch — public domain, no account.</p>
</div></div>
<script>
/* Humans go straight through to the viewer; crawlers do not run scripts, so
   they read the metadata above and stop. replace() keeps the Back button
   pointing at wherever the link was shared. */
location.replace({viewer_js});
</script>
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


def build_page(url, title_tag, og_title, h1, desc, meta, blurb, image, wide,
               viewer, og_type) -> str:
    image_tags = ""
    poster_img = ""
    if image:
        e = html.escape(image, quote=True)
        image_tags = (f'\n<meta property="og:image" content="{e}">'
                      f'\n<meta property="og:image:alt" content="{html.escape(og_title)}">')
        poster_img = f'<img src="{e}" alt="" width="200">'
    return PAGE.format(
        title_tag=html.escape(title_tag),
        og_title=html.escape(og_title, quote=True),
        h1=html.escape(h1), desc=html.escape(desc, quote=True),
        meta=html.escape(meta), blurb=html.escape(blurb),
        url=html.escape(url, quote=True), app_id=IOS_APP_ID,
        og_type=og_type, image_tags=image_tags, poster_img=poster_img,
        viewer=html.escape(viewer, quote=True), viewer_js=json.dumps(viewer),
        # A tall poster inside a wide card is letterboxed by every platform,
        # so a film with only a 2:3 poster gets the SMALL card, which shows
        # the poster whole. Decision 097's rule, applied to someone else's
        # layout.
        tw_card="summary_large_image" if wide else "summary")


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default="_site")
    ap.add_argument("--index", default=str(REPO / "catalog-index.json"))
    ap.add_argument("--details", default=str(REPO / "details"))
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

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "share.css").write_text(SHARE_CSS, encoding="utf-8")

    made = skipped = 0
    for r in rows:
        aid = str(at(r, I_ID) or "")
        title = strip_html(str(at(r, I_TITLE) or aid))
        year = at(r, I_YEAR)
        kind = KIND.get(at(r, I_TYPE), "Film")
        d = details.get(aid)
        synopsis = strip_html(at(d, D_SYNOPSIS) or "")
        director = at(d, D_DIRECTOR) or at(r, I_DIRECTOR)
        runtime = at(d, D_RUNTIME)
        backdrop = at(d, D_BACKDROP) or at(r, I_BACKDROP)
        poster = at(r, I_POSTER)

        if aid.startswith("series:"):
            slug = safe_segment(aid[len("series:"):])
            if not slug:
                skipped += 1
                continue
            path, url = out / "series" / slug, f"{SITE}/series/{slug}"
            viewer, og_type = f"{SITE}/#/series/{slug}", "video.tv_show"
        else:
            if not safe_segment(aid):
                skipped += 1
                continue
            path, url = out / "item" / aid, f"{SITE}/item/{aid}"
            viewer, og_type = f"{SITE}/#/item/{aid}", "video.movie"

        bits = [str(year)] if year else []
        bits.append(kind)
        if runtime:
            mins = int(runtime) // 60
            if mins:
                bits.append(f"{mins} min")
        if director:
            bits.append(f"dir. {director}")
        meta = "  ·  ".join(bits)

        headline = title + (f" ({year})" if year else "")
        # The description is what a person reads in the preview, so it leads
        # with what the film IS and ends with the one fact that matters here.
        desc = clip(synopsis, 180) if synopsis else meta
        if "free" not in desc.lower():
            desc = (desc.rstrip(" .") + ". ") if desc else ""
            desc += "Free to watch on Archive Watch — public domain."

        path.mkdir(parents=True, exist_ok=True)
        (path / "index.html").write_text(build_page(
            url=url, title_tag=f"{headline} — free to watch on Archive Watch",
            og_title=headline, h1=headline, desc=desc, meta=meta,
            blurb=clip(synopsis, 320) if synopsis else
                  "A public-domain title from the Internet Archive.",
            image=backdrop or poster, wide=bool(backdrop),
            viewer=viewer, og_type=og_type), encoding="utf-8")
        made += 1

    note = f"; skipped {skipped} unsafe id(s)" if skipped else ""
    print(f"[share] wrote {made:,} share pages under {out}/item and "
          f"{out}/series{note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
