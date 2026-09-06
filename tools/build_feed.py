#!/usr/bin/env python3
"""
build_feed.py — the daily programme as an Atom feed and a JSON Feed.

WHY A FEED AT ALL. Every other channel this project posts to belongs to
somebody else, and each one can change its terms, its reach or its price. A
feed at archivewatch.org is the one channel nobody can deprecate, and it is
the one other software can consume: newsreaders, Fediverse relay bots, and
anything that republishes. It is a syndication channel rather than a
discovery channel, and it is priced accordingly — about a hundred lines.

THE SOURCE IS THE LEDGER, and only the ledger. social/posted.json records
what the programme actually featured, one row per platform, and it is
append-only and committed (docs/SOCIAL-PROGRAM.md §7). That matters more here
than it looks:

  * A feed entry must never change after a reader has seen it. Re-deriving
    the programme from the date-seeded selector would NOT be stable — the
    selector consults the ledger to avoid repeats, so yesterday's answer
    moves as the ledger grows. The ledger is the only record that is fixed.
  * One film posted to five platforms is ONE entry, not five.

CONSEQUENCE, stated plainly: until the first account is connected the ledger
is empty and so is the feed. That is an empty programme, not a broken feed —
it fills on the first live post and needs no further work.

Run:
  python tools/build_feed.py --out _site
"""

from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SITE = "https://archivewatch.org"
FEED_TITLE = "Archive Watch — the daily programme"
FEED_SUB = ("One public-domain film a day: what it is, why it is free, and "
            "where to watch it. Free, ad-free, no account.")
MAX_ENTRIES = 60

I_ID, I_TITLE, I_YEAR, I_TYPE, I_POSTER = 0, 1, 2, 3, 4
D_SYNOPSIS, D_DIRECTOR, D_RUNTIME = 1, 2, 5


def at(row, i):
    return row[i] if row is not None and len(row) > i else None


def esc(s: str) -> str:
    return html.escape(s or "", quote=True)


def share_url(archive_id: str) -> str:
    if archive_id.startswith("series:"):
        return f"{SITE}/series/{archive_id[len('series:'):]}"
    return f"{SITE}/item/{archive_id}"


