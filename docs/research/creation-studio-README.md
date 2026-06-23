# Creation Studio (macOS) — research synthesis

The keystone digest of seven research briefs for the native macOS "Creation Studio."
Read this first; the briefs are the depth.

| # | Brief | Covers backlog features |
|---|---|---|
| 1 | [avfoundation-engine](creation-studio-avfoundation-engine.md) | 1, 3, 4, 5, 10 — the editing/render engine |
| 2 | [proxy-remote-editing](creation-studio-proxy-remote-editing.md) | 2 — proxy clips over remote archive.org |
| 3 | [nle-ux-teardown](creation-studio-nle-ux-teardown.md) | 1, 6, 10 — timeline + browser UX |
| 4 | [stock-archive-metadata](creation-studio-stock-archive-metadata.md) | 6, 8 — "Storyblocks for archive.org" |
| 5 | [supercut-subtitle-search](creation-studio-supercut-subtitle-search.md) | 8, 9 — search + the text→supercut differentiator |
| 6 | [publishing-upload](creation-studio-publishing-upload.md) | 7 — YouTube + archive.org upload |
| 7 | [macos-architecture-parity](creation-studio-macos-architecture-parity.md) | whole-app structure, parity, learning gate |

---

## The unified architecture (what the seven briefs agree on)

**One timeline model → one composition → preview and export are the same render.**
A `Timeline` of clips (each = `sourceAssetID` + `sourceRange` + `timelineRange` + per-clip
overlays/audio/effects) compiles to a single `(AVMutableComposition,
AVVideoComposition.Configuration, AVMutableAudioMix)` triple. Because `AVComposition`
*is* an `AVAsset`, the same triple feeds `AVPlayerItem` (scrub) and `AVAssetExportSession`
(render) — the user renders exactly what they previewed. Edits rebuild-and-swap
(`replaceCurrentItem`), never mutate a live composition. (Brief 1.)

**Sources are remote proxy references, not downloaded media.** A `ProxyClip` =
`catalogItemID` + `sourceURL` + `availableRange` + `sourceRange` (in/out) + `label`/`tags`
+ `posterFrameTime` — an OTIO-*shaped* custom Codable model (we emit `.otio` for
interchange but do **not** vendor the OTIO library). The library of proxy clips is the
annotation layer we own; archive.org owns the bytes. (Brief 2.)

**Library ≠ Project.** The proxy-clip **library** is app-global state (SwiftData +
iCloud, the FCP "event browser"); a **project** is a `.archiveproj` document
(`DocumentGroup`, the FCP "timeline"). This split drives the whole app shell. (Brief 7.)

**Native Mac shell, shared Swift Core underneath.** Reuse the already-extracted Core
verbatim — `CatalogDB`, `CatalogRefreshService`, `ResilientStreamLoader`, models,
networking, `CloudKitSyncService` (same CloudKit container → favorites/progress sync with
Apple TV + iPhone for free). Rebuild only the Mac-native UI: SwiftUI scenes (`WindowGroup`
browse + `DocumentGroup` editor + `Window` render queue + `Settings`), `NavigationSplitView`
sidebar, `.inspector()`, menu-bar `.commands`, `Transferable` drag-drop. The two
performance-critical surfaces drop to AppKit: the **timeline** (`NSView`+`CALayer` in
`NSScrollView` for magnification/hit-testing) and the **browser grid** (`NSCollectionView`
for reuse/prefetch/hover). (Briefs 3, 7.)

---

## The four cross-cutting decisions (these bind every feature)

1. **Cache-then-export, never stream-into-export.** `AVAssetExportSession` is unreliable
   on remote URLs (`-11800`/`-16974`). For every proxy clip, pre-fetch ONLY its
   moov-snapped in/out byte range through `ResilientStreamLoader` into a scratch cache,
   re-mux to a local faststart MP4 (`ffmpeg -c copy`), then compose/export from local
   files. This is the single biggest reliability risk and its resolution. (Brief 2.)

2. **The two-pass render is structural.** The per-frame Core Image grade and the CALayer
   overlay tool cannot share one `AVVideoComposition` (inherited Decision-033 constraint),
   so the engine needs an intermediate-render manager (grade → ProRes temp → overlay).
   Get the ordering wrong and overlays vanish or grades tint the titles. (Brief 1.)

