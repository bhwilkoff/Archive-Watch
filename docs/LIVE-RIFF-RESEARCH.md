# Live Riffing — research (2026-09-17)

> **Superseded in name, not in content.** The feature is now **Watch Together** / **Watch Together Studio** — the binding design doc is `docs/WATCH-TOGETHER.md` (Decision 127). This file is the research it rests on and is kept as written.
>
> **One claim in §3 was imprecise and is corrected in WATCH-TOGETHER §9.** The
> tvOS row says the app gets "the audio port `.continuityMicrophone`" — true,
> but it reads as though the microphone were an `AVCaptureDevice`. It is an
> `AVAudioSessionPortDescription`, selected with
> `AVAudioSession.setPreferredInput(_:)`; a capture device of type
> `.microphone` then records from whatever the routing subsystem chose. That
> distinction is why `.playAndRecord` appears to fail on tvOS: without such a
> port there is nothing to record from. Read against the tvOS 27 headers,
> 2026-09-17.

> Owner's ask: *"the best way to use the Archive Watch app to live stream
> yourself (and your friends) watching old movies and riffing, discussing, or
> otherwise commenting upon them. Ideally, you should be able to capture the
> film video, your own camera video, and your device audio as a single video
> stream that gets sent via YouTube or Twitch so that others can watch it live
> and use the features of those platforms to interact (chat, etc)."*
>
> This is research, not a design doc. Nothing here is built. The binding
> design docs stay as they are until a design pass turns the recommendation at
> the end into rules.

## 0. The one-paragraph answer

YouTube and Twitch both take **RTMP/RTMPS from any encoder** and give a
third-party app everything it needs through their APIs (YouTube: the Live
Streaming API creates the broadcast and hands back an ingest address + stream
key; Twitch: Helix `Get Stream Key` + `Get Ingest Servers`). Neither takes
WebRTC/WHIP from general creators, which decides the architecture: **the
device that renders the film must also run an RTMP encoder** — or a server
must. On iOS/iPadOS and macOS that encoder is one dependency (HaishinKit,
BSD-3, ten years old, RTMP/RTMPS/SRT, H.264/HEVC, ReplayKit and
ScreenCaptureKit built in); on Android it is RootEncoder (Apache-2). The film
is *our own* `AVPlayer`/Media3 output, so we never need screen capture — we
compose film + camera + overlays ourselves and mix film audio + mic ourselves,
exactly as the open-source iOS streamer Moblin does with its "video source"
widgets. Roku and the smart-TV web builds cannot broadcast (no camera, no mic, no
encoder). The Apple TV 4K (2nd gen+, tvOS 17+) **can**: Continuity Camera
hands a third-party tvOS app the iPhone's camera and microphone through
AVFoundation, and HaishinKit publishes from tvOS — so the box that plays the
film can also encode the show, with the phone propped up as the camera.
Google/Fire TV have no equivalent; there the phone or the Mac is the studio. "Friends in the stream" is a second product
(multi-party WebRTC + server-side compositing — LiveKit Egress or Cloudflare
RealtimeKit); the honest first version is **one host, one camera, one film,
platform chat on screen**, with friends riffing through the same platform's
chat or a call the host mixes in on the Mac.

## 1. What the platforms offer

### 1.1 YouTube Live

