#!/usr/bin/env python3
"""
social_select.py — choose the day's film and assemble its post copy.

Implements docs/SOCIAL-PROGRAM.md §1 and §3. The output is a POST SPEC: a JSON
document naming one film, the fragments of copy that describe it, and — for
every fragment — the catalog field it came from. Nothing here writes prose.
It selects sourced fragments and joins them; `--explain` prints the provenance
of each one, which is the §8 ship gate.

Reads the PUBLIC data plane (catalog-index.json + details/<shard>.json), not
the 134 MB catalog:
  * the same rows the apps see, so a film we promote is a film the app shows;
  * the workflow stays a two-minute job on a free runner.

Determinism: the pick is seeded by (slot, date), so re-running a day picks the
SAME film. A retry after a half-failed publish must not post a different movie
to the platform that already has one.

Run:
  python tools/social_select.py --slot now-showing            # today
  python tools/social_select.py --slot auto --explain         # what fires today
  python tools/social_select.py --slot on-this-day --date 2026-12-25
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import random
import re
import sys
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SOCIAL = REPO / "social"
LEDGER = SOCIAL / "posted.json"
PROGRAM = SOCIAL / "program.json"
SITE = "https://archivewatch.org"
UA = "ArchiveWatch-Social/1.0 (+https://archivewatch.org)"

# catalog-index.json row layout (tools/build_catalog_index.py `fields`).
I_ID, I_TITLE, I_YEAR, I_TYPE, I_POSTER, I_PRO = 0, 1, 2, 3, 4, 5
I_SEARCH, I_BACKDROP, I_PLAYABLE, I_DOC = 6, 7, 8, 9
I_RATING, I_VOTES, I_DIRECTOR, I_GENRES, I_COLOR = 10, 11, 12, 13, 14

# details shard record layout (tools/build_web_details.py).
D_URL, D_SYNOPSIS, D_DIRECTOR, D_CAST, D_GENRES = 0, 1, 2, 3, 4
D_RUNTIME, D_BACKDROP, D_CAPTIONS, D_COMMUNITY, D_EXTRAS = 5, 6, 7, 8, 9

KIND = {
    "feature-film": "Feature film", "silent-film": "Silent film",
    "short-film": "Short film", "animation": "Animation",
    "tv-series": "Classic TV", "tv-special": "Television",
    "tv-episode": "Episode", "newsreel": "Newsreel",
    "documentary": "Documentary", "ephemeral": "Ephemeral film",
    "commercial": "Commercial",
}


def http_json(url: str, timeout: int = 60):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def shard_of(archive_id: str) -> str:
    """FNV-1a 32, low byte — build_web_details.py's rule (and watch.js's)."""
    h = 2166136261
    for ch in archive_id.encode("utf-8"):
        h = ((h ^ ch) * 16777619) & 0xFFFFFFFF
    return f"{h & 0xFF:02x}"


def load_program() -> dict:
    if PROGRAM.exists():
        return json.loads(PROGRAM.read_text(encoding="utf-8"))
    return {}


def load_ledger() -> list:
    if LEDGER.exists():
        try:
            return json.loads(LEDGER.read_text(encoding="utf-8")).get("posts", [])
        except Exception:  # noqa: BLE001 — a corrupt ledger must not stop a post
            return []
    return []


def recently_posted(ledger: list, days: int = 365) -> set:
    """Film ids posted within `days`. §7 — no film repeats inside a year."""
    cutoff = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=days)).isoformat()
    return {p["id"] for p in ledger if p.get("at", "") >= cutoff and p.get("id")}


def quoted_reviews(ledger: list) -> set:
    """Every review already used, by (film, reviewer). §7 — never quote twice."""
    return {(p.get("id"), p.get("reviewer")) for p in ledger if p.get("reviewer")}


# --------------------------------------------------------------------------
# Copy fragments. Each returns (text, source) — the source is the catalog field
# the words came from, printed by --explain and checked by the ship gate.
# --------------------------------------------------------------------------

def strip_html(s: str) -> str:
    s = re.sub(r"<br\s*/?>", " ", s or "")
    s = re.sub(r"<[^>]+>", "", s)
    s = (s.replace("&amp;", "&").replace("&quot;", '"').replace("&#39;", "'")
          .replace("&nbsp;", " ").replace("&lt;", "<").replace("&gt;", ">"))
    return re.sub(r"\s+", " ", s).strip()


def sentence_cap(text: str, limit: int) -> str:
    """Trim to whole sentences under `limit`. A synopsis cut mid-clause reads
    like a broken feed; cut at a full stop or do not cut at all."""
    text = strip_html(text)
    if len(text) <= limit:
        return text
    cut = text[:limit]
    for end in (". ", "! ", "? "):
        i = cut.rfind(end)
        if i > limit * 0.45:
            return cut[: i + 1].strip()
    i = cut.rfind(" ")
    return (cut[:i] if i > 0 else cut).strip() + "…"


def meta_line(row: list, detail: list) -> tuple[str, str]:
    """Year · Kind · runtime · director — every part measured."""
    bits, src = [], []
    if row[I_YEAR]:
        bits.append(str(row[I_YEAR])); src.append("index.year")
    kind = KIND.get(row[I_TYPE], "")
    if kind:
        bits.append(kind); src.append("index.contentType")
    runtime = detail[D_RUNTIME] if len(detail) > D_RUNTIME else None
    if runtime:
        mins = int(runtime) // 60
        if mins:
            bits.append(f"{mins} min"); src.append("shard.runtimeSeconds")
    director = (detail[D_DIRECTOR] if len(detail) > D_DIRECTOR else None) or row[I_DIRECTOR]
    if director:
        bits.append(f"dir. {director}"); src.append("shard.director")
    return "  ·  ".join(bits), " + ".join(src)


def rating_line(row: list) -> tuple[str, str] | None:
    """Only past the same 1,000-vote floor the apps use (Decision 050): a 9.8
    from six people is noise, and quoting it would be the first unsourced
    superlative in the programme."""
    if len(row) > I_VOTES and row[I_RATING] and row[I_VOTES] and int(row[I_VOTES]) >= 1000:
        return f"{row[I_RATING] / 10:.1f} on IMDb from {int(row[I_VOTES]):,} voters", "index.rating10+votes"
    return None


def pick_review(detail: list, film_id: str, used: set) -> dict | None:
    """A real viewer's review, verbatim. Prefers a 4–5 star one with a body
    long enough to say something and short enough to quote whole."""
    community = detail[D_COMMUNITY] if len(detail) > D_COMMUNITY else None
    if not community or not community.get("rv"):
        return None
    best = None
    for rv in community["rv"]:
        stars = rv[0] if len(rv) > 0 else None
        title = strip_html(rv[1] or "") if len(rv) > 1 else ""
        body = strip_html(rv[2] or "") if len(rv) > 2 else ""
        who = (rv[3] or "").strip() if len(rv) > 3 else ""
        if not body or not who:
            continue
        if (film_id, who) in used:
            continue
        try:
            n = int(stars) if stars not in (None, "None", "") else 0
        except (TypeError, ValueError):
            n = 0
        if n and n < 4:
            continue
        if not (60 <= len(body) <= 400):
            continue
        cand = {"stars": n, "title": title, "body": body, "reviewer": who,
                "date": (rv[4] if len(rv) > 4 else None)}
        # A quote reads as a typo when it opens on a lowercase letter, even
        # though it is verbatim ("a tad too dark at times…" — horseoftroy on
        # The Magic Sword). Prefer one that starts like a sentence; the rule
        # picks a DIFFERENT review, it never edits one.
        cand["_rank"] = (1 if body[:1].isupper() else 0, len(body))
        if best is None or cand["_rank"] > best["_rank"]:
            best = cand
    if best:
        best.pop("_rank", None)
    return best


# --------------------------------------------------------------------------
# Selection
# --------------------------------------------------------------------------

# --------------------------------------------------------------------------
# The rights gate. STRICTER than the app's, deliberately.
#
# Listing a film in a catalogue and PROMOTING it on Facebook are different
# acts: the second is an affirmative public claim that this film is free to
# watch. So the programme posts only films whose public-domain basis can be
# STATED IN A SENTENCE, and it puts that sentence in the post — which is also
# the most genuinely educational thing on the card (§2, deepens understanding).
#
# The bases, in the order they are checked, all drawn from the pipeline's own
# vocabulary (audit_rights.py / remediate_catalog._GOV_PD_COLLECTIONS):
#   * a US government production — PD on creation, whatever its year;
#   * a Creative Commons dedication the uploader actually made;
#   * published before 1930 — US copyright expired by age (PD_BY_AGE);
#   * 1930-1963 — the rights audit confirmed it (Decision 027), the band
#     where non-renewal put most of this catalog in the public domain.
# Everything else — the 1964-77 renewal zone and anything modern without a
# government or CC basis — is NOT posted. Those are exactly the items
# Decision 027 left visible-but-unverifiable, and an unverifiable film is one
# we must not stand behind in public.
PD_BY_AGE = 1930
GOV_COLLECTIONS = {"prelinger", "prelingerhomemovies", "nasa", "nasaeclips",
                   "jsc-pao-video-collection", "usgovfilms", "nationalarchives",
                   "fedflix", "dl-archive"}


def pd_basis(row: list, detail: list) -> tuple[str, str] | None:
    """A statable public-domain basis, or None — and None means not posted."""
    year = row[I_YEAR]
    blob = (row[I_SEARCH] or "").lower() if len(row) > I_SEARCH and row[I_SEARCH] else ""
    if any(c in blob for c in GOV_COLLECTIONS):
        return ("A United States government production, and therefore in the "
                "public domain."), "index.search (gov collection)"
    if year and year < PD_BY_AGE:
        return (f"Published in {year}. Its US copyright has expired.",
                "index.year < 1930 (audit_rights.PD_BY_AGE)")
    if year and PD_BY_AGE <= year < 1964:
        return (f"Published in {year}, in the public domain in the United States.",
                "index.year 1930-1963 + rights audit (Decision 027)")
    return None


def eligible(row: list) -> bool:
    """The app's own gates. A film we promote must be one the app will show:
    professional artwork (Decision 097), playable, a real poster, and never a
    series spine (a spine has no film to watch)."""
    if str(row[I_ID]).startswith("series:"):
        return False
    if row[I_PRO] != 1:
        return False
    if not row[I_POSTER]:
        return False
    if len(row) > I_PLAYABLE and row[I_PLAYABLE] == 0:
        return False
    return True


def popularity(row: list) -> int:
    return int(row[I_VOTES] or 0) if len(row) > I_VOTES and row[I_VOTES] else 0


def candidates(index: dict, slot: str) -> list:
    rows = [r for r in index["items"] if eligible(r)]
    if slot == "from-the-vaults":
        keep = {"ephemeral", "newsreel", "documentary", "commercial", "short-film"}
        return [r for r in rows if r[I_TYPE] in keep]
    if slot in ("now-showing", "viewer-said", "double-bill"):
        # The backbone slots lead with films a reader might actually recognise
        # or be glad to discover: a real audience has rated them.
        return [r for r in rows if popularity(r) >= 500]
    return rows


def seeded_order(rows: list, slot: str, date: str) -> list:
    """Deterministic per (slot, date): a retry picks the same film."""
    seed = int(hashlib.sha256(f"{slot}|{date}".encode()).hexdigest()[:12], 16)
    rnd = random.Random(seed)
    out = list(rows)
    rnd.shuffle(out)
    return out


def on_this_day(rows: list, when: dt.date, shards: dict) -> list:
    """Films whose RELEASE DATE is today's month and day. Fires only on a real
    dated match — an anniversary we cannot source is not posted."""
    hits = []
    want = f"-{when.month:02d}-{when.day:02d}"
    for r in rows:
        d = shards.get(r[I_ID])
        if not d:
            continue
        extras = d[D_EXTRAS] if len(d) > D_EXTRAS else None
        rd = (extras or {}).get("rd") if isinstance(extras, dict) else None
        if rd and str(rd).endswith(want) and r[I_YEAR]:
            hits.append(r)
    return hits


def fetch_details(ids: list, verbose: bool = False) -> dict:
    """Fetch only the shards the shortlist needs (256 exist; a shortlist of 40
    touches ~30 of them)."""
    want = {}
    for i in ids:
        want.setdefault(shard_of(i), []).append(i)
    out = {}
    for sh, members in want.items():
        try:
            data = http_json(f"{SITE}/details/{sh}.json")
        except Exception as e:  # noqa: BLE001
            if verbose:
                print(f"  shard {sh}: {e}", file=sys.stderr)
            continue
        for i in members:
            if i in data:
                out[i] = data[i]
    return out


def build_spec(row: list, detail: list, slot: str, review: dict | None,
               partner: tuple | None = None) -> dict:
    """Assemble the post spec: fragments plus, for each, its source."""
    film_id = row[I_ID]
    title = row[I_TITLE]
    synopsis = strip_html(detail[D_SYNOPSIS] or "") if len(detail) > D_SYNOPSIS and detail[D_SYNOPSIS] else ""
    extras = detail[D_EXTRAS] if len(detail) > D_EXTRAS and isinstance(detail[D_EXTRAS], dict) else {}
    meta, meta_src = meta_line(row, detail)
    frags = []

    def add(kind, text, source):
        if text:
            frags.append({"kind": kind, "text": text, "source": source})

    add("meta", meta, meta_src)
    if extras.get("tg"):
        add("tagline", strip_html(extras["tg"]), "shard.extras.tagline (the film's own)")
    if review:
        add("review", f'"{sentence_cap(review["body"], 240)}"',
            f"shard.community.reviews — archive.org viewer {review['reviewer']}")
        add("review_credit", f"— {review['reviewer']}, archive.org", "shard.community.reviews.reviewer")
    if synopsis:
        add("synopsis", sentence_cap(synopsis, 320 if not review else 180), "shard.synopsis")
    r = rating_line(row)
    if r:
        add("rating", r[0], r[1])
    basis = pd_basis(row, detail)
    if basis:
        add("rights", basis[0], basis[1])

    spec = {
        "slot": slot,
        "id": film_id,
        "title": title,
        "year": row[I_YEAR],
        "kind": KIND.get(row[I_TYPE], row[I_TYPE]),
        "contentType": row[I_TYPE],
        "poster": row[I_POSTER],
        "backdrop": row[I_BACKDROP] if len(row) > I_BACKDROP else None,
        "link": f"{SITE}/item/{film_id}",
        "fragments": frags,
        "reviewer": review["reviewer"] if review else None,
        "genres": [g for g in (row[I_GENRES] or "").split("|") if g and g[:1].isupper()][:2],
    }
    if partner:
        prow, pdetail, why = partner
        spec["partner"] = {
            "id": prow[I_ID], "title": prow[I_TITLE], "year": prow[I_YEAR],
            "poster": prow[I_POSTER], "link": f"{SITE}/item/{prow[I_ID]}",
            "why": why,
        }
    return spec


def slot_for_date(when: dt.date, program: dict) -> str:
    """The programme's calendar (§3). One slot per day; the dated slots win."""
    if when.month == 1 and when.day == 1:
        return "public-domain-day"
    weekly = (program.get("weekly") or {})
    dow = when.strftime("%A").lower()
    if weekly.get(dow):
        return weekly[dow]
    # Default week: two review days, a double bill, a vaults day, rest Now Showing.
    default = {"tuesday": "viewer-said", "friday": "viewer-said",
               "wednesday": "double-bill", "sunday": "from-the-vaults"}
    return default.get(dow, "now-showing")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--slot", default="auto",
                    help="now-showing | viewer-said | on-this-day | double-bill | "
                         "from-the-vaults | public-domain-day | auto")
    ap.add_argument("--date", default=None, help="YYYY-MM-DD (default: today)")
    ap.add_argument("--out", default=None, help="write the post spec here")
    ap.add_argument("--explain", action="store_true",
                    help="print every fragment with the field it came from")
    ap.add_argument("--index", default=f"{SITE}/catalog-index.json")
    args = ap.parse_args()

    when = dt.date.fromisoformat(args.date) if args.date else dt.date.today()
    program = load_program()
    slot = args.slot if args.slot != "auto" else slot_for_date(when, program)

    index = (json.loads(Path(args.index).read_text(encoding="utf-8"))
             if not args.index.startswith("http") else http_json(args.index))
    ledger = load_ledger()
    skip = recently_posted(ledger)
    used_reviews = quoted_reviews(ledger)

    rows = [r for r in candidates(index, slot) if r[I_ID] not in skip]
    if not rows:
        print("no eligible film — nothing posted today", file=sys.stderr)
        return 3

    order = seeded_order(rows, slot, when.isoformat())

    # "On this day" needs release dates, which live in the shards: take a wide
    # shortlist, then narrow. Every other slot needs only its own shortlist.
    shortlist = order[: 400 if slot == "on-this-day" else 60]
    details = fetch_details([r[I_ID] for r in shortlist], verbose=args.explain)

    if slot == "on-this-day":
        hits = on_this_day(shortlist, when, details)
        if not hits:
            print("no dated anniversary today — falling back to now-showing", file=sys.stderr)
            slot = "now-showing"
        else:
            shortlist = hits

    pick = None
    partner = None
    for row in shortlist:
        d = details.get(row[I_ID])
        if not d:
            continue
        synopsis = d[D_SYNOPSIS] if len(d) > D_SYNOPSIS else None
        url = d[D_URL] if len(d) > D_URL else None
        if not url:                      # not playable right now — never promote it
            continue
        if not pd_basis(row, d):
            continue          # cannot state why it is free — do not promote it
        review = pick_review(d, row[I_ID], used_reviews)
        if slot == "viewer-said" and not review:
            continue
        if slot != "viewer-said" and not synopsis:
            continue
        pick = (row, d, review)
        break

    if not pick:
        print(f"no candidate satisfied slot '{slot}'", file=sys.stderr)
        return 3

    row, detail, review = pick

    if slot == "double-bill":
        # A pairing must be MEASURED, never asserted: same director, or the
        # same year. "These two go well together" is exactly the unsourced
        # claim §1 forbids.
        director = (detail[D_DIRECTOR] if len(detail) > D_DIRECTOR else None) or row[I_DIRECTOR]
        for other in shortlist:
            if other[I_ID] == row[I_ID]:
                continue
            od = details.get(other[I_ID])
            if not od or not (od[D_URL] if len(od) > D_URL else None):
                continue
            if not pd_basis(other, od):
                continue
            odir = (od[D_DIRECTOR] if len(od) > D_DIRECTOR else None) or other[I_DIRECTOR]
            if director and odir and director == odir:
                partner = (other, od, f"both directed by {director}")
                break
            if row[I_YEAR] and other[I_YEAR] == row[I_YEAR]:
                partner = (other, od, f"both released in {row[I_YEAR]}")
                break
        if not partner:
            slot = "now-showing"

    spec = build_spec(row, detail, slot, review, partner)
    spec["date"] = when.isoformat()

    if args.explain:
        print(f"slot: {slot}   date: {when}")
        print(f"film: {spec['title']} ({spec['year']})  [{spec['id']}]")
        print(f"link: {spec['link']}")
        print(f"poster: {spec['poster']}")
        print("\nfragments — every one traced to its source:")
        for f in spec["fragments"]:
            print(f"  [{f['kind']:14s}] {f['text'][:96]}")
            print(f"  {'':16s}  ← {f['source']}")
        if spec.get("partner"):
            print(f"\npartner: {spec['partner']['title']} ({spec['partner']['why']})")

    out = Path(args.out) if args.out else None
    if out:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(spec, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"[select] wrote {out}")
    elif not args.explain:
        print(json.dumps(spec, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
