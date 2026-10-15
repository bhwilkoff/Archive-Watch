# Roblox feasibility 01: long-form video in a Roblox experience

Researched 2026-10-15. Primary sources are the Roblox Creator Docs, read from the
`Roblox/creator-docs` GitHub repo that generates create.roblox.com (so the dates
come from its commit history); official DevForum announcements; and the Roblox
Terms of Use, read through the Help Center's Zendesk API (body last updated
2026-10-07, with a revision that takes effect 2026-11-01). Any claim I could not
confirm against a primary source is marked **UNVERIFIED**.

## TL;DR

- **Uploaded assets are the only sanctioned source of video.** Every video API
  takes an `rbxassetid` (or a local `VideoCapture` from the player's own gallery).
  No API takes a URL. No web view or browser object exists.
- **One asset can be at most 5 minutes long**, costs **2,000 Robux**, and needs an
  uploader who is **13+ and ID-verified**. Each uploader can upload **20 per day**.
  A 90-minute film is therefore 18 assets, about 36,000 Robux (roughly $360–450),
  plus about one day of one uploader's quota.
- **Playback is local to each client.** `VideoFrame.Playing` and `TimePosition`
  are `NotReplicated`. The newer VideoPlayer API, which replicates Play and Pause
  from the server, is **still a Studio beta and does not run in live
  experiences**. Its full release moved to **Mid 2027** in the Creator Roadmap
  Fall Update of 2026-09-18.
- **Only two videos can play at once on a client.** That leaves one slot to play
  the current chunk and one to preload the next.
- Pushing frames into an EditableImage from an external server can be built.
  It is limited to 1024×1024 and to a 500 HTTP requests/min server budget. Its
  audio still has to come from uploaded audio assets. It gives low-quality,
  hobby-grade results and is fragile.
- For about 100 curated features, the realistic path is **chunked uploads** at
  about $40k (about 3.6M Robux). For about 30,000 titles it is **not feasible**:
  about 720M Robux (about $7M) and decades of upload quota.

---

## 1. Playback objects

### 1a. `VideoFrame`: the API that ships in live experiences

Source: [VideoFrame reference](https://create.roblox.com/docs/reference/engine/classes/VideoFrame)
(YAML last updated 2026-08-06) and [Video frames guide](https://create.roblox.com/docs/ui/video-frames)
(last updated 2026-07-07).

- **What it is:** a GuiObject. It plays only when its parent is a `ScreenGui`,
  `SurfaceGui` or `BillboardGui`.
- **Source:** `Video` takes a content ID string (`rbxassetid://…`).
  `VideoContent` takes a `Content` value: `Content.fromAssetId` or `fromUri`, or
  `Content.fromObject(VideoCapture)`. The `VideoCapture` case plays a local
  screen recording from `CaptureService` "without first uploading it to Roblox".
  **No property or method accepts an http(s) URL.**
- **Controls:** `Play()`, `Pause()`, `Playing`, `TimePosition` (a double that can
  be written to seek "both before and during playback"), `Looped`, `Volume`,
  `IsLoaded`, `TimeLength` and `Resolution` (both read-only).
- **Events:** `Loaded`, `Played`, `Paused`, `Ended`, `DidLoop`.
- **Replication:** `Playing`, `TimePosition`, `IsLoaded`, `TimeLength` and
  `Resolution` are tagged **NotReplicated**. `Video`, `Looped`, `Volume` and the
  roll-off properties replicate.
  - So each client runs its own clock. A watch party has to sync itself: the
    server broadcasts a start timestamp, and each client sets `TimePosition` and
    corrects drift.
- **Audio:** the video's single audio track plays through the VideoFrame.
  - Under a SurfaceGui on a BasePart, the audio is **spatial**: it comes from the
    part's position, attenuates with distance (`RollOffMinDistance`,
    `RollOffMaxDistance`, `RollOffMode`) and has a Doppler effect.
  - Anywhere else, the VideoFrame is "global" and plays at the same volume
    everywhere.
- **Resolution:** playback "never exceeds 720p", and 4K uploads are transcoded
  down. Source: the 2023 beta FAQ in
  [Video uploads [Beta]](https://devforum.roblox.com/t/video-uploads-beta-add-short-form-video-to-your-experience/2630621),
  whose FAQ was updated 2024-09-26.
  - A hidden `MaximumResolution` property is marked InternalTest.
  - Staff wrote on 2026-07-01 that "increasing the maximum potential quality and
    maximum playback limit are both on the table"
    ([Video Observability](https://devforum.roblox.com/t/video-observability-monitor-and-optimize-your-in-game-usage/4710680),
    2026-06-30).
  - Whether the 720p cap still applies in Oct 2026 is **UNVERIFIED**.
- **Frame rate:** uploads up to 120 fps are accepted, and 1080p60 is
  recommended (2023 FAQ). The playback frame rate is not documented
  (**UNVERIFIED**).
- **Concurrency:** "Currently, a maximum of two videos can play simultaneously."
  Roblox added this line to the guide on 2025-10-27; it has been in the beta FAQ
  since 2023.
- **Buffering:** setting an ID preloads "a few seconds around the current
  timestamp". Roblox calls a full preload "unlikely except for very short clips"
  (Video Observability, 2026-06-30).
- **Performance on mobile and console:** no published per-platform figures.
  - Roblox says only that reducing unneeded video data helps "lower-end devices"
    (Video Observability).
  - That VideoFrame plays on every client platform (console included) is
    **UNVERIFIED**, though no doc lists an exclusion.

### 1b. `VideoPlayer` + `VideoDisplay` + `Wire`: the "Advanced Video API" (beta)

Sources: [announcement](https://devforum.roblox.com/t/studio-beta-advanced-video-api-synchronize-video-control-3d-audio-and-more/3972775)
(2025-10-02), the [VideoPlayer reference](https://create.roblox.com/docs/reference/engine/classes/VideoPlayer)
and the [VideoDisplay reference](https://create.roblox.com/docs/reference/engine/classes/VideoDisplay)
(both YAML updated 2026-08-06, both still tagged `NotBrowsable`).

- **VideoPlayer:** holds `VideoContent` (a `Content` asset) and the playback
  methods `LoadAsync()`, `Play()`, `Pause()` and `Unload()`. Its properties
  include `TimePosition`, `PlaybackSpeed` and `Volume`.
  - The reference says Play and Pause each "Replicates from server to client".
    `TimePosition`, `PlaybackSpeed` and `Volume` carry no NotReplicated tag.
  - The same page warns that playing on the server does not guarantee the video
    is loaded or in sync on every client, and it prefers client-side play.
  - `PlaybackSpeed` is documented as "Ranges from 0 to 1", so there is no
    speed-up.
- **VideoDisplay:** a GuiObject that renders frames from a VideoPlayer
  connected by a Wire.
- **Features:** one player can drive many surfaces in sync. Audio goes through
  the Audio API (`AudioEmitter` for 3D audio, plus wireable effects). The API
  also adds explicit memory load and unload.
- **Concurrency:** the two-concurrent-video cap still applies, but one video can
  feed many displays (announcement).
- **Status:** "Studio Beta … will not yet function in live experiences"
  (announcement).
  - The Spring 2026 roadmap moved it from Early 2026 to Late 2026
    ([Spring Update](https://devforum.roblox.com/t/creator-roadmap-2026-spring-update/4625473)).
  - The [Creator Roadmap 2026: Fall Update](https://devforum.roblox.com/t/creator-roadmap-2026-fall-update/4880208)
    (2026-09-18) lists "Advanced video API (Late 2025 → Mid 2027)".
  - **As of Oct 2026 it cannot be used in a published experience.**
- **Sourcing:** asset IDs only. Neither the announcement nor the reference
  mentions external URLs.

### 1c. Other video-adjacent APIs (none help)

- `CaptureService` / `VideoCapture` plays the player's own gameplay recordings.
- RDC26 ([what we announced](https://devforum.roblox.com/t/rdc26-what-we-announced/4865880))
  announced only pre-roll video **ads** and "Play on the Web". It announced no
  external-video or long-form feature.
- A "VideoCamera" request (May 2026,
  [Video API Requests](https://devforum.roblox.com/t/video-api-requests/4624670))
  is a feature request, not a feature.

## 2. Uploading video assets

Requirements as of the guide revision of 2026-07-07, which repeats the
[Open Cloud Assets usage guide](https://create.roblox.com/docs/cloud/guides/usage-assets):

| Item | Current value | History |
|---|---|---|
| Who | **13+ and ID-verified** (Asset Manager, Creator Dashboard, or Open Cloud API) | The same since the 2023 beta |
| Cost | **2,000 Robux per upload**, not refunded if a rejection is upheld on appeal | Unchanged since 2023. Staff said "no current plans to lower". A 2026-06-09 request to drop it ([Video uploading](https://devforum.roblox.com/t/video-uploading/4674898)) got no staff reply |
| Max length | **5 minutes** | 30 s (Oct 2023) → 60 s (Mar 2025) → 5 min (2025-07-14), per [Longer video uploads](https://devforum.roblox.com/t/longer-video-uploads-more-video-uploads/3532432) |
| Quota | **20 uploads per day** | 3 per 30 days (2023) → 10 per month (Mar 2025) → 20 per 30 days (doc, Apr 2025) → 10 per day (2025-07-14) → **20 per day** (doc commit 9a5d24f2, 2025-11-03) |
| Size | **< 3.75 GB** | 375 MB in the 2023 FAQ |
| Format | `.mp4` / `.mov`, ≤ 4096×2160, no alpha channel | 2023 FAQ: minimum 160×160, even dimensions, 0 or 1 audio track |
| Language | Language restriction **removed** (doc commit c92cf136, 2026-01-21) | 2023: English/Spanish audio and text only. 2025: added pt, id, zh, ja, ko |
| Update | Video assets are "Not available for updating" (Open Cloud) | |

- **Moderation:** videos go through the same review as images and audio.
  - The 2023 FAQ states that "a copyright detection system exists".
  - Wrong rejections, with no refund, are a recurring complaint: Dec 2024, a
    thread still active in Dec 2025
    ([no refund thread](https://devforum.roblox.com/t/video-upload-moderation-no-robux-refund-for-rejected-content-leading-to-significant-creator-losses/3281294));
    Jan 2025 ([incorrectly moderated](https://devforum.roblox.com/t/video-assets-incorrectly-moderated/3376431));
    May 2026, a video moderated silently with no notification or refund
    ([thread](https://devforum.roblox.com/t/video-asset-moderated-without-notification-or-refund/4647557)).
  - Turnaround times are not published (**UNVERIFIED**).
- **Copyright and public domain:**
  - The upload rule is "You have the legal rights to use the video asset."
  - **There is no field or process for asserting public-domain status.**
  - What happens when the detector meets an old film whose audio or picture
    matches a commercial reference copy (for example a restoration someone else
    claims) is **UNVERIFIED** and is the main moderation risk. Each false
    rejection burns 2,000 Robux.
  - [Rights Manager](https://create.roblox.com/docs/production/publishing/rights-manager)
    is only for rights holders filing removal requests. It is not a channel for
    an uploader's own claim.
  - The ToU also requires creators to warrant that their UGC does not "infringe
    … any third-party right".
- **Programmatic upload:** yes. The Open Cloud Assets API supports `video/mp4`
  and `video/mov` with the same limits, including "20 uploads per day if you're
  13+ and ID-verified".
  - The same page also gives a general "file size up to 20 MB" per call, which
    contradicts the 3.75 GB video row. The effective limit through Open Cloud is
    **UNVERIFIED**.
  - Whether an Open Cloud upload deducts the 2,000 Robux from the key owner, and
    whether a group-owned upload has its own quota, are **UNVERIFIED**. The likely
    answer is that it deducts the fee, and that the quota belongs to the
    ID-verified user.
- **Asset privacy:** video assets use the audio-style privacy system. Only the
  owner, or a universe granted access, can play them.

## 3. External streaming: is any sanctioned route possible?

- **No URL video source and no web view.** No class accepts an http(s) URL for
  video, image or audio, and no browser object exists.
- **HttpService** ([reference](https://create.roblox.com/docs/reference/engine/classes/HttpService),
  [guide](https://create.roblox.com/docs/cloud-services/http-service)):
  - It works only from game servers.
  - Each server gets **500 HTTP requests per minute**, plus 2,500 per minute for
    Open Cloud calls.
  - Requests must be HTTPS, and ports below 1024 are blocked except 80 and 443.
  - `CreateWebStreamClient` (SSE, chunked transfer, WebSockets) is "available in
    Studio only".
  - Bytes come back as Luau strings. The maximum response size is not in the
    current docs (**UNVERIFIED**).
- **EditableImage frame pushing**
  ([reference](https://create.roblox.com/docs/reference/engine/classes/EditableImage)):
  - **How it works:** the server fetches frames over HTTP, sends them to clients
    by RemoteEvent, and each client calls `WritePixelsBuffer` on an EditableImage
    shown in an ImageLabel or on a mesh.
  - **Documented limits:**
    - Maximum size is 1024×1024.
    - "Only a single EditableImage can be updated per frame."
    - Clients have "strict client-side memory budgets", and creation returns nil
      once the budget is spent.
    - The API is off by default in published experiences. The owner must turn on
      **Enable Mesh / Image APIs**, and the docs ask creators to review the ToU
      first. Per AssetService/EditableMesh docs, enabling it requires being 13+
      and ID-verified.
  - **Community results:**
    - A [gist](https://gist.github.com/kezzyhko/d625175ab668ff147ccab07481e1df71)
      ships raw RGBA (500×282 is 564 KB per frame).
    - A [complete guide to EditableImages](https://devforum.roblox.com/t/a-complete-guide-to-editableimages/3858566)
      (Aug 2025 comment) estimates about 24 fps by batching 3 frames per request
      under the 500 requests/min cap. That is an estimate, not a measurement.
    - Older pre-EditableImage attempts ran at 8 fps or 90p
      ([2021](https://devforum.roblox.com/t/streaming-video-to-roblox-somehow-worked/1206973),
      [2021](https://devforum.roblox.com/t/video-player-that-can-stream-full-movies-at-low-resolution/1074046)).
  - **Bandwidth:**
    - Raw 320×180 RGBA at 24 fps is about 5.5 MB/s per client, so a real
      deployment needs compression decoded in Luau (palette or RLE, or a hand
      decoder).
    - Roblox's server-to-client replication budget is not documented. Community
      lore puts it near 50–100 KB/s (**UNVERIFIED**), which would allow only
      tiny, low-fps frames.
  - **Audio cannot be streamed at all.** A film's soundtrack would have to be
    uploaded as **audio assets**: < 20 MB, ≤ 7 min each, **free**, 2,000 per 30
    days if ID-verified
    ([Audio assets](https://create.roblox.com/docs/audio/assets)). A 90-minute
    film would be about 13 audio assets, each moderated like any audio upload.
  - **Policy:**
    - No document forbids drawing externally sourced pixels.
    - The Community Standards say "Roblox may … proactively remove … assets it
      suspects infringe IP".
    - The 2024 beta said moderation of editable content was "on the roadmap".
    - Content pushed this way bypasses asset moderation entirely. The creator is
      fully responsible for it under the ToU, and Roblox can moderate the
      experience.
    - Whether Roblox would act against an experience that streams unmoderated
      external video is **UNVERIFIED**. No official statement or ban case was
      found. It is a real platform-risk area, given how much the 2025–26
      child-safety scrutiny centers on unmoderated content.
- **Off-platform links**
  ([Community Standards](https://about.roblox.com/community-standards)):
  - "You may not link to, share, or display URLs of any external websites or
    services except by using the Social Links feature" (16+, age-checked).
  - The ToU (updated 2026-10-07) says Roblox "deploys detection systems that help
    identify conversations that attempt to direct Users off Roblox".
  - A "watch it on archivewatch.org" in-experience link or QR is therefore not
    allowed outside the Social Links feature.
  - Games may also not call third-party advertising or measurement services.

## 4. Precedents

- **Chunked uploads.** Theater experiences show short uploaded content.
  - [CineBlox](https://www.roblox.com/games/5797596824/CineBlox) bills itself as
    "Roblox's largest movie destination". Every title it lists is labeled
    "Animated", and the titles read like Roblox-made shorts.
  - [The Cinema Movie Experience](https://www.roblox.com/games/70796533480456/The-Cinema-Movie-Experience)
    and [Movie Theater Hangout](https://www.roblox.com/games/5705505104/Movie-Theater-Hangout)
    exist. How they source video is **UNVERIFIED**; they are most likely uploaded
    clips or machinima.
  - No source shows a full-length feature film playing in any of them.
- **Pre-VideoFrame hacks (2020–21):** frame sequences uploaded as images, or
  fetched over HTTP, at 8 fps or 90p (threads cited above). These were hobby
  demos.
- **EditableImage players (2024–25):** gists and tutorials. No shipped, popular
  experience was found.
- **YouTube-replica "players":** none found that play real YouTube video.
  Anything like that would break the off-platform rule.
- **Moderation and bans:** no case was found of a theater experience banned
  specifically for films.
  - The related case is *My Movie*. Its fandom wiki (not a primary source) says
    it was blocked in Australia and the UK for a period, under a rule against
    games where players share media.
  - Asset-level moderation of video is well documented (section 2).

## 5. Bottom line: delivering a 90-minute public-domain film in 2026

**Option A: chunked VideoFrame playlist (the only fully sanctioned path)**

- **Method:** transcode to ≤ 5-minute segments (90 min is 18 segments) and upload
  each through Open Cloud by an ID-verified 13+ account.
- **Playback:** a client-side controller plays segment *n* and preloads *n+1*,
  using the two concurrent slots. The server replicates a schedule (film, start
  time) and each client seeks by setting `TimePosition`.
- **Quality:** expect up to 720p (if the 2023 cap still holds), spatial audio on a
  SurfaceGui screen, and a possible hitch at each segment boundary. Whether the
  boundaries are gapless is **UNVERIFIED**.
- **Cost per feature:** 18 × 2,000 = 36,000 Robux, about $360–450 at about
  $0.010–0.0125 per purchased Robux. Pack prices come from third-party listings,
  so this is **UNVERIFIED**. Rejected segments are not refunded.
- **Curated ~100 features (~90 min each):** about 1,800 assets, 3.6M Robux
  (**about $36–45k**), and about 90 days of one account's 20-per-day quota.
  Moderation risk is per segment.
- **Full catalog (~30,000 titles):** with many shorts, assume a mean of about 60
  minutes, so about 12 segments each.
  - That is about 360,000 assets and **about 720M Robux, about $7M**.
  - At 20 per day it is about 18,000 account-days (about 49 years for one
    uploader).
  - **Not feasible.** Spreading the work across many verified accounts would
    probably read as quota evasion (**UNVERIFIED**).
- **Watch-party semantics:** to be built by hand until the VideoPlayer API ships
  (Mid 2027 per the roadmap). When it does, server-replicated Play and Pause
  simplify this but do not guarantee sync.

**Option B: EditableImage + uploaded audio (technically possible, not recommended)**

- **Method:** stream from our own server to a game server by HttpService, then to
  clients by RemoteEvent.
- **Quality:** low resolution and low fps, limited by the 500 req/min cap,
  RemoteEvent bandwidth and client memory budgets. Audio still costs about 13
  free uploads per film, each moderated.
- **Advantages:** zero video fees and no video quota. It could reach the whole
  catalog for picture.
- **Risks:**
  - It bypasses asset moderation, so it carries policy and enforcement risk
    (**UNVERIFIED** how Roblox would treat it).
  - It is fragile: one game server feeds every client.
  - Quality would undercut the "visual dignity" goal.

**Option C: don't play the film in Roblox**

- Use Roblox for discovery and community (posters, synopses, trailers ≤ 5 min).
- It cannot link out except through the Social Links feature, which limits this
  as a funnel.

**Recommendation:**

1. If anything is built, it is **Option A for a small curated set**: start with
   10–20 features, about $4–9k, to measure moderation behavior on public-domain
   film before committing to 100.
2. Re-evaluate when the Advanced Video API ships (Mid 2027), and watch for
   changes to fee, length or concurrency. Staff have said all three are "on the
   table" but committed to nothing.

## Open questions (UNVERIFIED, worth a direct test or a DevRel question)

1. Does the copyright detector reject public-domain films whose restorations are
   claimed by others, and can an appeal succeed with public-domain evidence?
2. Is the 720p playback cap still in force, and what playback frame rate do
   clients get on mobile and console?
3. Is there a gap when chaining two VideoFrames, and how far does drift go over
   90 minutes?
4. Is the Open Cloud video fee charged identically, and is the quota per user or
   per group?
5. What is the HttpService response-size cap, and what is the practical
   RemoteEvent throughput for frame pushing?