| Question | Answer | Source |
|---|---|---|
| Ingest protocols | RTMP, RTMPS, HLS, DASH. RTMP/RTMPS for normal / low / ultra-low latency; HLS/DASH for HEVC/VP9/4K/HDR at higher latency. **No WebRTC/WHIP.** | [ingestion protocol comparison](https://developers.google.com/youtube/v3/live/guides/ingestion-protocol-comparison) |
| How an app goes live | YouTube Data API v3 "Live Streaming": `liveBroadcasts.insert` (title, scheduled time, privacy) + `liveStreams.insert` (`cdn.ingestionType` = `rtmp`/`hls`/`dash`, `cdn.resolution` 240p–2160p or `variable`, `cdn.frameRate` 30/60/`variable`) → `liveBroadcasts.bind` → push video → `transition` to `testing` then `live` → `complete`. The stream resource returns `cdn.ingestionInfo.{ingestionAddress, rtmpsIngestionAddress, backupIngestionAddress, streamName}` — address + stream key. | [getting started](https://developers.google.com/youtube/v3/live/getting-started), [liveStreams](https://developers.google.com/youtube/v3/live/docs/liveStreams) |
| Chat | `liveChatMessages.list` (poll, with `pollingIntervalMillis`) and `.insert`; the broadcast resource carries `snippet.liveChatId`. | Live Streaming API reference |
| Auth | OAuth 2.0 (`youtube` / `youtube.force-ssl` scopes); Google's **device authorization flow** exists for TV/limited-input devices — relevant if a TV app ever needed to *create* a broadcast on the user's behalf even though it cannot encode one. | Google Identity docs |
| Quota | Data API default 10,000 units/day; the live methods are ~50 units per insert/transition — a riff show costs a few hundred units. | Data API quota docs |
| Channel eligibility | Live streaming must be enabled on the channel: phone verification, **24-hour activation wait**, no live-streaming restrictions in the past 90 days. The **50-subscriber minimum applies to streaming from the YouTube mobile app**; an app that pushes RTMP through the API is an *encoder* and is not subject to it — worth confirming with a test account before promising it. | [YouTube Help – mobile](https://support.google.com/youtube/answer/9228390), [restrictions](https://support.google.com/youtube/answer/2853834) |
| Encoding | H.264 + AAC, keyframe every 2 s, CBR recommended. | YouTube encoder settings |

### 1.2 Twitch

| Question | Answer | Source |
|---|---|---|
| Ingest | RTMP/RTMPS to the nearest PoP from `GET https://ingest.twitch.tv/ingests`. Twitch has *tested* WebRTC ingest (WHIP) and transmuxes it to HLS anyway; **as of 2026 general creators still stream RTMP**. | [video broadcast guide](https://dev.twitch.tv/docs/video-broadcast/), [The Rig Wire, Aug 2026](https://therigwire.com/whip-whep-rtmp/) |
| Stream key | Helix `Get Stream Key` (scope `channel:read:stream_key`) — the app never asks the user to paste a key. | [Helix reference](https://dev.twitch.tv/docs/api/reference/) |
| Title / category | `Modify Channel Information` (`channel:manage:broadcast`). | same |
| Chat | Read: EventSub `channel.chat.message` (WebSocket transport works from a client app) or IRC; write: `Send Chat Message` (`user:write:chat`). Emotes, badges, follows/subs/raids all arrive as EventSub events. | same |
| Auth | OAuth; a **Device Code Grant** exists for devices without a browser (TV apps). | Twitch authentication docs |
| Quality tiers | "Enhanced Broadcasting" (multiple encodes in one E-RTMP stream): H.264 and HEVC ladders, 1440p for Partners/Affiliates via HEVC (June 2026), AV1/4K in beta; needs a supporting GPU and ≥12 Mbps up. Single-encode 1080p60 H.264 at ~6 Mbps remains the baseline any phone can do. | [Twitch blog](https://blog.twitch.tv/en/2024/01/08/introducing-the-enhanced-broadcasting-beta/), [Streamrun](https://streamrun.com/dual-format/twitch-enhanced-broadcasting) |

### 1.3 Others worth a line

* **Kick** — RTMPS ingest with a stream key, Moblin supports it; API smaller than Twitch's.
* **Cloudflare Stream Live** — takes RTMPS/SRT *and* WHIP; **simulcast (restream to RTMP destinations) is not available on WHIP inputs**, so it does not turn a browser into a YouTube encoder by itself. Live input $0.75/1,000 min, simulcast $0.02/min/target. [WebRTC beta](https://developers.cloudflare.com/stream/webrtc-beta/), [simulcasting](https://developers.cloudflare.com/stream/stream-live/simulcasting/)
* **Cloudflare RealtimeKit** (the former Dyte) — meetings SDK on Cloudflare's WebRTC network with composite-recording bots and **RTMP restream to YouTube/Twitch**; custom layouts are a "custom recording app" on Workers. The project already runs Workers (Pulse). [RealtimeKit](https://developers.cloudflare.com/realtime/realtimekit/)
* **LiveKit** (Apache-2, self-host or cloud) — rooms + **Egress**: a headless Chrome renders a *web template of your own* that joins the room, and the page is encoded to RTMP (YouTube/Twitch URLs documented). The cleanest server-side compositor there is. [Egress](https://docs.livekit.io/reference/other/egress/api/), [custom templates](https://docs.livekit.io/egress-ingress/egress/custom-template)

## 2. Where the encoder lives — three architectures

| | A. On-device studio | B. Cloud studio | C. Hybrid |
|---|---|---|---|
| Who composes film + camera + overlays | the app, on the phone/Mac | a server (LiveKit Egress / RealtimeKit bot) rendering a web layout | app composes the *host* tile; server composes host + friends |
| Who encodes RTMP | the device (HaishinKit / RootEncoder) | the server | server |
| Friends in picture | no (host only) — or on the Mac, a call window captured with ScreenCaptureKit | yes, natively (they join a room) | yes |
| Latency to platform | lowest; one hop | +1 hop and a transcode | same as B |
| Running cost | none | LiveKit Cloud / RealtimeKit per participant-minute + egress minutes | same as B |
| Works from tvOS / Roku / TV-web | tvOS 17+ on Apple TV 4K 2nd gen+: **yes**, via Continuity Camera (phone = camera + mic); Roku and TV-web: no | the TV can be a *viewer* of the room; still needs a phone for camera | same |
| Works from the web PWA | no — a browser cannot speak RTMP | **yes** (WebRTC in, RTMP out) — the only way the web app broadcasts | yes |
| Build effort | medium (per platform) | medium (one web template + one service) but ops | high |

**Recommendation:** ship A first on iPhone/iPad and Mac (they already hold the
player, the network layer and — on the Mac — the Creation Studio's compositing
muscle), and design the on-device studio so that its output is *also* a valid
LiveKit/RealtimeKit participant track. Then B/C is "the host publishes into a
room instead of to RTMP" and the server does the rest — no rewrite.

## 3. Per-platform feasibility (our five native fronts + web)

| Platform | Film | Camera | Mic + film audio mix | Encoder | Verdict |
|---|---|---|---|---|---|
| **iOS / iPadOS** | our `AVPlayer` → `AVPlayerItemVideoOutput` frames (no screen capture needed) | `AVCaptureSession` (multi-cam on supported devices; Center Stage) | film audio via `MTAudioProcessingTap` / `AVAudioEngine`; mic via capture; mix in-app; `AVAudioSession` `.playAndRecord` + `.mixWithOthers` | **HaishinKit** RTMP/RTMPS/SRT, H.264/HEVC hardware | **Best first target.** The fallback if in-app composition is slow: `RPScreenRecorder.startCapture` gives the app's own screen + app audio + mic as three sample-buffer streams — the film, the camera PiP and every overlay are already on that screen. Foreground only (a Broadcast Upload Extension survives backgrounding but loses app audio). |
| **macOS** | same AVFoundation path; the Creation Studio already renders film frames through Core Image/Metal | `AVCaptureDevice`, incl. **Continuity Camera** (the iPhone as webcam) | in-app mix; **ScreenCaptureKit can add any window + its audio** (a FaceTime/Discord call with the friends) — the OBS trick, native | HaishinKit (or FFmpeg via LGPL dylib if we want SRT bonding etc.) | **The "pro" studio.** Everything OBS does that matters here is reachable with system frameworks. |
| **tvOS** | yes | **Continuity Camera** (tvOS 17+, Apple TV 4K 2nd gen or later): the iPhone/iPad is the camera *and* the mic. `AVContinuityDevicePickerViewController` pairs it; the app gets an `AVCaptureDevice` of type `.continuityCamera`, real frames through `AVCaptureVideoDataOutput`, and the audio port `.continuityMicrophone` (or AirPods). One device at a time; the session ends when the app backgrounds or the phone leaves. | film audio + continuity mic mixed in-app, as on iOS | HaishinKit builds and publishes on tvOS; the A12/A15 has the hardware H.264/HEVC encoder | **The Apple TV can be the studio** — the film on the big screen, the phone propped as the camera, the stream encoded on the box. Two things to prove on hardware: 1080p decode + composite + encode headroom on the A12 (2nd gen) and the A15 (3rd gen), and that the picker's pairing flow survives a two-hour show. The fallback stays: the phone as the studio with the TV as the room's screen (SharePlay/AirPlay, D098). |
| **Android phone** | Media3 `ExoPlayer` → `SurfaceTexture`/OpenGL | CameraX | `AudioRecord` + app audio; Android 10+ `AudioPlaybackCapture` for app audio | **RootEncoder** (RTMP/RTSP/SRT/UDP; WHIP auth; OpenGL filters; "extra video sources": BitmapSource, CameraXSource; screen via MediaProjection) | Second target; PiP composition is custom OpenGL, which RootEncoder's filter stage is designed for. |
| **Google TV / Fire TV** | yes | no camera/mic on the dongles | — | — | Screen, not studio (same as tvOS). |
| **Roku** | yes | no | — | no encoder API | Never. |
| **Web PWA** | `<video>.captureStream()` | `getUserMedia` | `AudioContext` mix | **none — browsers cannot speak RTMP**; WebRTC only | Only via architecture B: publish to a LiveKit/RealtimeKit room and let the server push RTMP. |

## 4. What the competitors ship (the feature bar)

Sources: OBS Studio (GPL-2, the reference desktop studio), StreamYard (browser
studio, the reference for "guests + brand"), Streamlabs, Restream Studio,
Moblin (MIT, iOS, the reference for a *phone* studio), Prism Live Studio,
Larix. The list below is the union, ranked by how often it appears and how
much a riff show needs it.

**Must-have (every product has it, and a riff show is unwatchable without it)**
1. Program layout: film full-frame with the host camera as a **movable,
   resizable picture-in-picture**; presets (corner, side-by-side "theatre
   seats", host-only, film-only). MST3K's silhouette row is the iconic riff
   layout and belongs in the presets.
2. **Audio mixer**: film and mic on separate faders with meters; film ducking
   when the host talks; mute toggles; noise suppression on the mic.
3. **Starting-soon / pre-roll** screen with countdown and a music bed; an
   **intermission** card; an **ending** card. (StreamYard "pre-recorded
   video", OBS "scene", Moblin "slideshow".)
4. **Titles, logo, lower thirds** — the film's title/year/director as a lower
   third that we already hold (and can trust, after this month's audit),
   the host's name tag, a persistent bug/logo.
5. **Platform chat on screen** with emotes and badges; alerts for follows /
   subs / raids (Twitch EventSub; YouTube liveChatMessages).
6. **Go live in one tap**: OAuth once, the app fetches the stream key / creates
   the YouTube broadcast, sets title + category ("Just Chatting" / "Movies &
   TV" on Twitch; a YouTube category), shows a health readout (bitrate,
   dropped frames, connection).
7. **Record locally while streaming** (every product), so a show survives a
   dropped connection and can be posted as a VOD/clip.
8. **Stream health + adaptive bitrate** (Moblin, Larix, Streamlabs) — phones
   are on Wi-Fi.

**Should-have (differentiators the good ones have)**
9. **Scenes + transitions** (OBS/Streamlabs; StreamYard layouts): a cut or a
   short fade between "film", "host", "intermission".
10. **Multistream** (StreamYard/Restream/Moblin): YouTube *and* Twitch at once
    — HaishinKit and Moblin both do it on-device (two encodes or one encode,
    two connections); costs upload bandwidth.
11. **Guests by link** (StreamYard's whole business): friends join with a
    URL, appear in the layout, the host controls who is on screen. This is
    architecture B/C.
12. **Instant replay / clip** (Moblin, OBS replay buffer): "that line again".
13. **Remote control** (Moblin, Stream Deck): a second device — or the Apple
    Watch — as the switcher: next scene, mute, PiP position, pause the film.
14. **Playback controls on the film that the audience can see**: pause for a
    riff, scrub, chapter jump — with the position sent to the stream as an
    overlay so viewers know where they are.
15. **Browser/HTML widgets** (OBS browser source, Moblin browser widget) —
    the escape hatch for anything we did not build.

**Nice-to-have**
16. Green screen / background blur on the host camera (Moblin, StreamYard).
17. Tickers/banners for a scheduled riff programme.
18. AI clips/titles (StreamYard 2026) — not for us.

**What none of them have and we would:** the film is *ours*, from a catalog
with verified metadata, so the show can carry an accurate title card, the
year, director and cast, a "public domain since…" line, and a chapter list —
and the film can be paused, rewound and captioned by the same engine that
plays it, rather than being a window OBS captures.

## 5. Open-source building blocks

| Repo | Licence | What it gives us | Fit |
|---|---|---|---|
| [HaishinKit/HaishinKit.swift](https://github.com/HaishinKit/HaishinKit.swift) | BSD-3 | RTMP/RTMPS/SRT publish (WHIP alpha), H.264/HEVC, multi-cam, multi-stream, ReplayKit + ScreenCaptureKit inputs, text/bitmap overlays; iOS 15+, macOS 12+, tvOS, visionOS; Swift 6 strict concurrency | **Apple encoder.** App Store safe. |
| [eerimoq/moblin](https://github.com/eerimoq/moblin) | MIT | A complete iOS IRL studio: scenes and widgets (image, text, browser, **video file as a source**, PiP camera), chat overlay with Twitch/Kick/BTTV/7TV emotes, alerts, Twitch/YouTube/Kick integrations (title, category, viewer count, chat, stream create/delete), remote control, MP4 recording, replays, adaptive bitrate, bonding | **The design reference for the phone studio**, and MIT means specific pieces can be studied or borrowed with attribution. |
| [pedroSG94/RootEncoder](https://github.com/pedroSG94/RootEncoder) | Apache-2 | Android RTMP/RTSP/SRT/UDP; AAC/Opus, H.264/H.265/AV1; OpenGL filters; image/GIF/text overlays; extra video sources; screen capture; record while streaming; AEC/NS | **Android encoder.** |
| [livekit/livekit](https://github.com/livekit/livekit) + [livekit/egress](https://github.com/livekit/egress) | Apache-2 | WebRTC SFU + server compositor (Chrome renders our layout → RTMP) | **Friends + web path.** |
| [bluenviron/mediamtx](https://github.com/bluenviron/mediamtx) | MIT | RTMP/SRT/WHIP/HLS media server in one binary — a WHIP→RTMP relay for the web app, or a local LAN relay | Relay option if we self-host rather than LiveKit. |
| [obsproject/obs-studio](https://github.com/obsproject/obs-studio) | GPL-2 | The feature bar (§4); WHIP output landed in 30.x; not embeddable in App Store apps | Reference only. |
| [FFmpeg](https://ffmpeg.org) | LGPL/GPL | Encoding/muxing everywhere; LGPL build is App Store compatible as a dynamic framework | Only if HaishinKit/RootEncoder lack something (SRT bonding, RIST). |
| Cloudflare RealtimeKit | commercial | Rooms + recording bots + RTMP restream on infrastructure we already use | The managed alternative to LiveKit for §2-B. |

## 6. Friends

Three honest options, in increasing cost:

1. **Friends on the platform's chat.** Zero build. Twitch chat *is* the riff
   for most watch-along streams. The host reads chat on screen.
2. **Friends on a call the host mixes in (Mac only).** FaceTime/Discord/Meet
   window + its audio captured with ScreenCaptureKit and placed as a tile.
   Their faces and voices are in the stream; playback is synced for them by
   SharePlay (Apple) or by them simply watching the stream. Not possible on
   iOS — the system does not let an app capture another app's video or audio.
3. **Friends as guests by link** (StreamYard model). A LiveKit/RealtimeKit
   room; the host publishes the film as a video track (or the server plays
   it from the archive URL directly — the composite page can embed the film
   `<video>` itself, which is exactly what a LiveKit custom template is) plus
   camera; friends publish camera + mic from any browser; the server
   composites and pushes RTMP. This is also the *only* way the web PWA
   broadcasts, and the only way a TV-app owner without a Mac gets friends on
   screen. Per-minute cost, and someone owns the service.

## 7. Policy and legal

* Public-domain films can be publicly performed and streamed; riffing them
  is the RiffTrax model (their feature riffs of studio films are sold as
  audio-only *because* of rights; their shorts are PD). The catalog's rights
  audit (Decisions 027/114, and this month's footprint work) is what makes a
  "go live" button defensible — **only rights-KEEP films should be offered to
  the studio**, the same gate the Roku Search feed uses (D113).
* Expect **Content ID false claims** on YouTube for PD films whose remasters
  or scores are claimed by distributors; a claim mutes or blocks the VOD, not
  the live stream, and can be disputed. Music beds for pre-roll must be ours
  (PD or licensed).
* Twitch: streams of films fall under "Watch Parties" history — Twitch shut
  its Prime Video watch-party feature in April 2024 for low use; riffing
  *public-domain* films is a different thing and is common on the platform.
  Category choice matters for discovery ("Movies & TV" vs "Just Chatting").
* Camera + mic permissions, and on iOS the `AVAudioSession` category must
  allow playback + record + mixing; the app must keep the screen awake and
  survive being backgrounded (it cannot — plan the UX around "the phone is
  the studio and stays on").

## 8. Recommended plan

**Phase 0 — spike (a week).** iPhone: HaishinKit + `AVPlayerItemVideoOutput`
+ front camera + mic → RTMPS to a test YouTube channel and a test Twitch
channel. Measure CPU, thermals and bitrate at 1080p30/6 Mbps on the Pixel-era
iPhone we test on. This answers the only real unknown: whether in-app
composition of a decoded 1080p film plus a camera plus overlays holds 30 fps
on a phone, or whether the ReplayKit screen path is the way.

**Phase 1 — the phone studio (iOS/iPadOS).** One host, one camera, one film,
YouTube or Twitch, chat on screen, pre-roll/intermission/end cards, PiP
presets, audio faders with ducking, local recording, stream health.
Everything in §4's must-have list. Cast the program to the Apple TV for the
room. Gate on rights-KEEP films.

**Phase 1b — the Apple TV studio.** The same engine on tvOS with Continuity
Camera as the camera + mic input. Worth doing right after the phone, because
it is the way the owner already watches — the film on the television, the
phone on the coffee table pointed at the couch. Gate on the hardware
measurement in Phase 0 repeated on an Apple TV 4K.

**Phase 2 — the Mac studio.** Same engine; adds Continuity Camera, window +
audio capture for a friends' call, multistream, scenes/transitions, Stream
Deck/Watch remote. Lives beside the Creation Studio (docs/macOS-DESIGN.md
Part A) — they share the render path.

**Phase 3 — Android phone.** RootEncoder port of Phase 1.

**Phase 4 — guests by link + web broadcasting.** LiveKit (self-hosted on a
small box, or LiveKit Cloud) or RealtimeKit; a custom composite template that
is literally the web PWA's player page plus tiles; RTMP out. This is when
tvOS/Roku/TV-web owners get a path too (phone as camera, TV as screen, server
as encoder).

**Why this order:** it puts the whole product on the device we can test on
hardware today, with zero running cost, before spending on a service; and
every later phase reuses the same compositor and the same platform OAuth.

## 9. Open questions to settle before design

1. Does an API/RTMP stream from a third-party *mobile* app count as "mobile
   streaming" (50-subscriber gate) on YouTube? Test with a fresh channel.
2. Thermal/CPU headroom on the oldest iPhone we support for decode +
   composite + encode at 1080p30 — the Phase 0 spike.
3. Twitch category and how the show is discovered; whether Twitch's
   "Watch Parties"-era rules say anything about PD films.
4. Which of Moblin's widgets the owner actually wants on day one; the list in
   §4 is the market, not the brief.
5. Whether the friends feature is a product requirement or a "would be nice"
   — it is the difference between zero and non-zero running cost.

## Sources

Continuity Camera on tvOS: [WWDC23 "Discover Continuity Camera for tvOS"](https://developer.apple.com/videos/play/wwdc2023/10256/) · [Supporting Continuity Camera in your tvOS app](https://developer.apple.com/documentation/AVKit/supporting-continuity-camera-in-your-tvos-app) · [Apple Support: use your iPhone or iPad as a camera with Apple TV 4K](https://support.apple.com/guide/tv/use-your-iphone-or-ipad-as-a-camera-atvb45658929/tvos)

YouTube: [ingestion protocol comparison](https://developers.google.com/youtube/v3/live/guides/ingestion-protocol-comparison) · [HLS ingestion](https://developers.google.com/youtube/v3/live/guides/hls-ingestion) · [Live Streaming API getting started](https://developers.google.com/youtube/v3/live/getting-started) · [liveStreams resource](https://developers.google.com/youtube/v3/live/docs/liveStreams) · [mobile live requirements](https://support.google.com/youtube/answer/9228390) · [live restrictions](https://support.google.com/youtube/answer/2853834) · [StreamMetrix 2026 requirements](https://streammetrix.com/blog/youtube-live-requirements-2026-everything-you-need-start-streaming)
Twitch: [video broadcast guide](https://dev.twitch.tv/docs/video-broadcast/) · [Helix reference](https://dev.twitch.tv/docs/api/reference/) · [Enhanced Broadcasting beta](https://blog.twitch.tv/en/2024/01/08/introducing-the-enhanced-broadcasting-beta/) · [Enhanced Broadcasting help](https://help.twitch.tv/s/article/enhanced-broadcasting?language=en_US) · [Streamrun on dual-format](https://streamrun.com/dual-format/twitch-enhanced-broadcasting) · [watch parties shut down (Engadget)](https://www.engadget.com/twitch-is-ending-its-pandemic-era-prime-video-watch-parties-110004438.html)
WHIP/WebRTC: [RFC 9725](https://www.rfc-editor.org/rfc/rfc9725.html) · [webrtcHacks on OBS WHIP](https://webrtchacks.com/webrtc-cracks-the-whip-on-obs/) · [The Rig Wire, "WHIP is finished, Twitch still wants RTMP"](https://therigwire.com/whip-whep-rtmp/) · [Dolby: WebRTC to Twitch](https://bdriggs.medium.com/how-to-broadcast-a-webrtc-stream-on-twitch-238c96b1556c)
Cloudflare: [Stream WebRTC beta](https://developers.cloudflare.com/stream/webrtc-beta/) · [Stream simulcasting](https://developers.cloudflare.com/stream/stream-live/simulcasting/) · [Stream pricing breakdown](https://blog.blazingcdn.com/en-us/cloudflare-streaming-pricing-2025-breakdown-live-vod) · [RealtimeKit](https://developers.cloudflare.com/realtime/realtimekit/) · [RealtimeKit recording](https://developers.cloudflare.com/realtime/realtimekit/recording-guide/) · [RealtimeKit livestream any RTMP](https://docs.realtime.cloudflare.com/guides/livestream/advanced/livestream-any-rtmp)
LiveKit: [Egress API](https://docs.livekit.io/reference/other/egress/api/) · [custom templates](https://docs.livekit.io/egress-ingress/egress/custom-template) · [livekit/egress](https://github.com/livekit/egress)
Libraries: [HaishinKit README](https://github.com/HaishinKit/HaishinKit.swift/blob/main/README.md) · [Moblin](https://github.com/eerimoq/moblin) · [Moblin README](https://github.com/eerimoq/moblin/blob/main/README.md) · [RootEncoder README](https://github.com/pedroSG94/RootEncoder/blob/master/README.md) · [RPScreenRecorder](https://developer.apple.com/documentation/replaykit/rpscreenrecorder) · [ReplayKit + broadcast extension guide](https://www.forasoft.com/blog/article/how-to-implement-screen-sharing-in-ios-1193)
Competitors: [StreamYard branding platform](https://streamyard.com/blog/all-in-one-streaming-and-branding-platform) · [StreamYard review 2026](https://www.creatorstackclub.com/software/streamyard) · [OBS 30.2 multitrack](https://alternativeto.net/news/2024/7/obs-studio-30-2-launched-with-multitrack-streaming-enhanced-rtmp-flv-and-composable-themes) · [Teleparty alternatives 2026](https://watchtogether.watch/blog/teleparty-alternatives) · [RiffTrax](https://en.wikipedia.org/wiki/RiffTrax)
