# Runbook: frame-extracted cover generation (#86 / #13b)

The **mac-based screenshot protocol** that gives a real poster to catalog items
no third-party source covers — chiefly the ~2,400 vintage commercials (which
have no TMDb/Commons/Wikidata art at all) and the long tail of features, silents,
and animation that fell through enrichment. Every cover is a genuine still pulled
from the item's own video and scored for quality. **Nothing is hallucinated.**

Implements the plan in `docs/research/frame-extraction-plan.md`. Status:
**implemented + running.** This runbook is the operational truth; the research
doc is the original design.

---

## The three stages

```
 GENERATE (mac)            PUBLISH (archive.org)        WIRE (catalog)
 batch_covers.py    -->    upload_covers.py       -->   apply_covers.py
 frames -> posters/        posters -> IA item           url -> posterURL
 + manifest.jsonl          + uploaded.jsonl             in catalog.json
```

All three are **resumable** (each tracks its own done-set on disk) and safe to
re-run. Output lives under `tools/covers_out/` (gitignored — see below).

### Why this design

- **Generate is decoupled from publish** so the slow part (network frame-grabs)
  can run as an unattended overnight/multi-day batch on a Mac with `ffmpeg` +
  `opencv`, while hosting/credentials are a separate concern.
- **Hosting is archive.org** (Decision: owner-chosen 2026-06-05). One item,
  `archivewatch-covers`, holds every cover; each gets a stable public URL
  `https://archive.org/download/archivewatch-covers/<slug>.jpg`. Free, durable,
  unlimited, and on-brand (the app is a love letter to the Internet Archive).
  The tvOS app fetches it via URLSession, so there is no CORS concern.
- **Wiring is additive** (Decision 020): `apply_covers.py` only fills items that
  still lack real art, never overwrites a third-party poster, never drops items.

---

## Prerequisites

- macOS with `ffmpeg` + `ffprobe` on PATH (`brew install ffmpeg`) and
  `opencv-python` / `opencv-python-headless` importable as `cv2`.
- A local `catalog.json` (the work-list source):
  `python tools/catalog_release.py fetch`
- archive.org IAS3 credentials in the environment (NEVER commit them):
  ```bash
  export IAS3_ACCESS_KEY=...    # owner's archive.org S3 access key
  export IAS3_SECRET_KEY=...    # owner's archive.org S3 secret key
  ```
  For CI, add the same two names as GitHub Actions secrets.

---

## Stage 1 — GENERATE (`tools/batch_covers.py`)

Finds every item with no real designed artwork (`posterURL` empty or
`hasRealArtwork` not true), grabs the best frame, writes `posters/<slug>.jpg`.
Items are processed **most-popular-first** so the most-seen tiles get real art
soonest. Resumable: a finished item (`status: ok` in the manifest, or its file
on disk) is skipped on re-run.

```bash
# see the work-list size without doing anything
python tools/batch_covers.py --dry-run

# one content type (the documented primary target)
python tools/batch_covers.py --content-type commercial --workers 6

# everything missing, as an unattended batch (survives the shell via nohup)
nohup python3 tools/batch_covers.py --workers 10 --samples 9 \
      > tools/covers_out/run.log 2>&1 &
```

Notes:
- **Throughput is network-bound** (each item does ~9 HTTP range-seeks against
  archive.org), not CPU-bound — raise `--workers` to go faster, but stay polite
  (10 is a reasonable ceiling; archive.org will 503/throttle if hammered).
- stdout is block-buffered into `run.log`; **watch `manifest.jsonl` for live
  progress** (it flushes per item), or run with `PYTHONUNBUFFERED=1`.
- Scoring (in `frame_cover.py`): rejects near-black / blown-out / flat / blurry
  frames; big bonus for a detected frontal face. A face-bearing cover scores
  ~400+, a faceless-but-usable frame ~50-90. Items where no frame clears the bar
  get `status: no_frame` and keep their procedural card.

Progress check:
```bash
wc -l tools/covers_out/manifest.jsonl              # attempts
grep -c '"status": "ok"' tools/covers_out/manifest.jsonl
ls tools/covers_out/posters/*.jpg | wc -l          # covers on disk
```

## Stage 2 — PUBLISH (`tools/upload_covers.py`)

Uploads every `status: ok` cover into the `archivewatch-covers` archive.org item
via the IAS3 (S3-like) API. Resumable via `uploaded.jsonl`. Can run **while
Stage 1 is still going** — it only uploads what's finished, and a later run picks
up the rest.

```bash
export IAS3_ACCESS_KEY=...  IAS3_SECRET_KEY=...
python tools/upload_covers.py --item archivewatch-covers --limit 50   # smoke first
python tools/upload_covers.py --item archivewatch-covers              # the rest
```

A freshly-created archive.org item takes a few minutes to register; the
`download/<item>/<file>.jpg` URL then 302-redirects to the storage node (a `200`
after following the redirect). That redirect is normal — the app's URLSession
follows it automatically.

## Stage 3 — WIRE (`tools/apply_covers.py`)

Sets `posterURL` + `artworkSource="generated"` + `hasRealArtwork=true` on each
catalog item that has an uploaded cover and still lacks real art. Run inside the
standard catalog write path (Decision 018):

```bash
python tools/catalog_release.py fetch       # freshest catalog
python tools/apply_covers.py --dry-run      # preview counts
python tools/apply_covers.py                # mutate ./catalog.json
python tools/remediate_catalog.py           # normal pipeline cleanup (optional)
python tools/catalog_release.py publish     # push catalog-source release
gh workflow run publish-db.yml              # rebuild the app SQLite + index
```

`artworkSource="generated"` flows through `build_sqlite.py` exactly like any
non-`archive` source, so generated covers count as real art on Home/Browse and
sort ahead of poster-less tiles.

---

## `covers_out/` is gitignored

`tools/covers_out/` holds the working set (posters + manifests + logs) and can be
multiple GB at full scale. It is a local/CI scratch dir, not source — the durable
copies live on the archive.org item (`uploaded.jsonl` is the index). Keep it out
of git for the same reason the catalog isn't committed (Decisions 017/018).

---

## Re-running for new items (ongoing)

As `discover-content` ingests new commercials/films, they arrive without art.
Re-run all three stages; each skips what it already did, so only the genuinely
new items are processed, uploaded, and wired. This can be wrapped into a CI
workflow once the IAS3 secrets are added to the repo (deferred — see backlog).
