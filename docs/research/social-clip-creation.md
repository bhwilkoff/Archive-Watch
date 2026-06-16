# Research: Social-Media Clip Creation from Archival Film

*Compiled 2026-06-15. Scope: technical specs + craft/culture for a feature that lets
Archive Watch users clip public-domain archive.org films into social-media-ready
content. All figures current as of 2025–2026; source URLs inline.*

This brief answers two questions for the content-creation feature:

1. **What are the format/spec targets** a clip exporter must hit per platform
   (video, GIF, captions, vertical reframing, watermarking)?
2. **How are "fan edits" made and shared today** — the craft, the culture, and the
   minimum feature set that delivers the most creative value?

A sourcing caveat that runs through Topic 1: the platforms publish almost no exact
bitrate/file-size tables. **YouTube is the only platform with an authoritative,
published recommended-encoding table.** For TikTok, Meta, and X, the load-bearing
numbers come from reputable creator-tool publishers (Sprout Social, Hootsuite,
HeyOrca) that test against the live apps. Numbers conflict across sources where the
platform doesn't define them; conflicts are flagged.

---

# TOPIC 1 — Social-media video / GIF formats and specs (2025–2026)

## 1.1 The cross-platform safe encode (start here)

If we export ONE master that works almost everywhere:

- **Container:** MP4
- **Video codec:** H.264 (High Profile) — HEVC/H.265 is accepted on TikTok and inside
  the Apple ecosystem but H.264 is the universal floor
- **Audio codec:** AAC, 48 kHz, ≥128 kbps stereo
- **Resolution:** 1080×1920 (9:16) for vertical; 1080×1350 (4:5) for IG/FB feed;
  1920×1080 (16:9) for X
