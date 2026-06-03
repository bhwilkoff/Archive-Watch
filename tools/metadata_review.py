#!/usr/bin/env python3
"""
metadata_review.py — Tier 3 of the metadata-quality program
(docs/architecture/metadata-audit.md), run as an AGENT-LOOP iteration in Claude
Code (the agent IS the LLM — no per-row API cost). Two phases:

  select  -> writes the next batch of items needing semantic review to
             metadata_review_batch.json (popularity-ordered, not-yet-reviewed).
             The agent reads it, judges each synopsis, and WRITES its decisions
             to metadata_review_decisions.json.
  apply   -> reads the decisions, updates the catalog (synopsis +
             synopsisSource="agent-reviewed" + a reviewedHash so repeat runs skip
             unchanged items), and reports.

Review tracking lives ON the item (`agentReviewHash`), not a side file, so it
rides the catalog on the release. After one full pass, `select` only returns
NEWLY-sourced / changed titles — the sustainable steady state.

The agent's allowed actions per item (NEVER hallucinate):
  keep     — synopsis is already a real, faithful plot description.
  rewrite  — replace with a clean 1-3 sentence plot the agent can write
             FAITHFULLY (the plot was buried in junk, or it's a film the agent
             genuinely knows). Provide `synopsis`.
  null     — the text is an uploader note / wrong film / unsalvageable; remove it
             so Tier-2 enrichment refills a real one.

Usage:
  python tools/metadata_review.py select --limit 100
  python tools/metadata_review.py apply
"""

import argparse
import hashlib
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
BATCH = REPO / "metadata_review_batch.json"
DECISIONS = REPO / "metadata_review_decisions.json"


def _syn(it):
    v = it.get("synopsis")
    return (" ".join(v) if isinstance(v, list) else (v or "")).strip()


def _hash(it):
    """Identity of what the agent reviewed: the synopsis text (or '∅' when none).
    If Tier-2 later changes the synopsis, the hash changes and it's re-reviewed."""
    return hashlib.sha1((_syn(it) or "∅").encode("utf-8")).hexdigest()[:12]


def _reviewed(it):
    return it.get("agentReviewHash") == _hash(it)


def select(limit):
    cat = json.loads(CATALOG.read_text(encoding="utf-8"))
    items = [it for it in cat["items"] if it.get("contentType") != "tv-series"]
    # Popularity-first: perfect what users actually see, drain the tail over runs.
    items.sort(key=lambda it: it.get("popularityScore") or 0, reverse=True)
    batch = []
    for it in items:
        if _reviewed(it):
            continue
        batch.append({
            "archiveID": it.get("archiveID"),
            "title": it.get("title"),
            "year": it.get("year"),
            "director": it.get("director"),
            "contentType": it.get("contentType"),
            "collections": (it.get("collections") or [])[:3],
            "synopsis": _syn(it) or None,
        })
        if len(batch) >= limit:
            break
    BATCH.write_text(json.dumps(batch, ensure_ascii=False, indent=2), encoding="utf-8")
    remaining = sum(1 for it in items if not _reviewed(it))
    print(f"[review] wrote {len(batch)} items to {BATCH.name} "
          f"({remaining:,} of {len(items):,} still unreviewed)")
    print("[review] agent: read it, write decisions to "
          f"{DECISIONS.name} as [{{archiveID, action: keep|rewrite|null, "
          "synopsis?}}], then run `apply`.")
    return 0


def apply():
    if not DECISIONS.exists():
        print(f"[review] no {DECISIONS.name} — nothing to apply", file=sys.stderr)
        return 1
    decisions = {d["archiveID"]: d for d in json.loads(DECISIONS.read_text(encoding="utf-8"))}
    cat = json.loads(CATALOG.read_text(encoding="utf-8"))
    by_id = {it.get("archiveID"): it for it in cat["items"]}
    stats = {"keep": 0, "rewrite": 0, "null": 0, "skipped": 0}
    for aid, d in decisions.items():
        it = by_id.get(aid)
        if it is None:
            stats["skipped"] += 1
            continue
        # Optional title correction (any action) — the agent can also fix a junk
        # title, e.g. "The Ten Commandments / Blu-ray / MKV" -> "The Ten Commandments".
        if (d.get("title") or "").strip():
            it["title"] = d["title"].strip()
            stats["title_fixed"] = stats.get("title_fixed", 0) + 1

        action = d.get("action")
        if action == "rewrite" and (d.get("synopsis") or "").strip():
            it["synopsis"] = d["synopsis"].strip()
            it["synopsisSource"] = "agent-reviewed"
        elif action == "null":
            it["synopsis"] = None
            it["synopsisSource"] = None
        elif action != "keep":
            stats["skipped"] += 1
            continue
        it["agentReviewHash"] = _hash(it)   # mark reviewed at the post-action text
        stats[action] = stats.get(action, 0) + 1
    CATALOG.write_text(json.dumps(cat, ensure_ascii=False), encoding="utf-8")
    print(f"[review] applied: {stats}; wrote {CATALOG.name}")
    DECISIONS.unlink(); BATCH.unlink(missing_ok=True)
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("select"); s.add_argument("--limit", type=int, default=100)
    sub.add_parser("apply")
    args = ap.parse_args()
    return select(args.limit) if args.cmd == "select" else apply()


if __name__ == "__main__":
    sys.exit(main())
