# Creation Studio — Proxy Clips over Remote archive.org Video (Feature 2)

*Research brief — 2026-06-22. Scope: the non-destructive "proxy clip" model
for a native macOS Creation Studio editor that references REMOTE archive.org
videos by start/stop time WITHOUT downloading them.*

This is **Creation Studio Feature 2** — the foundation of the whole proxy
model: *save clips from different titles into a library without downloading,
using archive.org as the source but creating proxy clips that link to
start/stop times. We own the annotation layer; archive.org owns hosting.*

> Project constraints (binding): no separate backend — we own only an
> annotation layer; Apple frameworks in-app, `ffmpeg` CLI subprocess OK on
> Mac; storage = local (SwiftData/JSON) + the user's iCloud (Decision 028).
> Streaming already goes through the shared `ResilientStreamLoader`
> (`AVAssetResourceLoaderDelegate` on the `aw-stream://` scheme, with
> resume-on-reset + storage-node failover — Decisions 021/031/034,
> `ArchiveWatch/ArchiveWatch/Networking/ResilientStreamLoader.swift`).

---

## TL;DR recommendation

- **Data model:** a small **Codable proxy-clip + project model that mirrors
  OTIO's conceptual shape** (`MediaReference{target_url, available_range}` +
  `Clip{source_range}` + `Track`/`Timeline`), with **OTIO `.otio` JSON as an
  export/interchange format**, not the in-memory store. Do NOT adopt the OTIO
  C++ library or its Swift bindings as a dependency (no-third-party-packages
  rule, C++ interop weight); replicate the *schema concepts* in pure Swift.
- **Remote export:** **do not feed remote `AVURLAsset`s to
  `AVAssetExportSession`** — it fails unreliably on remote URLs (error
  `-11800` / `-16974`) and AVMutableComposition over HTTP degenerates into
  thousands of ~64 KB range requests. Instead **pre-fetch only the needed
  in/out byte ranges into a local scratch cache** (moov-indexed range
  download — the Decision-033-v2 idea), then build the composition / run
  `ffmpeg` from cache. This also makes scrubbing and re-export cheap.
- **Top risks:** (1) `AVAssetExportSession` is unreliable on remote sources;
  (2) AVMutableComposition's tiny-chunk HTTP request pattern makes live remote
  playback of multi-clip timelines stutter; (3) archive.org `.ia.mp4` files
  are not guaranteed faststart (moov-at-end), so byte-offset seeking needs a
  moov probe before range math.

---

## 1. The non-destructive model — store edits as REFERENCES, not media

### 1.1 The principle (EDL / AAF / OTIO lineage)

