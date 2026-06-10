#!/usr/bin/env python3
"""
catalog_release.py — fetch/publish the full catalog.json via a GitHub Release
instead of committing it to git (Decision 018).

The full catalog (~95 MB, 30k+ items) is a GENERATED accumulator, not
hand-authored source, so it doesn't belong in git — committing it every
rebuild bloated .git to 600 MB+ and pushed catalog.json toward GitHub's 100 MB
hard limit. We host it as a gzipped asset on a rolling "catalog-source"
Release (off the Pages/repo budget, like the SQLite DB in Decision 017).

Pipeline shape:
  - At the START of a catalog-mutating workflow:  catalog_release.py fetch
      -> downloads catalog.json.gz from the release, gunzips to ./catalog.json
  - tools mutate ./catalog.json on disk exactly as before (no tool changes)
  - At the END of the workflow:                   catalog_release.py publish
      -> gzips ./catalog.json and clobbers the release asset

Bootstrap: `fetch` is a no-op (exit 0, leaves any existing local file) when the
release/asset doesn't exist yet, so the first `publish` can seed it from a
local catalog.json.

Requires the `gh` CLI authenticated (GH_TOKEN in CI).
"""

import argparse
import gzip
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
GZ = REPO / "catalog.json.gz"
TAG = "catalog-source"
ASSET = "catalog.json.gz"
TITLE = "Catalog source (rolling)"


def _gh(*args, check=True, capture=False):
    return subprocess.run(["gh", *args], check=check, cwd=REPO,
                          capture_output=capture, text=True)


def _release_state():
    """'present', 'absent', or an error string. ONLY a definite not-found is
    'absent' — an auth/network/5xx failure must never be mistaken for the
    bootstrap case. During the 2026-06-10 GitHub API auth outage the old
    any-failure-means-absent check made fetch silently skip the download, and
    every downstream step crashed on the missing catalog.json (and a publish
    in that state could have re-seeded the release from a partial catalog)."""
    r = _gh("release", "view", TAG, check=False, capture=True)
    if r.returncode == 0:
        return "present"
    err = f"{r.stderr or ''} {r.stdout or ''}".strip()
    if "release not found" in err.lower() or "HTTP 404" in err:
        return "absent"
    return f"error: {err[:300]}"


def fetch():
    state = _release_state()
    if state == "absent":
        print(f"[catalog] release '{TAG}' not found — leaving local catalog.json as-is (bootstrap)")
        return 0
    if state != "present":
        print(f"[catalog] cannot reach release '{TAG}' — failing rather than "
              f"pretending bootstrap ({state})", file=sys.stderr)
        return 1
    r = _gh("release", "download", TAG, "--pattern", ASSET, "--clobber",
            "--dir", str(REPO), check=False, capture=True)
    if r.returncode != 0 or not GZ.exists():
        # The release exists, so a missing asset is only a bootstrap case if
        # the asset list (fetched successfully) really lacks it.
        a = _gh("release", "view", TAG, "--json", "assets",
                "--jq", ".assets[].name", check=False, capture=True)
        if a.returncode == 0 and ASSET not in (a.stdout or ""):
            print(f"[catalog] asset '{ASSET}' not on release '{TAG}' — bootstrap, leaving local file")
            return 0
        print(f"[catalog] download of '{ASSET}' failed — transient error, not "
              f"bootstrap: {(r.stderr or '').strip()[:300]}", file=sys.stderr)
        return 1
    with gzip.open(GZ, "rb") as fi, open(CATALOG, "wb") as fo:
        shutil.copyfileobj(fi, fo)
    GZ.unlink()
    print(f"[catalog] fetched {CATALOG.name} ({CATALOG.stat().st_size/1e6:.1f} MB) from release '{TAG}'")
    return 0


def publish():
    if not CATALOG.exists():
        print(f"[catalog] no {CATALOG} to publish", file=sys.stderr)
        return 1
    with open(CATALOG, "rb") as fi, gzip.open(GZ, "wb", compresslevel=9) as fo:
        shutil.copyfileobj(fi, fo)
    print(f"[catalog] {CATALOG.stat().st_size/1e6:.1f} MB -> {GZ.stat().st_size/1e6:.1f} MB gzipped")
    state = _release_state()
    if state == "absent":
        _gh("release", "create", TAG, "--title", TITLE, "--notes",
            "Rolling full catalog.json source (Decision 018). Not committed to git.")
    elif state != "present":
        print(f"[catalog] cannot reach release '{TAG}' — refusing to publish "
              f"({state})", file=sys.stderr)
        return 1
    _gh("release", "upload", TAG, str(GZ), "--clobber")
    GZ.unlink()
    print(f"[catalog] published {ASSET} to release '{TAG}'")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("action", choices=["fetch", "publish"])
    args = ap.parse_args()
    return fetch() if args.action == "fetch" else publish()


if __name__ == "__main__":
    sys.exit(main())
