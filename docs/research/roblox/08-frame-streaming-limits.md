# 08 — Streaming frames + sound into Roblox without uploading video: hard limits

Researched 2026-10-15. Docs were read from the Creator Hub's Markdown sources (`create.roblox.com/docs/en-us/<path>.md`). Every page fetched shows `last_updated: 2026-10-15`, so these are the current docs. Anything not stated by a Roblox doc or a Roblox staff/team post is marked **UNVERIFIED**.

## TL;DR

- **The pipe works, but it is narrow.** The path is: the server polls your origin with HttpService (500 requests/min). The server then pushes `buffer` payloads to each client over a RemoteEvent. Each client decodes the frame and writes it into its own EditableImage with `WritePixelsBuffer`. Clients cannot make HTTP requests.
- **The binding limit is server→client bandwidth, and Roblox does not publish it.** The community figure is about 50 KB/s per client (UNVERIFIED). At that budget, 320x180 at 12 fps needs about 14:1 compression on 8-bit grayscale. 160x90 grayscale fits at 4:1.
- **Policy may be the real blocker.** The staff announcement that took EditableImage into published experiences says: *"Do not load asset-like content from off-platform sites or unmoderated sources."* Streaming archive.org film frames is exactly that.
- **No audio can be generated at runtime.** There is no way to push PCM samples. Sound must be an uploaded asset (free; 2,000 uploads per 30 days if ID-verified; at most 7 min and 20 MB each) or a track from the Creator Store library.

---

## 1. HttpService (server only)

| Item | Value | Source |
|---|---|---|
| Who can call it | **Server Scripts only.** "HttpService cannot be used by LocalScripts" | HttpService reference, code-sample note — https://create.roblox.com/docs/reference/engine/classes/HttpService |
| External request rate | **500 requests/min per game server**. "Requests over these thresholds will fail." The in-experience HTTP guide says exceeding it stalls requests for about 30 s | HttpService `RequestAsync` → Limitations; https://create.roblox.com/docs/cloud-services/http-service |
| Open Cloud rate | 2,500/min, a separate pool | same |
| Max response body size | **Not documented. UNVERIFIED.** The only documented size cap is on `JSONEncode`, which accepts buffers up to 50 MiB. A community thread reports an ~80 KB cap on the URL (not the body) | HttpService `JSONEncode`; https://devforum.roblox.com/t/how-do-i-bypass-the-url-limit/2025748 |
| Timeout | `RequestAsync{Timeout=}` can only make a request *shorter* than "the default request timeout". The default is not stated (UNVERIFIED) | `RequestAsync` reference |
| Latency | Not documented. The Creator Dashboard has an HttpService **Response Time** chart for measuring it | http-service guide → Observability |
| Binary bodies | **Request**: `Body` "Can be any string, including binary data" (documented). **Response**: `Body` is a Luau string, and Luau strings are 8-bit clean, so binary should survive. This is **UNVERIFIED** for responses; no doc or staff statement covers it. If it fails, fall back to base64 and `EncodingService:Base64Decode` (native) | `RequestAsync` request-field table |
| Request compression | `Compress = Enum.HttpCompression.Gzip` on `RequestAsync`, or `compress=true` on `PostAsync`. **Gzip on the request only** | `RequestAsync`, `PostAsync` reference |
| Response `Content-Encoding` | Not documented. A community post (2026-02-20) says "roblox/libcurl currently supports [zstd] as a response encoding". By implication gzip responses are decompressed too. **UNVERIFIED**; no staff confirmation | https://devforum.roblox.com/t/support-zstd-http-compression/4412422 |
| Streaming HTTP (`CreateWebStreamClient`: SSE, RawStream, WebSocket) | Exists, but is **Studio-only**. The staff post (2025-10-23, Roblox Creator Services Team) says "this feature is restricted to Studio only", calls in live experiences are blocked, and at most 4 clients may be open at once. **Not usable for a live film stream** | https://devforum.roblox.com/t/websockets-support-in-studio-is-now-available/4021932 ; HttpService description: "Within Studio, use CreateWebStreamClient()…" |
| Headers | `User-Agent` and `Roblox-Id` are locked. Ports below 1024 are blocked except 80/443, and 1194 is blocked | `RequestAsync`; http-service guide |
| Enablement | Game Settings → Allow HTTP Requests | HttpService.HttpEnabled |

**EncodingService (confirmed, documented).** Service, NotReplicated. All methods are thread-safe (callable from Actors).