A proxy clip is a **pointer + a time window**, never copied pixels. This is
exactly what an EDL (CMX 3600), AAF, FCPXML, and **OpenTimelineIO** all encode:
"the order and length of cuts and references to external media… video and audio
media are referenced externally" — OTIO does **not** embed media
([OTIO README](https://github.com/AcademySoftwareFoundation/OpenTimelineIO),
[File Format Spec](https://opentimelineio.readthedocs.io/en/latest/tutorials/otio-file-format-specification.html)).
OTIO calls itself "a modern Edit Decision List (EDL) that also includes an API."

### 1.2 OTIO's reference-and-trim shape (adopt the *concepts*)

OTIO models a clip's timing with two ranges, which map cleanly onto our
in/out-point need
([serialized schema](https://opentimelineio.readthedocs.io/en/latest/tutorials/otio-serialized-schema.html)):

- **`ExternalReference`** (subclass of `MediaReference`):
  - `target_url` — the media URL (for us: archive.org `downloadURL`).
  - `available_range` — the full extent of the source media (a `TimeRange`).
  - `available_image_bounds`, `metadata`, `name`.
- **`Clip`**:
  - `media_reference` — the `ExternalReference` above.
  - `source_range` — *which portion of `available_range` is actually cut in.*
    "The `source_range` specifies which portion of the media reference's
    `available_range` actually gets used. This creates an in/out point effect."
- **`TimeRange`** = `{ start_time: RationalTime, duration: RationalTime }`.
- **`RationalTime`** = `{ value: Double, rate: Double }` (frame-rate-aware time,
  e.g. `value=1440, rate=24` = 60 s). This avoids float-second drift —
  important when the same clip is reused across exports at different fps.

So a single proxy clip is fully described by:
`target_url` + `available_range` (full runtime) + `source_range`
(in/out window) + `name`/`tags`/`metadata`. That is the entire Feature-2
model — everything else (multi-clip timelines, transitions) is composition of
these.

### 1.3 OTIO library vs. custom Codable — RECOMMENDATION: custom Codable, OTIO as export

There IS a Swift path to OTIO:
[OpenTimelineIO-Swift-Bindings](https://github.com/OpenTimelineIO/OpenTimelineIO-Swift-Bindings)
(hybrid C++/Swift SPM package) and
[OpenTimelineIO-AVFoundation](https://github.com/Synopsis/OpenTimelineIO-AVFoundation),
which converts an OTIO `Timeline` directly into `AVComposition` +
`AVVideoComposition` + `AVAudioMix` for `AVPlayer` playback and
`AVAssetExportSession` / `AVAssetWriter` export — mapping `ExternalReference`
→ `AVURLAsset`. That is conceptually perfect for us.

**But we should NOT take the dependency**, for three reasons:
1. **No-third-party-packages rule** (CLAUDE.md, Decision tvOS app stack). The
   bindings drag in the OTIO C++ core via SwiftPM C++ interop (needs Xcode
   ≥12.3); the AVFoundation bridge is a third package on top.
2. The AVFoundation bridge "currently supports basic jump-cut editing only"
   and explicitly lacks transition/effect infrastructure — we'd outgrow it
   immediately and still own the hard parts.
3. Our model is *tiny* (a handful of structs). Reimplementing the schema in
   pure `Codable` Swift is less code than integrating C++ interop, and it lets
   us add our archive.org-specific fields (catalogItemID, node hints) without
   fighting OTIO's metadata escape hatch.

**Plan:** in-memory + on-disk store is **our own Codable model** (§4). Provide
an **`.otio` JSON exporter** (and ideally importer) so a project can round-trip
to Resolve / FCP / Premiere via OTIO's own adapters
([adapters: FCPXML, AAF, CMX 3600 EDL, …](https://github.com/AcademySoftwareFoundation/OpenTimelineIO)).
Mirror OTIO field names where practical so the export is a near-1:1 mapping.

### 1.4 How pro NLEs do proxy/optimized media + relinking (the mental model)

FCP and Premiere separate the **edit decisions** from the **media that backs
them**, and let you swap the backing media without touching the cut:

- FCP keeps **proxy** (half-res, low-bitrate) and **optimized/original**
  versions side by side; you "switch between Proxy and Original/Optimized media
  in the View menu… relinking is automatic and instant"
  ([Apple — relink](https://support.apple.com/guide/final-cut-pro/relink-clips-to-media-files-ver26f5c8c9/mac),
  [Apple — optimized/proxy](https://support.apple.com/guide/final-cut-pro/create-optimized-and-proxy-files-verb8e5f6fd/mac),
  [Frame.io guide](https://blog.frame.io/2017/05/11/ultimate-guide-to-fcp-x-proxies/)).
  Proxy "increase[s] editing performance and take[s] up considerably less
  storage" — the exact economics we want.
- The clip in the timeline is a **reference**; relinking just rebinds the
  reference to a different file on disk.

**Our analogue:** the archive.org **remote stream is the "online/original"**,
and a **locally cached range (or low-res still filmstrip) is the "proxy."** The
proxy-clip reference (§4) is the relinkable pointer. "Relink" for us = re-derive
the `currentTarget()` node from `ResilientStreamLoader`'s metadata if a node
rotates — the URL identity is stable (`archive.org/details/{id}`), only the
storage node changes (Decision 034).

---

## 2. Playing & scrubbing remote ranges (live preview)

### 2.1 The mechanism

Build an `AVMutableComposition` whose video/audio tracks are populated by
`insertTimeRange(_:of:at:)` from each clip's source `AVURLAsset`, using each
clip's `source_range` as the inserted range. Play it with `AVPlayer`. Route
**every** source asset through our existing loader via
`ResilientStreamLoader.makeAsset(for:)` (the `aw-stream://` scheme), so each
remote source gets resume-on-reset + node failover for free.

### 2.2 The remote-composition latency trap (KNOWN, measured by others)

`AVMutableComposition` over HTTP has a documented pathology: AVPlayer requests
**sequential ~64 KB byte ranges** from the underlying remote files, and "the
byte range value stays at 64k throughout playback, causing hundreds or
thousands of requests for small byte ranges… even on high-speed wifi…
extremely choppy"
([openradar 6715120](http://www.openradar.appspot.com/6715120),
[Rosberry — building a video sequencer](https://rosberry.medium.com/pitfalls-to-avoid-when-building-your-own-video-sequencer-on-ios-517e33907bbb)).
This is worse than single-file playback (which our loader already handles well)
because the composition multiplexes reads across N remote files and AVFoundation
won't read ahead generously across composition segments.

**Mitigations (in priority order):**
1. **Cache the in/out range locally first, play from cache** (§3/§5). Once a
   clip's window is in the scratch cache, the composition reads a *local* file
   and the 64 KB pathology disappears. This is the single biggest win and the
   reason the proxy-cache strategy is the foundation, not an optimization.
2. **Our loader already coalesces** to 8 MB chunks with streaming delivery and
   node pinning (Decision 031) — so even an uncached composition is far better
   than the raw-`AVURLAsset` 64 KB pattern. But it still pays per-segment
   redirect/seek cost across many clips. Treat live uncached multi-clip preview
   as "best effort," cached preview as "smooth."
3. **Single-clip trimming preview** (the common case for Feature 2 — you're
   marking in/out on ONE title) does not hit the multiplexing problem; the
   existing loader streams that fine today.

### 2.3 Responsive scrubbing across many clips

- **Cancel-on-reseek:** the default `seek(to:)` does not cancel prior seeks;
  rapid scrub queues them and lags. Use the standard *pending-seek* pattern —
  keep one in-flight seek, coalesce the latest requested time, fire the next
  when the current completes
  ([AVPlayer scrubbing gist](https://gist.github.com/shaps80/ac16b906938ad256e1f47b52b4809512)).
- **Tolerant seeks while dragging, exact on release:** scrub with non-zero
  `toleranceBefore`/`toleranceAfter` (snap to nearest keyframe — fast); set
  both to `.zero` only on the final committed in/out mark (frame-accurate but
  slow). This is the same trade the playback loader notes for tolerant seeks.
- **Filmstrip via `AVAssetImageGenerator`** (§4.2): generate thumbnails
  asynchronously with `images(for:)` / `generateCGImagesAsynchronously`,
  with generous `requestedTimeToleranceBefore/After` so thumbs snap to
  keyframes instead of forcing decodes
  ([WWDC22 — responsive media app](https://developer.apple.com/videos/play/wwdc2022/110379/),
  [generateCGImagesAsynchronously](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/generatecgimagesasynchronously(fortimes:completionhandler:))).
  Generate against the **same `aw-stream://` asset** so thumbs reuse cached
  bytes. Cache the thumbnails per clip (§4) so the library/timeline paints
  instantly on revisit.

---

## 3. Exporting a composite whose sources are REMOTE

### 3.1 The reliability problem (this is the crux)

`AVAssetExportSession` "works well on local files, but commonly encounters
errors when exporting `AVURLAsset` objects created with remote URLs. A typical
error is Code `-11800` with an underlying error code `-16974`"
([export reliability](https://medium.com/@vdugnist/how-to-cache-avurlasset-data-downloaded-by-avplayer-5400677b8b9e),
[caching during streaming preferred over remote export](https://medium.com/@vdugnist/how-to-cache-avurlasset-data-downloaded-by-avplayer-5400677b8b9e)).
Export is long-running and unforgiving — a single mid-export connection reset
or node rotation can fail the whole job, and a composite multiplies that risk
across every source. **Streaming remote assets straight through
`AVAssetExportSession` is NOT a reliable production strategy.**

### 3.2 RECOMMENDED strategy — cache the needed ranges, then export from cache

**Pre-fetch only the in/out byte ranges each clip needs into a local scratch
cache, then build the composition (or call `ffmpeg`) entirely from local files.**
This is the Decision-033-v2 "range-download just the clip window keyed on the
moov index" idea, generalized to the whole timeline.

Pipeline:
1. **Probe the moov** for each distinct source once: range-fetch the header so
   we can map time → byte offsets. archive.org `.ia.mp4` files are NOT
   guaranteed faststart, so the moov may be at the **end** — fetch the tail
   first if the front probe shows no `moov` (see §3.4).
2. **Compute the byte span** for each clip's `[in, out]` window from the moov's
   sample tables (`stco`/`co64`/`stsc`/`stsz`/`stts`/`stss`), snapping `in`
   back to the **nearest preceding keyframe** (`stss`) so the cut decodes
   cleanly. Add a small metadata/keyframe buffer (rule of thumb: ~1 MiB SD /
   2 MiB HD / 5 MiB 4K)
   ([byte budget per seek](https://www.bigbinary.com/blog/mp4_transmuxing_and_streaming_support-loom-alternative-part-3)).
3. **Range-download** that span (HTTP `Range:` GET — archive.org storage nodes
   honor ranges; this is what our loader already does) into the scratch cache,
   reusing `ResilientStreamLoader`'s resume + failover so a node reset during
   the fetch doesn't fail the export.
4. **Re-mux the window into a self-contained local clip file** with `ffmpeg`
   stream-copy: `ffmpeg -ss {in} -to {out} -i {cached-or-remote} -c copy
   -movflags +faststart out.mp4` (transmux = no re-encode, fast,
   quality-preserving)
   ([stream copy/transmux](https://www.bigbinary.com/blog/mp4_transmuxing_and_streaming_support-loom-alternative-part-3)).
   Now every source is a clean local faststart MP4.
5. **Compose + export from local files** — at this point `AVMutableComposition`
   + `AVAssetExportSession` (or `AVAssetWriter`) is on solid ground (local
   files are the case Apple's export path handles reliably), or do the final
   concat/transition entirely in `ffmpeg`.

### 3.3 ffmpeg-on-remote as an alternative (and where it fits)

`ffmpeg` can read a remote URL directly and seek with `-ss`/`-to`; with the
**input-side fast seek** (`-ss` *before* `-i`) it issues an HTTP range request
and pulls only from the seek point
([partial remote fetch with ffmpeg](https://til.simonwillison.net/macos/downloading-partial-youtube-videos),
[ranged download piped to ffmpeg](https://transloadit.com/devtips/extract-thumbnails-from-videos-in-curl/)).
This is viable for a **single-clip** export ("save this one trimmed scene")
and is the simplest possible path. Caveats:
- ffmpeg's own HTTP reader has **no resume-on-reset / node-failover** — for a
  flaky host like archive.org's rotating storage nodes, prefer routing the
  fetch through our loader/curl with `Range:` and piping into ffmpeg, OR fetch
  to the scratch cache first (§3.2) and run ffmpeg on the local file. The cache
  path is strictly more robust.
- For a **multi-clip composite**, do §3.2 per clip then a final ffmpeg
  `concat`/filtergraph — don't try to stream N remote inputs live through one
  ffmpeg invocation.

### 3.4 The faststart/moov caveat (don't assume offsets)

Byte-offset seeking requires reading the moov atom; if `moov` is at the end of
the file (not faststart), the player/our code "may open a second connection
with a `Range: bytes=…` header to skip… and retrieve the moov"
([moov placement & range seeking](https://www.mpegflow.com/topics/containers/mp4-faststart),
[progressive playback atom story](https://fabiensanglard.net/mobile_progressive_playback/index.php)).
The moov holds `stco`/`co64` (absolute keyframe pointers) needed to compute the
byte span in §3.2. **Probe moov location first; never assume front placement
for archive.org `.ia.mp4`.** (This same non-faststart reality is already a known
issue for the Apple HLS-subtitle scrubbing path — see Decision 039b note.)

---

## 4. The proxy-clip data model

### 4.1 Fields (pure Codable; OTIO-shaped)

```
ProxyClip (Codable, SwiftData @Model or struct+JSON)
  id: UUID                         // our identity
  catalogItemID: String            // archive.org details id (the stable anchor)
  sourceURL: URL                   // downloadURL (.ia.mp4) — the ExternalRef target_url
  availableRange: TimeWindow       // full source extent (OTIO available_range)
  sourceRange: TimeWindow          // in/out window actually used (OTIO source_range)
  label: String                    // user scene name
  tags: [String]                   // "scene tagged on top of archive.org"
  posterFrameTime: Double?         // chosen thumbnail time (sec)
  thumbnailRef: String?            // local cache path / asset id for the poster frame
  createdAt / modifiedAt: Date     // for last-writer-wins sync (Decision 028)
  notes: String?
  sourceMeta: [String:String]      // title, year, runtime, rights — denormalized

TimeWindow (Codable)               // OTIO TimeRange analogue
  start: Double                    // seconds (store seconds for simplicity)
  duration: Double
  // OPTIONAL: rate: Double + value-in-frames if frame-accuracy is needed later

ClipProject (Codable)              // multi-clip timeline = ordered ProxyClip refs
  id / name / createdAt / modifiedAt
  trackClips: [ProjectClip]        // ordered refs into the library
ProjectClip
  proxyClipID: UUID                // reuse across multiple exports/projects
  timelineStart: Double            // position on the composite timeline
  // per-use overrides: trim, transition-in/out, speed, caption (additive later)
```

- Use **seconds (`Double`)** for storage simplicity; add an OTIO-style
  `RationalTime` (value+rate) only if/when frame-accurate cuts across mixed-fps
  sources become a requirement. The OTIO exporter converts seconds→RationalTime
  at export time.
- `catalogItemID` + `sourceURL` together are the relink anchor: the ID is
  permanent, the node-specific URL is re-derivable via the loader (§1.4).
- A `ProxyClip` is **reusable** — referenced by many `ClipProject`s; editing a
  project never mutates the library clip.

### 4.2 Poster frame / thumbnail capture

- Capture the poster frame and a small filmstrip with `AVAssetImageGenerator`
  against the `aw-stream://` asset (reuses cached bytes; tolerant times for
  speed — §2.3). Store the poster JPEG in the app cache and reference it from
  `thumbnailRef`; persist the *time*, not just the image, so it can be
  regenerated.
- The filmstrip for the trim UI is generated lazily and cached per clip.

### 4.3 Storage: local + iCloud, no backend

- **Local:** SwiftData (`@Model`) for the library + projects, OR a plain JSON
  document per project + a library index (matches the existing JSON-first
  habit). Both are tiny — references only.
- **iCloud (Decision 028, Apple island):** sync the **annotation layer only**
  via CloudKit private DB / SwiftData+CloudKit. The records are small
  (URLs + times + tags), so this is cheap and offline-first; merge with
  last-writer-wins on `modifiedAt` (same pattern as favorites/playlists). Cached
  media bytes and generated thumbnails are **device-local, never synced** (they
  are re-derivable from the references). This keeps the "no media leaves the
  device except the user's own clip exports" posture.

### 4.4 Library UX — "scenes tagged on top of archive.org"

- The library is a grid of poster-framed proxy clips with their `label` +
  `tags`, filterable by tag / source title / catalog category. Each card =
  one reference; tapping plays the `source_range` window via the
  cache-then-stream path.
- Drag library clips into a `ClipProject` timeline to assemble; the same proxy
  clip can appear in several projects. This is the FCP "event browser → timeline"
  reference model with archive.org as the camera-original.

---

## 5. Caching + disk economics

The goal — *"far less hard drive space"* — is achieved precisely because we
**never store whole films, only the in/out byte ranges actually used.**

- **Scratch cache keyed by `(catalogItemID, byteRange)`** using the
  `AVAssetResourceLoaderDelegate` scratch-file pattern: on a data request,
  serve any overlapping already-downloaded ranges from the scratch file, fetch
  only the gaps over HTTP, append to the scratch file, and record the range in
  a sidecar index — "download each byte only one time, even across multiple app
  sessions"
  ([scratch-file caching](https://jaredsinclair.com/2016/09/03/implementing-avassetresourceload.html),
  [resource-loader caching](https://medium.com/@vdugnist/how-to-cache-avurlasset-data-downloaded-by-avplayer-5400677b8b9e)).
  Our `ResilientStreamLoader` already owns the network path and writes ranged
  data; extend it to **persist** the ranges it streams instead of discarding
  them, so trimming a clip warms the cache for that clip's export.
- **Only cache ranges in use:** the moov header (small, per source) + each
  clip's keyframe-snapped `[in,out]` window. A 90-minute film contributes only
  the few seconds you clipped.
- **Eviction:** LRU by total cache budget (e.g. a few GB ceiling). Evict whole
  per-source range files for sources not referenced by any *current* project
  first; a `ProxyClip` whose bytes were evicted is still fully valid — it just
  re-fetches its window on next play/export (references are the source of
  truth, cache is disposable). Pin ranges for clips in an open project so an
  in-progress export never has its bytes evicted.
- **Cache location:** `Library/Caches` (purgeable, never synced) — matches the
  existing catalog-DB cache discipline (Decision 017/019) and the tvOS
  writable-directory rule.

---

## Sources

- [OpenTimelineIO — GitHub (EDL-like, references external media, adapters)](https://github.com/AcademySoftwareFoundation/OpenTimelineIO)
- [OTIO File Format Specification](https://opentimelineio.readthedocs.io/en/latest/tutorials/otio-file-format-specification.html)
- [OTIO Serialized Schema (ExternalReference / source_range / available_range)](https://opentimelineio.readthedocs.io/en/latest/tutorials/otio-serialized-schema.html)
- [OpenTimelineIO-Swift-Bindings](https://github.com/OpenTimelineIO/OpenTimelineIO-Swift-Bindings)
- [OpenTimelineIO-AVFoundation (OTIO → AVComposition/AVVideoComposition/AVAudioMix)](https://github.com/Synopsis/OpenTimelineIO-AVFoundation)
- [openradar 6715120 — AVMutableComposition causes non-optimal 64k network requests](http://www.openradar.appspot.com/6715120)
- [Rosberry — Pitfalls building a video sequencer on iOS](https://rosberry.medium.com/pitfalls-to-avoid-when-building-your-own-video-sequencer-on-ios-517e33907bbb)
- [AVPlayer scrubbing (cancel-on-reseek pattern)](https://gist.github.com/shaps80/ac16b906938ad256e1f47b52b4809512)
- [Vlad Dugnist — caching AVURLAsset; remote AVAssetExportSession fails (-11800/-16974)](https://medium.com/@vdugnist/how-to-cache-avurlasset-data-downloaded-by-avplayer-5400677b8b9e)
- [Jared Sinclair — implementing AVAssetResourceLoaderDelegate (scratch-file cache)](https://jaredsinclair.com/2016/09/03/implementing-avassetresourceload.html)
- [Apple — AVAssetExportSession](https://developer.apple.com/documentation/avfoundation/avassetexportsession)
- [Apple — AVURLAsset / resource loader delegation](https://developer.apple.com/documentation/avfoundation/avurlasset)
- [Apple — generateCGImagesAsynchronously](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/generatecgimagesasynchronously(fortimes:completionhandler:))
- [WWDC22 — Create a more responsive media app](https://developer.apple.com/videos/play/wwdc2022/110379/)
- [Apple — FCP relink clips](https://support.apple.com/guide/final-cut-pro/relink-clips-to-media-files-ver26f5c8c9/mac)
- [Apple — FCP optimized & proxy media](https://support.apple.com/guide/final-cut-pro/create-optimized-and-proxy-files-verb8e5f6fd/mac)
- [Frame.io — Ultimate Guide to FCP X Proxies](https://blog.frame.io/2017/05/11/ultimate-guide-to-fcp-x-proxies/)
- [MP4 faststart / moov atom & range seeking](https://www.mpegflow.com/topics/containers/mp4-faststart)
- [Fabien Sanglard — Progressive playback: an atom story](https://fabiensanglard.net/mobile_progressive_playback/index.php)
- [BigBinary — MP4 transmuxing, range requests, byte budget per seek](https://www.bigbinary.com/blog/mp4_transmuxing_and_streaming_support-loom-alternative-part-3)
- [Simon Willison — downloading partial videos with ffmpeg -ss](https://til.simonwillison.net/macos/downloading-partial-youtube-videos)
- [Transloadit — ranged download piped into ffmpeg](https://transloadit.com/devtips/extract-thumbnails-from-videos-in-curl/)

*Cross-references: Decisions 021/031/034 (ResilientStreamLoader), 033 (Clip
Studio, range-download v2 idea), 028 (sync islands / no backend), 039b (moov
faststart note).*
