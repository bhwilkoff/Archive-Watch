# Streaming external video into Roblox without uploading video assets: precedents

Researched 2026-10-15. Sources are DevForum threads, GitHub repos and gists, and Roblox Creator Hub docs. A claim marked **UNVERIFIED** comes only from a search snippet or a forum assertion that I could not check against code or a primary page. Calculations of my own are labeled "(calc)".

---

## 0. Headline findings

1. **Every published "YouTube in Roblox" project uses the same pipeline.** An off-platform server (Node or Python) downloads the video (ytdl-core or yt-dlp), decodes it (ffmpeg or OpenCV) and serves **raw, uncompressed pixel bytes** over HTTP. The Roblox *server* polls with `HttpService:GetAsync`, batches several frames per request, and relays them to clients over `RemoteEvent`s as `buffer`s. The client draws them with `EditableImage:WritePixels`/`WritePixelsBuffer`. Before EditableImage (2023-24), "pixels" were `Frame` GUI objects or parts, and frame rates were single digits.
2. **None of these projects is a live, public, mass-player product.** All of them are showcases, Studio or localhost demos, or explicitly kept private ("can't be public"). The one that monetized (2022, 213x120 at 10 fps, no sound) drew immediate ban warnings. I found **no confirmed case of an experience that streams external video to many concurrent players in production**.
3. **Audio is the unsolved half.** The workarounds are: no sound (most projects); a **separately uploaded Roblox audio asset** used as the master clock, with video frames picked by `Sound.TimePosition` (kezzyhko's gist, the 2021-23 frame players); or local-only exploit tricks (`getcustomasset`). Nobody has streamed external audio into a Roblox experience by any legitimate API.
4. **Roblox staff have stated the policy in writing.** In the EditableImage Client Beta announcement (FGmm_r2, 2024-11-20), staff wrote: *"Do not load asset-like content from off-platform sites or unmoderated sources e.g. DataStores, source code, or StringValues."* The APIs also require a 13+, **ID-verified** owner who opts in, and the stated reason is "creator accountability for APIs that could result in policy violating content". Community Standards prohibit "Attempting to circumvent our safety systems." Several project authors withheld their code because it "bypasses Roblox image moderation" (boatbomber, 2022).
5. **The hard engineering limits** are: external HTTP is capped at **500 requests/min per server**; EditableImage is capped at **1024x1024** with a strict client memory budget; and **only one displayed EditableImage updates per rendered frame**. The one realistic-sounding throughput claim (htauk, 2025) is 3 RGBA frames per request x 8 req/s ≈ **24 fps**, with the resolution unstated.

---

## 1. Projects, mechanism by mechanism

### 1.1 kezzyhko — "Video player for Roblox on EditableImage" (GitHub gist)
<https://gist.github.com/kezzyhko/d625175ab668ff147ccab07481e1df71> (6 revisions; page says "last active 2026-08-17"; creation date not shown). This is the most complete public code I found, and I read it directly.
- **Frame source:** `VideoPlayer.py` uses Python `http.server` + OpenCV + NumPy and reads a local MP4. Each frame is `np.pad(frame, ((0,0),(0,0),(0,1)), constant_values=255).tobytes()`: **raw 4-byte pixels, with no compression and no resize**. The example file is `KillerBean_500x282.mp4`. OpenCV's BGR order passes through unconverted, so red and blue are probably swapped (my reading of the code).
- **Endpoints:** `/<id>/info` returns JSON {Framerate, Width, Height, AudioId}. `/<id>/frame/<start>-<end>` returns the concatenated raw frames.
- **Roblox server:** `HttpService:GetAsync` fetches **200-frame blocks** (`FRAMES_PER_BLOCK = 20*10`). (calc) At 500x282 that is 564 KB/frame and **~113 MB per response**. The server splits the string into 10 MB pieces (`ONE_EVENT_BUFFER_LIMIT = 10^7`), converts each with `buffer.fromstring`, and fires it to the requesting client over a `RemoteEvent` with its byte offset.
- **Client:** It `buffer.copy`s chunks into a preallocated block buffer. On every `Heartbeat` it calls `editableImage:WritePixels(Vector2.zero, res, array)`. The array is built by converting every byte to a float `/255` in a Luau loop, which is the old pre-`WritePixelsBuffer` API and very slow.
- **Audio:** A pre-uploaded Roblox `Sound` (AudioId) is the master clock: `frameIndex = math.round(audio.TimePosition * fps) + 1`.
- **Achieved fps, resolution and player count:** none reported. It is a per-client demo, and each viewer pulls its own copy through the server.

### 1.2 htauk (Fallden4) — "YouTube Browser + Player" and the 24 fps recipe
- Showcase: <https://devforum.roblox.com/t/youtube-browser-player/3672662> (2025-06-01). It has a Node backend, YouTube **browsing in-game**, and "everything realtime except video loading (~20 s)". **"Audio isn't in game."** It was not released, and the thread gives no reason (a community reply says it "can't be public").
- Recipe (reply in "A complete guide to EditableImages", <https://devforum.roblox.com/t/a-complete-guide-to-editableimages/3858566>, 2025-08-10): Node + **yt-dlp** + **FFmpeg**. Each request returns the **last 3 frames as one RGBA buffer**. Roblox splits the buffer into 3 frame buffers and renders them onto an EditableImage. The arithmetic: "HTTP request limit is 500 requests/min" ≈ 8 req/s, x 3 = **~24 fps**. The resolution is not stated. **UNVERIFIED** as a measured rate; it is the author's own arithmetic.
- (calc) Raw RGBA at 256x144 is 147 KB/frame, so 24 fps is ~3.5 MB/s into the server and the same again out to **each** client over remotes. That is far beyond what Roblox replication is normally budgeted for, which is why nobody reports multi-player numbers.

### 1.3 Bloxxy213_DVL — "Playing youtube videos in roblox" (2022)
<https://devforum.roblox.com/t/playing-youtube-videos-in-roblox/1706175> (2022-03-11). A NodeJS script turns a YouTube video ID into frames. It achieved **213x120 at 10 fps, with no sound** ("I have no plans for sound"). The rendering method is not described; it predates EditableImage, so it was probably GUI frames (**UNVERIFIED**). The author claimed a "family-friendly check" and **sold custom videos at $100 each**. Replies warned that similar projects "ended up all getting banned". The author argued that single-player servers limit exposure. No staff reply.

### 1.4 dollychun — "Streaming video to roblox, Somehow worked" (2021)
<https://devforum.roblox.com/t/streaming-video-to-roblox-somehow-worked/1206973> (2021-05-06). The server sends frames in real time through HttpService, as bytes in strings (`string.byte`) with some compression. No fps, resolution or audio details. Asked whether it passed moderation, **the author said it did not** and that the fix would be disabling HTTP. A reply said it "probably counts as bypassing moderation". The code was kept secret. SquarePapyrus12 described a similar **screen-capture livestream capped at 8 fps**.

### 1.5 tacovaIk — "Need help with video streaming system" (2022)
<https://devforum.roblox.com/t/need-help-with-video-streaming-system/2089418> (2022-12-27). A Python server emits **Luau table source** `{{r,g,b},…}`, which Roblox fetches and `loadstring`s. It took about **60 s to load 200 frames (~3.3 fps sustained)**. A reply suggested packing each pixel as one integer `65536r+256g+b`, which made it "a little quicker". This is a good example of why text or JSON formats fail.

### 1.6 JoshPlayzRoJosh — "EditableImage Screen 'Sharing'" (2024)
<https://devforum.roblox.com/t/editableimage-screen-sharing/3127592> (2024-08-21). A Python screenshot server returns **JSON**. The screen is a **40x19 grid of 760 EditableImages** (~2000x950), each tile fetched by its own `GetAsync` ("over 700 requests in less than 40 seconds"). JSON-decoding ~0.5 MB caused spikes, and full frames froze Studio for 30-60 s. It was never solved. Replies suggested delta (changed-region) updates, compression, Actors, PNG batches and `WritePixelsBuffer`. A pre-EditableImage version built from **parts as pixels** also existed (Pastor James).

### 1.7 TheRealANDRO — External Image Loader (2022, later V3 on EditableImage)
<https://devforum.roblox.com/t/made-an-external-image-loader/1703259> (2022-03-10). Their own API returns RGB values for an image URL (GIFs too), drawn with boatbomber's **GradientCanvas** (a GUI-frame canvas). The author wrote: *"I will never release this creation to the public as this can be used to bypass moderation."* boatbomber added: *"I will not open source the parsers as it bypasses Roblox image moderation."*

### 1.8 Artzified — "Bad Apple in Roblox (HTTP Python Video Player)" (2023)
<https://devforum.roblox.com/t/bad-apple-in-roblox-http-python-video-player/2421771> (2023-06-12). A localhost Python server sends pixel strings as JSON, with **one Actor per row** (Parallel Luau). The author says it is "not meant for production" and works only with localhost unless hosted. Other Bad Apple versions: Bedu009 on EditableImage (<https://devforum.roblox.com/t/made-bad-apple-with-the-new-image-api/2768383>, 2023-12-29, no details), a text/chat version (<https://github.com/Malakai0/Bad-Apple>), and a YouTube demo (<https://www.youtube.com/watch?v=SM80tYgAPc8>, not watched; **UNVERIFIED**).

### 1.9 AlexR32/Roblox-Videoplayer: a CLIENT EXPLOIT, not an experience
<https://github.com/AlexR32/Roblox-Videoplayer> (archived 2023-11-17). I read `Backend.js` and `Videoplayer.lua`. The **Express + ytdl-core + ffmpeg-static** backend remuxes YouTube itag 247/244/243/242/278 VP9 video-only + highest audio into **WebM** (or transcodes to libvpx-vp9), and serves MP3 for the audio player. The "client" is an **executor script**. It is loaded via `loadstring(game:HttpGet(...))` and uses executor-only globals `request`/`syn.request`, `writefile`, and `getcustomasset`/`getsynasset`. It writes the WebM to the local disk and points a `VideoFrame.Video` at the local file (`Window.Video.Video = GetAsset("videos/<id>.webm")`), parented to `CoreGui`. That gets **full native video and audio, only for the cheating user**. This is the likely basis of "roblox got netflix now"-style videos (<https://www.youtube.com/watch?v=s7pCRftw_S8>, not watched; **UNVERIFIED**). It is impossible for a legitimate experience: `getcustomasset` and `VideoFrame` with a local path are not available to game scripts.

### 1.10 Asset-based players (uploaded frames, NOT external streaming; included for contrast)
- PuppoJon, "Roblox Video Player" (<https://devforum.roblox.com/t/roblox-video-player/1154477>, 2021-04-07): each frame is an uploaded image, synced to an uploaded audio clip. Bulk import is capped at ~200 per batch and ~400 per day, so the author used alt accounts. One user got **two moderation warnings** uploading frames.
- iceeburr, "Video Player v1.1" (<https://devforum.roblox.com/t/archive-video-player-v11-play-your-own-video-inside-roblox-full-resolution-fps-and-audio/2423381>, 2023-06-13): ~2,100 frames uploaded over 3 days via the Open Cloud Assets API. Text in frames gets flagged, an audio asset was banned, and the author warns the API-key account can be banned. It was archived for an EditableImage rewrite.
- PlaybackService (<https://devforum.roblox.com/t/playbackservice-video-player-module/2294879>, 2023-04-13): an image-ID table played at 30 fps.
- Sprite-sheet advice: <https://devforum.roblox.com/t/how-would-i-be-able-to-play-a-custom-video-in-my-roblox-game-without-uploading-500-frames/1210023>.

### 1.11 "Netflix in Roblox", "RoTube", watch-party experiences
- **Netflix Nextworld** (May 2024) is an official Netflix-branded Roblox universe of games and hangouts, **not film playback** (<https://www.netflix.com/tudum/roblox-nextworld>). Its watch-party area was described as "envisioned", not built (secondary: <https://blog.vive.com/us/stranger-things-one-piece-in-netflixs-roblox-metaverse/>).
- **"RoTube":** no project by that name found.
- **"Maro: Movies with Friends!"** (<https://www.roblox.com/games/118061026882416/Maro-Movies-with-Friends>) claims "Watch movies and YouTube videos!" and says it gets creators' permission. When fetched it had **no running servers**. Its mechanism is not stated; given its permission model, it most likely uses uploaded VideoFrame assets (**UNVERIFIED**).

---

## 2. Codecs and decoders in Luau (with numbers where they exist)

| Project | What | Performance |
|---|---|---|
| QOI port, seanjosep39 — <https://devforum.roblox.com/t/qoi-the-fast-and-lossless-image-de-compressor-ported-to-luau/2921027> (2024-04-09; v2.2.0 2025-08-29) | Lossless image codec on `buffer` | Decode ~8 ms @ 440x415, ~11 ms @ 511x506, ~23 ms @ 1024x683, ~40 ms @ 1024x1024; 55-68% smaller than raw. v2.2 claims 14x faster encode and 7x faster decode than v1. The best published number: 256x144 QOI decode is probably ~1-2 ms (calc, extrapolated) |
| Picguin, wizevaxel — <https://devforum.roblox.com/t/picguin-high-performance-luau-image-codecs/4667402>, <https://github.com/wizevaxel/picguin> (2026-06-04; png@0.2.0 2026-09-13) | Pure-Luau PNG + APNG | No timings; "~2.5x zlib speedup" |
| Jpeg Decoder Module, Viv3k_87 — <https://devforum.roblox.com/t/jpeg-decoder-module-open-source/4024093> (2025-10-25) | Pure-Luau JPEG, client-side, returns RGB | No numbers; others warn it is "really slow" on the server |
| PNG decompressor showcase — <https://devforum.roblox.com/t/png-decompressor-showcase/3155884>; MaximumADHD Roblox-PNG-Library; PngLibary <https://devforum.roblox.com/t/pnglibary-working-way-to-load-images-over-1024x1024/2788400> | PNG | Table-based is slow (the 2^26 table limit); buffers are "so much faster". PngLibary author: "would not recommend… performance issues" |
| plainenglishh/remote-image-library — <https://github.com/plainenglishh/remote-image-library> | PNG URL to EditableImage, with rate-limit queuing | — |
| LuauImageParser / Metatable — <https://devforum.roblox.com/t/image-parser-api-render-external-images-to-roblox/3586131> (2025-03-31) | URL to EditableImage via `WritePixelsBuffer`, Cloudflare Worker backend | — |
| H.264 / MPEG / VP9 in Luau | **None found.** No project decodes a real video codec in Luau; every streamer sends raw or near-raw pixels | — |

---

## 3. Platform limits that bound any such design (primary docs)

- **HttpService:** "The current limitation for sending and receiving **external** HTTP requests is 500 requests per minute… Requests over these thresholds will fail." (`HttpService:RequestAsync` reference, Creator Hub). HttpService is **server-only** in live games; clients cannot fetch.
- **HTTP streaming (SSE/WebSocket, `HttpService:CreateWebStreamClient`)**: **Studio only**: "This feature is restricted to Studio only." Calls in live experiences are blocked. Staff said live-server support is "a direction we would like to explore" (LeafGreen888, 2025-08-28, <https://devforum.roblox.com/t/http-streaming-now-supports-server-sent-events-in-studio/3905367>). A community reply speculated this is why: someone "would 100% stream NSFW content into an EditableImage". Staff did not answer that point.
- **EditableImage:** max **1024x1024**; "Only a single EditableImage can be updated per frame on the display side"; "strict client-side memory budgets"; fails by default in published games until **Enable Mesh / Image APIs** is toggled, and the docs say to "review the Terms of Use before enabling the toggle". Not replicated. `WritePixels`/`ReadPixels` were removed in favor of `WritePixelsBuffer`/`ReadPixelsBuffer` (2024-10-23, <https://devforum.roblox.com/t/studio-beta-major-updates-to-in-experience-mesh-image-apis/3225681>).
- **UnreliableRemoteEvent:** payloads over **1,000 bytes** are dropped (current remote-events doc; the launch post said 900 B, <https://devforum.roblox.com/t/introducing-unreliableremoteevents/2724155>). Useless for frame data. Reliable `RemoteEvent` + `buffer` is what kezzyhko used.
- **Per-client bandwidth:** I found no documented hard cap for server-to-client remote throughput. The ~50 KB/s figure commonly cited on DevForum is **UNVERIFIED**.

---

## 4. Moderation, staff statements and policy text

**Official staff statement (the strongest primary source).** "[Client Beta] In-experience Mesh & Image APIs now available in published experiences", FGmm_r2 on behalf of the Geometry, Rendering and Avatar teams, **2024-11-20**, <https://devforum.roblox.com/t/client-beta-in-experience-mesh-image-apis-now-available-in-published-experiences/3267293>:
> "Do not load asset-like content from off-platform sites or unmoderated sources e.g. DataStores, source code, or StringValues. Storing or retrieving settings, slider values, or seed values for procedural generation is generally acceptable."

The same post says "you must be 13+, ID-verified, and explicitly opted-in to using the APIs in published experiences", and that "ID verification allows us to increase creator accountability for APIs that could result in policy violating content." It adds that free-form 2D creation replicated without moderation makes an experience **Moderate (13+)**.

**Asset-loading permissions** exist "to prevent misuse": `CreateEditableImageAsync` loads only assets owned by or shared with the experience owner, the Studio user or the player (EditableImage reference). Streaming raw pixels via HttpService sidesteps this path entirely, which is exactly what the staff bullet above addresses.

**Community Standards** (<https://about.roblox.com/community-standards>, fetched 2026-10-15):
- Misusing Roblox Systems: "Attempting to circumvent our safety systems."
- Directing Users Off-Platform: "You may not link to, share, or display URLs of any external websites or services except by using the Social Links feature…"
- IP: Roblox "will remove infringing content upon receiving a valid copyright or trademark takedown request."

**Terms of Use** (version effective 2026-11-01, as fetched): I found **no clause that names external images or video by name**. The relevant hooks are the generic ones: no circumventing "any technological measure designed to protect the Services", Roblox's statement that it evaluates experiences for "potential bypasses to our safety systems", and the Creator Terms' Restrictions on Use. The EditableImage doc links to `#creators-restrictions-on-use` as the governing section. **UNVERIFIED** whether an older ToU revision carried specific Mesh/Image API language.

**Enforcement record:**
- I found **no Roblox staff post announcing a ban** of a specific external-video project, and **no news coverage** of one.
- Evidence of enforcement is community testimony only: "they ended up all getting banned" (2022 thread, §1.3), and authors pre-emptively withholding code (§1.4, §1.7).
- The 2019 thread <https://devforum.roblox.com/t/image-rendering-using-httpservice/350176> already carried the warning "Bypassing moderation is something that could potentially get you in trouble" (community, not staff).
- Open 2026 feature request for an image-filtering API for EditableImages: <https://devforum.roblox.com/t/add-an-image-filtering-api-to-assetservice-for-editableimages/4704256> (2026-06-26, no staff reply). It shows there is still **no sanctioned way to moderate runtime pixels**. Developers cite the Maturity questionnaire's freeform-content question as the operative rule. The exact wording is **UNVERIFIED** because it was not transcribed.
- Community discussion (boyned blog, <https://blog.boyned.com/articles/i-cannot-use-editable-images/>; ID-verification complaint thread <https://devforum.roblox.com/t/remove-required-id-verification-for-editablemeshes-images/3981479>, 2025-10) confirms that ID verification attaches to the **experience owner**.

---

## 5. What this means for Archive Watch (inference)

- **Technically feasible, at low resolution.** A Worker or server with yt-dlp/ffmpeg could send archive.org frames as raw or QOI RGBA batches to a Roblox server, relay them over `RemoteEvent` buffers, and draw them with `WritePixelsBuffer` at roughly ≤256x144 and ~12-24 fps, with no external audio. Audio would require uploaded Roblox audio assets, which are moderated and length- and cost-limited, or captions only.
- **Policy-wise it is exactly what staff told creators not to do** ("asset-like content from off-platform sites"). Any experience doing it would be ID-attributed to the owner and exposed to removal. A public-domain catalog does not change the moderation-bypass character of the pipeline, because Roblox never sees the pixels.
- **The sanctioned route is uploaded `VideoFrame` assets** (see 03-publishing-policy.md), which are moderated, cost Robux, and are capped in length.
