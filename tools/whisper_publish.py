#!/usr/bin/env python3
"""
whisper_publish.py — publish caption deltas from a running whisper/opensubtitles
batch WITHOUT clobbering concurrent CI catalog writers.

The Mac batch mutates the LOCAL catalog.json in place, but CI crons (color-classify
every 8h, nightly enrich, etc.) independently fetch→mutate→publish the same
catalog-source release. A naive `catalog_release.py publish` of the local file would
overwrite whatever those crons added since the run started. So this tool is
ADDITIVE (Decision 020): it downloads the CURRENT release catalog, applies ONLY the
caption fields (captions / subtitleHLS / captionsChecked / whisperGenerated) for
items this pipeline generated, and re-publishes. Caption fields and the crons'
enrichment fields never collide, and either side re-applies on its next pass, so
the small fetch→upload race is self-healing.

Run (any time during/after a batch; safe to repeat):
  python tools/whisper_publish.py            # subs upload + catalog delta + rebuild
  python tools/whisper_publish.py --no-rebuild   # skip deploy-pages/publish-db triggers
"""

from __future__ import annotations

import argparse
import gzip
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LOCAL = REPO / "catalog.json"
SUBS = REPO / "subs"
DONE_MD = REPO / "docs" / "whisper-captions-done.md"   # human accuracy checklist
TAG = "catalog-source"
ASSET = "catalog.json.gz"
SUBS_TAG = "subtitle-assets"

# Only these keys are pushed onto the release catalog (additive, conflict-free).
DELTA_KEYS = ("captions", "subtitleHLS", "captionsChecked", "whisperGenerated")
OUR_SOURCES = {"whisper", "opensubtitles"}


def gh(*args, check=True, capture=False):
    return subprocess.run(["gh", *args], check=check, text=True,
                          capture_output=capture)


def collect_deltas():
    """{archiveID: {delta keys}} for items THIS pipeline captioned."""
    cat = json.load(open(LOCAL))
    items = cat["items"] if isinstance(cat, dict) else cat
    deltas = {}
    for it in items:
        caps = it.get("captions") or []
        if it.get("subtitleHLS") and any(c.get("source") in OUR_SOURCES for c in caps):
            deltas[it["archiveID"]] = {k: it[k] for k in DELTA_KEYS if k in it}
    return deltas


def merge_delta_files(paths):
    """Union {archiveID: caption-fields} across shard delta files (CI matrix)."""
    merged = {}
    for p in paths:
        with open(p) as f:
            merged.update(json.load(f))
    return merged


_DONE_HEADER = (
    "# Whisper auto-caption accuracy checklist\n\n"
    "Films auto-captioned by whisper.cpp (Decision 039 Phase 4). Each whisper run\n"
    "APPENDS new films here — your ticks and notes above are preserved.\n\n"
    "To spot-check one: open **watch** and turn on captions, or read the raw **vtt**.\n"
    "Tick the box once you've confirmed it reads correctly; strike through or note\n"
    "any that are wrong so we can re-run them with a bigger model.\n\n"
)


def update_done_list(items, path=DONE_MD):
    """APPEND-ONLY checklist of whisper-captioned films. New films are added under
    the existing content (dedup by archiveID), so manual ticks/notes survive every
    re-run. Returns the number of newly-appended rows."""
    films = [it for it in items
             if it.get("subtitleHLS")
             and any(c.get("source") == "whisper" for c in (it.get("captions") or []))]
    films.sort(key=lambda it: it.get("popularityScore") or 0, reverse=True)

    body = path.read_text(encoding="utf-8") if path.exists() else _DONE_HEADER
    seen = set(re.findall(r"/item/([^\s)]+)\)", body))   # ids already listed
    rows = []
    for it in films:
        iaid = it["archiveID"]
        if iaid in seen:
            continue
        seen.add(iaid)
        title = (it.get("title") or iaid).replace("\n", " ").strip()
        year = it.get("year") or ""
        ct = it.get("contentType") or ""
        vtt = next((c.get("vttURL") or c.get("url")
                    for c in it["captions"] if c.get("source") == "whisper"), "")
        yr = f" ({year})" if year else ""
        rows.append(f"- [ ] **{title}**{yr} · {ct} · "
                    f"[watch](https://archivewatch.org/item/{iaid}) · [vtt]({vtt})")
    if not rows and path.exists():
        return 0
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body.rstrip("\n") + "\n" + "\n".join(rows) + ("\n" if rows else ""),
                    encoding="utf-8")
    return len(rows)


