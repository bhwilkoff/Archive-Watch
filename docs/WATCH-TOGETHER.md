# Watch Together — binding design doc

**Binding.** Every change to Watch Together — private or public — on any
platform must trace to a rule here. Where no rule fits, add the rule first
(`binding-design-doc-discipline`), then build.

Owner's brief (2026-09-17): *"reframe the feature set as 'Watch Together' and
'Watch Together Studio'. We already have the ability to do SharePlay which is
a private Watch Together experience. We are now building out the Watch
Together features so that the entire world can watch these movies together.
Let's start with Apple platforms and then build out from there where
possible."*

Research behind this document: `docs/LIVE-RIFF-RESEARCH.md` (platforms, APIs,
competitors, building blocks). This file turns that research into rules; the
research file stays as written.

---

## §1 — The two halves, one name

| | **Watch Together** (private) | **Watch Together** (public) |
|---|---|---|
| Who watches | the people on your FaceTime call | anyone on YouTube or Twitch |
| Mechanism | SharePlay group session (Decision 098, `docs/SHAREPLAY.md`) | an RTMPS broadcast produced by **Watch Together Studio** |
| Sync | `AVPlaybackCoordinator` — every peer plays its own copy | one program stream; the platform delivers it |
| Talking | the call | the host on camera + platform chat |
| Entry point | Detail → Watch Together → *With friends* | Detail → Watch Together → *With the world* |

The user-facing name is **Watch Together** on both halves, qualified by *with
friends* / *with the world*. "SharePlay" and "stream"/"broadcast" are
implementation words and appear in settings and diagnostics only. The
production surface — camera, layout, audio, go-live, chat, health — is
**Watch Together Studio** ("the Studio" in copy once the viewer is inside it).

`docs/SHAREPLAY.md` remains the binding doc for the private half; nothing in
it changes. This file governs the public half and the shared entry point.

## §2 — Why we build it (the learning-orientation test)

1. *Deepen understanding.* A show carries what the catalog verified this
   month: title, year, director, cast, and a "public domain since …" line on
   the title card and lower third, plus the chapter list. The audience learns
   what the film IS, from data that was audited, not from what a streamer
   remembers.
2. *Invite participation.* The host authors the show — layout, pauses, riffs,
   what to say about the film; the audience talks back through the platform's
   chat, which is on screen. Nothing is generated for the host.
3. *Support agency.* The Studio is a teacher of broadcasting, not a hider of
   it: bitrate, dropped frames, thermals and the audio meters are always
   visible, the stream key relationship belongs to the host's own account, and
   every automatic step (fetch the key, create the broadcast) is named on
   screen as it happens.
4. *Clarity over cleverness.* One program layout at a time from a small set of
   presets; no scene graph, no free-form widgets in v1. A host can predict
   what the audience sees.

**Automate the mechanical, preserve the meaningful.** Encoding, muxing, the
OAuth dance, key fetching and health are automated. Choosing the film, the
layout, when to pause, and what to say are never automated.

## §3 — Architecture (binding)

### §3.1 The device that plays the film encodes the show

YouTube and Twitch take RTMP/RTMPS from any encoder and nothing else from
general creators (research §1). So the Studio is **on-device**: the app that
already holds the decoded film composites it with the camera and overlays,
mixes film audio with the microphone, encodes H.264 + AAC in hardware and
publishes RTMPS itself. No server in v1; zero running cost; nothing to
operate.

### §3.2 Native frameworks only — no encoder dependency

The project ships with **no third-party packages** (CLAUDE.md repo map) and
that holds here. The Studio is built on `AVFoundation` (film frames via
`AVPlayerItemVideoOutput`, film audio via `MTAudioProcessingTap`, camera and
mic via `AVCaptureSession`), `CoreImage`/`Metal` (composite),
`VideoToolbox` (H.264), `AudioToolbox` (AAC) and `Network.framework` (TLS).
The RTMP publisher is **ours**: handshake, chunking, AMF0
`connect`/`createStream`/`publish`, FLV video/audio tags with AVC/AAC
sequence headers. Moblin's MIT implementation is the reference for protocol
corners; nothing is vendored. Decision 127 records why.

### §3.3 The film is never screen-captured

The Studio composites *our own* player output. ReplayKit/screen capture is
not used for the program: it would capture UI chrome, be foreground-only in
the worst way, and lose the separation of film and mic audio that the mixer
needs. Research §3's ReplayKit note was the fallback if composition could not
hold 30 fps on the oldest supported iPhone. **That fallback is now closed**:
the iPhone 12 renders the program in 8.41 ms of a 33.3 ms budget and the
Apple TV 4K 2nd gen in 10.70 ms (§9). In-app composition is the architecture
on every Apple device we ship to; ReplayKit is not needed and is not a
tier.