def parse_stamp(value: str):
    """The ledger stamps UTC ISO strings. Returns None when it cannot be read.

    An unreadable date is a DROP, not a guess. Substituting "now" was the
    first version and it is worse than useless: the row sorts to the top of
    the feed (a non-numeric string sorts above every date), takes the newest
    slot in every reader, and stays there — and a reader that has already
    fetched an entry never re-reads it, so there is no fixing it afterwards.
    A film we cannot place in time is a film we cannot syndicate."""
    try:
        d = dt.datetime.fromisoformat((value or "").replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None
    if d.tzinfo is None:
        d = d.replace(tzinfo=dt.timezone.utc)
    return d.astimezone(dt.timezone.utc)


def rfc3339(value: str) -> str:
    d = parse_stamp(value) or dt.datetime.now(dt.timezone.utc)
    return d.isoformat(timespec="seconds").replace("+00:00", "Z")


def collapse(posts: list) -> list:
    """One film per entry. The ledger holds a row per PLATFORM, so a film that
    went to five places would otherwise appear five times in a row — which is
    exactly what a reader unsubscribes over."""
    seen = {}
    for p in posts:
        aid = p.get("id")
        if not aid or parse_stamp(p.get("at", "")) is None:
            continue
        key = (p.get("at", "")[:10], aid)
        row = seen.setdefault(key, {**p, "platforms": []})
        if p.get("platform") and p.get("url"):
            row["platforms"].append((p["platform"], p["url"]))
        # Keep the EARLIEST stamp for the day so the published date is when
        # the programme ran, not when the slowest platform finished.
        if p.get("at", "") < row.get("at", "~"):
            row["at"] = p["at"]
    return sorted(seen.values(), key=lambda r: r.get("at", ""), reverse=True)


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default="_site")
    ap.add_argument("--ledger", default=str(REPO / "social" / "posted.json"))
    ap.add_argument("--index", default=str(REPO / "catalog-index.json"))
    ap.add_argument("--details", default=str(REPO / "details"))
    args = ap.parse_args()

    ledger = Path(args.ledger)
    posts = []
    if ledger.exists():
        try:
            posts = json.loads(ledger.read_text(encoding="utf-8")).get("posts", [])
        except Exception as e:  # noqa: BLE001
            print(f"[feed] unreadable ledger: {e}", file=sys.stderr)
    entries = collapse(posts)[:MAX_ENTRIES]

    catalog, details = {}, {}
    ipath = Path(args.index)
    if ipath.exists():
        for r in json.loads(ipath.read_text(encoding="utf-8"))["items"]:
            catalog[str(at(r, I_ID))] = r
    dpath = Path(args.details)
    if dpath.exists():
        for sh in dpath.glob("*.json"):
            try:
                details.update(json.loads(sh.read_text(encoding="utf-8")))
            except Exception:  # noqa: BLE001
                continue

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    updated = (entries[0]["at"] if entries
               else dt.datetime.now(dt.timezone.utc).isoformat())

    atom = ['<?xml version="1.0" encoding="utf-8"?>',
            '<feed xmlns="http://www.w3.org/2005/Atom">',
            f"<title>{esc(FEED_TITLE)}</title>",
            f"<subtitle>{esc(FEED_SUB)}</subtitle>",
            f'<link rel="alternate" type="text/html" href="{SITE}/"/>',
            f'<link rel="self" type="application/atom+xml" href="{SITE}/feed.xml"/>',
            f"<id>{SITE}/</id>",
            f"<updated>{rfc3339(updated)}</updated>",
            "<author><name>Archive Watch</name></author>",
            f"<icon>{SITE}/assets/app-icon/app-icon.png</icon>"]
    jsonfeed = {"version": "https://jsonfeed.org/version/1.1",
                "title": FEED_TITLE, "description": FEED_SUB,
                "home_page_url": f"{SITE}/", "feed_url": f"{SITE}/feed.json",
                "items": []}

    for e in entries:
        aid = e["id"]
        row = catalog.get(aid)
        det = details.get(aid)
        title = e.get("title") or (at(row, I_TITLE) or aid)
        year = at(row, I_YEAR)
        headline = f"{title} ({year})" if year else str(title)
        link = share_url(aid)
        poster = at(row, I_POSTER)
        synopsis = at(det, D_SYNOPSIS) or ""
        director = at(det, D_DIRECTOR) or ""
        runtime = at(det, D_RUNTIME)

        facts = []
        if year:
            facts.append(str(year))
        if runtime and int(runtime) // 60:
            facts.append(f"{int(runtime)//60} min")
        if director:
            facts.append(f"dir. {director}")

        body = []
        if poster:
            body.append(f'<p><img src="{esc(poster)}" alt="{esc(headline)}" '
                        f'width="240"></p>')
        if facts:
            body.append(f"<p>{esc(' · '.join(facts))}</p>")
        if synopsis:
            body.append(f"<p>{esc(synopsis)}</p>")
        body.append(f'<p><a href="{esc(link)}">Watch it free on Archive '
                    f'Watch</a> — public domain, no account.</p>')
        # Where it was also posted, so a reader can follow the account they
        # prefer rather than only the feed.
        if e.get("platforms"):
            links = ", ".join(f'<a href="{esc(u)}">{esc(p)}</a>'
                              for p, u in sorted(set(e["platforms"])))
            body.append(f"<p>Also posted on {links}.</p>")
        content = "\n".join(body)

        stamp = rfc3339(e.get("at", ""))
        atom += [
            "<entry>",
            f"<title>{esc(headline)}</title>",
            f'<link rel="alternate" type="text/html" href="{esc(link)}"/>',
            # The id must be stable and unique forever. The share URL alone
            # is not: a film could legitimately be featured again in a later
            # year, and two entries sharing an id collapse in every reader.
            f"<id>tag:archivewatch.org,{stamp[:10]}:{esc(aid)}</id>",
            f"<updated>{stamp}</updated>",
            f"<published>{stamp}</published>",
            f'<content type="html">{esc(content)}</content>',
            "</entry>"]
        item = {"id": f"tag:archivewatch.org,{stamp[:10]}:{aid}",
                "url": link, "title": headline, "content_html": content,
                "date_published": stamp}
        if poster:
            item["image"] = poster
        jsonfeed["items"].append(item)

    atom.append("</feed>")
    (out / "feed.xml").write_text("\n".join(atom) + "\n", encoding="utf-8")
    (out / "feed.json").write_text(
        json.dumps(jsonfeed, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")

    if not entries:
        print("[feed] the ledger is empty, so the feed has no entries yet — "
              "it fills on the first live post (docs/SOCIAL-SETUP.md)")
    print(f"[feed] {len(entries)} entr{'y' if len(entries)==1 else 'ies'} "
          f"-> {out}/feed.xml and {out}/feed.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
