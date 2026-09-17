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

### §3.4 Only films the audit can PROVE clear may go live

A broadcast goes out under the host's **own** YouTube or Twitch account, so a
wrong call here does not degrade a screen — it risks a real person's channel.
The gate is therefore narrower than the one deciding what the app will play,
and it is the one the Roku Search feed already applies to films it advertises
to a third party: **`--tier guaranteed`, i.e. `safe_pd_age` alone** (Decision
113; the owner set that bar on 2026-09-10 after measuring the looser one, in
which 107 post-1963 titles rode in on an uploader's CC mark, a CC0 dedication
on a studio cartoon, or membership of a government collection).

`audit_rights.bucket()`'s verdict is carried into the client database as
`items.rightsBucket` (schema 2) so the client applies the audit's OWN answer
rather than inventing a weaker test from `rightsStatus` and `year` — the
Decision-116 failure, where one client's tolerance hid an incorrect contract.

`StudioRights` is the predicate. Three rules bind it:

1. **An unknown verdict is a NO.** A device plays from a cached database and
   is not entitled to today's schema, so a missing or null `rightsBucket`
   refuses. The alternative is broadcasting a film whose rights nobody could
   read.
2. **Television and commercials never go live**, whatever their rights say —
   the TV spines have never passed the rights audit at all (the open owner
   decision in SCRATCHPAD).
3. **Every refusal explains itself.** A greyed-out control with no reason is
   the outcome §5 forbids, and "films published between 1964 and 1977 had
   their copyrights renewed automatically" teaches the viewer something true
   about the public domain — which is §2's whole argument.

Widening to `strict` is an **owner decision, not a developer one** (Decision
027 reserves rights calls). `StudioRights.Tier` is the single knob.

`tools/test_studio_rights.swift` asserts 14 cases including the one-year-past
boundary (1930), a `safe_pd_age` bucket with no year to support it, and the
cached-schema case; and it fails if any refusal is shorter than a sentence.
**The eligible pool, counted (2026-09-17)** from a locally built
`catalog.sqlite` carrying the new column:

| | Films |
|---|---|
| items in the shipped database | 24,943 |
| **go-live eligible (`guaranteed`)** | **4,210 (16.9%)** |
| if widened to `strict` | 7,517 (30.1%) |

Bucket distribution: `presumed_pd` 11,253 · `safe_pd_age` 4,236 · null 2,765
(the 2,771 episodes, correctly) · `safe_gov` 2,648 · `renewal_zone` 1,333 ·
`safe_archive_license` 1,233 · `renewal_zone_bw` 906 · `commercial_keep` 389 ·
`unknown_year` 178 · `safe_cc` 2.

The pool is a real one to riff: The Cabinet of Dr. Caligari, Keaton's *Cops*,
the 1925 *Wizard of Oz*, *Tarzan of the Apes*, the 1923 *Ten Commandments*.
**20 items are refused despite carrying `safe_pd_age`** because they have no
year to support the age claim — the boundary case §3.4's rule tests, firing on
real data. 0 slipped through dated 1930 or later.

