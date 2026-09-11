#!/usr/bin/env python3
"""
fit_roku_covers.py — give a film whose poster is the wrong SHAPE a conformant
one, instead of withholding the film from Roku Search.

THE PROBLEM THIS SOLVES (measured 2026-09-11). Roku accepts a main image at
2:3 or 16:9 and nothing else. It does not resize, letterbox or forgive: an
off-aspect main image is REMOVED, and an asset left with no images is
rejected —

    Invalid aspect ratio ASPECT_RATIO_4_3 for main image <url>.
      Image will be removed. Valid aspect ratios are 16x9 or 2x3.
    All images have been removed. An asset must have at least one image.

Our answer had been to drop the asset at build time, which is honest but
expensive: **882 of 3,972 eligible films** — a fifth of everything the feed
is allowed to advertise — were withheld for no reason but the proportions of
a Wikimedia still. They have the rights evidence, a playable file and a real
poster; the poster is simply 4:3, or a panorama, or 500x1106.

And withholding has a second cost that is invisible from the file. Roku's
report counts an asset it is RECONCILING (removing from the channel index
because the feed no longer lists it) as a rejection, carrying forward the
errors from when it was last present. Measured across four ingestions:

    job 3   3,106 assets   passed 3,052   errors 54   <- 98%
    job 4   2,903 assets   passed 2,849   errors 54   <- the SAME 54 ids
    job 5   3,106 assets   passed 3,052   errors 54   reconciled 54
    job 6   3,106 assets   passed 3,052   errors 54   reconciled 54

The id list is byte-identical across a feed that changed size by 203 assets,
and NONE of the 54 is in the feed. They are stuck: reconciled every run,
never cleared, holding the report at 98% while the standalone validator —
which scores the FILE — reads the same URL at 100%. The only way to clear
such a record is to put the id back in the feed with an image that passes.

SO: fit, never crop, never stretch. The original is scaled to fit INSIDE a
400x600 (exact 2:3) canvas and centred; the bars are filled with a blurred,
cover-scaled copy of the same image. That is this project's established
idiom for art whose shape does not match its frame (Decision 097, the Roku
`blurSrc` wash, Android's `washBlur`) and it obeys 097's binding rule — the
artwork itself is never reshaped, so a 4:3 still stays a 4:3 still and a
panorama stays a panorama.

Output goes into the SAME tarball the generated covers use
(tools/publish_roku_covers.py, the `roku-covers` release), which
deploy-pages.yml restores to _site/roku-search/covers — the one host Roku's
fetcher can actually read (archive.org refuses it). The map this writes,
ops/roku-fitted-covers.json, is what build_roku_search_feed.py consults.

Run (owner's Mac — a residential IP; CI runners are refused by several of
these hosts):
    python tools/catalog_release.py fetch
    python tools/fit_roku_covers.py                 # build into build/roku-covers
    python tools/publish_roku_covers.py             # pack + upload the tarball
"""

from __future__ import annotations

import argparse
import concurrent.futures as cf
import hashlib
import io
import json
import sys
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
import build_roku_search_feed as F  # noqa: E402

OUT_DIR = REPO / "build" / "roku-covers"
MAP = REPO / "ops" / "roku-fitted-covers.json"
W, H, QUALITY = 400, 600, 84


def fitted_name(url: str) -> str:
    """Keyed on the SOURCE url, so two films sharing a poster share one file."""
    return "fit-" + hashlib.sha1(url.encode("utf-8")).hexdigest()[:16] + ".jpg"