3. **No backend — three data planes.** (a) Shared, read-only: catalog + the new **stock
   index** (`clips.sqlite`: shots + Vision tags + MobileCLIP embeddings via `sqlite-vec`)
   + the new **subtitle index** (`subtitle.sqlite`: FTS5 cues + a word-timing table) all
   published to a Release / Pages, queried on-disk natively and via WASM+Range on web
   (Decision 029 pattern). (b) User annotation layer: proxy-clip library + projects in
   SwiftData + iCloud (references only). (c) Device-local, never synced, re-derivable:
   media/range caches, thumbnails, render scratch. (Briefs 4, 5, 7.)

4. **Word-level timing reuses the subtitle work AND dodges the whisper trap.** SRT/VTT is
   line-level; isolating a single spoken word needs word timing. Recommended: Apple's
   **SpeechTranscriber/SpeechAnalyzer** (macOS 26, on-device per-word `CMTimeRange`) — but
   it *recognizes*, so validate its word stream against the **caption text we already
   hold** (token diff: keep agreeing words, drop invented ones). The caption is ground
   truth for *what was said*, the recognizer supplies *when* — which is exactly the
   Decision-039b hallucination fix applied to timing. MFA forced alignment for the rough
   audio tail. (Brief 5.)

---

## The learning gate (non-negotiable, from Decision 033)

The set passes the four-question test **only because** the two automation-heavy features
yield an **editable timeline of candidates, never a one-tap finished cut**:
- **#9 (text → supercut)**: the app does the mechanical work (search, forced-align,
  assemble a rough cut, pad boundaries to silence); the human keeps the meaningful work
  (which takes, what order, where to cut). Unmatched words become explicit editable gaps,
  never silent drops.
- **#6 (auto-tagged stock)**: auto-tags surface candidates to browse; the human chooses.

Automate the mechanical, preserve the meaningful.

---

## Recommended phasing (MVP → differentiator)

- **Phase 0 — Mac shell + parity.** App target, reuse the Swift Core, browse/play/library/
  search on Mac (shares the CloudKit container). Proves the reuse thesis. *(Brief 7.)*
- **Phase 1 — The editor spine.** Proxy-clip library, the AppKit timeline, multi-clip
  composition across titles, cache-then-export to MP4. The hardest plumbing. *(Briefs 1,2,3.)*
- **Phase 2 — Layers.** Timed text overlays (#3), audio import/record/mix (#4), multi-
  format/quality export incl. ProRes (#5). *(Brief 1.)*
- **Phase 3 — Stock archive (#6).** CI pipeline: PySceneDetect → Vision classify →
  MobileCLIP embeddings → `clips.sqlite`; the Storyblocks-style browser. *(Brief 4.)*
- **Phase 4 — Search + supercut (#8, #9).** `subtitle.sqlite` FTS5 + word-timing pipeline;
  the text→supercut generator into an editable timeline. The differentiator. *(Brief 5.)*
- **Phase 5 — Publish (#7).** archive.org IAS3 (user's keys) first; YouTube
  (OAuth+resumable) second, defaulting to Private/Unlisted until Google verification.
  *(Brief 6.)*

---

## Open questions to resolve in the binding design doc

1. **"Apple-frameworks-only" interpretation for the indices.** `sqlite-vec` (a SQLite
   extension that compiles into the SQLite the app already links) and **MobileCLIP** (a
   Core ML model, not a Swift package) are arguably within "Apple frameworks + no third-
   party *Swift packages*." Needs an explicit decision. Heavy CLI tools (ffmpeg,
   PySceneDetect, MFA) run as subprocess/CI, already blessed.
2. **YouTube verification reality.** Unverified-app uploads are forced Private + 100-user
   cap. Lead with archive.org for public sharing; treat YouTube as Private/Unlisted export.
3. **Timeline complexity level.** Brief 3 recommends CapCut-approachability (magnetic main
   track + 1–2 overlay/audio tracks, drag-trim only) for v1, deferring the ripple/roll/
   slip/slide tool suite — matches our audience (curious browsers, not pros).
4. **De-risk spikes before committing:** the SwiftUI/`NSDocument` save+security-scoped-
   bookmark seam, and the AppKit timeline scroll/zoom/hit-test prototype.

---

*Next artifacts: `docs/macOS-DESIGN.md` (binding), DECISIONS entry, and the two project
skills (`macos-creation-studio-engine`, `macos-native-app-shell`).*
