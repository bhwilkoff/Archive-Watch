# Research: Mining archive.org's un-metadata'd ephemera into a searchable stock archive

*Compiled 2026-06-22. Scope: the pipeline + on-device stack to turn Archive Watch's
huge tail of thin-metadata ephemera / home-movies into a "Storyblocks for
archive.org" — automated shot detection, auto-tagging, semantic/visual search,
silent-vs-sound classification, and a no-backend index. This is Creation-Studio
**FEATURE 6** (stock-clip mining) and supports **FEATURE 8** (understanding which
items are silent home-movies / unprocessed scenes). All figures current as of
2025–2026; source URLs inline.*

The problem: most of our ephemera tail has a title, maybe a year, and nothing
useful for finding *the shot you want* ("a 1950s kitchen," "a parade," "vintage
cars on a city street"). Storyblocks-style stock search is built on per-clip
metadata that archive.org simply does not have for this material. We have to
**manufacture** it — at scale, in CI, with no inference backend to run — and serve
it through the same SQLite-on-a-Release / SQLite-on-Pages data plane the catalog
already uses (Decisions 017/018/029).

The good news: we already own most of the machinery. We run ffmpeg+opencv frame
extraction, an Apple **Vision** macOS CLI (`CoverScorer`: OCR / face / aesthetics),
and an ffmpeg-`signalstats` color classifier — all in GitHub Actions, some on macOS
runners for Vision/Metal. Every stage below is a sibling of those.

**Recommended stack at a glance** (detail in each section):

| Stage | Tool | Where it runs | Output per item |
|---|---|---|---|
| 1. Shot detection | **PySceneDetect** (`AdaptiveDetector`, `HashDetector` fallback) over ffmpeg-decoded frames | Linux CI (cheap) | shot list: in/out timecodes + 1 representative frame each |
| 2. Auto-tagging | Apple **Vision** `VNClassifyImageRequest` (+ face/text/horizon) on the representative frame | macOS CI (extend CoverScorer) | subject tags + confidences per shot |
| 3. Semantic / visual search | **MobileCLIP** (Core ML) image embeddings per shot; text encoder for NL queries; **`VNGenerateImageFeaturePrint`** for "more like this" | macOS CI (embed) + on-device (query) | 512-d image embedding per shot |
| 4. Audio analysis | Apple **SoundAnalysis** `SNClassifySoundRequest` (silence/music/speech/noise) + ffmpeg `silencedetect` pre-filter | macOS CI | per-item: silent? music? speech? |
| 5. Index at scale | sharded CI matrix → a `clips.sqlite` (shots + tags + FTS5) + **`sqlite-vec`** vector table; published as a Release asset / Pages | GitHub Actions | one queryable DB |
| 6. Storyblocks parity | category facets from tags + orientation/duration columns + the representative-frame thumbnail as preview | client | browse + filter UI |

---

# 1. Shot / scene detection — split long ephemera into usable clips

A 22-minute home-movie reel or industrial film is not a "stock clip." It's 15–60
shots that each are. We need to cut it into shots, with an in/out timecode and one
representative frame per shot, so each shot becomes an independently
taggable/searchable/previewable unit.

## 1.1 Options and trade-offs

**PySceneDetect** (Python + OpenCV) is the right primary tool — it is purpose-built,
scriptable, runs headless in CI, and exposes multiple detectors tuned for different
content. Its detectors and defaults
([PySceneDetect detectors docs](https://www.scenedetect.com/docs/latest/api/detectors.html)):

- **`ContentDetector`** — HSV-colorspace weighted frame difference; default
  threshold **27.0**. Fast, good for hard cuts on clean color footage. Weak on
  gradual transitions.
- **`AdaptiveDetector`** — same scoring but with a *rolling-average* threshold
  (default adaptive threshold **3.0**), so it tolerates camera shake / fast motion
  without firing a false cut. **This is the right default for ephemera**: amateur
  home-movie footage is full of pans, jitter, and exposure swings that a fixed
  threshold mis-cuts.
- **`ThresholdDetector`** — average RGB intensity; default **12**. Detects
  **fade-in/out and dissolves to/from black** — extremely common in old reels
  (leader, splices, fade transitions). Run it alongside the content detector to
  catch fades the HSV detector misses.
- **`HashDetector`** — perceptual hashing, default normalized-hamming **0.395**.
  **Resilient to compression artifacts and degraded footage** — the recommended
  *fallback* for grainy, scratched, low-bitrate archival scans where pixel-diff
  detectors over-fire on film grain.
- **`HistogramDetector`** — Y-channel (luminance) histogram diff, default **0.05**.
  Robust to lighting variation; another good degraded-footage option.

The independent
[shot-detection benchmark (albanie/shot-detection-benchmarks)](https://github.com/albanie/shot-detection-benchmarks)
comparing ffmpeg, Shotdetect, and PySceneDetect found PySceneDetect slightly ahead
on recall at default settings, with the universal caveat that **recall is content-
dependent** (sports/fast-motion are hard) and threshold tuning trades precision for
recall. Newer large-scale work
([Scene Detection Policies for Large-Scale Video Analysis, arXiv 2506.00667](https://arxiv.org/html/2506.00667v1))
confirms that an adaptive policy plus a representative-keyframe choice per shot is
the standard pattern for exactly our use case.

**ffmpeg `select='gt(scene,T)'`** is the *fast* alternative — a one-liner scene
filter that emits frames where the scene-change score exceeds `T` (e.g.
`-vf "select='gt(scene,0.3)',showinfo"`). It is the speed leader (ffmpeg > PySceneDetect
> ffprobe on throughput per the benchmark) but is a blunt single-threshold tool with
no fade handling, no rolling average, and no clean shot-list API. **Use it only as a
pre-filter / sanity check, not the primary cutter.**

**AVFoundation / Vision shot-boundary**: Apple does **not** ship a public
shot-boundary-detection request. (Vision detects horizon, faces, text, saliency,
objects, feature prints — but there is no `VNDetectSceneCutRequest`.) Building shot
detection on AVFoundation means decoding frames and diffing them yourself —
reinventing PySceneDetect with less tuning. **Not worth it.** Keep shot detection in
the cheap Linux ffmpeg/PySceneDetect lane; reserve the macOS runners for Vision/CLIP
work that actually requires them.

## 1.2 Recommended approach

1. Decode at low res (e.g. 320px wide) for detection speed — PySceneDetect's
   downscale factor; detection accuracy barely changes, throughput jumps.
2. Run **`AdaptiveDetector` + `ThresholdDetector`** together (content cuts + fades).
   For items flagged degraded (low bitrate, heavy grain — we can read bitrate from
   the existing pipeline), swap in **`HashDetector`**.
3. Emit a shot list: `(shot_index, start_tc, end_tc, duration)`.
4. **Drop micro-shots** (< ~1.5 s) and merge — stock users want usable clips, not
   single-frame flashes. Drop leader/black shots via the `ThresholdDetector` floor.
5. Pick **one representative frame per shot** — not the first frame (often a
   transition smear). Reuse the CoverScorer pattern: sample N frames mid-shot, score
   by sharpness + aesthetics + `isUtility`, keep the best non-utility frame. That
   single frame is the unit fed to tagging + embedding + used as the preview thumb.

This is the same ffmpeg→best-frame protocol the cover pipeline already runs
(Decision 023), generalized from one-frame-per-item to one-frame-per-shot.

---

# 2. Auto-tagging / classification — build the subject vocabulary

For Storyblocks-style category browse we need subject tags per shot: *beach, city,
kitchen, parade, car, crowd, factory, child, dog, mountain*. The representative
frame from §1 is the input.

## 2.1 Apple Vision — `VNClassifyImageRequest` (the workhorse)

`VNClassifyImageRequest` runs Apple's **built-in multi-label image classifier** —
**1,303 identifiers** (≈1,000 classes) in a **hierarchical taxonomy**, returning
independent per-class confidences (not a softmax), so it reports *all* objects in a
frame, not just the dominant one
([VNClassifyImageRequest docs](https://developer.apple.com/documentation/vision/vnclassifyimagerequest),
[Classifying images for categorization and search](https://developer.apple.com/documentation/Vision/classifying-images-for-categorization-and-search),
[WWDC19 "Understanding Images in Vision"](https://developer.apple.com/videos/play/wwdc2019/222/)).
Apple's guidance is to threshold with a **precision/recall curve per identifier**
(the API exposes `hasMinimumRecall(_:forPrecision:)` on each observation) so you can
pick, e.g., "tags at precision 0.7." This is exactly our CoverScorer pattern — same
framework, same macOS-CLI shape, just a different request.

This gives us a free, on-device, no-API-cost **base tag layer** covering common
objects/scenes. The hierarchical taxonomy is a bonus: a "tabby cat" label rolls up
to "cat" → "animal," which maps cleanly onto a category tree.

**Complement Vision classification with other built-in requests on the same frame:**

- **`VNDetectFaceRectanglesRequest`** → face count → tags like *portrait, crowd,
  people* (and the count itself is a useful filter facet).
- **`VNRecognizeTextRequest`** (OCR) → on-screen text (signage, title cards,
  intertitles). Doubles as a **silent-film / title-card detector** for FEATURE 8 and
  as searchable text. (CoverScorer already does text-coverage scoring — reuse it.)
- **`VNDetectHorizonRequest`** / saliency → landscape-vs-interior heuristics.

## 2.2 Limits and how to extend

The built-in classifier knows *objects/scenes*, not *eras or vibes* — it will not
emit "1950s" or "mid-century kitchen." Two ways to add the archival-specific
vocabulary:

- **Derived tags from data we already have**: decade from the catalog year →
  `1950s` tag; `colorMode` (Decision 025) → `black-and-white` / `color` filter;
  collection → `home-movie` / `industrial` / `newsreel`.
- **Custom Create ML image classifier** (later): Apple's Create ML trains a small
  Core ML classifier from labeled examples; we could train an "archival era / scene"
  classifier and run it as a second `VNCoreMLRequest`. Deferred — the built-in
  classifier + derived tags cover v1.

The killer capability for "1950s kitchen" type queries is **not** more discrete
tags — it's semantic search (§3), where a CLIP text query matches the *visual
content* directly without needing a literal "kitchen" tag to exist.

---

# 3. Semantic / visual search — the real differentiator

Discrete tags get you category browse. They do **not** get you "find shots of
vintage cars on a rainy street" over silent footage with no subtitles and no
description. That is **CLIP-style embedding search**: embed every shot's
representative frame into a shared image/text vector space; embed the user's natural-
language query with the matching text encoder; rank shots by cosine similarity.

## 3.1 MobileCLIP (Core ML) — recommended

Apple open-sourced **MobileCLIP** as Core ML models
([apple/coreml-mobileclip](https://huggingface.co/apple/coreml-mobileclip),
[Apple ML Research: MobileCLIP](https://machinelearning.apple.com/research/mobileclip)).
Key facts for our purposes:

- A family of image+text encoders, **512-dimensional** shared embedding space,
  3–15 ms inference, 50–150M params.
- **MobileCLIP-S0** matches OpenAI ViT-B/16 zero-shot while being **4.8× faster and
  2.8× smaller** — the right pick for an on-device app; larger S1/S2/B variants trade
  size for accuracy.
- Separate **image encoder** and **text encoder** — we run the image encoder in CI
  to embed every shot, and ship the (small) text encoder in the app to embed queries
  live. Apple Source Code License.

This is proven on-device: the [Queryable](https://github.com/mazzzystar/Queryable)
app runs CLIP / MobileCLIP on iOS to search the photo library by natural language —
the exact pattern, applied to our shot library instead of a camera roll. Conversion
is standard `coremltools` (trace PyTorch → Core ML); for cinema-specific vocabulary
there's even [CinemaCLIP](https://github.com/Synopsis/cinemaclip), a CLIP+taxonomy
tuned to the visual language of film, if the generic model under-performs on
archival aesthetics.

**Architecture:** CI embeds shots (image encoder, macOS runner, Metal/ANE). App
embeds the query string (text encoder, ~tens of MB, ships in the bundle). Cosine
similarity = dot product of L2-normalized vectors → top-K shots. No server, no
per-query cost, works offline.

## 3.2 `VNGenerateImageFeaturePrintRequest` — the cheap "more like this"

Vision's `VNGenerateImageFeaturePrintRequest` produces a `VNFeaturePrintObservation`
whose `computeDistance` gives a Euclidean distance between two images — smaller =
more similar
([Analyzing Image Similarity with Feature Print](https://developer.apple.com/documentation/vision/analyzing-image-similarity-with-feature-print)).
It is **image→image only — there is no text side** — so it can't do natural-language
search, but it's perfect for the **"find clips that look like this one"** button and
for de-duping near-identical shots. It needs no model download (built into Vision)
and is already in the CoverScorer toolbox. (Note: the iOS17 revision changed
distance values vs iOS16 — pin `Revision1` if we ever store distances; we won't,
we'll recompute.)

**Recommendation:** ship **both**. MobileCLIP for text→image NL search (the headline
feature); feature print for image→image "more like this" and dedupe. They are
complementary, not redundant.

## 3.3 Why this is the wedge

Our ephemera has *no* subtitles, *no* descriptions, often *no* real title. Discrete
tags are sparse and miss the long tail of queries. A CLIP image embedding captures
the *visual content itself*, so "1950s kitchen" or "vintage cars" matches the pixels
— turning un-metadata'd footage into searchable stock without anyone writing a
caption. That is the entire Storyblocks value proposition, manufactured for free.

---

# 4. Audio analysis — silent vs music vs speech (FEATURE 8)

FEATURE 8 wants to know *which items are silent home-movies / unprocessed scenes*.
That's an audio-track classification problem with three tiers of effort:

## 4.1 Fast pre-filter — ffmpeg

- **No audio stream at all** → trivially "silent" (read with `ffprobe`).
- **`silencedetect`** filter (`-af silencedetect=noise=-50dB:d=2`) → measures how
  much of the runtime is below a silence floor. A reel that is ≥95% silent is a
  silent home-movie even if it has a (dead) audio track. Cheap, runs in the Linux
  lane.
- **`astats` / `volumedetect`** → mean/peak volume sanity.

This alone separates *genuinely silent* footage (the FEATURE 8 target) from anything
with an audio track, with near-zero cost.

## 4.2 Content classification — Apple SoundAnalysis

For items that *do* have audio, **`SNClassifySoundRequest`** runs Apple's built-in
sound classifier — **300+ sound classes** (speech, music, instruments, environmental
noise, human sounds), windowed **0.5–15 s**, on-device, no custom model needed
([SNClassifySoundRequest docs](https://developer.apple.com/documentation/soundanalysis/snclassifysoundrequest),
[WWDC21 built-in sound classification](https://developer.apple.com/videos/play/wwdc2021/10036/)).
Run it over the extracted audio (`SNAudioFileAnalyzer`) and aggregate the windows
into per-item flags: `hasSpeech`, `hasMusic`, `isMostlyNoise/silent`. That tells us
whether a clip is usable as **silent B-roll** (no speech to talk over), has a
**music bed**, or carries **dialogue** — all useful stock-search facets ("silent
B-roll only") and the core FEATURE-8 signal.

This is a third macOS-CLI sibling to CoverScorer (Vision) and the color classifier —
same Actions pattern, `SoundAnalysis` instead of `Vision`.

**Recommendation:** ffmpeg `silencedetect` as the cheap first pass for the
silent/not-silent split (covers the FEATURE-8 question for most items in the Linux
lane), then SoundAnalysis only on items with a live audio track for the
speech/music/noise breakdown.

---

# 5. Indexing at scale — the no-backend constraint

The hard architectural constraint: **we have no inference backend and no database
server.** The catalog already lives as SQLite on a GitHub Release (Decisions 017/018)
and is mirrored to Pages for the web viewer (Decision 029). The stock index must fit
the same model.

## 5.1 The CI pipeline (sibling of cover/color pipelines)

A new `stock-index.yml` workflow, sharded exactly like the whisper/cover jobs
(`--shard-index/--shard-count` over a runner matrix), processing the ephemera tail
popularity-first, resumable via a per-item marker (`stockIndexed`):

```
per item (ephemera/home-movie/unprocessed tail):
  1. ffmpeg decode (low-res)         [Linux]
  2. PySceneDetect shot list         [Linux]   → shots + timecodes
  3. ffmpeg silencedetect            [Linux]   → silent? (FEATURE 8)
  per shot:
  4. best representative frame       [Linux]   → thumbnail (CoverScorer scoring)
  5. Vision classify + face + OCR    [macOS]   → tags
  6. MobileCLIP image embed          [macOS]   → 512-d vector
  per item (if audio track):
  7. SoundAnalysis                   [macOS]   → speech/music flags
  → emit a compact per-shard delta file
publish job (single, additive):
  merge shards → build clips.sqlite → publish to Release + deploy to Pages
```

Split Linux vs macOS stages so the expensive macOS-runner minutes only do
Vision/CLIP/SoundAnalysis. Keep publish **single and additive** (the whisper-shard
lesson, Decision 039a) so parallel shards never clobber the shared Release asset.

## 5.2 Storing the shots + tags — SQLite + FTS5

A `clips.sqlite` (separate from `catalog.sqlite`, or a new set of tables in it):

- `shots(shot_id, archive_id, start_tc, end_tc, duration, orientation, thumb_url)`
- `shot_tags(shot_id, tag, confidence, source)` — Vision labels + derived (decade,
  color, collection-type)
- `shots_fts` — FTS5 over the concatenated tag text + OCR text for keyword search
- per-item audio flags (`silent`, `has_speech`, `has_music`) as columns

Thumbnails follow the cover pattern (Decision 023): one representative JPEG per shot,
hosted on the `archivewatch-covers` archive.org item, URL stored in the DB. No
thumbnail bytes in git or in the DB.

## 5.3 Storing the embeddings — `sqlite-vec`

This is the one genuinely new piece. **`sqlite-vec`** is a pure-C, dependency-free
SQLite extension for KNN vector search — the successor to `sqlite-vss`, written to
*run anywhere SQLite runs, including the browser via WASM*
([asg017/sqlite-vec](https://github.com/asg017/sqlite-vec),
[sqlite-vec stable release](https://alexgarcia.xyz/blog/2024/sqlite-vec-stable-release/index.html)).
It stores the 512-d MobileCLIP vectors in a virtual table and does SIMD-accelerated
cosine/L2 KNN — exactly our "rank shots by similarity to the query embedding"
operation, with **no Pinecone/Weaviate/FAISS server**.

Storage math: 512 floats × 4 bytes = **2 KB/shot** (1 KB at fp16, which sqlite-vec
supports). 100k shots ≈ 100–200 MB of vectors — comparable to the existing catalog
DB, and a candidate for fp16/int8 quantization if it needs slimming. This is well
within the "ship a SQLite DB as a Release asset" model.

**Three serving paths, all backend-free:**

1. **macOS app (Creation Studio, the primary surface):** download `clips.sqlite`
   (with the `sqlite-vec` table) once, query on-disk. The app embeds the query string
   with the bundled MobileCLIP **text** encoder, hands the 512-d vector to a
   `sqlite-vec` KNN query, gets top-K shots. Fully offline, no per-query cost. (Same
   on-disk SQLite pattern as the catalog; `sqlite-vec` compiles into the app's SQLite
   the way FTS5 does.)
2. **iOS app:** identical, with `VNGenerateImageFeaturePrint` available for the
   image→image "more like this" path without even loading CLIP.
3. **Web viewer (Pages):** `sqlite-vec` compiles into the **official SQLite WASM
   build**, and GitHub Pages serves **HTTP Range requests** out of the box, so a
   range-VFS (the `sql.js-httpvfs` pattern we already validated for the catalog,
   Decision 029) can query the vector DB **without downloading it whole**
   ([sqlite-vec in the browser with WASM](https://alexgarcia.xyz/sqlite-vec/wasm.html),
   [Query SQLite on GitHub Pages with sql.js-httpvfs](https://recca0120.github.io/en/2026/03/07/sql-js-httpvfs-static-hosting/)).
   The web side needs a CLIP text encoder in WASM/ONNX to embed the query, or can
   fall back to FTS5 tag/OCR keyword search where shipping CLIP-in-browser is too
   heavy. (KNN over range-fetched vectors is less efficient than tag search; for web,
   FTS5 tag search first, CLIP semantic search as the upgrade — mirrors the
   Decision-029 "index now, FTS later" staging.)

**Net:** the entire index is *data* — one (or two) SQLite files on a Release + Pages.
No server, no schema deploy, additive evolution (new tag columns / new shot rows
decode in old clients). It fits the existing data plane exactly.

---

# 6. Storyblocks parity — the browse/search UX it enables

What the index above lets the Creation Studio UI offer, mapped to what Storyblocks
ships
([Storyblocks AI search guide](https://www.storyblocks.com/resources/blog/how-to-use-ai-search-for-storyblocks-library),
[Storyblocks video search](https://www.storyblocks.com/video/search),
[vertical-orientation footage](https://www.storyblocks.com/video/search/vertical-orientation)):

| Storyblocks feature | Our source | Notes |
|---|---|---|
| **Category / subject browse** | Vision tags + hierarchical taxonomy → category tree | "Beach," "City," "People," "Vehicles," etc. roll-up from the 1,303-label taxonomy |
| **Keyword + fuzzy search** | FTS5 over tags + OCR text | FTS5 gives substring/prefix; fuzzy via trigram or client-side |
| **Natural-language / "AI" search** | MobileCLIP text→image | the differentiator — works on un-captioned footage |
| **"More like this"** | `VNGenerateImageFeaturePrint` distance / CLIP image→image | per-shot similarity |
| **Orientation filter** (landscape/portrait/vertical) | shot width:height → column | derivable for free from the frame |
| **Duration filter** | shot duration column | from the shot list |
| **Resolution / frame-rate filter** | ffprobe at index time | store as columns |
| **Audio filter** (silent / music / speech) | SoundAnalysis + silencedetect flags | "silent B-roll only" facet — uniquely valuable for archival |
| **Preview / hover-scrub** | representative-frame thumbnail per shot (+ optional short clip extract) | thumb is free; a 2-s preview clip is a future extract job |
| **Color filter** | `colorMode` (Decision 025) | B&W vs color, already have it |

Storyblocks publishes little about *how* it tags/indexes internally
([Storyblocks search reference](https://www.getguru.com/reference/storyblocks-search))
— it's an indexed keyword + fuzzy + (recently) AI-semantic system. Our parity comes
from manufacturing the per-clip metadata they have human-curated, using the on-device
ML we already run.

---

# Recommendations summary

1. **Shot detection in the cheap lane.** PySceneDetect `AdaptiveDetector` +
   `ThresholdDetector` (HashDetector for degraded footage) over ffmpeg-decoded
   low-res frames; drop micro-shots; one scored representative frame per shot. ffmpeg
   `select='gt(scene,…)'` only as a fast pre-filter. AVFoundation/Vision have no
   shot-boundary API — don't build one.
2. **Tag with Vision, on macOS, as a CoverScorer sibling.** `VNClassifyImageRequest`
   (1,303-label multi-label classifier) + face + OCR per representative frame, plus
   derived tags (decade, colorMode, collection-type).
3. **Semantic search via MobileCLIP Core ML.** CI embeds shots (image encoder, 512-d,
   macOS); app embeds queries live (text encoder, bundled); cosine top-K. Add
   `VNGenerateImageFeaturePrint` for image→image "more like this." This is the wedge:
   NL search over un-captioned footage.
4. **Audio: ffmpeg `silencedetect` first** (the FEATURE-8 silent/not split, Linux,
   cheap), **SoundAnalysis** (`SNClassifySoundRequest`, 300+ classes, macOS) for the
   speech/music breakdown on items with audio.
5. **Index = data, no backend.** Sharded CI matrix (cover/whisper pattern) → a
   `clips.sqlite` with shots + FTS5 tags **+ a `sqlite-vec` virtual table** for the
   embeddings; published to a GitHub Release and deployed to Pages. macOS/iOS query
   on-disk (`sqlite-vec` compiles in like FTS5); web queries via WASM + Range-request
   VFS, with FTS5 tag search as the always-available fallback. Thumbnails on the
   `archivewatch-covers` archive.org item. Additive schema, single additive publish.
6. **Storyblocks parity** falls out for free: orientation/duration/resolution/color/
   audio facets are all columns derived at index time; category browse from the Vision
   taxonomy; preview = the representative-frame thumbnail.

---

## Sources

- [PySceneDetect — Detectors (ContentDetector / AdaptiveDetector / ThresholdDetector / HashDetector / HistogramDetector + defaults)](https://www.scenedetect.com/docs/latest/api/detectors.html)
- [PySceneDetect documentation](https://www.scenedetect.com/docs/latest/)
- [albanie/shot-detection-benchmarks — ffmpeg vs Shotdetect vs PySceneDetect](https://github.com/albanie/shot-detection-benchmarks)
- [Scene Detection Policies and Keyframe Extraction for Large-Scale Video Analysis (arXiv 2506.00667)](https://arxiv.org/html/2506.00667v1)
- [VNClassifyImageRequest — Apple Developer Documentation](https://developer.apple.com/documentation/vision/vnclassifyimagerequest)
- [Classifying images for categorization and search — Apple Developer](https://developer.apple.com/documentation/Vision/classifying-images-for-categorization-and-search)
- [WWDC19 — Understanding Images in Vision Framework](https://developer.apple.com/videos/play/wwdc2019/222/)
- [Analyzing Image Similarity with Feature Print (VNGenerateImageFeaturePrintRequest) — Apple Developer](https://developer.apple.com/documentation/vision/analyzing-image-similarity-with-feature-print)
- [apple/coreml-mobileclip — Hugging Face (Core ML MobileCLIP variants)](https://huggingface.co/apple/coreml-mobileclip)
- [Apple ML Research — MobileCLIP](https://machinelearning.apple.com/research/mobileclip)
- [mazzzystar/Queryable — CLIP / MobileCLIP photo search on iOS](https://github.com/mazzzystar/Queryable)
- [Synopsis/cinemaclip — CLIP + taxonomy for the visual language of cinema](https://github.com/Synopsis/cinemaclip)
- [SNClassifySoundRequest — Apple Developer Documentation](https://developer.apple.com/documentation/soundanalysis/snclassifysoundrequest)
- [WWDC21 — Discover built-in sound classification in SoundAnalysis](https://developer.apple.com/videos/play/wwdc2021/10036/)
- [asg017/sqlite-vec — vector search SQLite extension](https://github.com/asg017/sqlite-vec)
- [Introducing sqlite-vec v0.1.0 (stable release) — Alex Garcia](https://alexgarcia.xyz/blog/2024/sqlite-vec-stable-release/index.html)
- [sqlite-vec in the Browser with WebAssembly — Alex Garcia](https://alexgarcia.xyz/sqlite-vec/wasm.html)
- [Query SQLite on GitHub Pages with sql.js-httpvfs (Range requests)](https://recca0120.github.io/en/2026/03/07/sql-js-httpvfs-static-hosting/)
- [Storyblocks — Your guide to using AI search](https://www.storyblocks.com/resources/blog/how-to-use-ai-search-for-storyblocks-library)
- [Storyblocks — Video search & filters](https://www.storyblocks.com/video/search)
- [Storyblocks Search reference (Guru)](https://www.getguru.com/reference/storyblocks-search)