def fetch_release_catalog():
    """Download + parse the current catalog-source release catalog."""
    with tempfile.TemporaryDirectory() as td:
        gz = Path(td) / ASSET
        gh("release", "download", TAG, "-p", ASSET, "-O", str(gz))
        with gzip.open(gz, "rt", encoding="utf-8") as f:
            cat = json.load(f)
    return cat["items"] if isinstance(cat, dict) else cat


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-rebuild", action="store_true")
    ap.add_argument("--apply-deltas", nargs="+", default=[],
                    help="shard delta JSON files (CI); union them instead of reading local catalog.json")
    ap.add_argument("--done-list-only", action="store_true",
                    help="just (re)generate docs/whisper-captions-done.md from the live release "
                         "catalog (+ local catalog.json if present) and exit; no upload/publish")
    args = ap.parse_args()

    if args.done_list_only:
        items = fetch_release_catalog()
        if LOCAL.exists():                         # include not-yet-published local builds
            loc = json.load(open(LOCAL))
            items = items + (loc["items"] if isinstance(loc, dict) else loc)
        added = update_done_list(items)
        print(f"[pub] done-list: +{added} films -> {DONE_MD.relative_to(REPO)}")
        return 0

    if args.apply_deltas:
        deltas = merge_delta_files(args.apply_deltas)
    elif LOCAL.exists():
        deltas = collect_deltas()
    else:
        print("[pub] no local catalog.json and no --apply-deltas"); return 2
    print(f"[pub] {len(deltas)} caption deltas to apply", flush=True)
    if not deltas:
        return 0

    # 1. Upload the generated subs/ (union into the rolling subtitle-assets release).
    if SUBS.exists() and any(SUBS.iterdir()):
        with tempfile.TemporaryDirectory() as td:
            tar = Path(td) / "subs.tar.gz"
            subprocess.run(["tar", "czf", str(tar), "-C", str(REPO), "subs"], check=True)
            if gh("release", "view", SUBS_TAG, check=False, capture=True).returncode != 0:
                gh("release", "create", SUBS_TAG, "--title", "Subtitle assets (rolling)",
                   "--notes", "VTT + HLS subtitle assets served to Pages at /subs (Decision 039).")
            # Merge with the prior tarball so we never drop earlier subs.
            prior = Path(td) / "prior.tar.gz"
            if gh("release", "download", SUBS_TAG, "-p", "subs.tar.gz", "-O", str(prior),
                  check=False, capture=True).returncode == 0:
                subprocess.run(["tar", "xzf", str(prior), "-C", str(REPO)], check=False)
                subprocess.run(["tar", "czf", str(tar), "-C", str(REPO), "subs"], check=True)
            gh("release", "upload", SUBS_TAG, str(tar), "--clobber")
        print("[pub] subs uploaded", flush=True)

    # 2. Fetch the CURRENT release catalog, apply caption deltas, re-publish.
    with tempfile.TemporaryDirectory() as td:
        gz = Path(td) / ASSET
        gh("release", "download", TAG, "-p", ASSET, "-O", str(gz))
        with gzip.open(gz, "rt", encoding="utf-8") as f:
            cat = json.load(f)
        items = cat["items"] if isinstance(cat, dict) else cat
        applied = 0
        for it in items:
            d = deltas.get(it.get("archiveID"))
            if d:
                it.update(d)
                applied += 1
        # Upload a file named EXACTLY like the asset. The `path#asset` rename form
        # with --clobber SILENTLY NO-OPS (verified 2026-06-22: the asset's
        # size/updatedAt never change, gh returns 0) — so name it correctly and
        # --clobber matches by name.
        out_gz = Path(td) / ASSET
        with gzip.open(out_gz, "wt", encoding="utf-8") as f:
            json.dump(cat, f, ensure_ascii=False, separators=(",", ":"))
        gh("release", "upload", TAG, str(out_gz), "--clobber")
        print(f"[pub] catalog: applied {applied}/{len(deltas)} deltas onto the live release", flush=True)
        # Append newly-captioned films to the human accuracy checklist (append-only).
        added = update_done_list(items)
        print(f"[pub] done-list: +{added} films -> {DONE_MD.relative_to(REPO)}", flush=True)

    # 3. Rebuild the served DB + Pages.
    if not args.no_rebuild:
        gh("workflow", "run", "deploy-pages.yml", check=False)
        gh("workflow", "run", "publish-db.yml", check=False)
        print("[pub] triggered deploy-pages + publish-db", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
