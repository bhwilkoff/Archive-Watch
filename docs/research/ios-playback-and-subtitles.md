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

## Sourcing subtitles (the actual work) — FREE, on-demand, no bulk download

Whisper is GONE (Decision 039b — it hallucinated). **OpenSubtitles.com's API is now
effectively paid** (~20 free downloads/day), and the **full OpenSubtitles dump is 127 GB
(no disk)** — both rejected. The plan is layered, all $0:

### 1. archive.org's own captions — the backbone (already shipped)
`enrich_subtitles.py` harvests each item's `.asr.srt`/uploader `.srt`/`.vtt`. **Best
source for PD cinema:** free, already hosted, no redistribution/ToS issue, and
**perfectly in sync** (it's the same upload we stream). ~4,800 films.

### 2. SubDL + SubSource — free, on-demand top-up (`tools/free_subtitles.py`)
Per-film community APIs — tiny `.srt` each, **no bulk download**, only the matched files
hit disk. Both need a free key (gitignored `tools/subtitle_keys.env`).
- **SubDL** (PRIMARY, matches by **imdb_id** — we have ~47%): `GET
  https://api.subdl.com/api/v1/subtitles?api_key=…&imdb_id=tt…&type=movie&languages=EN`
  → JSON `subtitles[]`; each `url` is a `.zip` under `https://dl.subdl.com` holding the
  SRT. Caps: ~2,000 searches/day but **~300 downloads/day/IP** (the real limit → a slow
  trickle; run it for the imdb-having head).
- **SubSource** (WORKHORSE, matches by **title+year**): free key, **~7,200 req/day**
  (60/min) → ~2,400–3,600 films/day, so a full ~25–30k sweep is **~1–2 weeks**, not days.
  Weaker matching → the sync guard matters more here.
- Run **popularity-first**; the head is covered in a day or two, the sweep harvests
  whatever exists over ~2 weeks.
- **ToS:** free/non-commercial + attribution (we link both on About). Shipping only the
  PD-matched subset is clean.
- **Response shapes are from each provider's docs**; the harness can't reach these hosts
  (egress allowlist), so `--probe tt…` dumps the raw response to lock the parser to
  reality on the owner's Mac before a full run.

### Coverage reality (set expectations)
SubDL/SubSource index **modern releases, not obscure pre-1965 PD prints**, so expect a
**high no-match rate on the tail**. The *yield* is the limiter, not the rate: ~a week of
sweeping nets a **few thousand** subs on top of the ASR backbone, weighted to the popular
head. The long tail stays uncaptioned until a real sub exists — **accurate-or-none**.

### THE correctness guard (most important finding): sync verification
PD films have many redundant scans of *different runtimes*, so a downloaded sub is often
timed to a different cut (fixed offset) or different FPS (linear drift, ~4% at 23.976 vs
25). **Cheap, decisive check (no viewing needed): parse the SRT, take the LAST cue's end
timestamp, compare to `item.runtimeSeconds`; if it deviates by >~10%, REJECT the sub.**
Already wired into `free_subtitles.py`. This auto-rejects the dominant failure mode —
critical for SubSource's weaker title+year matching.

### Rejected sources (don't revisit)
- **OpenSubtitles.com API** — now paid / 20-dl-day cap. `tools/opensubtitles_subtitles.py`
  kept only as a tiny VIP backstop if the owner ever buys VIP; not the plan.
- **127 GB `opensubs.db` dump** (milahu/archive.org) — real timed SRT indexed to IMDb,
  but no disk. `tools/subtitle_dump_match.py` documents it (coverage probe needs only the
  294 MB `subtitles_all.txt.gz` index; extract needs the 127 GB DB) — fallback only.
- **OPUS / Helsinki-NLP corpus** — the common downloads are MT text with timing stripped;
  only `raw/en.zip` keeps timing and needs a custom parser. Not worth it.
- OpenSubtitles.org legacy XML-RPC (VIP-only since 2024), bipuldey19 scraper (dead
  mirror), Podnapisi (~33% uptime), Subscene (shut down 2024), YIFY (modern-only).

---

## Strategy, ranked

1. **Keep the native HLS delivery** (it works — Fantastic Planet). Ensure captioned
   films use the H.264 `.ia.mp4` video so skip works.
2. **archive.org ASR** = the coverage backbone (in-sync, free).
3. **SubDL** = imdb-id top-up for the head (300 dl/day/IP trickle).
4. **SubSource** = the title+year workhorse for the ~2-week full sweep (7,200 req/day).

Delivery is unchanged across platforms: Apple = HLS rendition (native CC + skip),
Android = `SubtitleConfiguration`, web = `<track>`; every source feeds the SAME
SRT→VTT→HLS pipeline as archive.org.