### §3.4 Only rights-KEEP films may go live

The Studio offers a film only when the rights audit KEEPS it — the same gate
the Roku Search feed uses (Decision 113/114). A hidden or unaudited item never
reaches the go-live sheet. This is the whole reason the audit exists.

### §3.5 One engine, every Apple platform

`StudioEngine` (shared Swift, Swift 6 strict concurrency) is platform-free:
inputs are a film `AVPlayer`, an `AVCaptureSession`, and a layout; outputs
are an RTMPS connection and a local recording. Platforms differ only in the
camera source and the UI:

| Platform | Camera + mic | Notes |
|---|---|---|
| iPhone / iPad | built-in cameras | **first** — the device we can measure |
| Apple TV 4K (2nd gen+) | Continuity Camera (tvOS 17+): the iPhone is camera and mic | the film on the television, the phone on the table — the owner's own room |
| Mac | any camera incl. Continuity Camera | later adds window+audio capture for a friends' call |

Android follows (RootEncoder is the only place a dependency is allowed to be
discussed, and that is a later decision). Roku and the TV web builds are
screens, never studios.

## §4 — The Studio surface (binding)

Layouts are **presets**, chosen by name, never dragged into arbitrary shapes
in v1:

| Preset | Program |
|---|---|
| `film` | film full-frame, no camera (intermission-safe) |
| `corner` | film full-frame, host camera PiP bottom-right (default) |
| `theatre` | the MST3K row: film full-frame, host silhouette/camera strip along the bottom |
| `side` | film 2/3 left, camera 1/3 right |
| `host` | camera full-frame, film paused in a PiP |

Every program carries a **lower third** drawn from catalog data (title, year,
director; "public domain since YYYY" when known) that the host toggles; a
**pre-roll** card with countdown, an **intermission** card and an **end** card
are the same renderer with the film hidden.

Audio: two faders (film, mic) with meters, film **ducks** under the mic by a
fixed 12 dB while speech is detected, mute on each. No EQ, no effects.

Health: bitrate, dropped-frame count, encoder queue depth, thermal state and
connection state are visible at all times while live, in the same six
typographic levels as everything else (CLAUDE.md typography rule). A health
value is never hidden to make the screen calmer.

Chat: the platform's live chat rendered as an overlay the host can show or
hide; messages are the platform's data and are never stored.

Go-live is one sheet: platform (YouTube / Twitch), title (pre-filled from the
film), category, privacy (YouTube), then **Go live**. Authorization is the
platform's OAuth; a stream key is fetched by API and never typed. A raw
`rtmps://` URL + key entry exists for a **custom destination** and is the
diagnostic path the harness uses.