def render(data: bytes) -> bytes | None:
    """Fit onto an exact 2:3 canvas over a blurred cover of itself."""
    from PIL import Image, ImageFilter
    try:
        im = Image.open(io.BytesIO(data))
        im.load()
        im = im.convert("RGB")
    except Exception:  # noqa: BLE001
        return None
    if im.width < 80 or im.height < 80:
        return None                      # a favicon-sized "poster" is not one

    # the wash: cover the canvas, then blur it past recognition
    s = max(W / im.width, H / im.height)
    wash = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))),
                     Image.LANCZOS)
    left, top = (wash.width - W) // 2, (wash.height - H) // 2
    canvas = wash.crop((left, top, left + W, top + H)).filter(
        ImageFilter.GaussianBlur(18))

    # the artwork: fit whole, never cropped, never stretched
    s = min(W / im.width, H / im.height)
    art = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))),
                    Image.LANCZOS)
    canvas.paste(art, ((W - art.width) // 2, (H - art.height) // 2))

    buf = io.BytesIO()
    canvas.save(buf, "JPEG", quality=QUALITY, optimize=True, progressive=True)
    return buf.getvalue()


def fetch(url: str) -> bytes | None:
    req = urllib.request.Request(url, headers={"User-Agent": F.USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            return r.read()
    except Exception:  # noqa: BLE001
        return None


def one(url: str) -> tuple:
    """(url, name|None, status)"""
    name = fitted_name(url)
    dst = OUT_DIR / name
    if dst.exists():
        return url, name, "cached"
    data = fetch(url)
    if data is None:
        return url, None, "unfetchable"
    out = render(data)
    if out is None:
        return url, None, "undecodable"
    dst.write_bytes(out)
    return url, name, "built"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tier", choices=("catalog", "strict", "guaranteed"), default="guaranteed")
    ap.add_argument("--art", choices=("any", "professional"), default="professional")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    catalog = json.loads((REPO / "catalog.json").read_text(encoding="utf-8"))["items"]
    index_ids = {r[0] for r in json.loads(
        (REPO / "catalog-index.json").read_text(encoding="utf-8"))["items"]}
    dims = json.loads((REPO / "ops" / "image-dims.json").read_text(encoding="utf-8"))

    eligible = [it for it in catalog
                if F.eligibility(it, index_ids, args.tier, args.art) is None]

    # Resolve exactly as the feed build does — the dims cache and Roku both
    # see the RESOLVED url, and keying on the raw one is the bug that shipped
    # unmeasured Wikimedia stills into the 97% feed.
    resolver = F.ImageResolver(network=True, covers_dir=None)
    raw = [F.image_url(it.get("posterURL")) or "" for it in eligible]
    resolver.prefetch_commons([u for u in raw if u])

    want: set = set()
    for it in eligible:
        main = resolver.resolve(F.image_url(it.get("posterURL")))
        bg = resolver.resolve(F.image_url(it.get("backdropURL"), "background"))
        if F.image_verdict(main, dims) == "ok":
            continue
        if bg and F.image_verdict(bg, dims) == "ok":
            continue                      # a 16:9 backdrop already rescues it
        if main and main.startswith("http"):
            want.add(main)

    urls = sorted(want)
    if args.limit:
        urls = urls[:args.limit]
    print(f"[fit] eligible={len(eligible)}  off-aspect or unmeasured mains={len(urls)}")
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    mapping = json.loads(MAP.read_text()) if MAP.exists() else {}
    counts = {"built": 0, "cached": 0, "unfetchable": 0, "undecodable": 0}
    with cf.ThreadPoolExecutor(max_workers=args.workers) as ex:
        for i, (url, name, st) in enumerate(ex.map(one, urls), 1):
            counts[st] += 1
            if name:
                mapping[url] = name
            if i % 100 == 0:
                print(f"[fit] {i}/{len(urls)} {counts}", flush=True)
    print(f"[fit] {counts}")

    # A url that could not be fetched is left OUT of the map rather than
    # recorded as a failure: the next run retries it, and the feed simply
    # withholds that film meanwhile (Decision 088's rule for transient reads).
    MAP.parent.mkdir(parents=True, exist_ok=True)
    MAP.write_text(json.dumps(mapping, indent=0, sort_keys=True) + "\n")
    print(f"[fit] {MAP.relative_to(REPO)}: {len(mapping)} urls -> fitted covers")
    return 0


if __name__ == "__main__":
    sys.exit(main())
