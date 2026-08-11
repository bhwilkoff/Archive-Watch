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
import json
import shutil
import subprocess
import sys
import time
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


def _transient(err: str) -> bool:
    """A retryable GitHub-API blip (vs a definite 404/auth error). These are common on the
    api.github.com path and cause spurious job failures — e.g. cast-images 2026-06-25:
    'error connecting to api.github.com'."""
    e = err.lower()
    return any(s in e for s in (
        "error connecting", "could not resolve", "connection reset", "connection refused",
        "timeout", "timed out", "i/o timeout", "eof", "tls handshake", "temporary failure",
        "http 500", "http 502", "http 503", "http 504", "server error", "try again"))


def _gh_net(*args):
    """A network gh call (view/upload/create/download) with retry on a transient API blip.
    Raises CalledProcessError after the last attempt (so a REAL failure still fails the job)."""
    last = None
    for attempt in range(5):
        r = _gh(*args, check=False, capture=True)
        if r.returncode == 0:
            return r
        last = r
        err = f"{r.stderr or ''} {r.stdout or ''}"
        # A definite not-found is not transient — return so the caller handles bootstrap.
        if "release not found" in err.lower() or "HTTP 404" in err:
            return r
        if attempt < 4 and _transient(err):
            time.sleep(3 * (attempt + 1))   # 3,6,9,12s
            continue
        break
    return last


def _release_state():
    """'present', 'absent', or an error string. ONLY a definite not-found is
    'absent' — an auth/network/5xx failure must never be mistaken for the
    bootstrap case. During the 2026-06-10 GitHub API auth outage the old
    any-failure-means-absent check made fetch silently skip the download, and
    every downstream step crashed on the missing catalog.json (and a publish
    in that state could have re-seeded the release from a partial catalog).
    Retries transient API blips (_gh_net) before reporting an error."""
    r = _gh_net("release", "view", TAG)
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
    r = _gh_net("release", "download", TAG, "--pattern", ASSET, "--clobber",
                "--dir", str(REPO))
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



# A published catalog only ever grows, slowly. Anything much smaller than what
# is already there is truncation, not curation.
SHRINK_FLOOR = 0.85


def _asset_size() -> int:
    """Bytes of the currently published asset, or 0 if it cannot be read.

    Unknown means unknown: if the size cannot be established this does NOT
    block the upload, because refusing on a network hiccup would strand every
    run behind a check that is meant to catch corruption, not connectivity.
    """
    c = _gh_net("release", "view", TAG, "--json", "assets")
    if c.returncode != 0:
        return 0
    try:
        for a in json.loads(c.stdout).get("assets", []):
            if a.get("name") == ASSET:
                return int(a.get("size") or 0)
    except Exception:
        return 0
    return 0


def publish():
    if not CATALOG.exists():
        print(f"[catalog] no {CATALOG} to publish", file=sys.stderr)
        return 1
    with open(CATALOG, "rb") as fi, gzip.open(GZ, "wb", compresslevel=9) as fo:
        shutil.copyfileobj(fi, fo)
    print(f"[catalog] {CATALOG.stat().st_size/1e6:.1f} MB -> {GZ.stat().st_size/1e6:.1f} MB gzipped")

    # REFUSE A SHRUNKEN CATALOG. The publish steps now run even when a compute
    # step above them was killed (so a timeout stops discarding a whole run's
    # work) — which means this can be reached with a catalog that was being
    # written when the kill landed, and uploading that would clobber the real
    # one. Decision 020's lesson, applied at the last gate rather than only at
    # the merge: a catalog that suddenly halves is a bug, not a result.
    existing = _asset_size()
    if existing and GZ.stat().st_size < existing * SHRINK_FLOOR:
        print(f"[catalog] REFUSING to publish: {GZ.stat().st_size/1e6:.1f} MB is under "
              f"{SHRINK_FLOOR:.0%} of the {existing/1e6:.1f} MB already published. "
              f"A catalog does not shrink like that; something upstream was "
              f"interrupted mid-write.", file=sys.stderr)
        GZ.unlink()
        return 1

    state = _release_state()
    if state == "absent":
        c = _gh_net("release", "create", TAG, "--title", TITLE, "--notes",
                    "Rolling full catalog.json source (Decision 018). Not committed to git.")
        if c.returncode != 0:
            print(f"[catalog] could not create release '{TAG}': {(c.stderr or '').strip()[:300]}",
                  file=sys.stderr)
            return 1
    elif state != "present":
        print(f"[catalog] cannot reach release '{TAG}' — refusing to publish "
              f"({state})", file=sys.stderr)
        return 1
    up = _gh_net("release", "upload", TAG, str(GZ), "--clobber")
    if up.returncode != 0:
        print(f"[catalog] upload of {ASSET} failed after retries: {(up.stderr or '').strip()[:300]}",
              file=sys.stderr)
        return 1
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
