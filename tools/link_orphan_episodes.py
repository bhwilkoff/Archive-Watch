#!/usr/bin/env python3
"""Attach an orphan episode/special to the spine it belongs to.

The owner opened a TV show from Home on iPhone and got a movie: the Classic TV
shelves are full of items like `Beverly_Hillbillies_Ep43_Chickadee_Returns`
typed `tv-special`, so there is no series behind them to open. Beverly
Hillbillies HAS a spine; two of its episodes were simply never attached to it.
Catalog-wide: 1,459 orphan tv-specials against 4,693 episodes correctly inside
spines, and 291 series cards that appear on no shelf at all.

The requirement is the owner's, verbatim: an episode (or special) should be
visible within the full spine of episodes and navigable, no matter where in the
app you reach it. So this LINKS rather than hides — Decision 035's
`dedupe_orphan_episodes` deals with orphans that DUPLICATE a mapped episode;
this one deals with orphans that are simply missing from their series.

It reuses D035's matchers deliberately: the contiguous-phrase series match and
the SxE parser already carry the guards paid for in false positives there ("The
Lone Star Ranger" film vs "The Lone Ranger", "Man with a Movie Camera" vs "Man
with a Camera"). Precision over recall, as ever — a wrongly attached episode
puts a stranger's film inside somebody's series.

Two kinds of attachment, both of which the owner asked for:
  * an orphan with a parsed (S,E) whose slot is EMPTY in exactly one matching
    spine becomes that episode;
  * an orphan with no (S,E) that matches exactly one spine becomes a SPECIAL of
    that series — it still belongs, it just has no numbered slot.
A slot already FILLED by a different archiveID is a duplicate, not a gap; that
is D035's job and is left alone.
"""
from __future__ import annotations
import argparse, json, re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dedupe_orphan_episodes import (            # the guards, already paid for
    extract_series_names, series_matches, parse_se, load_spines, norm, _NOT_SINGLE,
)

ORPHAN_TYPES = ("tv-special",)

# A RANGE is a bundle, not an episode: "The Kojak-Chronicles S01e16-18" carries
# three episodes and would otherwise claim slot 16 alone, burying two. D035's
# _NOT_SINGLE catches promos and compilations but not ranges, because hiding a
# bundle needs no slot while ATTACHING one does.
_RANGE = re.compile(r"s\d{1,2}\s*e\s*\d{1,2}\s*[-–]\s*\d{1,2}"
                    r"|e(?:p|pisodes?)?\s*\d{1,3}\s*[-–]\s*\d{1,3}", re.I)
# "Ep01" / "Episode 3" with no season — extremely common in these uploads, and
# without it a real numbered episode falls through to SPECIAL and loses its slot.
_BARE_EP = re.compile(r"\bep(?:isode)?\s*[._-]?\s*(\d{1,3})\b", re.I)


def _is_linkable(it) -> bool:
    if it.get("contentType") not in ORPHAN_TYPES:
        return False
    if it.get("seriesID") or it.get("excluded"):
        return False
    blob = f"{it.get('title') or ''} {it.get('archiveID') or ''}"
    if _RANGE.search(blob):
        return False                              # a multi-episode bundle owns no single slot
    return not _NOT_SINGLE.search(blob.lower())   # promos/compilations are not episodes


def match_spine(it, spines):
    """The single spine this orphan belongs to, or None when ambiguous."""
    cands = extract_series_names(it)
    if not cands:
        return None
    hits = [sp for sp in spines if series_matches(cands, sp["name"])]
    return hits[0] if len(hits) == 1 else None


def plan(items, spines):
    """(episode_links, special_links, skipped_duplicate) — pure, no mutation."""
    eps, specials, dup = [], [], 0
    for it in items:
        if not _is_linkable(it):
            continue
        sp = match_spine(it, spines)
        if not sp:
            continue
        blob = f"{it.get('title') or ''} {it.get('archiveID') or ''}"
        se = parse_se(blob)
        if not se:
            # A bare "Ep01" is an episode number with an implied season 1. Only
            # trusted when the spine actually HAS that slot free in season 1 —
            # otherwise it stays a special rather than inventing a position.
            m = _BARE_EP.search(blob)
            if m:
                cand = (1, int(m.group(1)))
                # Only when that slot is genuinely FREE. A filled slot means the
                # spine already has that episode, so this is a duplicate rather
                # than a gap — it stays a special instead of contesting it.
                if cand not in sp["slots"]:
                    se = cand
        if se:
            held = sp["slots"].get(se)
            if held and held != it.get("archiveID"):
                dup += 1                       # D035's territory, not ours
                continue
            eps.append((it, sp, se))
        else:
            specials.append((it, sp))
    return eps, specials, dup


def apply_links(eps, specials):
    for it, sp, (s, n) in eps:
        it["seriesID"] = sp["slug"]
        it["seasonNumber"], it["episodeNumber"] = s, n
        it["seriesTitle"] = sp["raw"]
        it["contentType"] = "tv-episode"
        it["linkedToSpine"] = "episode"
    for it, sp in specials:
        it["seriesID"] = sp["slug"]
        it["seriesTitle"] = sp["raw"]
        it["linkedToSpine"] = "special"        # stays tv-special: it has no slot


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", default="catalog.json")
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    cat = json.loads(Path(a.catalog).read_text(encoding="utf-8"))
    items = cat["items"] if isinstance(cat, dict) else cat
    spines = load_spines()          # each carries its own slug (file stem)

    eps, specials, dup = plan(items, spines)
    for it, sp, se in eps[:12]:
        print(f"  EPISODE  S{se[0]:02d}E{se[1]:02d}  {(it.get('title') or '')[:34]:36} -> {sp['raw']}")
    for it, sp in specials[:8]:
        print(f"  SPECIAL            {(it.get('title') or '')[:34]:36} -> {sp['raw']}")
    print(f"\n{len(eps)} orphan episodes and {len(specials)} specials belong to an existing "
          f"spine; {dup} skipped as duplicates of an already-mapped episode (Decision 035).")

    if a.apply:
        apply_links(eps, specials)
        Path(a.catalog).write_text(json.dumps(cat, ensure_ascii=False), encoding="utf-8")
        print(f"[link] wrote {a.catalog}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