Recording: the same encoded stream is written to an `.mp4` locally while live
(Decision 099's download location rules apply on iOS; tvOS records nothing).

## §5 — What Watch Together must never do

- Never play the film alone from a Watch Together action (SHAREPLAY §6) — the
  public half inherits it: **Go live** either goes live or says why not.
- Never offer a film the rights audit did not keep (§3.4).
- Never capture another app's audio or video on iOS/tvOS — the friends' call
  path is Mac-only and uses ScreenCaptureKit on a window the host picked.
- Never store a stream key beyond the session; never log one; never put one
  in a URL the app prints.
- Never coordinate the caption scout (SHAREPLAY §3) — the Studio composites
  the caption overlay the viewer sees; the scout stays local.
- Never use `AVPlayer.isMuted` or its volume as the film's broadcast level.
  The audio tap is `PostEffects`, so local muting silences the stream too
  (measured, §9). The film's level on air is `StudioAudioMixer.filmGain`.
- Never hide health numbers; never auto-lower quality silently — an
  adaptive-bitrate step is shown as it happens.

## §6 — Platform requirements checklist

1. `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` (iOS, macOS,
   tvOS — Continuity Camera needs both on tvOS).
2. `AVAudioSession` per platform, and never guessed — a failed activation
   silently stops `AVPlayer` (§9): **iOS/iPadOS** `.playAndRecord` + `.default`
   + `[.mixWithOthers, .allowBluetooth, .defaultToSpeaker]`; **tvOS**
   `.playback` + `.moviePlayback` + `[.mixWithOthers]` until a Continuity
   microphone is attached, and only then `.playAndRecord`. `.moviePlayback`
   with `.playAndRecord` is invalid on every platform (OSStatus -50), and
   `.defaultToSpeaker` does not exist on tvOS. Restore the previous category
   on close.
3. `UIApplication.isIdleTimerDisabled` while live; the Studio is a foreground
   experience and says so if backgrounded (a background session ends the
   show with an end card, never a frozen frame).
4. Network: the publisher runs on its own queue; back-pressure drops
   **video** frames first and never audio (viewers forgive a frame, not a
   gap in the host's voice).
5. Thermal: `ProcessInfo.thermalState` `.serious` halves the encode
   resolution and says so; `.critical` ends the show with the end card.

## §7 — Phases

| Phase | Deliverable | Gate |
|---|---|---|
| **0** | `StudioEngine` + `RTMPPublisher` proven against a local ingest (`mediamtx` on the Mac, verified by `ffprobe`), then against a test YouTube and Twitch channel; CPU/thermal numbers at 1080p30 on the iPhone 12 (our oldest) and the Apple TV 4K 2nd gen | numbers in §9 |
| **1** | iPhone/iPad Studio: presets, lower third, cards, faders + ducking, custom destination + YouTube + Twitch go-live, chat overlay, health, local recording | verified on the glass by the harness, two platforms live |
| **1b** | Apple TV Studio via Continuity Camera | the picker flow survives a two-hour show |
| **2** | Mac Studio: Continuity Camera, friends' call window capture, multistream | |
| **3** | Android phone (RootEncoder — a decision of its own) | |
| **4** | Guests by link / web broadcasting (a server compositor) | owner decision — running cost |

## §8 — Tests (run before any Studio surface ships)

1. `tools/test_rtmp_publish.swift` — the publisher pushes a synthetic H.264 +
   AAC program to a local `mediamtx`; `ffprobe` reads back the stream and the
   harness asserts codec, resolution, frame rate and audio sample rate. The
   negative control is a wrong stream key, which must be refused with the
   server's reason.
2. On-device Studio Lab (debug-only screen): starts the engine against a
   custom destination and prints fps / dropped / CPU / thermal every second to
   the console; the harness reads the numbers.
3. A ten-minute soak on the iPhone 12 and the Fireplace Apple TV at 1080p30:
   no dropped-frame growth after the first minute, thermal state never
   `.serious`.

## §9 — Measurements (filled in as they are taken)

### RTMP publisher, against mediamtx v1.21.0 + ffprobe 7.1.1 (2026-09-17, Mac)

`tools/test_rtmp_publish.swift` — synthetic 640x360@30 H.264 (VideoToolbox) +
44.1 kHz mono AAC (AudioConverter), 121 video / 120 audio frames:

```
OK: publish handshake accepted by mediamtx
  120/120 frames — sent 120v/119a, 41375 bytes, dropped 0
… publisher: publishing, 121v/120a, 42353 bytes, dropped 0
  video: h264 640x360 @ 30/1
  audio: aac 44100 Hz
OK: dead destination refused — Connection refused (NWError 61)
PASS
```

mediamtx's own log reads `stream is available and online, 2 tracks (H264,
MPEG-4 Audio)` — the handshake, the AMF0 `connect`/`createStream`/`publish`,
the `onMetaData` frame, the AVC/AAC sequence headers and the FLV tags are all
accepted by an independent server, and an independent demuxer reads the
recording back with the right shape. Nothing about the real destinations is
proven by this; it proves the transport.

**Two findings worth keeping.**

1. *The first failure was the harness, not the protocol.* mediamtx reset the
   connection (`NWError 54`) after ~41 of 121 frames, which reads exactly like
   a malformed stream. It was a data race: VideoToolbox calls back on its own
   thread and the harness appended to an unlocked `[CMSampleBuffer]` the actor
   drained from. A publisher bug and a harness bug present the same symptom —
   the server hanging up — so the instrument gets the lock before the protocol
   gets the blame.
2. *A late-joining live RTMP reader cannot be the assertion.* Probing
   `rtmp://…` while publishing returned `h264 0x0`: the AVC sequence header is
   sent once, at the start, and VideoToolbox does not repeat SPS/PPS in band,
   so a reader that arrives later has no dimensions to find. The test asserts
   against mediamtx's **recording** instead, which is the bytes the server
   actually accepted, and is not a race. (A real destination replays the
   sequence header to its own viewers; that is the platform's job, not ours.)

### Decode + composite + encode at 1080p30 (2026-09-17)

`tools/measure_studio_headroom.swift` — a real archive.org film
(`TheGeneral720p.mp4`) through `AVPlayer` → `AVPlayerItemVideoOutput` →
`ProgramRenderer` (layout `corner`) → VideoToolbox H.264 → `RTMPPublisher` →
local mediamtx. The engine's own clock drives the program at the target rate,
so "fps rendered" is what the show would actually carry.

Every row below is a run where the film was **verified to be arriving**
(`filmFrames` ≈ program frames); see "the two faults the instrument caught".

| Host | Program | Mean fps | Worst second | Render mean | Clock overruns | Dropped | Thermal |
|---|---|---|---|---|---|---|---|
| Mac15,3 (M3 Pro, 8 cores), macOS 27.0 | 1920×1080@30 | **30.1** | 30.0 | **3.40 ms** of 33.3 (10%) | 0 | 0 | nominal |
| **iPhone 12** (iPhone13,2, A14, 3.6 GB), iOS 26.6.1 | 1920×1080@30 | **30.2** | 30.0 | **8.71 ms** of 33.3 (26%) | 1 (warm-up) | 0 | nominal over 25 s |
| **Apple TV 4K 2nd gen** (AppleTV11,1, A12, 3.0 GB), tvOS 27.0 | 1920×1080@30 | **30.2** | 30.0 | **10.70 ms** of 33.3 (32%) | 0 | 0 | nominal over 25 s |

Film frames pulled: iPhone 12 **748**, Apple TV **728**, against ~750 program
frames each — the composite is real on both. Encoded ~4.5–5 Mbps at a 6 Mbps
ceiling.

Published ~4.5 Mbps over 25 s, 753 video frames, none dropped. **The
composite is 10% of the frame budget on this host**, which is the answer
§3.3 was waiting for on the Mac: in-app composition is not the expensive
part — the film decode is, and AVFoundation does that in hardware anyway.

The iPhone 12 is the oldest hardware the app supports, and it holds 1080p30
with **three quarters of the frame budget unused** and no thermal movement over
30 s. §3.3's ReplayKit fallback is therefore NOT needed: in-app composition is
the right architecture on every device we ship to. The one clock overrun is the
first frame, before the encoder has a session warmed.

Measured with `AW_STUDIO_LAB=1` via `devicectl … --console`, encoding to a null
sink. **The null sink is not a shortcut — it is the point:** on iOS a LAN
destination sits behind the local-network permission prompt, which a human
would have to tap, and the standing rule is that the owner is never the tester.
The publisher is proven independently against mediamtx (above), so it does not
need to be in the path of a headroom measurement. `encodedBytes` gives the real
program bitrate either way (~4.5 Mbps here at a 6 Mbps ceiling).

The Apple TV 4K 2nd gen is the Decision-096 hardware floor and it holds
1080p30 with two thirds of the frame budget unused, ~4.7 Mbps encoded, 728
film frames pulled for ~750 program frames, and no thermal movement. **Every
Apple device the app ships to can be the Studio.**

### The two faults the instrument caught (2026-09-17)

Both would have shipped as a working-looking Studio that broadcast a frozen
picture, and neither was visible in fps, encode count, render time, dropped
frames, bitrate-as-published or thermals.

**1. `AVPlayerItemVideoOutput` asked for 32BGRA returns nothing on tvOS.**
It works on iOS. On an Apple TV 4K 2nd gen it yielded **1 frame in 607** while
the program kept a steady 30 fps. The decoder there hands back its native
biplanar YUV; Core Image consumes either, so the engine now requests **no
format at all** (`outputSettings: nil`). Never pin a pixel format on a path
whose producer is the system decoder.

**2. `AVAudioSession.playAndRecord` fails on tvOS, and a failed activation
stops `AVPlayer` dead.** `setActive` threw "Session activation failed", and the
next diagnostic line read `rate=0.00 status=readyToPlay keepUp=y hasNew=n` —
the player was never playing. tvOS has no capture input until a Continuity
microphone is attached, so the Studio uses `.playback` there and moves to
`.playAndRecord` only when a real microphone arrives. (On iOS the pairing
`.playAndRecord` + `.moviePlayback` is itself invalid — OSStatus **-50**;
`.moviePlayback` is a playback-only mode. And `.defaultToSpeaker` does not
exist on tvOS.)

**The lesson is the instrument, not the bugs.** The first Apple TV run printed
`PASS 1920x1080@30` — mean 30.3 fps, 0 drops, thermal nominal — and was
measuring a still image. What exposed it was the **encoded bitrate**: 49–99
kbps where the iPhone showed ~4,500, because a static frame compresses to
nothing. `StudioHealth.filmFramesPulled` is now a first-class counter for
exactly this reason, the Lab refuses to call a run a composite measurement when
the film supplied fewer than a quarter of the program's frames, and
`filmDiagnostics()` separates "the player is not playing" from "no buffer for
this time". A host whose film freezes must be told; a green dashboard over a
frozen program is the failure mode this feature is most exposed to.

### The audio path (2026-09-17)

The film's audio is tapped off the player's own audio mix with
`MTAudioProcessingTap` — the mechanism the caption scout already uses
(Decision 058), so the program costs **one** decode, not two. The host's
microphone comes off the same `AVCaptureSession` as the camera. A dedicated
ticker pulls a fixed 1024-frame chunk from both rings every 1024/44100 s,
applies the §4 faders and the duck, and encodes AAC.

Measured on the Mac against a real film:

```
film audio: tapped
  filmAud 88200 samples/s   (= 44100 × 2ch, exactly the program rate)
  aac 43 frames/s           (= 44100 / 1024 = 43.07)
  level 0.02 – 0.16         (tracking the film's score)
648 AAC frames encoded and published over 15 s
```

**A/V alignment, from the server's own recording** — the strongest check
available, since it is an independent demuxer reading what the server
accepted:

| Stream | Duration |
|---|---|
| h264 1920×1080 | 15.033 s |
| aac 44100 2ch | 15.022971 s |

**10 ms of divergence over 15 seconds** (0.07%). Both clocks are measured from
the same program origin, and the publisher's timestamps share one timeline.

**Two findings.**

1. *The tap is `PostEffects`, so the host's local mute silences the
   broadcast.* Measured: with the player muted, the ring still received 88,200
   samples/s and every level read **0.00**. This is the right default — what
   the room hears is what the audience hears — but it means the Studio's film
   fader must be `StudioAudioMixer.filmGain`, never `AVPlayer.isMuted`. §5
   carries the rule.
2. *A film with no audio track is a real case, not a failure.* This catalog is
   full of silent cinema, so `FilmAudioTap.attach` returns false rather than
   erroring, `filmHasAudio` reports it, and the Lab distinguishes "no track"
   from "a track that delivered nothing" — the second is a defect, the first is
   Buster Keaton.

The film ring padded ~3–4% of samples, almost all in the first second while
the player fills its buffer. Worth watching in the soak, not worth a fix yet.

### Video + audio together, on device (2026-09-17)

| Host | Program | Mean fps | Render mean | Film audio | AAC | Level |
|---|---|---|---|---|---|---|
| iPhone 12 | 1920×1080@30 | 30.3 | **6.43 ms** of 33.3 (19%) | 90,312 samples/s | 43/s | 0.08–0.14 |

589 film frames of ~600 program frames; 868 AAC frames over 20 s; 0 dropped,
0 clock overruns, thermal nominal. Adding the whole audio path — a second
decode tap, a mixer ticker and an AAC encode — did not move the render budget.

### Permission is a human action, and a harness must never wait on one

`AVCaptureDevice.requestAccess` presents a system alert and suspends until it
is tapped. A device run hung with no output past `film …` — indistinguishable
from a deadlock in our own code — because the harness was waiting for a finger.
The standing rule is that the owner is never the tester, so the Lab now
**reports** the authorization status and refuses an undecided permission rather
than requesting it:

```
permissions: camera=not-determined microphone=not-determined
SKIP camera — grant it once on the device …; AW_STUDIO_ASK=1 will present the prompt
WARN no camera available — continuing film-only
```

`AW_STUDIO_ASK=1` is the deliberate opt-in that presents the prompt. There is
no supported way to pre-grant camera or microphone access on a real device
(`simctl privacy` is simulator-only), so this is a genuine one-time human
action — and the Lab names exactly where to do it instead of hanging.

### Still to measure (Phase 0 remainder)

- The camera tile's and microphone's cost on device — **blocked on a one-time
  camera + microphone grant** on the iPhone 12 and, for Continuity Camera, on
  the Apple TV. Everything else in Phase 0 is measured.
- A ten-minute soak on both devices: dropped-frame growth and thermal
  state (§8.3).
- The real destinations: YouTube and Twitch over RTMPS.
- The camera tile's cost (the Mac run had no camera attached).
- The audio path: film tap + mic mix → AAC.
- A ten-minute soak: dropped-frame growth and thermal state (§8.3).
