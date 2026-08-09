#!/usr/bin/env python3
"""
content_type.py — the ONE content-type classifier, with no dependencies.

Extracted from ingest_candidates.py so that any pipeline step can reach it.
That module imports `requests`, `omdb_lib` and `archive_lib` at module level,
and several catalog steps (remediate_catalog among them) run in CI as a bare
`python tools/x.py` with no third-party packages installed — so importing the
classifier from there failed silently at exactly the moment it was needed.

Keep this file import-free. Anything that classifies content should import from
HERE rather than re-deriving the rules, because a second copy is how the two
drift and how an item ends up typed one way on ingest and another on remediate.
"""


def classify(collections, subjects, runtime_sec, year):
    """Lightweight content-type classifier. Mirrors the JS builder's
    heuristics closely enough for discovery items; the weekly rebuild can
    refine later."""
    cl = " ".join(collections).lower()
    subj = " ".join(subjects).lower()
    # Commercials/ads are a distinct type (interstitial + collection content,
    # kept off Home — see CatalogDB.notCommercial). Match the dedicated ad
    # collections by name only (not the broad "advertising" subject, which also
    # tags docs ABOUT advertising) so we don't mislabel feature films.
    if any(k in cl for k in ("aw_commercials", "classic_tv_commercials",
                             "vhscommercials", "videogamecommercials")):
        return "commercial"
    if "tv" in cl or "television" in cl or "classic_tv" in cl:
        return "tv-series" if "series" in cl else "tv-special"
    if "animation" in cl or "cartoon" in cl or "animation" in subj:
        return "animation"
    if "newsreel" in cl or "news" in cl:
        return "newsreel"
    if "prelinger" in cl or "ephemeral" in cl or "advertising" in subj:
        return "ephemeral"
    if year and year < 1928:
        return "silent-film"
    if runtime_sec and runtime_sec < 2400:  # < 40 min
        return "short-film"
    if "documentary" in cl or "documentary" in subj:
        return "documentary"
    return "feature-film"
