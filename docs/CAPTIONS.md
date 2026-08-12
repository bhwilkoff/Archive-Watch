# Captions across Apple platforms — the binding tier model

This document resolves, per platform and OS version, which caption tiers exist,
which one a viewer gets for a given film, what they can choose, and what each
platform can never do. Quote it before changing any caption path. Every cell is
**measured**, not asserted — the audit and harnesses at the bottom re-derive it.

Decisions this document binds together: 039/039b (sources; no auto-ASR),
043 (archive ASR dropped), 054 (on-device tracks served by a loader),
058/059/060 (live transcription; tvOS has no models), 062/063 (published files
judged; system declines rough audio), 064 (fixed at source), 067 (plain-url
path for generated subtitles).

## The three tiers

| # | Tier | Source | Where it appears |
|---|------|--------|------------------|
| 1 | **Published subtitle file** | uploader files, SubDL, SubSource, viewer's own OpenSubtitles account, on-device transcription saved by "Get subtitles" | The player's native subtitle menu, all platforms, all OS versions |
| 2 | **Live on-device transcription** | `LiveCaptions` — muted scout player at 2× ahead of playback → `SpeechAnalyzer` (26+) | An overlay styled by the viewer's system caption settings; **iOS/iPadOS/macOS, and tvOS 27** (tvOS 26 has no speech models — D060; 27 ships them, measured on device — D068) |
| 3 | **System-generated subtitles** | The OS itself, 27+ ("Generated Subtitles" accessibility feature) | The player's native subtitle menu, labelled "English (US) Transcribed" |

## The matrix — what a sound-era film shows

Measured from the live catalog 2026-08-12 (`tools/audit_caption_tiers.py`):
**32,742** visible playable films — **5,718** with a published file (22.9% of
sound-era), **19,200** sound-era films with none (the tier-2/3 population),
**7,824** silent films, which are *correctly* captionless on every tier:
fabricating dialogue over a silent film is the worst outcome available (039b).

| Viewer on | Film has a published file (5,718) | Film has none (19,200) |
|---|---|---|
| tvOS 26 | native menu | **nothing** — no speech models (D060) and no OS generation |
| tvOS 27 | native menu | **our live-transcription engine** (D068 — the system's generated track is offered but never emits on this beta; a concurrent watch stands our engine down if it ever does) |
| iOS/iPadOS 26 | native menu | live transcription overlay |
| iOS/iPadOS 27 | native menu | system-generated; live transcription if the system declines |
| macOS 26 | native menu | live transcription overlay |
| macOS 27 | native menu | system-generated; live transcription if the system declines |

Two qualifiers apply everywhere:

- **The system declines audio it cannot hear well (D063).** On rough archival
  optical sound it produces *nothing* rather than guessing. Where our own
  engine exists (iOS/macOS, tvOS 27) it takes over; on tvOS 26 there is no
  fallback — a declined film there is captionless, and that is the OS's
  judgment, not a bug. Our engine attempts what the system declines and
  discards its own output when the audio defeats it too (`CaptionQuality`).
- **A published file is judged, not trusted (D062).** The first minutes are
  checked against a transcript of the actual audio; a mistimed file is shifted,
  a wrong-cut file replaced by live transcription (iOS/macOS). Files are also
  fixed **at the source** (D064) — the only route by which tvOS 26, web and
  Android ever get a corrected file.

## Which asset shape plays, and why it decides the tiers

The tier a film can reach is set **when the player item is built**, not later:

| Film state | Asset shape | Tiers reachable |
|---|---|---|
| Has published subtitles | `CaptionedHLSLoader` (Config C: playlists via custom scheme, segment direct) | Tier 1 in the native menu |
| Subtitles fetched/transcribed on device | `LocalSubtitleHLSLoader` (same shape, playlists from disk) | Tier 1 |
| No subtitles, OS 27+ | **plain `AVPlayerItem(url:)`** | Tier 3 (and tier 2 as fallback on iOS/macOS) |
| No subtitles, OS 26 | `ResilientStreamLoader` | Tier 2 (iOS/macOS); nothing on tvOS |

The plain-url row is Decision 067 and rests on a measurement that overturned
two recorded beliefs: through `aw-stream://` the system is **never even
offered** a generated track (not "offered but silent" — that reading came from
a cross-contaminated harness), and wrapping the MP4 in an HLS playlist does
**not** qualify it either. Only an ordinary URL is captioned. The cost — losing
D021/031/034 resilience on uncaptioned films — is guarded by
`CaptionStallMonitor`, which rebuilds on the resilient loader after a
persistent stall (captions lost, playback saved: the same trade captioned
films already make).

## What the viewer can choose, and where

- **Track choice** lives in the player's native subtitle menu on every
  platform: published languages, the device-saved track, and (27+) the
  system's generated track. Nothing custom to learn (D045's principle).
- **Whether captions appear at all** is the viewer's system accessibility
  preference (`MACaptionAppearanceGetDisplayType`). The app never overrides a
  viewer's selection and never selects anything for a forced-only viewer.
- **Style** (font, size, color) is the system caption style everywhere — the
  native tracks obey it natively; the live overlay reads the same settings
  (`SystemCaptionStyle`). There is deliberately no in-app style UI.
- **"Get subtitles"** on Detail (iOS/macOS/tvOS) searches the viewer's
  OpenSubtitles account, or transcribes on device (iOS/macOS, with the
  download size stated first — D054/058).
- There is deliberately **no "prefer generated over file" switch**: a human
  file beats a machine track, and when the file is *wrong* the judge already
  replaces it (D062). A toggle would duplicate an automatic decision — the
  dead-control class D056 removed once already.
- Machine-made or translated renditions we ever publish must carry
  `CHARACTERISTICS="public.machine-generated"` (± `public.translation`) so
  AVKit labels them "Generated"/"Translated" (`hls_manifests`, 4-tuple form).
  Nothing carries it today because every published track is human.

## Translated subtitles (future)

iOS/macOS 27 can translate an *existing* subtitle track on device; tvOS cannot
(transcription only). The captioned path loses no system options to its loader
(measured — direct HLS and `CaptionedHLSLoader` offer identical menus), so the
foundation is sound, but translation itself is **unverified**: a monolingual
Mac offers no translation targets. Verify on a device with a second language
configured before claiming it. Server-side translated VTTs would reach every
platform including tvOS 26 and Android — if added, they are exactly what the
`public.machine-generated,public.translation` characteristics are for.

## Auditing — re-derive this document

- **Catalog**: `python tools/audit_caption_tiers.py` (read-only; fetch first).
- **Device shape** (macOS 27): `/tmp/awsel direct && /tmp/awsel loader` from
  `tools/test_system_caption_selection.swift` — asserts the plain shape is
  captioned AND the loader is not (the negative control that keeps D067
  honest). One shape per process, always.
- **Per-shape emission**: `tools/test_generated_subtitle_shapes.swift`.
- **On the device itself**: Settings → Automatic Captions → **Caption
  Diagnostics** runs the full tier probe on-screen — the only oracle for an
  Apple TV, whose console cannot be read from a development machine.

The rule under all of it: **never conclude a caption track works because one
was offered.** Assert emitted text. That conflation has cost this app four
separate regressions.