- **Frame rate:** 30 fps (match source; 24/25/60 also fine)
- **Bitrate:** ~8 Mbps for 1080p is the safe target (YouTube's official 1080p number)

**9:16 (1080×1920) is the universal vertical default** for TikTok, IG Reels/Stories,
YouTube Shorts, and Facebook Reels. **4:5 (1080×1350)** is preferred for Instagram and
Facebook *feed* posts. **16:9 (1920×1080)** remains the X/Twitter default.

## 1.2 Per-platform video specs

### TikTok
| Spec | Value |
|---|---|
| Aspect ratio | **9:16 preferred** (full-screen); 1:1 and 16:9 supported (letterboxed) |
| Resolution | **1080×1920** |
| Duration | ~3 s min; **10 min** in-app; **60 min** via web/TikTok Studio |
| Max file size | **287.6 MB (iOS)**, **72 MB (Android)** in-app; up to **4 GB** via web |
| Codec / container | H.264 (HEVC ok) / MP4·MOV·WEBM, AAC |
| Frame rate | 30 (23–60 supported) |
| Bitrate | 8–12 Mbps for 1080p |

Sources: [Stack Influence](https://stackinfluence.com/tiktok-video-sizes-the-ultimate-2025-guide/) ·
[Sprout Social](https://sproutsocial.com/insights/social-media-video-specs-guide/) ·
[Metricool](https://metricool.com/tiktok-video-length/)
*(Sprout cites a 1 GB in-feed cap — the iOS/Android/web split above is the more current breakdown.)*

### Instagram Reels
| Spec | Value |
|---|---|
| Aspect ratio | **9:16 preferred** (1.91:1 accepted) |
| Resolution | **1080×1920** (no 4K) |
| Duration | 3 s min; **~3 min in-app** (raised from 90 s, Jan 2025); **~15 min via upload** |
| Max file size | **4 GB** |
| Codec / container | H.264 / MP4·MOV, AAC |
| Frame rate | 30 (23–60) |
| Bitrate | 3.5–5 Mbps |

Sources: [Hootsuite](https://blog.hootsuite.com/instagram-video-sizes/) ·
[Social Media Today — Reels to 3 min](https://www.socialmediatoday.com/news/instagram-officially-expands-reels-length-3-minutes/737766/)

### Instagram Feed (video)
| Spec | Value |
|---|---|
| Aspect ratio | **4:5 preferred** (most mobile real estate); 1:1, 1.91:1 supported |
| Resolution | **1080×1350** (4:5) or 1080×1080 (1:1) |
| Duration | 3 s to up to 60 min |
| Max file size | **4 GB** |
| Codec / container | H.264 / MP4·MOV, AAC |
| Frame rate | 30 (23–60) |

*(Note: feed videos are auto-classified as Reels and follow Reels' discovery behavior.)*
Sources: [Hootsuite](https://blog.hootsuite.com/instagram-video-sizes/) ·
[Sprout Social](https://sproutsocial.com/insights/social-media-video-specs-guide/)

### Instagram Stories
| Spec | Value |
|---|---|
| Aspect ratio | **9:16 preferred** |
| Resolution | **1080×1920** (min width ~500 px) |
| Duration | **1–60 s per segment**; longer is auto-split |
| Max file size | 4 GB per segment |
| Codec / container | MP4, MOV (GIF accepted) |
| Frame rate | 30 (23–60) |

Sources: [Hootsuite](https://blog.hootsuite.com/instagram-video-sizes/) ·
[Sprout Social](https://sproutsocial.com/insights/social-media-video-specs-guide/)

### YouTube Shorts
| Spec | Value |
|---|---|
| Aspect ratio | **9:16 preferred**; ≤16:9 vertical to qualify for the Shorts shelf |
| Resolution | **1080×1920** (4K vertical accepted; 1080p is the sweet spot) |
| Duration | up to **3 min (180 s)** since Oct 2024 (was 60 s) |
| Max file size | account limit (up to 256 GB); practically gated by the 3-min length |
| Codec / container | H.264 High Profile / MP4·MOV·WebM, AAC-LC or Opus @ 48 kHz |
| Frame rate | 24/25/30/48/50/60 |
| Bitrate (official, SDR, 24–30 fps) | **1080p: 8 Mbps**; 720p: 5 Mbps; 4K: 35–45 Mbps; HDR 1080p: 10 Mbps; audio 384 kbps stereo |

*Copyrighted music in Shorts is limited to 60 s; Shorts >60 s must use cleared/royalty-free audio — relevant because our content is PD but user-added music may not be.*
Sources: [YouTube Help — recommended encoding (official)](https://support.google.com/youtube/answer/1722171) ·
[vidIQ](https://vidiq.com/blog/post/youtube-shorts-vertical-video/)

### X / Twitter
| Spec | Value |
|---|---|
| Aspect ratio | **16:9 recommended**; supports 9:16, 1:1, range 1:2.39–2.39:1 |
| Resolution | **1920×1080 recommended**; 1280×720 common for free tier |
| Duration | **Free: 140 s (2:20)**; Premium: up to 2 h @ 1080p; Premium+: up to 4 h |
| Max file size | **Free: 512 MB**; Premium+: up to **16 GB** |
| Codec / container | H.264 / MP4·MOV, AAC 128–256 kbps |
| Frame rate | 30 (≤60) |
| Bitrate | 2–5 Mbps |

Sources: [HeyOrca](https://www.heyorca.com/blog/x-twitter-media-specs-best-practices-2026) ·
[Highperformr](https://www.highperformr.ai/blog/twitter-video-length-limit)

### Facebook (Feed + Reels)
**Major 2025 change (June 17, 2025):** Meta announced *all* Facebook videos are now
published as Reels with **no length or format/orientation caps** (the old 90-second
Reels limit is being removed; the "Video" tab is renamed "Reels"). Spec guidance is in
transition; numbers below are current best practice.

| Spec | Feed | Reels |
|---|---|---|
| Aspect ratio | **4:5 preferred** (1080×1350); 16:9, 1:1 supported | **9:16 preferred** (min 4:5) |
| Resolution | 1080×1350 or 1280×720 | **1080×1920** (min 720×1280) |
| Duration | caps being removed (all video → Reels) | 90-s cap removed June 2025; 15–60 s performs best |
| Max file size | ~4 GB (Sprout cites 3 GB for older feed video) | ~4 GB |
| Codec / container | H.264 / MP4·MOV, AAC ≥128 kbps | MP4; H.264 + AAC |
| Frame rate | 30+ | 30+ |

Sources: [TechCrunch — all FB video → Reels (June 17, 2025)](https://techcrunch.com/2025/06/17/facebook-announces-that-all-videos-on-its-platform-will-soon-be-shared-as-reels) ·
[Sprout Social](https://sproutsocial.com/insights/social-media-video-specs-guide/)

## 1.3 Comparison summary table

| Platform | Preferred ratio | Rec. resolution | Min–Max duration | Max file size | Codec/container | Frame rate | Bitrate |
|---|---|---|---|---|---|---|---|
| TikTok | 9:16 | 1080×1920 | ~3 s – 10 min (app) / 60 min (web) | 287.6 MB iOS / 72 MB Android / 4 GB web | H.264 (HEVC) / MP4·MOV·WEBM, AAC | 30 (23–60) | 8–12 Mbps |
| IG Reels | 9:16 | 1080×1920 | 3 s – ~3 min (app) / ~15 min (upload) | 4 GB | H.264 / MP4·MOV, AAC | 30 (23–60) | 3.5–5 Mbps |
| IG Feed | 4:5 | 1080×1350 | 3 s – up to 60 min | 4 GB | H.264 / MP4·MOV, AAC | 30 (23–60) | 3.5–5 Mbps |
| IG Stories | 9:16 | 1080×1920 | 1–60 s per segment | 4 GB | H.264 / MP4·MOV·GIF, AAC | 30 (23–60) | 3.5–5 Mbps |
| YT Shorts | 9:16 | 1080×1920 | up to 3 min (180 s) | account limit | H.264 / MP4·MOV·WebM, AAC/Opus | 24/25/30/48/50/60 | 8 Mbps (official) |
| X / Twitter | 16:9 | 1920×1080 | 0.5 s – 2:20 (free) / up to 2–4 h (Premium) | 512 MB free / 16 GB Premium+ | H.264 / MP4·MOV, AAC | 30 (≤60) | 2–5 Mbps |
| FB Feed | 4:5 | 1080×1350 | caps being removed | ~4 GB | H.264 / MP4·MOV, AAC | 30+ | audio ≥128 kbps |
| FB Reels | 9:16 | 1080×1920 | 90-s cap removed; 15–60 s best | ~4 GB | H.264 / MP4, AAC | 30+ | — |

## 1.4 GIF best practices

### Giphy (the authoritative spec)
- File size: **100 MB** upload limit; **≤8 MB recommended**
- Frame rate: **15–24 fps**
- Frame count: **<200 frames** total (Giphy's stated guidance; constrains duration × fps)
- Duration: up to **15 s** allowed; **≤6 s recommended**
- No single hard max-dimension published — Giphy generates renditions server-side; minimize frame count

Source: [GIPHY — GIF Creation Best Practices](https://support.giphy.com/hc/en-us/articles/360019914771-GIF-Creation-Best-Practices)
*(Giphy's page 403s to bots; specs corroborated by [FastMakerGIF](https://fastmakergif.com/blog/best-gif-sizes-social-media) and [Giphy's API repo](https://github.com/Giphy/GiphyAPI/issues/81).)*

### General social-media GIF guidance
- **Dimensions:** 1280×720 (16:9) landscape; 720×720 or 1080×1080 (1:1) square; target <~3 MB
- **Frame rate:** 15–20 fps (10–12 for email)
- **Duration:** 2–4 s ideal for feeds
- **Looping:** GIFs loop infinitely by default; design a **seamless loop** (last frame → first frame cleanly). For boomerang/ping-pong, bake the reverse frames in — most platforms ignore explicit GIF loop counts.

Sources: [FastMakerGIF — sizes](https://fastmakergif.com/blog/best-gif-sizes-social-media) ·
[FastMakerGIF — frame rate/duration](https://fastmakergif.com/blog/gif-frame-rate-duration-best-practices) ·
[SVGator](https://www.svgator.com/blog/animated-gif-best-practices-to-optimize-gifs-like-pros/)

### GIF file-size ceilings per platform
| Platform | Limit | Notes |
|---|---|---|
| Giphy | 100 MB upload (8 MB rec.) | renditions generated server-side |
| X / Twitter | **5 MB mobile / 15 MB web** | rec. 1200×675 or 800×800, ~20 fps; **X converts GIFs to MP4** |
| iMessage (Tenor) | upload 5 MB; keep sent GIFs **<~600 KB** | avoids carrier transcoding |
| Instagram | ~8 MB | no native GIF feed post — GIFs only as Giphy *stickers* in Stories/Reels/DMs |
| Facebook | ~8 MB | 1200×630, 15 fps |
| Discord | 8 MB free / 50 MB Nitro | custom emoji 256 KB @ 128×128, ≤50 frames |
| Slack | 5 MB | custom emoji 128 KB @ 128×128 |

Sources: [GIFLance 2025](https://www.giflance.com/blog/optimization-guides/complete-gif-optimization-guide-2025) ·
[GIFDB](https://gifdb.com/gif-format-guide/gif-size-limits-social-media/) ·
[Challix iMessage](https://challix.com/blogs/guides/how-to-use-and-send-gifs-on-imessage)

### Where GIFs still live (2025–2026)
- **Messaging is the GIF stronghold:** iMessage (Tenor keyboard in the OS), Slack, Discord, WhatsApp, SMS/RCS — where the GIF *format* is still natively sent and looped.
- **Tenor (Google) and Giphy** dominate the libraries integrated into keyboards/composers.
- **X** keeps a GIF composer button but serves MP4. **Instagram** uses GIFs only as stickers.

### WebP vs GIF vs MP4
- **File size:** GIF → lossy WebP cuts size **~64% on average**; lossless WebP is **~19% smaller** than GIF. (Example: 2.26 MB GIF → ~740 KB WebP, no perceptible loss.)
- **Quality:** GIF = 256 colors, 1-bit transparency. **WebP = 16.7M colors, 8-bit alpha** (semi-transparent edges/fades).
- **Support:** WebP is native in all major browsers (2025). **GIF still wins universal support** across messaging/email — why it persists in chat.
- **MP4 displacing GIF:** X converts uploaded GIFs to MP4 (an MP4 can be ~10× smaller than the equivalent GIF). Platforms accept a GIF at the composer, then store/serve video.
- **When to use which:** GIF for messaging/email or any surface where WebP/MP4 isn't guaranteed; WebP for web/app embeds you control; MP4/H.264 for true social-feed video.

Sources: [Cloudinary — GIF vs WebP](https://cloudinary.com/guides/image-formats/gif-vs-webp) ·
[WEBP-to-PNG — animated images 2025](https://webp-to-png.tools/blog/animated-images-in-2025-webp-vs-apng-vs-gif-real-world-use-cases/)

## 1.5 Captions / subtitles & why burned-in matters

### Sound-off viewing statistics (attribute carefully)
- **Facebook: ~85%** of users watch video with sound off (Facebook internal stat — this is the source of the famous "85%", **not** the Verizon study).
- **Verizon Media + Publicis Media study (April 2019, n=5,616 US adults 18–54)** — still the most-cited primary research:
  - **69%** watch video without sound in public
  - **80% more likely to finish a video** when captions are available
  - **50%** say captions are important / usually watch sound-off
  - Open captions on mobile ads drove **+8% ad recall, +10% memory quality, +13% brand linkage**
- **~75%** watch mobile video on mute (Sharethrough/Digiday), **~85% among Millennials**
- **~80% of caption users are NOT deaf/HoH** (Ofcom — commonly miscited to Verizon)

Sources: [3Play Media — Verizon/Publicis](https://www.3playmedia.com/blog/verizon-media-and-publicis-media-find-viewers-want-captions/) ·
[Digiday — 75% on mute](https://digiday.com/sponsored/75-percent-of-people-watch-mobile-videos-on-mute/)
*Defensible headline figures: "up to 85% of social video is watched without sound" (Facebook) + the Verizon/Publicis 2019 numbers, kept separately attributed. The Verizon study is now 6 years old.*

### Why burned-in (open) captions matter
- Most feeds autoplay muted — captions are the only way the message lands; the **80%-completion** lift and **+8–13% ad metrics** are the core engagement argument.
- **Burned-in survives re-uploads/re-renders** across TikTok/Reels/Shorts and renders identically on every device — no reliance on a platform caption toggle (often off by default) that can be stripped on embeds.
- For full accessibility, pair burned-in (open, non-toggleable) captions with a real closed-caption track (.srt/.vtt) where the platform supports it.

Sources: [Pixflow — AI captions 2026](https://pixflow.net/blog/ai-automatic-captions-subtitles/) ·
[Manchester Digital — Mute is the New Norm](https://www.manchesterdigital.com/post/title-productions/mute-is-the-new-norm-why-captions-win-in-2025-video)

### Safe zones for 9:16 vertical (1080×1920)
Regions NOT covered by platform UI (caption box, username, audio bar, like/comment/share rail, progress bar). Conservative 2025–2026 consensus; platforms move UI often (both IG Reels and YT Shorts *enlarged* bottom UI in late 2025).

| Platform (1080×1920) | Top margin | Bottom margin | Right margin (action rail) |
|---|---|---|---|
| TikTok | ~108–130 px | ~250–320 px | ~120 px |
| Instagram Reels | ~108–220 px | ~320–420 px (audio bar grew ~+50 px late 2025) | ~60 px |
| YouTube Shorts | top ~10% clear | bottom ~10–15% clear | right side for buttons |

**Cross-platform safe rule of thumb:** keep all captions/text within the **central ~80% vertically and ~90% horizontally** — leave roughly **~12% (~220 px) clear at top, ~22% (~420 px) clear at bottom, ~10–15% clear on the right**. Designing to IG Reels' largest margins keeps you safe on TikTok and Shorts too.

Sources: [Kreatli — Safe Zone Hub](https://kreatli.com/guides/safe-zone-guide) ·
[Zeely — TikTok safe zones](https://zeely.ai/blog/tiktok-safe-zones/) ·
[Postplanify — safe zones 2026](https://postplanify.com/blog/social-media-safe-zones-2026-complete-guide)

### Auto-caption accuracy norms (clear audio)
- Whisper-based (Subtitle Edit + Whisper): ~98% · YouTube Studio: ~95% · browser editors (VEED/Kapwing/Flixier): ~75–85%
- Best practice: auto-generate, then human-review (ASR errors on names, jargon, accents — relevant for old archival audio with period diction/noise)
- **Caption style for muted feeds:** large bold sans-serif, high contrast (white + dark stroke/shadow or semi-opaque box), 1–2 lines at a time, word/phrase-level highlighting ("karaoke" style is now dominant), inside the safe zone.

Sources: [Pixflow](https://pixflow.net/blog/ai-automatic-captions-subtitles/) ·
[Maestra — AI subtitle generators 2026](https://maestra.ai/blogs/best-ai-subtitle-generators)

## 1.6 Adapting wide/old archival footage into 9:16 vertical

This is the single most Archive-Watch-specific section: our source is 4:3 academy
silents and 16:9 widescreen, and the target is 9:16. Definitions first:

- **Letterboxing** = bars top/bottom; content **wider** than the frame (16:9 in a narrow frame).
- **Pillarboxing** = bars left/right; content **narrower** than the frame (4:3 in a wide frame).
- **Windowboxing** = bars on **all four sides** — exactly what 4:3 academy footage does in a 9:16 frame with no crop/fill.

Sources: [wolfcrow](https://wolfcrow.com/pan-and-scan-process-vs-letterboxing-pillarboxing-and-windowboxing/) ·
[Wikipedia: Pillarbox](https://en.wikipedia.org/wiki/Pillarbox)

### The blurred-background fill ("blur-pad") — recommended default
Instead of black bars, fill the empty vertical space with a scaled-up, heavily blurred
copy of the *same* footage, with the sharp original centered on top.

**Two-track recipe (NLE/CapCut):**
- Background: horizontal clip scaled to fill 1080×1920, **Gaussian blur radius ~40–80**
- Foreground: original at 95–100% scale, centered
- Optional polish: foreground opacity 70–85%, subtle vignette on the blurred plate

**FFmpeg filter chain (for an automated/server-side pipeline — fits our tooling):**
```
split[original][copy];
[copy]scale=ih*16/9:-1,crop=h=iw*9/16,gblur=sigma=20[blurred];
[blurred][original]overlay=(main_w-overlay_w)/2:(main_h-overlay_h)/2
```

Sources: [edicionvideopro — 9:16 guide](https://edicionvideopro.com/en/editing-techniques/916-aspect-ratio-guide-vertical-video-for-tiktok-reels/) ·
[junian.dev — FFmpeg vertical blur](https://www.junian.dev/tech/ffmpeg-vertical-video-blur/) ·
[FlexClip](https://www.flexclip.com/learn/fill-in-sides-of-vertical-video.html)

### Crop vs. fit-with-blur tradeoffs
| Approach | Best when | Limit |
|---|---|---|
| Crop/scale into frame | subject centered / occupies ~1/3 of width | **hard cap ~200% scale** before visible pixelation; loses frame edges |
| Fit + blur fill | action spans full width; zero content loss; protect resolution | original occupies only the center band (smaller subject); sloppy blur looks lazy |

**Archival-specific caution:** old scans are low-res, so the **200% scale ceiling is
hit fast** — favor **fit + blur** over aggressive crop to protect quality. 4:3 silents
are the windowbox case: blur-plate fill preserves the original composition far better
than cropping. No mainstream tool ships a dedicated 4:3→9:16 recipe (they assume 16:9
source) — this is a manual/FFmpeg decision.

### Auto-reframe / content-aware reframing
- **Adobe Premiere Auto Reframe** (Sensei AI): subject-tracking, targets 16:9/1:1/9:16.
- **CapCut Auto Reframe / Smart Crop**: AI motion-tracking (now behind CapCut Pro).
- **DaVinci Resolve Smart Reframe**: equivalent.
- **Caveat:** built for single-subject modern footage. For wide multi-subject newsreels,
  crowd scenes, or silent films, auto-reframe "swims" or picks the wrong subject — fall
  back to blur fill or keyframed crops.

Sources: [Adobe — Auto Reframe](https://helpx.adobe.com/premiere/desktop/add-video-effects/commonly-used-effects/auto-reframe-overview.html) ·
[CapCut — Auto Reframe pricing](https://www.capcut.com/help/why-do-i-have-to-pay-for-auto-reframe)

## 1.7 Watermarking & attribution conventions

### Watermark placement (concrete numbers)
- **Placement:** bottom-right is the convention; **but for 9:16 the bottom and right edges carry the most platform UI**, so an **upper-corner** watermark is often safer on vertical.
- **Opacity:** consensus working range **~50–70%** (30–60% called the sweet spot; ~70% "noticeable without dominating").
- **Size:** **5–10% of screen area**; ~100×100 to 200×200 px on 1080p; a transparent PNG ~150×150 px is a cited default.

Sources: [Zight — watermark best practices](https://zight.com/blog/best-practices-for-video-watermark-design/) ·
[imagitool](https://imagitool.com/blog/best-watermark-placement-spots)

### Competitor-watermark penalties (well-sourced — matters for cross-posting)
- **Your own logo is fine.** Instagram chief Adam Mosseri (Oct 23, 2024): *"If it's your own logo, don't worry about it."*
- **Competitor watermarks are deprioritized.** Reels carrying *other apps'* logos (TikTok, Shorts, CapCut) are kept out of Explore/recommendations (penalty instituted 2021, reaffirmed 2024).
- **Cross-platform:** YouTube Shorts also suppresses watermarked content.
- **Broader crackdown:** by July 2025 Meta added formal **unoriginal-content** penalties (demonetization + reduced reach) compounding the watermark penalty for lazy reposts.
- **Implication for us:** the exporter should brand only with the user's/our own mark — never emit anything that looks like a competitor watermark.

Sources: [Social Media Today — Mosseri clarification](https://www.socialmediatoday.com/news/instagram-clarifies-including-your-own-logo-on-a-reel-is-ok/730852/) ·
[Stack Influence](https://stackinfluence.com/video-content-optimization-in-2025/) ·
[ALM Corp — Meta original-content rules 2026](https://almcorp.com/blog/meta-original-content-rules-2026-facebook-instagram-creators/)

### Attribution for archival footage (maps to our existing source-credit discipline)
- **Documentary fair-use standard:** attribute via **on-screen identification OR final credits**; identify the copyright owner of the material used.
- **Standard credit format:** owner, title, production year, source.
- **Internet Archive / Prelinger norm (directly relevant):** attribution is **requested but NOT required** — *"We would appreciate attribution or credit whenever possible, but do not require it."* Suggested lines:
  1. *"Archival footage supplied by Internet Archive (at archive.org) in association with Prelinger Archives"*
  2. *"Archival footage supplied by Internet Archive (at archive.org)"*
  3. *"Archival footage supplied by archive.org"*
  (Caveat: the *films* are free, but Prelinger/Getty *metadata* — descriptions/shotlists — is copyrighted and not for commercial reuse.)
- **Belt-and-suspenders convention:** a brief on-screen source line (in the safe zone, so it survives reshare) **plus** a fuller credit + link in the caption.

Sources: [CMSI — Documentary Statement of Best Practices in Fair Use](https://cmsimpact.org/code/documentary-filmmakers-statement-of-best-practices-in-fair-use/) ·
[Internet Archive — Prelinger help](https://help.archive.org/help/prelinger-archive/) ·
[NYU — Creative Reuse guide](https://guides.nyu.edu/creative-reuse)

---

# TOPIC 2 — How "fan edits" are made and shared (craft + culture)

## 2.1 What a modern "edit" is (two distinct things)

**A. The classic feature-length fan edit (re-cut of a movie).** A viewer-modified
version of a film that removes/reorders/adds material — an unofficial director's cut
built from home-video footage. Popularized by **The Phantom Edit (2000)** (Mike J.
Nichols's recut of *Star Wars: Episode I*). Community hub: **fanedit.org**. Long-form,
single-work transformations of *copyrighted* studio films — and legally sensitive
(fanedit.org was briefly shut in 2008 after MPAA complaints). **Not** our use case
directly, but the cultural ancestor.

**B. The modern social-media "edit" (the dominant 2024–2026 meaning).** *The Harvard
Crimson* (Nov 2024) defines edits as "clips of films, TV shows, and other media...
assembled by editors into short, eye-catching montages paired with music," valued as
"a different art form" for the editor's "personal touches and nuance." Defining traits:
- Short montage (**8–30 s**; 15–30 s performs best)
- **Beat-synced cutting** — cuts/transitions land on the musical beat (the core mechanic)
- The **"edit aesthetic"** — fast cuts, thumping soundtrack, glowing filters, "fancam energy"
- **Coloring/grading and overlays** as a signature creative layer

**Evolution:** feature recuts (2000s) → AMVs / K-pop **fancams** (late 2010s) → the
TikTok "edit" (2020s), now covering film/TV characters, athletes, politicians, and even
oneself. Commercialized: **Hollywood now pays teen editors up to ~$20,000** for
TikTok-style edits boosting trailers.

Sources: [Harvard Crimson (2024)](https://www.thecrimson.com/article/2024/11/12/tiktok-fan-edit-think-piece/) ·
[Wikipedia: Fan edit](https://en.wikipedia.org/wiki/Fan_edit) ·
[Wikipedia: The Phantom Edit](https://en.wikipedia.org/wiki/The_Phantom_Edit) ·
[Transformative Works & Cultures](https://journal.transformativeworks.org/index.php/twc/article/view/575) ·
[AOL/WaPo — Hollywood pays teen editors](https://www.aol.com/articles/why-hollywood-paying-17-old-102101156.html)

## 2.2 Creation workflow and which features matter most

Canonical workflow:
1. **Choose audio FIRST.** Import the song/trending sound; mark 1–2 s beat points. Audio is the skeleton.
2. **Trim & assemble the "spine cut."** ~25–30 s, clips on the beats, every pause trimmed. Frame-level trim/split.
3. **Beat-sync cuts/transitions.** They land on beats; CapCut auto-detects beats and places markers.
4. **Add overlays/text/motion** after the spine clicks.
5. **Color grade ("coloring").** Match shots; a sub-craft distributed as shareable PSDs/presets (own credit norm: "CC").
6. **Speed ramps / time-remapping.** Slow-mo, "velocity edits" (keyframed speed curves snapped to the beat).
7. **One hero transition/effect** per video (overuse signals "editing for editing's sake").
8. **Export 9:16, 1080×1920.**

**Most important single element: music/beat synchronization** — every source converges
on this. Audio drives clip selection, cut timing, *and* discovery.

**The "coloring" subculture (product flag):** editors share free **overlay packs** (light
leaks, grain, VHS/TV textures, dust) and **coloring PSDs**, applied via **blending modes**
(light leak = Screen; TV/dark = Multiply) with opacity tuning. Blending modes + opacity
on overlay layers are table stakes for this audience — and archival film already *has*
the grain/VHS aesthetic this subculture manufactures, which is a natural fit.

**Tools that dominate:**
| Tool | Role | Why |
|---|---|---|
| CapCut | default/mass-market | AI auto-beat-sync, trending effects/templates pre-timed to audio, easy 9:16 export |
| Alight Motion | "pro" mobile | keyframe anything; home of velocity edits + serious overlay work |
| VN | lightweight free | CapCut-like, watermark-free |
| After Effects | top-tier desktop | high-end motion graphics; aspirational ceiling |
| TikTok native | speed over depth | trim, speed, layered sounds, trending filters |

Sources: [beCreatives](https://becreatives.co/edit-video-tiktok/) ·
[Riverside](https://riverside.com/blog/how-to-edit-tiktok-videos) ·
[Alight Motion vs CapCut](https://alightmotiontab.com/alight-motion-vs-capcut/) ·
[TikTok — overlays for edits](https://www.tiktok.com/discover/overlays-for-edits)

## 2.3 How edits are shared and discovered

- **Hashtags:** broad (`#edit`, `#edits`, `#capcut`, `#capcutedit`, `#overlays`, `#coloring`) + per-fandom tags.
- **Trending sounds are the primary discovery vector** — picking the trending audio is a *reach* decision as much as a creative one.
- **Attribution etiquette (a real subculture norm; omitting an obvious one invites call-out):**
  - **IB** = Inspired By · **DT** = Dedicated To · **CC** = Coloring Credit · **AC** = Audio Credit
  - **RM** = Remake · **DC** = Dance/Choreo Credit · **CTTO** = Credit To The Owner (source unknown)
  - **OC** = Original Content · **MEP** = Multi-Editor Project

**Product implication:** these abbreviations are metadata the community already maintains
by hand. A tool that auto-captures source clips, coloring-preset author, and audio — and
stamps an IB/CC/AC-style credit block — aligns with existing etiquette instead of
fighting it.

Sources: [SocialRails — IB meaning](https://socialrails.com/social-media-terms/ib-meaning-tiktok) ·
[TikTok — how to give credits](https://www.tiktok.com/discover/how-to-give-credits-in-edits) ·
[Buffer — trending songs](https://buffer.com/resources/trending-songs-tiktok/)

## 2.4 Public-domain / archival remix culture (our home turf)

- **Sources & framing:** found-footage/archival remix is "deeply traditional, dating back to primitive cinema"; digital access made the archive "closer, more accessible." Hubs: **Prelinger Archives on the Internet Archive**, **Public Domain Review**, **Library of Congress** moving-image guides.
- **Rights:** ~65% of the Internet Archive's holdings are US public domain; reusers are "warmly encouraged to download, use and reproduce these films in whole or in part."
- **Crediting norm:** requested-but-not-required (see 1.7) — the cultural *opposite* of TikTok's "trending clip, no source" default. **This is where Archive Watch can add genuine value: bake provenance in.**
- **Educational/provenance framing:** university guides teach archival reuse as rights-literacy (know source, know license, credit appropriately).

Sources: [Internet Archive — Prelinger help](https://help.archive.org/help/prelinger-archive/) ·
[Rick Prelinger — BFI Sight & Sound](https://www2.bfi.org.uk/news-opinion/sight-sound-magazine/features/rick-prelinger-we-have-always-recycled) ·
[Public Domain Review — Prelinger](https://publicdomainreview.org/collections/source/prelinger-archives/) ·
[NYU — Creative Reuse](https://guides.nyu.edu/creative-reuse)

## 2.5 Minimum viable feature set, ranked by creative payoff

**Tier 1 — non-negotiable core (the form doesn't exist without these):**
1. **Audio import + automatic beat detection** with beat markers on the timeline. Highest payoff — beat-sync *is* the genre.
2. **Multi-clip sequencing + frame-precise trim/split.**
3. **Snap-to-beat editing** (cuts/transitions magnetize to beat markers) — makes beat detection usable for non-experts.

**Tier 2 — defines the "edit aesthetic":**
4. **Speed ramps / time-remapping (velocity edits).**
5. **Color grading / "coloring" with importable/shareable presets** (PSD-equivalent).
6. **Overlay layers with blending modes + opacity** (light leaks, grain, VHS/TV, dust — which archival footage already evokes).
7. **Beat-synced transitions** (a small curated set; one hero transition, not fifty).

**Tier 3 — discovery, polish, differentiation:**
8. **Text / caption / lyric overlays** (timing snaps to beats; burned-in for muted feeds; inside safe zones).
9. **9:16 export at 1080×1920**, watermark-light (and never a competitor watermark).
10. **Templates pre-timed to audio** — proven mass-market on-ramp.
11. **Trending-sound / audio library** — discovery, not just creation. *(Note our music-rights caveat: PD video + non-PD music; YT Shorts limits copyrighted music to 60 s.)*
12. **Built-in attribution/credits block** — auto archive-credit line for PD footage + IB/CC/AC stamps. **Our distinctive wedge:** turns a compliance requirement into a culturally-native feature.

**One-line product takeaway:** if we ship only three things — **automatic beat
detection, snap-to-beat multi-clip trimming, and a coloring/overlay layer with
presets.** Beat-sync is the heart; coloring is the soul. For the archival angle
specifically, **auto-generated provenance credits** are the feature no competitor has.

---

## Confidence notes / caveats

- File-size figures for TikTok and Facebook vary across sources (platforms don't publish them); the most current/granular breakdown is given and conflicts flagged.
- Instagram and Facebook duration limits are **moving targets in 2025** due to the "all video is Reels" consolidation.
- Safe-zone pixel values vary ±~100 px between sources; both IG Reels and YT Shorts enlarged bottom UI in late 2025 — design to the most conservative margins and verify with a current overlay tool.
- The "85% sound-off" stat is **Facebook's**, not Verizon/Publicis's; the Verizon study (2019) is the most-cited primary research but is 6 years old.
- The Verge/Vox/Wired/NYT did not surface dedicated long-form edit explainers; the strongest culture writing was the Harvard Crimson piece + academic literature. Craft specifics live in CapCut/Alight Motion docs and tutorial blogs, cited as best-available primary sources. The "beat-sync → +23% completion" stat is from a tutorial blog — treat as marketing, not verified research.