```
EncodingService:Base64Encode(input: buffer): buffer
EncodingService:Base64Decode(input: buffer): buffer          -- errors on invalid base64
EncodingService:CompressBuffer(input: buffer, algorithm: Enum.CompressionAlgorithm, compressionLevel: int = 1): buffer
EncodingService:DecompressBuffer(input: buffer, algorithm: Enum.CompressionAlgorithm): buffer
EncodingService:GetDecompressedBufferSize(input: buffer, algorithm): number?
EncodingService:ComputeBufferHash(input: buffer, algorithm: Enum.HashAlgorithm): buffer
EncodingService:ComputeStringHash(input: string, algorithm: Enum.HashAlgorithm): string
```

- `Enum.CompressionAlgorithm` has exactly one item, **Zstd** (0). Levels run from −7 to 22.
- Source: https://create.roblox.com/docs/reference/engine/classes/EncodingService and https://create.roblox.com/docs/reference/engine/enums/CompressionAlgorithm
- **Ship date: UNVERIFIED.** No announcement post was found. Community posts call it "recent" in early 2026 (e.g. https://devforum.roblox.com/t/fastest-text-compression-zstd/3815978).
- **Client availability: UNVERIFIED** but likely. NotReplicated means each side has its own instance. Verify in a LocalScript before designing around it.

**buffer library.** `buffer.create(size)` takes up to **1 GiB**. It provides read/write u8/i8/u16/i16/u32/i32/f32/f64, `readbits`/`writebits`, `fromstring`/`tostring` and `copy`. Source: https://create.roblox.com/docs/reference/engine/libraries/buffer

## 2. Server → client transport

| Item | Value | Source |
|---|---|---|
| UnreliableRemoteEvent payload | **1,000 bytes**; larger events are **dropped**. The current docs say 1,000; older doc versions said 900. Unordered, no guaranteed delivery. Roblox compresses buffers inside the payload, so the on-wire size is hard to predict | https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent ; https://create.roblox.com/docs/scripting/events/remote |
| RemoteEvent (reliable) payload | **No documented per-message cap.** The old wiki's "2 MB per event" is cited by the community only (UNVERIFIED) | https://devforum.roblox.com/t/remote-event-data-limit/1638382 |
| Rate limit | "approximately 500 requests per second, per client", shared across all remotes of one type. Documented for **client→server**; server→client is not documented | RemoteEvent reference → Throttling |
| Ordering | RemoteEvents arrive in fire order, including across instances. Unreliable events have no ordering | scripting/events/remote |
| Per-player bandwidth budget | **Not documented by Roblox.** Community folklore puts it at ~50 KB/s per client; the poster admits "I couldn't find documentation on it". **UNVERIFIED — measure** with `Stats.DataReceiveKbps` on real phones | https://devforum.roblox.com/t/remote-event-limitations/3882204 ; https://devforum.roblox.com/t/i-have-question/3397777 |
| Cost on the client | The docs warn that heavy remote traffic burns CPU "processing incoming packets each frame" | https://create.roblox.com/docs/performance-optimization/improve |
| Buffers as arguments | Supported, and compressed in flight (UnreliableRemoteEvent doc: "encode and compress certain object types, such as buffers") | UnreliableRemoteEvent reference |

**Alternatives offer nothing better:**
- Attributes and StringValue replicate over the same channel, and only the latest value survives, so frames would be lost.
- MemoryStore and DataStore are server-only.
- **A client cannot fetch HTTP (confirmed)**: HttpService is server-only, and `CreateWebStreamClient` is Studio-only.
- EditableImage is NotReplicated, so each client must build its own copy from bytes it receives.

## 3. EditableImage

| Item | Value | Source |
|---|---|---|
| Max size | **1024x1024** (the default from `CreateEditableImage` is 512x512) | EditableImage.Size; AssetService:CreateEditableImage — https://create.roblox.com/docs/reference/engine/classes/AssetService |
| Memory budget | **Device-specific and dynamic; no number is published.** Creation returns `nil` when the budget is exhausted. "one 1k x 1k image uses the same budget as four 512 x 512 images" (staff, 2024-11-20). Server, Studio and plugins have "unlimited memory" | EditableImage → Memory Limits; https://devforum.roblox.com/t/3267293 |
| Display update rate | "Only a single EditableImage can be updated per frame on the display side." With one screen that is fine; with several screens, each extra screen costs a frame of latency | EditableImage → Update Limitations |
| WritePixelsBuffer | `(position: Vector2, size: Vector2, buffer)`. RGBA8, length = w·h·4. That is 230,400 B per 320x180 frame and 518,400 B per 480x270. **Timing on mobile: no published ms figure. UNVERIFIED** | EditableImage reference |
| Enablement | Off by default in published games. Turn on Creator Dashboard → Configure → Settings → **Enable Mesh / Image APIs** (Studio: Experience Settings → Security → Allow Mesh / Image APIs) | EditableImage → Enabling for Published Experiences |
| Owner requirement | Staff post (2024-11-20, "Client Beta: In-Experience Mesh & Image APIs Now Available in Published Experiences"): "you must be **13+, ID-verified, and explicitly opted-in** to using the APIs in published experiences". For groups, the **group owner** must be verified. The current class page names only the toggle and the Terms of Use, so whether the ID requirement still applies is **UNVERIFIED** | https://devforum.roblox.com/t/3267293 |
| **Runtime content rules** | Same staff post: **"Do not load asset-like content from off-platform sites or unmoderated sources"** (DataStores, source code and StringValues are given as examples). Settings and procedural seeds are fine. If 2D user content replicates without moderation, the Content Labels questionnaire must be updated, which makes the experience **Moderate / 13+**. An archive.org frame stream is off-platform, unmoderated, asset-like content. **This is the most likely reason a published experience gets actioned.** | https://devforum.roblox.com/t/3267293 |

A related prior attempt, the "EditableImage Screen Sharing" thread (2024-08 to 09), used 760 EditableImages, one HTTP GET each, with JSON payloads. `JSONDecode` caused lag spikes and Studio froze for 30–60 s. It reported no fps, had no staff reply, and was never solved: https://devforum.roblox.com/t/editableimage-screen-sharing/3127592

## 4. Luau decode performance

- **Native codegen (`--!native` / `@native`) is documented for server-side scripts only.** The docs say: "server-side scripts in your game can be compiled directly into the machine code". https://create.roblox.com/docs/luau/native-code-gen
- Client native codegen in live experiences is an open community request with no staff answer (https://devforum.roblox.com/t/enable-native-for-clients/3170510, 2024-09 to 2025-01).
- The Luau runtime recap (2025-12-19) says the codegen module "has gained support for working on Android and has been tested in production". That is not a statement that client LocalScripts run natively. https://luau.org/news/2025-12-19-luau-recap-runtime-2025/
- On iOS, assume interpreted code (Apple's executable-memory rules; community reasoning). **Plan for INTERPRETED Luau on the client.**
- **Published throughput numbers: none found.** The only buffer-vs-table benchmark (2024-03-28) is in chart images with no text values: https://devforum.roblox.com/t/topic/2893571/1

**Estimates (UNVERIFIED, to be measured on a mid-range Android phone and an iPhone):**
- Interpreted Luau on a mid-range phone: roughly 20–80 M simple VM ops/s.
- A 320x180 frame is 57,600 px.

| Codec on the client | ops/px | ops/frame | ms/frame interpreted (est.) | 12 fps feasible? | 24 fps? |
|---|---|---|---|---|---|
| zstd (EncodingService, **native C++**) + 4/8-bit gray → RGBA via a 256-entry u32 LUT + `writeu32` | ~6–8 | ~0.4 M | 5–20 | yes | probably |
| above + frame delta (add or skip unchanged runs) | ~8–12 | ~0.6 M | 8–30 | yes | marginal |
| palette + RLE decoded in Luau | ~10–15 | ~0.7 M | 10–35 | yes | marginal |
| 4x4 block DCT (separable integer IDCT + clamp) | ~25–40 | ~2 M | 25–100 | marginal | no |

**Recommendation:** let zstd (native) do the entropy work, and keep only a LUT expansion plus an optional delta in Luau. Put the decode in an Actor (EncodingService is thread-safe), and `WritePixelsBuffer` the frame once per frame on the main thread. Avoid DCT on the client.

## 5. Audio without uploads

- **No runtime PCM, synthesis or streaming API exists.**
  - The complete Audio* class list in the docs index (`llms.txt`, 2026-10-15) is: Analyzer, ChannelMixer/Splitter, Chorus, Compressor, DeviceInput/Output, Distortion, Echo, Emitter, Equalizer, Fader, Filter, Flanger, Gate, Limiter, Listener, PitchShifter, Player, Recorder, Reverb, SearchParams, SpeechToText, TextToSpeech, Tremolo.
  - There is **no AudioGenerator, AudioWaveGenerator, AudioStreamer or editable audio** class.
  - `Enum.AudioSampleFormat` (Int16 / Float32, "in an audio stream buffer") exists, but **no documented class consumes it**. That may be a future API (UNVERIFIED speculation).
- `AudioPlayer.Asset` is a ContentId and needs an asset. `AudioPlayer.AudioContent` is a hidden Content property. Its only documented non-asset source is `AudioRecorder:GetTemporaryContent()`.
- `AudioRecorder` is marked "**in development and is not available yet**". It is limited to 60 s and records only graph audio that is already playing, not samples you supply. https://create.roblox.com/docs/reference/engine/classes/AudioRecorder
- `AudioPlayer:GetWaveformAsync` only reads samples; it cannot write them.
- `AudioTextToSpeech` generates audio at runtime, but only speech.
- **Uploads** (https://create.roblox.com/docs/audio/assets):
  - Formats: mp3/ogg/wav/flac. Each file must be "less than 20 MB in size and 7 minutes in duration", at most 48 kHz, mono/stereo/5.1.
  - **Free**: ID-verified creators get 2,000 per 30 days; unverified get 100 per 30 days.
  - A 90-min film is 13 chunks of 7 min. Seams must be scheduled on `TimePosition`.
  - Audio goes through moderation and asset privacy.
- **Licensed library**:
  - The Creator Store has "more than 100,000 professionally-produced sound effects and music tracks from top audio and music partners", free to use in experiences (audio/assets doc above).
  - APM: a "hundreds of thousands of tracks" license with a **250 licensed tracks per game** cap (help article; age unknown, UNVERIFIED as of 2026): https://en.help.roblox.com/hc/articles/360000927163
  - Monstercat: 51 tracks (2020).
  - The license terms quoted on the DevForum bar using licensed music to build "a streaming service or music library" (UNVERIFIED wording).
  - Scoring a silent film with library cues is allowed in principle. License fit for continuous accompaniment is a question for the owner and Roblox.
- **For comparison, real video upload**: 13+ ID-verified, **2,000 Robux per video**, at most 5 min and 3.75 GB, 20 per day, at most 2 videos playing at once. https://create.roblox.com/docs/ui/video-frames

## 6. Bandwidth math (320x180 @ 12 fps)

Each viewer receives its own copy, so the server's outbound traffic is per-viewer × N. HTTP ingest is one stream per server, whatever the number of viewers.

| Format | raw B/frame | 4:1 B/frame | per player KB/s | 1 viewer | 10 viewers | 50 viewers |
|---|---|---|---|---|---|---|
| RGB24 | 172,800 | 43,200 | **518** | 518 KB/s | 5.2 MB/s | 25.9 MB/s (207 Mbps) |
| 8-bit gray (silent B&W) | 57,600 | 14,400 | **173** | 173 KB/s | 1.7 MB/s | 8.6 MB/s (69 Mbps) |
| 4-bit gray | 28,800 | 7,200 | **86** | 86 KB/s | 864 KB/s | 4.3 MB/s |
| 8-bit gray, 160x90 | 14,400 | 3,600 | **43** | 43 KB/s | 432 KB/s | 2.2 MB/s |

Checked against the limits found:

- **Per-player ~50 KB/s (UNVERIFIED folklore).** Only 160x90 gray at 4:1 fits. 320x180 gray needs about 14:1, which is about 4.3 KB per frame or 0.6 bits/px. That is real-codec territory, and film grain defeats delta and RLE.
- **UnreliableRemoteEvent at 1,000 B.** One 14.4 KB frame needs 15 packets, so 180 events/s per client. Losing any one tears the frame, so keyframes need the reliable RemoteEvent, which blocks on head-of-line delivery.
- **HttpService at 500/min (8.3/s).** Fetching per frame (12/s) is impossible. Batch 2–5 s segments: at 1 request per 2 s that is 30/min, and each response is ~345 KB (8-bit gray, 4:1). Max response size is UNVERIFIED.
- **EditableImage memory.** 320x180 is about 5.5% of the 1024² unit budget, so memory is not the constraint.

### What to measure first (each answers a stated unknown)
1. Real server→client ceiling. Send reliable buffers at 25/50/100/200 KB/s to a phone and read `Stats.DataReceiveKbps` and frame time. Expect a stall near ~50 KB/s if the folklore holds.
2. Does a binary `RequestAsync` response survive byte-for-byte? Compare `ComputeBufferHash` with a known file.
3. Is EncodingService available in a LocalScript, and how fast does zstd decompress a 300 KB buffer on a phone?
4. `WritePixelsBuffer` ms for 320x180 on a mid-range Android phone and an iPhone.
5. Before building anything, ask Roblox (or read the current Terms) whether streaming public-domain film frames from an off-platform host breaches the "off-platform … asset-like content" rule.
