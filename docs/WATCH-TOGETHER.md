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
needs. (Research §3's ReplayKit note is the fallback if composition cannot
hold 30 fps on the oldest supported iPhone; that measurement is Phase 0 and
its result is recorded in §9.)

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
- Never hide health numbers; never auto-lower quality silently — an
  adaptive-bitrate step is shown as it happens.

## §6 — Platform requirements checklist

1. `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` (iOS, macOS,
   tvOS — Continuity Camera needs both on tvOS).
2. `AVAudioSession` `.playAndRecord` with `.mixWithOthers` and
   `.defaultToSpeaker` while the Studio is open; restored on close.
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

*(empty — Phase 0)*
