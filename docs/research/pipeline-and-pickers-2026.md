# Research: archive.org pipeline + version/track selection UX (2026-08-17)

Agent findings, condensed; sources in the full report. Feeds tasks #45/#49.

## Archive.org derivative ground truth (probed live)
- Classic film items carry: h.264 (640×480-class, ~830kbps), 512Kb MPEG4
  (320×240 — actually h.264 per project memory), Ogg. Modern derive =
  "h.264 IA" (.ia.mp4), ~1.83M items. For already-compliant sources the
  derive is a normalization/remux.
- NOTHING guaranteed: fresh uploads (derive latency hours-days),
  _rules.conf suppression, failed derives on exotic sources, dark items.
- IA's OWN player uses derivatives ONLY (verified via embed config:
  512kb="240p", h264="480p") and side-loads .asr.srt. Third-party PD sites
  embed IA's player or link derivatives; nobody transcodes.
- Re-derive via Tasks API (derive.php, same IAS3 keys) — ONLY on items the
  account owns/can edit. Rate-limited; X-Accept-Reduced-Priority queues.

## Repair-and-rehost: viable, cheap, third rung
Ladder enforced at catalog build:
1. Codec-gate every downloadURL with REAL ffprobe data (never the format
   label — "MPEG4" hides AV1).
2. Prefer IA's own derivative ladder: compliant original → h.264 IA →
   h.264 → 512Kb MPEG4.
3. Remux/re-encode + upload `archivewatch-fix-<slug>` items ONLY for the
   popular tail with neither safe original nor derivative. One film per
   item (50GB/file, 500GB/item, ≤5k files/day; over_limit backoff).
   Provenance metadata linking the source item. PD repair-reuploads are
   accepted practice; describe as repair, not mirror.
DO NOT bulk-HLS-rehost (302-per-segment, adds failure modes, solves no
codec problem). Progressive faststart MP4 + resilient delivery = the shape.

## Codec/container safety policy (catalog gate `codecSafe`)
SAFE: MP4/M4V/MOV faststart, interleave span ≤~2s; H.264 8-bit 4:2:0
  ≤High@4.1; AAC-LC/MP3; captions side-loaded VTT (never embedded mov_text).
CONDITIONAL (second rendition only): HEVC hvc1 (ATV HD + old Android shaky).
UNSAFE (repair or derivative, never ship): AV1 (no HW decode on ANY
  shipping ATV; A17 Pro/M3+ only), VP9/VP8, MPEG2, MPEG-4 Part 2, VC-1;
  MKV/WebM/AVI/OGV containers (841k+ Matroska movie items on IA!); AC-3/
  DTS/Opus/Vorbis audio.

## Version/track picker UX (all APIs tvOS 15+; app floor is 17)
- Detail: long-press Play → "Play Version" menu (Infuse pattern) + explicit
  row when >1 version. Labels: `480p · H.264 · 575 MB — Archive derivative`
  / `… — uploader original` / `… — Archive Watch repaired`. Filter unsafe
  versions per platform (never gray out).
- Persistence: global policy default (Best quality / Most compatible /
  Smallest) + PER-TITLE override (SwiftData by archiveID) — the thing Plex
  users ask for and don't get; cheap differentiation.
- In-player: transportBarCustomMenuItems = "Version" UIMenu + caption-source
  UIMenu (Published file / Auto / Off — required since the D070 overlay
  bypasses the native subtitle group). Switch = persist-then-teardown +
  resume (path exists).
- infoViewActions: "Choose Version…" beside "Play from beginning".
- contextualActions: after stall counter trips on a heavy version, offer
  "Switch to 480p version".
- customInfoViewControllers: richer Subtitles & Provenance tab (set once;
  tvOS 26 live-swap crash fixed in b6 but don't).

## Best-in-class conventions verified
Infuse: long-press Play Version; global match-device policy + per-play
override. Plex: auto most-suitable + per-play Play Version (no per-title
persistence — the gap). Jellyfin: detail-page dropdown "1080p H264". Apple
TV app: no version picker (HLS adapts). IA player: res-labeled quality menu.
