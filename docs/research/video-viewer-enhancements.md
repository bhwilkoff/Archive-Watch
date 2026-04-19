# Video Viewer Enhancements — Future Work

Captured 2026-04-19. The MVP player is `AVKit.VideoPlayer(player:)` wrapping a
plain `AVPlayer`. Works end-to-end; lacks the controls a cinematheque audience
will expect once the catalog is thick. Below is the roadmap for the next few
sessions, in priority order.

## 1. Closed captions / subtitles

**Why:** Accessibility-first (Decision 006's "10-foot viewing is a household
activity"), plus many Archive items have side-loaded SRT files.

**Archive side:**
- The same `ArchiveMetadataResponse.files` that powers `DerivativePicker` also
  enumerates `.srt`, `.vtt`, `.scc`, `.asrt`, and `.closedcaption` files.
- Common formats, in rough order of appearance:
  - `SubRip` (`.srt`) — most common
  - `WebVTT` (`.vtt`) — growing
  - `Scenarist Closed Captions` (`.scc`) — occasional for broadcast archive TV

**AVKit side:**
- Convert SRT → WebVTT in memory (trivial format delta: timecodes + tags).
- Wrap the primary MP4 + the VTT into an `AVMutableComposition` with a
  `AVMutableCompositionTrack(mediaType: .closedCaption)` or, simpler, expose
  the VTT as an `AVAssetTrack` of media type `.text`.
- Easiest shipping path: download the VTT, feed it via `AVPlayerItem`'s legible
  media selection group and let AVKit's subtitle menu render it.
- Respect system "Closed Captions + SDH" accessibility preference.

**Sourcing:**
- Archive first. OpenSubtitles second (free metadata API + free-tier downloads
  with rate limits — see catalog-scaling-plan source 2).
- Persistent cache in Application Support keyed on archiveID.

## 2. Playback speed

**Why:** Silent and educational shorts read better at 1.25× or 1.5× for some
viewers. Standard streaming affordance.

**AVKit side:**
- `AVPlayer.rate` accepts any positive Float. Common menu: 0.5, 0.75, 1.0,
  1.25, 1.5, 2.0.
- Snap the audio pitch with `AVPlayer.automaticallyAdjustsTimeOffsetFromLive`
  off (default for on-demand) and don't touch audio pitch correction — VOD
  auto-pitches when rate != 1.0.
- For silent films with no audio track, pitch concerns don't apply; allow
  even higher (2.5×, 3×).

**UI:** A segmented control in a `Menu` invoked by long-press on the Play/
Pause button via Siri Remote, or a bottom-sheet transport overlay.

## 3. Audio track selection

**Why:** A handful of Archive uploads include multiple language tracks (dub +
original), and international uploads frequently have English + local.

**AVKit side:**
- `AVAsset.tracks(withMediaType: .audio)` enumerates; attach as
  `AVMediaSelectionGroup` on the asset.
- AVKit renders a language switcher in the default transport UI when more
  than one audio track exists — often we get this free.

**Archive side:**
- The `files[]` array frequently has `original` MP4 + one or more derivatives.
  When two different language versions exist, they're typically separate items
  (e.g. `film_name_english`, `film_name_french`) — resolve these at catalog
  build time and link via `alternateVersions` list on the item.

## 4. Quality / bitrate selection

**Why:** On slower connections or to save bandwidth on 4K displays showing
480p originals upscaled.

**AVKit side:**
- Already mostly handled by AVKit's default UI when using HLS. For direct MP4
  download URLs (what Archive serves), we'd need to:
  - Enumerate `files[]` filtering video tier 1–7, each becomes a "quality"
    option.
  - Present user-selectable in a Menu: "High (h.264 MP4, 1.1 GB)",
    "Medium (MPEG-4, 460 MB)", "Low (512Kb MPEG-4, 160 MB)".
- Persist choice keyed on archiveID so re-watches resume at same tier.

## 5. Black-and-white enhancement filter

**Why:** Pre-1930s nitrate prints on modern HDR OLED read as flat, gray, and
murky. A cinematheque-grade display filter would contribute directly to the
"make the archive watchable" mission.

**AVKit side:**
- Attach an `AVVideoComposition` with a `CIFilter` stack:
  - `CIColorControls` — increase contrast ~1.15, saturation = 0 (already
    B&W but some prints leak color casts we don't want), brightness ±0.02.
  - `CIHighlightShadowAdjust` — lift shadows ~0.15, reduce highlights ~0.1
    to recover detail in blown-out nitrate.
  - `CIUnsharpMask` — radius 2, intensity 0.3 for controlled sharpening.
  - Optional `CIToneCurve` with a mid-gray S-curve for that "restored print"
    look.
- Three presets: **Off** (native Archive), **Restored** (current-day home
  viewer), **Nitrate** (exaggerated for 10-foot living-room).
- Default: **Restored** for items with `contentType == .silentFilm` or
  `year < 1960`; **Off** for everything else.
- Performance: `CIContext` on the Metal backend on A13+ devices handles 1080p
  in real time without dropping frames. Apple TV 4K (2nd/3rd gen) are fine.

**UI:** A tasteful eye-icon in the player overlay opens the "Display" menu.

## 6. Chapters

**Why:** Some Archive uploads mark chapter points, especially multi-reel
features.

**AVKit side:**
- `AVPlayerItem` exposes `chapterMetadataGroups`. The chapter menu appears in
  AVKit's default transport UI whenever metadata is present.
- No Archive-side sourcing — it's file-embedded. Detection is automatic.

## 7. Picture-in-picture (iPhone/iPad companion)

**Why:** Out of scope for v1 tvOS-only, flagged for the eventual iPad viewer.

## Implementation sequence

1. **CC/Subtitles** (biggest impact; no dependencies) — one sprint.
2. **B&W enhancement filter** (differentiator; matches editorial voice) — one
   sprint; include as default-on for silent/pre-1960.
3. **Playback speed** (simple; ship with CC) — part of the CC sprint.
4. **Quality selection** (requires catalog-side work to enumerate tiers) —
   needs builder changes to emit the full derivative list, not just the
   chosen pick. Medium sprint.
5. **Audio track selection** (rare; do when a user asks) — deferred.
6. **Chapters** (auto when present; no work) — already happening once
   `AVPlayerItem` transport is adopted.

## Not-doing list

- Network DRM integration (no DRM on Archive content — irrelevant).
- External trickplay sprite sheets (Archive doesn't produce these).
- Cloud sync of watch progress (Decision 009 — local only).
- Real-time translation (no stable free API that isn't OpenAI-scale; revisit
  when Apple's on-device translation API covers tvOS).
