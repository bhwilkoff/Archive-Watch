# Frame Extraction as a Last-Resort Cover Art Source

**Status:** Not implemented. Reserved for after all 3rd-party sources are
exhausted and we still have items without real designed artwork.

**Priority:** Low — only address if we observe users being frustrated by
procedural-fallback cards on popular items. For the long tail (home
movies, obscure industrials, unknown uploaders), the procedural card
is an honest representation.

---

## When to build this

Build this pass **only** when all of the following are true:

1. Every available 3rd-party source (TMDb, Fanart.tv, OMDb, Wikidata,
   LoC, AAPB, Commons, Wikipedia) has been tried and come up empty for
   the item.
2. The item is in the shipping full catalog (i.e., quality + popularity
   above threshold). Long-tail items don't warrant the compute.
3. The item's Archive-default thumbnail (`services/img/{id}`) is a poor
   representation — which is detectable by checking if it's the standard
   grey "no preview" placeholder or by running a cheap image-signature
   check (histogram entropy, dominant-color variance).

Until those conditions hit, the app's procedural-poster fallback is
the right answer — it's visually coherent with the cinematheque brand
and doesn't require any compute.

---

## What the pass does

Extract one or two candidate thumbnail images from the item's actual
video file, rank them by a composite "good cover art" score, pick the
best, and upload to a hosted location the app can fetch.

Pipeline for a single item:

1. **Download (or stream)** the resolved `stream_url` (Archive.org MP4).
   Use a partial-range GET to pull only the middle third of the file —
   avoids title cards and end credits. Cache locally; most items are
   50–800 MB.

2. **Extract candidate frames** with `ffmpeg`:
   ```
   ffmpeg -ss 15% -to 80% -i input.mp4 \
          -vf "select='gt(scene,0.3)',fps=1/30" \
          -frames:v 30 candidates/frame_%03d.jpg
   ```
   - `-ss 15% -to 80%` skips intro + credits.
   - Scene-change detection (`gt(scene,0.3)`) prioritizes frames at
     visual transitions — usually at the start of a new shot, often
     with a clean composition.
   - `fps=1/30` — one frame every 30 seconds as a sampling rate.
   - Cap at 30 candidates.

3. **Score each candidate**:

   | Signal | Weight | How |
   |---|---|---|
   | Face detection count | +10 per face | `OpenCV` Haar cascade + DNN face detector |
   | Face area / frame area | +20 × ratio | Big faces = promotional-style cover |
   | Rule of thirds composition | +5 | Saliency detection; reward subjects on intersections |
   | Colour variance | +5 | Stddev of HSV across frame; kills black/static shots |
   | Brightness | −5 if mean < 30 or > 220 | Skip too-dark / washed-out frames |
   | Edge density | +3 | Canny edge count; kills frames with no subject |
   | Text-dominant | −15 | OCR score; reject title cards |
   | Colour bar / SMPTE test pattern | −100 | Detects distinctive calibration patterns |

   Composite score is a simple linear sum. No ML training required —
   all heuristics.

4. **Pick the top frame**, scale to 2:3 poster aspect (1000×1500), save
   as JPEG at quality 85. Expect ~80–150 KB per poster.

5. **Upload to a CDN**. Options, from simplest to most work:

   - **Dedicated `poster-cache` repo on GitHub Pages** — drops into our
     existing hosting model; downside is 80–150 KB × 100k items =
     8–15 GB, which violates GH soft limits and needs Git LFS.
   - **Archive.org Item** — upload generated posters as a new item
     under a dedicated creator. Free, durable, fits the product.
   - **Cloudflare R2 / AWS S3** — lowest friction; requires an account
     and DNS setup.
   - **IPFS / Pinata** — content-addressed, permanent; pragmatic if we
     care about the work outliving any one hoster.

6. **Write the URL** to `enrichment.poster_url` with
   `artwork_source='generated'`. The app treats this as designed art
   (`hasRealArtwork=true`) because it's a real still from the film,
   not the archive-default first-frame placeholder.

---

## Cost + time

Per-item processing on a modest Mac (M-series, single-threaded):
- Download 400 MB: ~15s on a gigabit
- ffmpeg scene-detection + sampling: ~10s
- OpenCV scoring of 30 candidates: ~5s
- Upload + DB write: ~1s

**Total ~30s/item.** Parallelizing 4 workers: ~8s/item effective.

For 50,000 items that would otherwise have no designed art: **~110 hours
single-threaded, ~28 hours with 4 workers**. Feasible as an overnight
batch.

Storage: 100 KB × 50k = **5 GB**. Fits R2 free tier (10 GB/mo).

---

## Building blocks to write

```
tools/frame_extract/
├── __init__.py
├── download.py        # partial-range HTTP GET → local file cache
├── extract.py         # ffmpeg wrapper — scene-detect + sample
├── score.py           # face detection + composition + heuristics
├── pipeline.py        # orchestrator
├── upload.py          # pluggable target (GH / Archive / R2)
└── tests/
    └── fixtures/      # known-good / known-bad frame samples
```

CLI:
```bash
python -m tools.frame_extract --limit 100          # smoke test
python -m tools.frame_extract --only-shipping      # shipping full catalog
python -m tools.frame_extract --workers 4          # parallelism
python -m tools.frame_extract --upload r2          # target
```

Schema additions to `enrichment`:
```sql
ALTER TABLE enrichment ADD COLUMN generated_from_frame_at_ms INTEGER;
ALTER TABLE enrichment ADD COLUMN generated_score REAL;
ALTER TABLE enrichment ADD COLUMN generated_at TEXT;
```

These let us re-run with a better scoring algorithm later and pick
different frames if desired.

---

## Quality gates before shipping generated art

Before any frame-extracted poster is written to the catalog:

1. **Face floor**: composite score must be > 20 — items with no faces
   and no strong composition don't get a fabricated "designed" poster;
   they stay as procedural cards.
2. **Diversity**: no two poster thumbnails in a shelf should be from
   within 10s of each other in video time (prevents near-identical
   covers on a series).
3. **Manual sample review**: for the first N=500 extracted posters,
   human-review a random 5% before batch-committing. If reject rate
   > 20%, tune scoring and re-run.
4. **`hasRealArtwork` honesty**: re-consider whether extracted frames
   should set `hasRealArtwork=true`. Extracted frames are honest
   representations of the film but they aren't designed marketing art
   — the app could distinguish them with a third state
   (`designed` / `extracted` / `procedural`) so shelves can mix
   tastefully.

---

## Why we're not doing this now

- **3rd-party coverage is already 99.8% for the seed catalog.** Users
  see real designed art on every tile of the bundled experience.
- **31% real-art coverage on the full 25k catalog is sufficient** —
  the rest gets Archive first-frame thumbs that are often better than
  nothing and match the film's actual visual identity.
- **Compute + storage cost is real.** We'd burn 28+ hours and 5+ GB
  for what is, realistically, last-mile coverage.
- **Frame extraction without face detection is a net negative.** A
  random mid-video frame can easily be worse than the procedural
  fallback, which at least respects the app's design language.

Revisit when: (a) we have telemetry showing users bounce off
procedural cards, (b) we have a specific editorial push for a long-
tail collection where real frames matter, or (c) we've exhausted
every cheap 3rd-party source and the user experience demands it.
