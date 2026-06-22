# Research: iOS/tvOS playback + sidecar subtitles + scrubbing

*Date: 2026-06-22. Findings cross-verified against Apple docs, WWDC, Apple developer
forums, and shipping AVPlayer subtitle libraries (sources inline).*

Two problems the owner hit while testing, both rooted in how Apple's AVPlayer treats
archive.org's progressive MP4s:

1. **~3,938 films are effectively unplayable on modern iPhone/tvOS** — their only
   derivative is `512Kb MPEG4` (MPEG-4 Part 2), or `.ogv`/`.mkv`/`.avi`.
2. **Captioned films can't scrub** (Santa Fe Trail) **and non-faststart ones can't
   start** (King Solomon's) — because we wrap the MP4 in a *single-segment HLS*
   playlist to show WebVTT captions.

The two are independent; both have a definitive fix.

---

## Part 1 — Unplayable formats (corrected by on-device evidence)

**The "4,000 unplayable" was a misdiagnosis. MPEG-4 Part 2 (`512Kb MPEG4`) DOES play
on the owner's device** — Gumbasia (320×240 MPEG-4 Simple Profile) plays correctly.
Apple dropped MPEG-4 Part 2 from the iPhone 16/17 *spec sheets*, but the **software
decoder still handles Simple-Profile MP4-container files** in practice. So the **3,913
`512kb` films need no action** — they play (slower start on non-faststart files, which
the owner explicitly doesn't mind). Faststart is a start-LATENCY optimization, not a
playability requirement.

**Only the non-MP4 containers are genuinely stuck:** `.ogv` (Theora), `.mkv`
(Matroska), `.avi`/`.divx` (DivX/XVID), and MPEG-2 (`_mpeg2video`) are not AVPlayer-
playable, and `pick_video` finds **no MP4 derivative** for them on archive.org. After
removing `.mov` (QuickTime — plays) and the 512kb files (play), this is just **16
obscure long-tail items**. They were **excluded** (so they never show a broken player).
`tools/repick_derivatives.py` re-points any such item to an MP4 derivative when one
exists (H.264 OR MPEG-4-in-MP4 — both play); the 16 simply have none.

**A mass H.264 transcode is NOT needed.** If specific notable stuck titles are wanted
later (e.g. Chaplin's *The Immigrant* 1917, which exists only as `.mkv` here), the fix
for THOSE is a small `ffmpeg -c:v libx264 -pix_fmt yuv420p -movflags +faststart …`
transcode hosted on a GitHub Release or archive.org — a per-title cleanup, not a 4,000-
film batch. Sources: [iPhone 17 specs](https://www.apple.com/iphone-17/specs/),
[archive.org H.264 derivatives](https://blog.archive.org/2013/02/09/new-mp4-h-264-derivative-technique-simpler-and-easy/) (kept for reference; the agent's "mp4v unplayable" was inferred and the device disproved it for Simple Profile).

---

## Part 2 — Subtitles + scrubbing together: the custom overlay

**The owner is right that this is not impossible** — but the native CC menu cannot do
it, and the HLS approach we shipped is the wrong tool.

**Why the current HLS path breaks (HIGH confidence):**
- AVPlayer has **no public API** to side-load a remote `.vtt`/`.srt` onto a progressive
  MP4 for the native CC menu (Apple-staff confirmed on the forums). The native subtitle
  UI only lists tracks *inside the asset* or *in an HLS manifest*.
- So we wrapped the MP4 in HLS — but the only HLS we can build from a non-fragmented
  progressive MP4 is a **single segment** (`#EXTINF:<whole film>`). HLS seeks to
  *segment boundaries*; with one segment the only seek point is t=0 → **no scrubbing**.
  And single-segment HLS must locate `moov` to start → **fails on non-faststart MP4s**.
- `EXT-X-BYTERANGE` can't rescue it: byte ranges of a progressive MP4 aren't
  independently decodable (they must start on a keyframe / carry an fMP4 init segment).
  Making it seekable means **fragmenting** the video (a remux), i.e. Part 1's hosting
  problem again.
- `AVMutableComposition` can't add a downloaded VTT as a selectable track either
  (Apple-staff: *"not possible to use AVMutableComposition to establish media selection
  groups for the subtitles"*). `textStyleRules`/`AVMediaSelectionGroup` only style/select
  tracks that already exist.

**The fix every AVPlayer-based player uses: a custom subtitle overlay.**
- Play the **bare progressive MP4** (via `ResilientStreamLoader`) — AVPlayer gives
  **full native scrubbing** on progressive MP4 (it range-requests the tail `moov` then
  seeks; our loader already serves arbitrary ranges + reports `contentLength`).
- Fetch + parse the WebVTT into a time-sorted cue list, and render the **active cue as a
  custom text view**, synced via `addPeriodicTimeObserver` (binary-search by playhead).
  This is exactly what the shipping AVPlayer subtitle libraries do
  ([mhergon/AVPlayerViewController-Subtitles](https://github.com/mhergon/AVPlayerViewController-Subtitles),
  [ASBPlayerSubtitling](https://github.com/autresphere/ASBPlayerSubtitling)); VLC/Infuse
  use their *own* decoder, not AVPlayer, so they're not our model.
- We already have the building blocks: the **Clip Studio caption overlay** (Decision
  033/037) renders timed cues over an `AVPlayerLayer`.

**Tradeoffs (accepted):**
- No native CC menu / language picker → build a minimal **CC on/off + language control**
  ourselves.
- Custom view isn't a system caption → honor the user's Settings → Accessibility →
  caption styling manually; clamp/scale for 10-foot tvOS.
- Position over **our own `AVPlayerLayer`** (not `AVPlayerViewController.contentOverlayView`
  — Decision 037 showed AVKit's gestures/timing fight an overlay there), so captions
  land inside the picture, not the letterbox bars, and fade with the transport via the
  same user-activity timer pattern Decision 037 used on web.

**This is the unifying fix:** moving captioned playback OFF the HLS path and onto
`[ResilientStreamLoader + overlay]` simultaneously restores **scrubbing**, fixes the
**non-faststart start** failures, and keeps **subtitles** — and it preserves the
Decision-021/031/034 node-failover/resume resilience that HLS threw away.

**Alternative (deferred):** server-side fMP4/CMAF remux + a real multi-segment HLS gives
the *native* CC menu + scrubbing, but it re-hosts every captioned film AND replaces our
resilient loader with AVFoundation's own (flaky on archive.org nodes). Only worth it
per-title if the native CC chrome is specifically wanted.

---

## Recommended sequencing

1. **Subtitle overlay (Apple players)** — the higher-leverage fix: it restores
   scrubbing + start for ALL captioned films AND keeps subtitles, with no hosting cost.
   Implement on a shared `AVPlayerLayer` transport for iOS + tvOS; Android/web already
   side-load VTT natively and keep both (no change).
2. **Transcode pipeline** — drain the 3,938 unplayable films (popularity-first) once the
   IAS3 keys are in CI. Independent of #1.

Both keep the catalog/data plane unchanged; #2 only rewrites `downloadURL`s as films are
transcoded. This is also the right home for **OpenSubtitles**: the same overlay renders
its cues, and the same side-load schema carries them.
