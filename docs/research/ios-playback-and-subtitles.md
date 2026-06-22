# Subtitle strategy: native HLS (proven) + sourcing beyond archive.org

*Date: 2026-06-22. Built on the configuration the owner VERIFIED working on-device,
plus sourcing research (OpenSubtitles docs cited inline).*

## What works — and it's fully native (no overlays)

**Fantastic Planet plays natively with native skip AND the native subtitle (CC)
menu.** That is the whole architecture, and it's already shipped:
- Video: the film's **H.264 `.ia.mp4`** derivative (archive.org's standardized
  faststart H.264 remux). `downloadURL = …H264.AAC.ia.mp4`.
- Subtitles: a **native HLS subtitle rendition** — `master.m3u8` with
  `#EXT-X-MEDIA:TYPE=SUBTITLES` → a WebVTT playlist (`build_subtitle_assets.py`),
  the MP4 as the video, served to `AVPlayerViewController`.
- Result: AVPlayer shows the **native CC menu**, **native scrubbing/skip**, native
  transport. Nothing custom.

**This is the target config for every captioned film. Do NOT build custom subtitle
overlays** — they're unnecessary; the native HLS path does all three.

### The one requirement: captioned films must use the H.264 `.ia.mp4` video

The HLS video segment points at `item.downloadURL`. The films that worked are on the
H.264 `.ia.mp4` derivative (Fantastic Planet). The films that broke (the now-removed
whisper set — Santa Fe Trail/King Solomon's) pointed at **raw, non-`.ia` originals**
(often non-faststart, sometimes MPEG-4-Part-2), where the single-segment HLS can't
seek / can't start.

**Action:** for any film we caption, the `subtitleHLS` video must be the H.264 faststart
derivative. Of 4,831 currently-captioned items only ~334 are on `.ia.mp4`; the rest
should be re-pointed to their `.ia.mp4` (archive.org derives one for most popular films;
the existing faststart re-pick covers this). Where no H.264 `.ia.mp4` exists, that film
is a candidate for the legacy-codec follow-up (rare) — caption it only once it has a
playable H.264. *(Note: a raw original can also be faststart H.264 and work; the safe
rule is "prefer `.ia.mp4`", not "assume non-`.ia` is broken.")*

---

## Sourcing subtitles (the actual work)

Whisper is GONE (Decision 039b — it hallucinated). Two sources remain, layered:

### 1. archive.org's own captions — the backbone (already shipped)
`enrich_subtitles.py` harvests each item's `.asr.srt`/uploader `.srt`/`.vtt`. **Best
source for PD cinema:** free, already hosted, no redistribution/ToS issue, and
**perfectly in sync** (it's the same upload we stream). ~4,800 films.

### 2. OpenSubtitles — human-quality top-up for the popular head (owner getting a key)
REST API `https://api.opensubtitles.com/api/v1` (verified against the official docs):
- **Auth:** `Api-Key` header on every request (free key from the account → API
  Consumers) + optional `POST /login` → 24h JWT to raise the download cap. Required
  `User-Agent: ArchiveWatch v…`. Read `base_url` from the login response (VIP host).
- **Search (FREE, unlimited, not quota-counted):**
  `GET /subtitles?imdb_id={tt}&languages=en&order_by=download_count&machine_translated=exclude&ai_translated=exclude`.
  Pick the top human result; prefer `from_trusted`, track `hearing_impaired`. The
  `file_id` is in `attributes.files[0].file_id` (NOT the subtitle `id`).
- **Download (quota-counted):** `POST /download {"file_id":…}` → a temporary `link` +
  `remaining` + `reset_time`; then `GET link` → SRT. Caps: **5/day anon, ~20/day free,
  ~1000/day VIP** (per authed user; 406/429 = cap hit).
- **ToS:** non-commercial use allowed + attribution back-link (we have one). **Bulk
  re-hosting subtitle files at scale is the gray area — email OpenSubtitles before a
  large sustained run.**

### Matching (precision-first)
`imdb_id` (we have ~47%) → `tmdb_id` → `query=title&year` → `moviehash` (64-bit hash of
the file's first+last 64KB; the gold standard for *sync*, and we already do ranged MP4
reads so we can compute it offline). Expect a **high no-match rate on obscure pre-1965
PD films** — OpenSubtitles indexes modern rips, not silents.

### THE correctness guard (most important finding): sync verification
PD films have many redundant scans of *different runtimes*, so a downloaded sub is often
timed to a different cut (fixed offset) or different FPS (linear drift, ~4% at 23.976 vs
25). **Cheap, decisive check (no viewing needed): parse the SRT, take the LAST cue's end
timestamp, compare to `item.runtimeSeconds`; if it deviates by >~10%, REJECT the sub.**
This auto-rejects the dominant failure mode. Pair with `moviehash` matches (perfect sync
by construction) wherever we can afford to hash.

### Other sources (ranked for pre-1965 PD)
1. archive.org ASR (backbone, in-sync). 2. OpenSubtitles (head top-up). 3. **SubDL**
(subscene's successor; 300/day anon by `imdb_id`/`tmdb_id` — a more generous second
community source to fill OS gaps). Skip YIFY/YTS (modern-release catalog, no PD),
Subscene (shut down May 2024), Wikisource transcripts (untimed prose, not captions).

---

## Strategy, ranked

1. **Keep the native HLS delivery** (it works — Fantastic Planet). Ensure captioned
   films use the H.264 `.ia.mp4` video so skip works.
2. **archive.org ASR** = the coverage backbone (in-sync, free).
3. **OpenSubtitles** = popularity-first human top-up for the head (quota makes it
   hundreds-not-thousands on free; VIP for more). Harden `opensubtitles_subtitles.py`
   with the **sync-verification guard** + a never-re-download cache + quota backoff.
4. **SubDL** = optional second community source for OS gaps.

The long tail that whisper would have (badly) filled simply stays uncaptioned until a
real sub exists — **accurate-or-none** is the owner's standard. Delivery is unchanged
across platforms: Apple = HLS rendition (native CC + skip), Android = `SubtitleConfiguration`,
web = `<track>`; OpenSubtitles/SubDL feed the SAME SRT→VTT→HLS pipeline as archive.org.
