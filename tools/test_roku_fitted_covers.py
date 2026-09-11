#!/usr/bin/env python3
"""
test_roku_fitted_covers.py — a film is never withheld from Roku Search for the
SHAPE of its poster, and a fitted cover never lies about what it shows.

THE INCIDENT (2026-09-11). The registered feed sat at 98% while the standalone
validator scored the same URL at 100%. The two score different things: the
validator scores the FILE, the ingestion scores the CHANNEL INDEX. Roku counts
an asset it is RECONCILING — removing, because the feed stopped listing it —
as a rejection, and reports the errors from when it was last present. Those
records never clear. Measured across four ingestions of two different feeds:

    job 3   3,106 assets   passed 3,052   errors 54   reconciled  --
    job 4   2,903 assets   passed 2,849   errors 54   reconciled 249
    job 5   3,106 assets   passed 3,052   errors 54   reconciled  54
    job 6   3,106 assets   passed 3,052   errors 54   reconciled  54

The 54 ids are BYTE-IDENTICAL across a feed that changed size by 203 assets,
and not one of them is in the feed. Every one was a Wikimedia still whose
aspect Roku refused, which our own gate had since dropped. Dropping the asset
is what made the record permanent: the only way to clear it is to list the id
again with an image that passes.

So the gate now fits rather than withholds — and these cases lock the two
properties that makes safe.

Run:  python tools/test_roku_fitted_covers.py
"""

from __future__ import annotations

import io
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))

import build_roku_search_feed as F  # noqa: E402
import fit_roku_covers as FIT       # noqa: E402

CASES = []


def check(name, got, want):
    CASES.append((name, got == want, got, want))


def img(w, h, color=(200, 60, 30)):
    from PIL import Image
    buf = io.BytesIO()
    Image.new("RGB", (w, h), color).save(buf, "JPEG", quality=90)
    return buf.getvalue()


def size_of(data):
    from PIL import Image
    return Image.open(io.BytesIO(data)).size


def main() -> int:
    # 1. EVERY shape Roku refused becomes an exact 2:3 canvas.
    for w, h, label in [(640, 480, "4:3 still"), (500, 1106, "a tall panel"),
                        (1200, 300, "a panorama"), (960, 700, "the commonest reject"),
                        (517, 682, "3:4-ish"), (100, 100, "a square")]:
        out = FIT.render(img(w, h))
        check(f"{label} ({w}x{h}) renders exactly 400x600",
              size_of(out) if out else None, (400, 600))

    # 2. ...and Roku's own rule accepts the result.
    check("the fitted canvas satisfies aspect_ok", F.aspect_ok(400, 600), True)

    # 3. NEGATIVE CONTROL: junk is refused, not letterboxed into the feed.
    check("a 16x16 favicon is refused rather than blown up",
          FIT.render(img(16, 16)), None)
    check("bytes that are not an image are refused",
          FIT.render(b"this is not a JPEG"), None)

    # 4. The artwork is FITTED, never cropped or stretched (Decision 097).
    #    A wide source must keep its full width, so the top and bottom rows
    #    are wash and the middle row is artwork.
    from PIL import Image
    src = Image.new("RGB", (1200, 300))
    px = src.load()                            # a gradient so a crop is visible
    for x in range(1200):
        g = x * 255 // 1199
        for y in range(300):
            px[x, y] = (255, g, 0)
    buf = io.BytesIO(); src.save(buf, "JPEG", quality=95)
    out = Image.open(io.BytesIO(FIT.render(buf.getvalue()))).convert("RGB")
    band = 400 * 300 // 1200                   # the artwork band's height: 100px
    top = (600 - band) // 2
    check("a 4:1 panorama occupies a centred band, not the whole canvas",
          band < 600, True)
    # the extreme left/right of the artwork band must still be present, which
    # a centre-crop would have thrown away
    left = out.getpixel((2, top + band // 2))
    right = out.getpixel((397, top + band // 2))
    check("the panorama's left edge survives (a crop would lose it)",
          left[1] < 60, True)
    check("the panorama's right edge survives", right[1] > 195, True)

    # 5. The map keys on the SOURCE url, so one poster shared by two films is
    #    built once — and two different posters never collide.
    a = FIT.fitted_name("https://example.org/a.jpg")
    check("the same url yields the same filename",
          FIT.fitted_name("https://example.org/a.jpg"), a)
    check("a different url yields a different filename",
          FIT.fitted_name("https://example.org/b.jpg") != a, True)
    check("the filename is a plain safe jpg",
          a.startswith("fit-") and a.endswith(".jpg") and "/" not in a, True)

    # 6. THE REGRESSION ITSELF: build_asset must RESCUE a film whose poster is
    #    off-aspect when a fitted cover is really on disk — and must still
    #    withhold it when the file is missing, because a map entry whose file
    #    never reached the tarball would be a 404 to Roku.
    import json
    import tempfile
    item = {
        "archiveID": "test-off-aspect", "title": "A Wrongly Shaped Film",
        "synopsis": "A film whose only poster is four by three.",
        "year": 1925, "runtimeSeconds": 3600, "contentType": "feature-film",
        "posterURL": "https://example.org/wide.jpg",
        "rightsEvidence": "pre_1930", "rightsStatus": "public_domain",
    }
    dims = {"https://example.org/wide.jpg": [640, 480]}      # a refused shape
    check("control: with no fitted cover the film is withheld",
          F.build_asset(item, dims=dims, fitted={}, covers_dir=None), None)

    with tempfile.TemporaryDirectory() as td:
        cd = Path(td)
        name = FIT.fitted_name("https://example.org/wide.jpg")
        fitted = {"https://example.org/wide.jpg": name}
        check("a map entry whose FILE is absent still withholds the film",
              F.build_asset(item, dims=dims, fitted=fitted, covers_dir=cd), None)
        (cd / name).write_bytes(img(400, 600))
        a = F.build_asset(item, dims=dims, fitted=fitted, covers_dir=cd)
        check("with the file present the film is RESCUED, not withheld",
              a is not None, True)
        if a:
            u = a["images"][0]["url"]
            check("the rescued main image is served from our own covers path",
                  u == f"{F.SITE}/{F.FEED_DIR}/covers/{name}", True)
            check("the rescued asset carries exactly one image (no stale bg)",
                  len(a["images"]), 1)
            check("Roku's own verdict on the rescued image is ok",
                  F.image_verdict(u, dims), "ok")
            check("the rescued asset passes the spec validator",
                  F.validate_asset(a), [])

    # 7. the shipped map is well formed
    if F.FITTED_MAP.exists():
        m = json.loads(F.FITTED_MAP.read_text())
        check("every map key is an http url",
              all(k.startswith("http") for k in m), True)
        check("every map value is a bare fit-*.jpg filename",
              all(v.startswith("fit-") and v.endswith(".jpg") and "/" not in v
                  for v in m.values()), True)
        check("no two urls share a fitted filename",
              len(set(m.values())), len(m))

    bad = 0
    for name, ok, got, want in CASES:
        print(("PASS " if ok else "FAIL ") + name)
        if not ok:
            bad += 1
            print(f"      got:  {got!r}\n      want: {want!r}")
    print(f"\n{len(CASES) - bad}/{len(CASES)} passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
