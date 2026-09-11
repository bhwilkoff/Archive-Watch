#!/usr/bin/env python3
"""
build_vetting_page.py — a public, NUMBERED account of how titles are vetted.

WHY THIS EXISTS. On the r/classicfilms thread announcing the app
(2026-09-11) a reader asked the sharpest question anyone has asked about it:

    "Do you do anything to vet the films, or does it just play whatever
     archive.org has labeled/tagged as a film? I ask because we've seen a lot
     of very similar apps (mostly web-based) posted here, and when you start
     digging into the films you find a lot of them are mislabeled, low
     quality, just trailers, etc. Without a human actually vetting the
     library, it's hard for me to get excited about another vibe coded custom
     interface."

That is a fair prior, and the honest answer is long: the pipeline audits
rights, verifies external matches against the Archive item's OWN signals,
probes that every file actually decodes, and hides what it cannot evidence.
None of that was written anywhere a skeptic could read it. A claim about
curation with no numbers behind it is exactly what the question is about.

WHY IT IS GENERATED, NOT WRITTEN. Hand-typed counts rot, and a stale number
presented as current is worse than no number (Decision 108). Every figure on
this page is computed from the SAME catalog.json the apps are built from, at
deploy time, into the Pages artifact — never committed (Decision 018).

Run:  python3 tools/build_vetting_page.py --out _site
"""

from __future__ import annotations

import argparse
import collections
import datetime
import html
import json
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent

# Rights buckets that HIDE a title, in the order a reader should meet them:
# biggest and most obvious first. The text is the human reading of the bucket,
# written to be checkable rather than reassuring.
HIDE_LABELS = {
    "modern_copyright_confirmed":
        "Modern films with no licence behind them — confirmed against the "
        "Archive item's own rights statement, not guessed from the year.",
    "commercial_modern_risk":
        "Advertising from 1995 onward, where a brand's copyright is live.",
    "commercial_slop":
        "Compilation and bulk-upload reels with no identifiable work in them.",
    "renewal_zone_commercial":
        "1964-77 films with a large enough commercial footprint that a "
        "renewal is likely — a studio picture wearing an uploader's licence.",
    "wrongmatch_idyear":
        "Modern uploads wearing an old film's year because an external match "
        "was wrong. A 2022 documentary matched to a 1919 short is not a 1919 "
        "short.",
    "renewed_copyright_classic":
        "Pre-1964 films whose copyright was demonstrably renewed.",
    "copyrighted_trailer":
        "Trailers, which are separately copyrighted and are not the film.",
    "modern_noyear_risk":
        "Modern-looking uploads carrying no year at all, so age cannot clear "
        "them.",
    "unplayable_format":
        "Files in a container no supported player can open.",
}

# Markers written by the PLAYABILITY verifiers rather than the rights audit.
PLAY_LABELS = [
    ("playbackDead", "the video file is gone from archive.org since ingest"),
    ("strictFail", "the file is truncated or has no moov atom — it cannot decode"),
    ("codecUnsupported", "AV1 or VP9, which no Apple device decodes"),
    ("needsReSource", "a copy that needs re-sourcing before it can be offered"),
]


def measure(catalog: pathlib.Path) -> dict:
    items = json.loads(catalog.read_text(encoding="utf-8"))["items"]
    visible = [i for i in items if not i.get("excluded")]
    hidden = [i for i in items if i.get("excluded")]

    buckets = collections.Counter(i.get("rightsAudit") or "other" for i in hidden)
    play = {k: sum(1 for i in hidden if i.get(k)) for k, _ in PLAY_LABELS}
    adult = sum(1 for i in hidden if i.get("isAdult"))
    trailers = sum(1 for i in items if i.get("contentType") == "trailer"
                   or i.get("rightsAudit") == "copyrighted_trailer")

    return {
        "total": len(items),
        "visible": len(visible),
        "hidden": len(hidden),
        "buckets": buckets,
        "play": play,
        "adult": adult,
        "trailers": trailers,
        "playback_verified": sum(1 for i in items if i.get("playbackVerified")),
        "match_verified": sum(1 for i in items if i.get("matchVerified")),
        "poster_checked": sum(1 for i in items if i.get("posterChecked")),
        "real_art": sum(1 for i in visible if i.get("hasRealArtwork")),
        "pre1930": sum(1 for i in visible if i.get("rightsEvidence") == "pre_1930"),
        "licensed": sum(1 for i in visible if i.get("rightsEvidence") == "source_licensed"),
    }


def row(n: int, text: str) -> str:
    return (f'<tr><td class="n">{n:,}</td><td>{html.escape(text)}</td></tr>')