**Widening to `strict` would roughly double the pool and is the owner's
call**, not a developer's (Decision 027). It admits `safe_gov` (free in the US,
not everywhere) and `safe_archive_license`/`safe_cc` (an uploader's claim about
a film they did not make — the exact class that put A Bridge Too Far and The
Simpsons pilot into the Roku feed's strict tier).

### §3.5 One engine, every Apple platform

`StudioEngine` (shared Swift, Swift 6 strict concurrency) is platform-free:
inputs are a film `AVPlayer`, an `AVCaptureSession`, and a layout; outputs
are an RTMPS connection and a local recording. Platforms differ only in the
camera source and the UI:

| Platform | Camera + mic | Notes |
|---|---|---|
| iPhone / iPad | built-in cameras | **first** — the device we can measure |
| Apple TV 4K (2nd gen+) | Continuity Camera (tvOS 17+): the iPhone is the camera, and the mic arrives as an **`AVAudioSession` port** (§9) | the film on the television, the phone on the table — the owner's own room |
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
| `theatre` | the MST3K row: film full-frame, camera strip along the bottom **right** |
| `side` | film 2/3 left, camera 1/3 right |
| `host` | camera full-frame, film in a PiP **top right** |

Every tile sits on the **5% title-safe line**, and no tile may overlap the
lower third's bottom-left stack — both were violated in the first draft and
caught by rendering the frames (§9). A layout whose camera is the ground
declares `cameraIsBackground` so the z-order follows it.

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
   AAC program to a local `mediamtx`; `ffprobe` reads back the server's
   recording and the harness asserts codec, resolution, frame rate and audio
   sample rate. The negative control is a port PROVEN closed first.
1a. `tools/test_rtmp_destinations.swift` — the same publisher against the real
   YouTube and Twitch ingest hosts with a deliberately invalid key. Requires
   `connectAcknowledged`, never merely a socket close. Needs no credential;
   run it before believing any platform change.
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

### The real ingest hosts, with no credential (2026-09-17)

`tools/test_rtmp_destinations.swift` publishes to YouTube's and Twitch's
**actual** ingest endpoints with a deliberately invalid stream key. That
exercises DNS → TCP → TLS → the C0/C1/C2 handshake → AMF0 `connect` →
`createStream` → `publish`, and the only untested step is whether a *good* key
is accepted. **A stream key is a credential and no test needs one.**

```
✓ YouTube primary (RTMPS, 443)  — connect acknowledged; closed on the bad key in 0.6s
✓ YouTube primary (RTMP, 1935)  — connect acknowledged; closed on the bad key in 0.4s
✓ YouTube backup  (RTMPS, 443)  — connect acknowledged; closed on the bad key in 0.3s
✓ Twitch global   (RTMPS, 443)  — connect acknowledged; closed on the bad key in 0.8s
✓ Twitch global   (RTMP, 1935)  — connect acknowledged; closed on the bad key in 0.6s
```

Getting there took three real protocol defects, and **two of the three passed
on two servers out of three** — which is the finding worth keeping.

1. **`connect` must be transaction 1.** The protocol fixes that number and
   YouTube hardcodes it. Ours went out as transaction 2 (the counter started
   at 1 and pre-incremented), YouTube's `_result` came back as `1.0`, nothing
   matched, and the connect timed out — while mediamtx and Twitch echoed
   whatever they were sent and worked. Found only by dumping the wire
   (`AW_RTMP_WIRE=1`), which showed YouTube replying `[t5/4] [t6/5] [t20/240]
   [t20/21]` with a payload decoding to `"_result" 1.0 {fmsVer: "FMS/3,5,3,824"
   …}`. The server was answering the whole time.
2. **The connect object must be the full ffmpeg-shaped one** — `fpad`,
   `capabilities`, `audioCodecs`, `videoCodecs`, `videoFunction` alongside
   `app`/`type`/`flashVer`/`tcUrl` — and `tcUrl` must omit a default port.
   YouTube ignored the four-field version; Twitch accepted it.
3. **The client's chunk size is 128 until it says otherwise.** Moving Set
   Chunk Size after `connect` (ffmpeg's order) while still chunking at 4096
   made mediamtx report `received type 1 chunk without previous chunk`: it read
   128 bytes of our 300-byte connect and then looked for a chunk header in the
   middle of the payload. `outChunkSize` now starts at 128 and is raised only
   once the Set Chunk Size message has gone out.

**And the test itself was wrong first.** It counted *any* socket close as
"reached and refused", so it printed PASS for all five while YouTube was
actually failing at the handshake — a close during the handshake and a close
on a bad key look identical from the client. `RTMPHealth.connectAcknowledged`
now records that the server answered `connect`, and the test requires it. The
local harness had the mirror-image flaw: a hardcoded "dead" port that a
previous run's own server was still listening on, so the negative control
silently stopped being negative. It now proves the port is closed first.

### The overlay — five layouts and four cards, on the glass (2026-09-17)

`StudioOverlayRenderer` draws the lower third (title, "1926 · Buster Keaton,
Clyde Bruckman", "PUBLIC DOMAIN SINCE 1954") and the four cards. Text is
rasterised with Core Text into a bitmap only when its CONTENT changes, so a
steady lower third is laid out once for a whole show.
`tools/render_studio_overlay.swift` renders every state over a **worst-case
stand-in film** — bands from near-black to near-white, brightest across the
bottom where the lower third lives — plus a 16:9 stand-in camera with a border
and centre cross, so a squashed or mis-inset tile is obvious. The PNGs land in
`build/qa/studio-overlay/` and the rule is to LOOK at them.

**Four defects, every one of which only a rendered frame could show:**

1. *The scrim was too weak to do its job.* A 0.72→0 vertical ramp left the
   provenance line at an effective 0.39 alpha over a 240-grey band —
   unreadable. It is now a three-stop gradient that HOLDS 0.94→0.90 across the
   type and fades only above it.
2. *The scrim was full-width and darkened the camera.* In `corner` it dimmed
   the bottom 40% of the host's face. It now fades to the right as well,
   erased with `.destinationOut` in the same pass, so it ends where the type
   does. A scrim exists to make type legible — nothing else.
3. *`theatre` put the camera strip on top of the lower third,* because the
   strip was centred and the lower third is bottom-left. The strip is now
   anchored bottom-RIGHT inside the 5% title-safe margin. `host`'s film tile
   had the same collision and moved to the top-right.
4. *`host` drew no film at all.* The renderer always drew film-then-camera, so
   the full-frame camera painted straight over the film PiP. Z-order now
   follows the layout (`StudioLayout.cameraIsBackground`).

**And the overlay was not free, twice over.** Caching the text was necessary
and not sufficient: compositing the cached layer as a full-frame 1920×1080
RGBA image took the Mac's render mean from **3.40 ms to 9.02 ms** even though
it never changed and is ~90% transparent. Cropping the CIImage to the rect it
actually drew into brought it to **4.63 ms** — the overlay's true cost is
**1.2 ms**, not 5.6. A cached layer still has to be blended; bound its extent.

| 1920×1080@30 | Mac15,3 (M3) | Apple TV 4K 2nd gen (A12) |
|---|---|---|
| no overlay | 3.40 ms | 7.03 ms |
| full-frame overlay composite | 9.02 ms | — |
| overlay cropped to content | **4.63 ms** | **10.13 ms** |

The overlay's true cost is **1.2 ms on the Mac and 3.1 ms on the A12** — the
Apple TV, the weakest device the Studio runs on, sits at 30% of its frame
budget with the film, the composite, the encode, the audio mixer and the lower
third all running. 0 dropped frames, thermal nominal.

### The go-live sheet, on the glass (2026-09-17)

`GoLiveSheet_iOS` — iOS-DESIGN §8.9. Verified on the iPhone 12 with
`AW_GOLIVE_DEMO=<archiveID>` and `devicectl device capture screenshot`
(`build/qa/golive/`).

**The rules came before the shape, and that changed the shape.** The Studio
looked like a new §3 surface or a `fullScreenCover` of its own — both of which
iOS-DESIGN §11.4 forbids. Reading the doc first produced the right answer
instead: the Studio is **the player in a production mode** (§8.8), adding
camera, layout, faders, health and go-live as §8.5 overlay affordances over
the same `AVPlayerViewController` and the same resilient asset. §8.2 also had
to be amended, because it mandates `.playback` and the Studio needs the
microphone.

**The first screenshot caught the fail-closed path working in the wild.** The
General (1926) — as clear as a film gets — was REFUSED, with *"This copy has
no rights verdict in the catalog on this device, so it cannot be streamed.
Updating the catalog may resolve it."* The phone's cached database is schema 1
and carries no `rightsBucket` yet. That is §3.4's rule 1 behaving exactly as
written, on a real device, before any eligible film has ever been offered —
and it is the behaviour that would otherwise have been impossible to trust.

Two observations from the same frame: the film's meta line reads "1926 ·
Clyde Bruckman" because the catalog's `director` field holds one name where
the film has two — the sheet reports the record rather than improving it,
which is correct. And the disabled primary action sits beside its reason, not
alone (§5).

### The publisher reaches the platforms from DEVICE hardware (2026-09-17)

macOS proving the protocol does not prove it from a phone or a television:
different TLS stack, different network path, different service-class handling.
`AW_STUDIO_PROBE=1` runs the same invalid-key probe from inside the app.

| Device | YouTube RTMPS | YouTube RTMP | Twitch RTMPS | Twitch RTMP |
|---|---|---|---|---|
| iPhone 12 (iOS 26.6.1) | ✓ 1.2 s | ✓ 0.3 s | ✓ 0.7 s | ✓ 0.4 s |
| Apple TV 4K 2nd gen (tvOS 27.0) | ✓ 6.0 s | ✓ 0.3 s | ✓ 0.8 s | ✓ 0.4 s |

"✓" = `connect` **acknowledged**, then refused on the bad key. 4/4 on both.
Still no credential involved. (The Apple TV's 6.0 s first RTMPS connect is a
cold TLS session on a box that had just woken; the second is 0.3 s.)

### A process note worth keeping

The `rightsBucket` change was dispatched to CI **before** being run locally,
and `publish-db` failed. The project's own guard caught it in one line —
`AssertionError: items tuple has 32 fields, _ITEM_COLS has 31` — and then a
second site did the same thing again (episodes are materialised into `items`
by a separate row builder, which still supplied 31). Running
`python3 tools/build_sqlite.py` locally takes three minutes and would have
found both before a 40-minute CI run did. A schema change touches every
producer of that table, and there is rarely only one.

### The Studio's in-player affordances (2026-09-17)

`StudioControls_iOS` — iOS-DESIGN §8.8 in the §8.5 overlay pattern, the same
capsule shape `EpisodePlayerContainer` already uses. Verified on the iPhone 12
(`AW_STUDIO_CONTROLS_DEMO=1`, `build/qa/golive/studio-controls2.png`).

**The first version put every health number on one line, and it did not fit.**
The capsule ran nearly the full width of the screen and collided with the
shell's own controls; on a smaller phone it would truncate. §4 says health is
never hidden — but *not hidden* does not mean *all on one line*. The capsule
now carries **state · bitrate · one warning chip**, and every number lives in
the sheet's Health section one tap away. Nothing is concealed and it fits.

The warning chip earns its place: the demo deliberately runs the
frozen-film case, and the sheet says it in words a host can act on — *"The
film has stopped sending new frames — your audience is seeing a still
picture. The sound and your camera are unaffected."* That is the failure this
feature is most exposed to (§9), and it is the one a green dashboard would
hide.

Each fader carries a **live meter**, not just a slider: a fader whose effect
you cannot see until the audience has already heard it is not a control.

Also caught on the glass: `Int(x * 100) / 100` is integer maths, and it
rendered a 10.13 ms render time as "0 ms per frame". `String(format:)`.

**Not yet verified:** the capsule over the REAL player rather than the app
shell. `AVPlayerViewController`'s own chrome auto-hides, so where the capsule
can sit without colliding is a question only the wired Studio can answer.

### Wired to the player (2026-09-17)

`StudioPlayerContainer_iOS` hosts the Studio as §8.8 describes: `PlayerView`
builds and owns the transport exactly as it does for ordinary playback, and the
engine only adds OUTPUTS to the item it already has. The one addition to
`PlayerView` is `onPlayerReady`, which hands over the live `AVPlayer` — called
again on a rebuild, because a Decision-077 copy fallback brings a new player
exactly as it brings a new SharePlay coordinator.

The Detail entry point is now **one menu named Watch Together with two items**
(§1): *With friends…* (SharePlay, unchanged) and *With the world…*. The public
one is always offered, even for a film the audit will not clear — the sheet
explains why, and a hidden control teaches nothing.

The Studio cover binds to an **item**, not a Bool (§4.4) — the rule that came
from the black-player race.

**Two build-time findings worth keeping.** Seven inline `onChange` modifiers
plus a sheet, an overlay, an alert and a task defeated the SwiftUI
type-checker outright ("unable to type-check this expression in reasonable
time"), so the body is split into sub-expressions and the control bindings
live in one `ViewModifier`. That is not a style preference: it is also seven
places to forget one, replaced by a single `applyControls()`.

### Both branches of the gate, on the device, against a real verdict (2026-09-17)

Schema 2 shipped, the phone was reinstalled clean so it fetched the new
database, and both paths were screenshot (`build/qa/golive/`):

- **The General (1926)** — the sheet offers the form: "Public domain —
  published 1926, before 1930" in marquee orange, a title pre-filled from the
  catalog, privacy, layout, the policy sentence, and **Go Live enabled**.
- **Voyage to the Planet of Prehistoric Women (1967)** — refused, bucket
  `renewal_zone_bw`.

**And the refusal leaked its internal name.** The first screenshot read *"The
rights audit has not cleared this copy for streaming (renewal_zone_bw)"* —
`explain` had a case for `renewal_zone` but not for its black-and-white
sibling, so a real bucket fell through to the default and showed a host a
word from our source code. It now reads *"Films published between 1964 and
1977 had their copyrights renewed automatically."*

The durable fix is `tools/test_studio_rights_coverage.py`: it enumerates every
bucket `audit_rights.bucket()` can return, straight out of that file, and
fails if any lacks a sentence in `StudioRights.explain`. It found **twelve**
more gaps beyond the one the screenshot caught — `no_evidence`,
`modern_noyear_risk`, `uploader_cannot_dedicate`, `wrongmatch_bw`,
`renewed_copyright_classic`, the commercial family, and the rest. A contract
spanning two languages that agree only by string needs a test that reads
both; that is Decision 116's lesson, and this is the second time in this
feature it has applied.

### The platform clients (2026-09-17)

`StudioPlatforms.swift`. Shapes verified against the current documentation
rather than memory:

| | Call |
|---|---|
| YouTube | `POST /youtube/v3/liveStreams?part=snippet,cdn,status` → `cdn.ingestionInfo.{rtmpsIngestionAddress, streamName, …}`; `POST /liveBroadcasts` (title, privacy, `enableAutoStart`); `POST /liveBroadcasts/bind`; `POST /liveBroadcasts/transition`; `GET /liveChat/messages`. Scope `…/auth/youtube`. |
| Twitch | `GET /helix/users` (resolve the broadcaster id), `PATCH /helix/channels` (title, `game_id`), `GET /helix/streams/key` → `data[0].stream_key`. Scopes `channel:read:stream_key`, `channel:manage:broadcast`. Headers `Authorization: Bearer`, `Client-Id`. Ingest PoPs from the public `ingest.twitch.tv/ingests`. |

Three choices worth naming:

1. **The title is set BEFORE the key is fetched on Twitch.** A stream that
   goes live under the previous show's title is worse than one that fails to
   set a category — so the category is best-effort and the title is not.
2. **YouTube gets `enableAutoStart`/`enableAutoStop`**, so the broadcast goes
   live when bytes arrive rather than needing a transition the host would have
   to know about.
3. **The ingest template's `/{stream_key}` is stripped, not substituted**, and
   `rtmp://` is upgraded to `rtmps://` — the publisher takes an address and a
   key separately (§the publisher's own API), and RTMPS on 443 traverses more
   networks than RTMP on 1935.

`tools/test_studio_platforms.swift` proves what can be proven with **no
credential**, which is more than it sounds:

```
✓ Twitch ingest resolves — rtmps://ingest.global-contribute.live-video.net/app
✓ ingest is RTMPS · carries an app path, not a key placeholder · a backup PoP is offered
✓ unauthenticated Twitch call is refused — HTTP 401 {"error":"Unauthorized","message":"Invalid OAuth token"}
✓ unauthenticated YouTube call is refused — HTTP 401 "Request had invalid authentication credentials"
```

Both platforms answer with **their own readable reason**, which is what a host
needs to see — not a crash and not a silent empty result.

**The token exchange is deliberately NOT stubbed.** Returning a placeholder
token would make every caller appear to work and fail at the far end with an
error nobody could trace. `StudioPlatformAuth.token` reports exactly what is
missing: an application registered by the account's owner (a Google Cloud
project with YouTube Data API v3; a Twitch application) and its client id in
the gitignored `Secrets.xcconfig`, beside the TMDb token. Until then the
go-live sheet's YouTube and Twitch paths surface that sentence.

**Owner action, and it is the last one.** Everything upstream of the token is
verified on real hardware.

### Chat in the program (2026-09-17)

The audience, on screen — §2.2's participation test made literal. Chat is
composited **into the program**, so every viewer sees the conversation, not
just the host. Rendered over the worst-case stand-in film with deliberately
awkward fixtures: a message longer than the column, a platform event, a
Japanese line, an emoji-only line, and a display name longer than its message
(`build/qa/studio-overlay/chat-*.png`).

Design choices, each for a reason:

- **A pill per message, not a column panel.** A panel is furniture the
  audience must look past; a pill darkens the film only where there are words.
- **Newest at the bottom**, the direction every chat client scrolls, so a
  viewer's eye already knows where a new line appears.
- **Laid out from the bottom up, stopping when the column is full**, so the
  OLDEST message falls off. A top-down layout with a height clamp silently
  drops the newest — which is the only one that must always be visible.
- **Wrapped by measurement, not character count.** This audience writes in
  more than one script, and a character budget is not a width.
- **Events get the marquee colour**, not a badge we would have to fetch.
- **A separate cache from the lower third.** Chat changes every few seconds
  and the film's title does not; one key for both would re-lay the title on
  every message.

**The bug this caught:** in the `side` layout the chat column ran straight
through the host's face. The camera is vertically centred in the right column,
so its BOTTOM is `(height − ch) / 2` — and I had used `(height + ch) / 2`, its
top. In Core Image's coordinate system y grows upward, which is exactly where
that sign error hides. Every other layout was fine, which is how it would have
shipped.

**Cost** (Mac, 1920×1080@30): render mean **4.63 → 5.41 ms**, so the chat
layer is **0.78 ms** — a second cropped composite, not a second full frame.

### The Apple TV as the Studio — Continuity Camera (2026-09-17)

`StudioContinuity.swift`, written against the **tvOS 27 SDK headers** rather
than memory, and they corrected two things:

1. **The microphone is an `AVAudioSessionPortDescription`, not a capture
   device.** `AVContinuityDevice` exposes `videoDevices: [AVCaptureDevice]`
   *and* `audioSessionInputs: [AVAudioSessionPortDescription]`. You select the
   port with `AVAudioSession.setPreferredInput(_:)`, and a capture device of
   type `.microphone` then records from whatever the routing subsystem chose —
   the header is explicit that tvOS exposes exactly one microphone device and
   "the audio routing subsystem decides which physical microphone to use".
2. **`AVCaptureDeviceTypeContinuityCamera` IS available on tvOS 17**, so once a
   phone has been paired a discovery session finds it without the picker. The
   picker is therefore a **one-time** human step, not a per-show one.

**And this explains §9's tvOS audio failure.** `.playAndRecord` fails on tvOS
("Session activation failed") because there is nothing to record *from*. Once
a continuity microphone port exists the category is legitimate — so the
session is raised only then, and lowered back to `.playback` when the phone
walks away. What looked like a platform quirk was a missing precondition.

**Verified on the Fireplace Apple TV 4K (2nd gen, AppleTV11,1, tvOS 27.0):**

```
continuity: none — No iPhone is paired as a camera yet.
SKIP camera — pair an iPhone once on this Apple TV (the system picker);
              a paired phone is found automatically afterwards
WARN no camera available — continuing film-only
```

`AVContinuityDevicePickerViewController.isSupported` returned **true** on this
box — the state is `none` (nothing paired), not `unsupported`. That is the
research doc's central claim about the hardware, now measured rather than
asserted: **a 2nd-generation Apple TV 4K can be the Studio.**

The coordinator reports and continues film-only rather than hanging or
failing, the same rule the iOS camera permission follows: a harness must never
wait on a human, and the owner is never the tester.

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
