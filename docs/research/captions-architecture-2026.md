# Research: subtitle/caption architecture (2026-08-17)

Agent findings, condensed; full sources at bottom. Feeds tasks #47/#49.

## Verdicts
1. **Overlay renderer (current tvOS path) = industry standard.** Infuse, VLC,
   and Plex (MPV-based enhanced player) ALL render external subs with their
   own engine, never native AVPlayer tracks. Apple's only native answer for
   streaming is HLS renditions. Upgrade path: adopt AVCaptionRenderer
   (WWDC26-256) as the overlay's drawing layer so styling matches system
   captions exactly; MACaptionAppearance profiles + new preview APIs.
2. **No client-side playlist trick fixes single-segment buffering.** Spec
   (rfc8216bis): progressive MP4 is NOT a legal segment format; fMP4 segments
   must begin with moof; EXT-X-BYTERANGE doesn't relax that. The D070
   whole-film-buffering finding is structural. REJECTED: byteranging the
   original MP4; AVMutableComposition subtitle tracks (Apple forums: no
   media-selection groups client-side, always-on); AVPlayerItemLegibleOutput
   (read-only).
3. **Endgame = pipeline remux to single-file fMP4** (`ffmpeg -c copy -f hls
   -hls_segment_type fmp4 -hls_flags single_file -hls_time 6`): ONE contiguous
   file + EXT-X-MAP/EXT-X-BYTERANGE playlist + segmented WebVTT rendition.
   Buys: per-segment buffering (reset costs one 6s segment, not a flush),
   native CC menu + MediaAccessibility styling, AirPlay-receiver-fetchable,
   inside Apple's named envelope for tvOS 27 generated subtitles, one media
   URI (302 paid once). Costs: AVFoundation owns the connection (D021/031/034
   resilience retired on that path — mitigated by segment granularity).
   Host fMP4 as archive.org derivative (D023 covers pattern), playlists+VTT
   on Pages. Pilot top-1,000 most-watched, scenario-harness-gated.
4. **Generated captions:** WWDC26 position = automatic, NO adoption API, no
   config; named classes = HLS + file-based. Remote progressive from a
   third-party app sits in the gap — emission is opportunistic, period. Our
   scout architecture has NO public equivalent (verified absence); D058/068/
   069/071 are the state of the art. Keep engine-leads + reversible stand-down.
5. **Timing correction at scale: adopt alass (primary) + ffsubsync
   (cross-check)** replacing the SpeechAnalyzer judge for SOURCE-level fixes:
   VAD + signal alignment, NO speech models → runs on ubuntu CI (removes the
   D060/064 local-only constraint); alass handles SPLITS/segment drift (the
   progressive-drift class the constant-shift judge is blind to — His Girl
   Friday +11→+20s); ~30-60s/film; Bazarr ships ffsubsync at library scale.
   Apply only on agreement (≤0.5s delta) — precision over recall (D064).
   Disagreement/heavy splits → local SpeechAnalyzer judge (still the only
   tool that can condemn a WRONG-FILM file by content — VAD can't).
   Sync-on-ingest for new provider fetches (Bazarr's pattern). Caveat: ubuntu
   runners once failed 31/31 ffmpeg pulls of archive.org (IP throttling) —
   plan retries/audio-range extraction/self-hosted fallback.
6. **Picker UX (task #49):** transportBarCustomMenuItems (tvOS 15+) = the
   caption-source picker home — UIMenu "Subtitles" with checkmarked
   single-selection: Off / English (file) / Auto-generated. Set BEFORE
   presentation. customInfoViewControllers (tvOS 11+) for a richer
   Subtitles&Provenance tab — set once, never live-swap (tvOS 26 crash).
   AVLegibleMediaOptionsMenuController (27) only where tracks are native.

## Key sources
rfc8216bis-22 · hlsbook.net/hls-fragmented-mp4 · WWDC26-256 · WWDC25-277 ·
kanderson-wellbeats/sideloadWebVttToAVPlayer · Apple forums 16554/45060/
100733/737573/796922 · github smacke/ffsubsync · github kaegi/alass ·
SubtitleEdit discussion 8222 · Bazarr wiki · Firecore/Plex support docs