def render(m: dict) -> str:
    hide_rows = "".join(
        row(m["buckets"][k], v) for k, v in HIDE_LABELS.items() if m["buckets"].get(k)
    )
    play_rows = "".join(
        row(m["play"][k], v) for k, v in PLAY_LABELS if m["play"].get(k)
    )
    today = datetime.date.today().isoformat()
    pct = 100.0 * m["hidden"] / max(m["total"], 1)
    return f"""<!DOCTYPE html>
<html lang="en" data-theme="dark">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>How titles are vetted — Archive Watch</title>
  <meta name="theme-color" content="#0A0A0A">
  <meta name="description" content="What Archive Watch checks before a film is
    shown, what it hides and why — with the current numbers from the live catalog.">
  <link rel="stylesheet" href="css/styles.css">
  <link rel="stylesheet" href="css/legal.css">
</head>
<body class="legal-page">

  <header class="legal-topbar">
    <span class="brand-mark" aria-hidden="true"></span>
    <h1>Archive Watch</h1>
    <a href="index.html">Home</a>
  </header>

  <main class="legal-main">
    <h2>How titles are vetted</h2>
    <p class="updated">Measured from the live catalog on {today}.</p>

    <p>
      A fair thing to assume about an app built on the Internet Archive is that
      it shows whatever the Archive has tagged as a film — and that a lot of
      that is mislabeled, unplayable, or a trailer standing in for a feature.
      That is true of the raw material. This page is the account of what is
      done about it, with the current numbers, so the claim can be checked
      rather than taken on trust.
    </p>

    <p>
      The catalog holds <strong>{m['total']:,}</strong> records.
      <strong>{m['visible']:,}</strong> are shown.
      <strong>{m['hidden']:,}</strong> — {pct:.0f}% — are hidden, and every one
      of them is hidden for a stated, reversible reason.
    </p>

    <h3>What is hidden on rights</h3>
    <p>
      Public domain is treated as something to be evidenced, not assumed. Age
      alone clears a film only before 1930. Everything later needs a real
      licence, a government origin, or a rights statement on the Archive item
      itself. An uploader ticking "public domain" is a claim, not evidence, and
      does not clear anything on its own.
    </p>
    <table class="facts"><tbody>{hide_rows}</tbody></table>

    <h3>What is hidden because it does not play</h3>
    <p>
      Every file is probed, not trusted. A title that cannot decode is removed
      rather than left to fail in front of a viewer.
    </p>
    <table class="facts"><tbody>{play_rows}</tbody></table>

    <h3>What is checked on the titles that remain</h3>
    <table class="facts"><tbody>
      {row(m['playback_verified'], "titles whose video file has been fetched and verified to decode")}
      {row(m['match_verified'], "titles whose external match was checked against the Archive item's own identifiers, date and colour — so a 1950s game show cannot wear a 2012 anime's poster")}
      {row(m['poster_checked'], "artwork URLs checked for liveness, on a repeating schedule rather than once")}
      {row(m['pre1930'], "films clear on age alone (published before 1930)")}
      {row(m['licensed'], "films clear on a real licence recorded by the Archive item")}
      {row(m['trailers'], "trailers identified and removed as data, so a trailer is never served as the feature")}
      {row(m['adult'], "adult titles hidden; mature content is off by default on every platform")}
    </tbody></table>

    <h3>What is still wrong</h3>
    <p>
      A vetting page that only lists successes is marketing. These are the
      known gaps, and they are worked in the open:
    </p>
    <ul>
      <li>
        <strong>Television has never been through the rights audit.</strong>
        Episodes live outside the film catalog and were gathered by a path
        that applied no rights test. Several hundred shows from 1978 onward
        are almost certainly still copyrighted.
      </li>
      <li>
        <strong>The 1964-77 band is judged by footprint, not by record.</strong>
        US copyright of that era depended on renewal, and renewal records are
        not machine-readable at this scale. Films with a large commercial
        footprint are hidden; smaller ones are shown. Some of those will be
        wrong in both directions.
      </li>
      <li>
        <strong>Wrong external matches keep surfacing.</strong> They are found
        and cleared continuously — a batch of about a hundred was found and
        hidden on 11 September 2026 alone — which means more remain.
      </li>
    </ul>

    <h3>If you find something wrong</h3>
    <p>
      Report it and it gets fixed. Suggestions and corrections go through
      <a href="curate/">the curation tool</a>, and anything hidden here is
      hidden behind a flag that can be reversed — nothing is deleted.
    </p>
  </main>
</body>
</html>
"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="_site")
    ap.add_argument("--catalog", default=str(REPO / "catalog.json"))
    a = ap.parse_args()
    cat = pathlib.Path(a.catalog)
    if not cat.exists():
        print(f"no catalog at {cat} — refusing to publish a page with no numbers",
              file=sys.stderr)
        return 1
    m = measure(cat)
    if m["total"] < 10_000:
        print(f"catalog holds only {m['total']} items — refusing to publish "
              f"numbers this small", file=sys.stderr)
        return 1
    out = pathlib.Path(a.out) / "vetting"
    out.mkdir(parents=True, exist_ok=True)
    (out / "index.html").write_text(render(m), encoding="utf-8")
    print(f"vetting page: {m['visible']:,} shown / {m['hidden']:,} hidden "
          f"of {m['total']:,}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
