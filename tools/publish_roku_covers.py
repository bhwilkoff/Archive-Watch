#!/usr/bin/env python3
"""
publish_roku_covers.py — host the generated frame covers on archivewatch.org
for the Roku Search feed, because archive.org will not serve them to Roku.

WHY. Roku's Search feed validator downloads every image itself. The covers
this catalog generates for poster-less films (Decision 023) live as files of
the archive.org item `archivewatch-covers`, and archive.org refuses that
download to datacenter fetchers — every one of the ~6,100 cover URLs came
back IMAGE_DOWNLOAD_ERROR on 2026-09-10 even once resolved to the storage
node, while TMDb, Amazon and Wikimedia images passed in the same run. The
same refusal is why the CI runners cannot fetch audio for the word index
(Decision 089) and why the covers were generated on this Mac in the first
place. So the covers Roku needs are published where Roku can read them:
GitHub Pages, at /roku-search/covers/<file>.

HOW. The files come from the local generation cache (tools/covers_out/
posters, the batch_covers output) and, for any the cache lacks, from
archive.org over this residential connection. Each is resized to 400x600 —
a 2:3 poster Roku accepts, a third of the bytes — and the set is packed
into ONE tarball on the rolling `roku-covers` GitHub Release, exactly the
shape the subtitle assets use. deploy-pages.yml restores it into the Pages
artifact, and build_roku_search_feed.py points a cover at archivewatch.org
whenever the file is there, at the archive.org node otherwise.

Only covers the FEED would publish are packed (~6,100, not all 20,000),
because every byte lands in every Pages deploy.

Run (owner's Mac, needs `gh` and the catalog):
  python tools/catalog_release.py fetch
  python tools/publish_roku_covers.py            # build + upload
  python tools/publish_roku_covers.py --no-upload
"""

from __future__ import annotations

import argparse
import concurrent.futures as cf
import io
import json
import subprocess
import sys
import tarfile
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
import build_roku_search_feed as F  # noqa: E402

CACHE = REPO / "tools" / "covers_out" / "posters"
OUT_DIR = REPO / "build" / "roku-covers"
TARBALL = REPO / "build" / "roku-covers.tar.gz"
TAG = "roku-covers"
ASSET = "roku-covers.tar.gz"
WIDTH, HEIGHT, QUALITY = 400, 600, 82


def needed_covers(tier: str) -> list:
    catalog = json.loads((REPO / "catalog.json").read_text(encoding="utf-8"))
    index_ids = {r[0] for r in json.loads((REPO / "catalog-index.json").read_text(encoding="utf-8"))["items"]}
    names = []
    for it in catalog.get("items", []):
        if F.eligibility(it, index_ids, tier):
            continue
        u = F.image_url(it.get("posterURL")) or ""
        if u.startswith(F.COVERS_URL):
            names.append(u[len(F.COVERS_URL):])
    return sorted(set(names))


def fetch(name: str) -> bytes | None:
    req = urllib.request.Request(F.COVERS_URL + name, headers={"User-Agent": F.USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.read()
    except Exception:  # noqa: BLE001
        return None


def convert(name: str) -> str:
    """'ok' | 'fetched' | 'missing' | 'bad'"""
    from PIL import Image
    dst = OUT_DIR / name
    if dst.exists():
        return "ok"
    src = CACHE / name
    data, how = None, "ok"
    if src.exists():
        data = src.read_bytes()
    else:
        data = fetch(name)
        how = "fetched"
        if data is None:
            return "missing"
        CACHE.mkdir(parents=True, exist_ok=True)
        src.write_bytes(data)          # the cache is the durable copy
    try:
        im = Image.open(io.BytesIO(data)).convert("RGB")
        if im.size != (WIDTH, HEIGHT):
            im = im.resize((WIDTH, HEIGHT), Image.LANCZOS)
        im.save(dst, "JPEG", quality=QUALITY, optimize=True, progressive=True)
        return how
    except Exception:  # noqa: BLE001
        return "bad"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tier", choices=("catalog", "strict", "guaranteed"), default="catalog")
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--no-upload", action="store_true")
    args = ap.parse_args()

    names = needed_covers(args.tier)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    counts = {"ok": 0, "fetched": 0, "missing": 0, "bad": 0}
    with cf.ThreadPoolExecutor(max_workers=args.workers) as ex:
        for i, res in enumerate(ex.map(convert, names), 1):
            counts[res] += 1
            if i % 1000 == 0:
                print(f"[covers] {i}/{len(names)} {counts}", flush=True)
    print(f"[covers] {len(names)} needed → {counts}")

    with tarfile.open(TARBALL, "w:gz", compresslevel=6) as tf:
        for p in sorted(OUT_DIR.glob("*.jpg")):
            tf.add(p, arcname=p.name)
    size = TARBALL.stat().st_size / 1e6
    n = len(list(OUT_DIR.glob("*.jpg")))
    print(f"[covers] {TARBALL.name}: {n} files, {size:.1f} MB")
    if n < 1000:
        print("[covers] refusing to upload a tarball this small", file=sys.stderr)
        return 1
    if args.no_upload:
        return 0
    view = subprocess.run(["gh", "release", "view", TAG], capture_output=True, text=True)
    if view.returncode != 0:
        subprocess.run(["gh", "release", "create", TAG, "--title", "Roku search-feed covers (rolling)",
                        "--notes", "Frame covers resized for the Roku Search feed; rebuilt by tools/publish_roku_covers.py."],
                       check=True)
    # --clobber deletes before it uploads (Decision 089); this asset is
    # rebuildable from the local cache, and the deploy falls back to the
    # archive.org URLs while it is absent, so the window is survivable.
    subprocess.run(["gh", "release", "upload", TAG, str(TARBALL), "--clobber"], check=True)
    print(f"[covers] uploaded {ASSET} to release {TAG}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
