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

Research behind this document: `docs/WATCH-TOGETHER-RESEARCH.md` (platforms, APIs,
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

### §3.4a The gate has LIMITS, and the host is told them before the first broadcast (binding)

Researched 2026-09-17, and it closes two of §9's open questions while opening
a caveat the rights gate cannot close. `StudioRights.hostWarning` carries it,
identically on every platform (enforced by
`tools/test_studio_rights_parity.py`), and it is shown on the pre-broadcast
surface — the iOS go-live sheet, the macOS and Android program panels, and on
tvOS a **one-time confirmation** before a host's first broadcast, because a
television's transport menu starts the Studio directly and there is no other
moment at which anybody reads anything (tvOS-DESIGN §8.8). It is dismissed
once, per device (`AWStudioWarningAccepted`), and the dev door honours it too.
Verified on the glass on an Apple TV 4K 3rd gen, 2026-09-17: the alert reads
**"Before your first broadcast"**, carries the warning in full, and offers
**Start the broadcast** / **Not now** — a real choice, not an acknowledgement.

**1. An automated matcher does not read our rights audit.** YouTube's own
copyright page states that a live stream may be replaced by a placeholder,
interrupted or **terminated**, and the channel struck — and, verbatim, *"your
live stream can be interrupted even if you've licensed the third-party
content"* unless the rights holder has allowlisted the channel. A creator
running a "Public Domain Theater" was kicked off and warned while streaming
**His Girl Friday**, public domain for fifty years. (That film is the one this
project's own gate refuses as `presumed_pd` — "probably in the public domain
but nothing proves it" — so the gate was right, and the incident is what the
gate's caution is FOR.)

**2. The gate clears a FILM by age; it cannot clear a COPY's score.** A
silent film's modern recorded score or a modern restoration can be under
copyright even though the film is not — and for silent cinema, which is the
entire `guaranteed` tier, a modern score is the norm rather than the
exception. `audit_rights` judges the work's age from catalogue metadata; it
has never judged a particular upload's soundtrack, and nothing in this feature
changes that.

**Why say it rather than quietly narrow the tier**: narrowing further would
leave almost nothing (4,210 films is already 16.9% of the catalogue), and the
risk is not a property of the film — it is a property of the platform's
matcher and of one upload's audio. §2's learning orientation answers this the
same way it answers provenance: expose the structure and let the host weigh
it. A host who learns this from the app before going live is better placed
than one who learns it from a strike.

**Closed while researching this** (§9's open questions): YouTube's
**50-subscriber minimum applies to the YouTube mobile app**, and the
requirements page lists encoder/RTMP streaming separately with no subscriber
threshold — so our path is not subject to it, though that is documentation
rather than a test and a fresh channel would confirm it. And **Twitch retired
Watch Parties on 2 April 2024**, so there is no licensed-content route there;
public-domain films are the route, with three copyright strikes counting as a
repeat infringer. Twitch's risk is a rights-holder NOTICE after the fact,
where YouTube's is an automated interruption during the stream — different
shapes, and only YouTube's can cut a broadcast off mid-film.

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
  in a URL the app prints. **Audited 2026-09-17: two error paths broke this.**
  `publish(to:)` takes `rtmp://host/app/KEY`, and both `badURL` throws
  interpolated that whole URL — and `RTMPPublishError`'s description is
  rendered VERBATIM in three user-visible places (`studioRefusal` on tvOS,
  `refusal` on the Mac, the readout's `lastError`) and written to the Studio Lab
  log, so a live credential had a path onto a television screen. Reaching it
  needs a malformed destination, so it had never fired. Fixed with
  `redactingKey(_:)`, which replaces the last path component with `<key>` and
  drops the query entirely — YouTube's backup ingest carries one, and a query
  is exactly where a credential hides. Redaction rather than omission, because
  "bad destination" with nothing after it diagnoses no typo.
- Never coordinate the caption scout (SHAREPLAY §3) — the Studio composites
  the caption overlay the viewer sees; the scout stays local.
- Never use `AVPlayer.isMuted` or its volume as the film's broadcast level.
  The audio tap is `PostEffects`, so local muting silences the stream too
  (measured, §9). The film's level on air is `StudioAudioMixer.filmGain`.
- Never hide health numbers; never auto-lower quality silently — an
  adaptive-bitrate step is shown as it happens.

## §6 — Platform requirements checklist

1. `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` (iOS, macOS,
   tvOS — Continuity Camera needs both on tvOS). **Audited 2026-09-17 and both
   were MISSING from `ArchiveWatch/Info.plist`**, which serves the tvOS and iOS
   targets alike (`SUPPORTED_PLATFORMS = appletvos … iphoneos`); it carried
   only the photo-library and speech keys. `StudioLab` calls
   `AVCaptureDevice.requestAccess(for: .video)` and `StudioContinuity` builds a
   real `AVCaptureSession`, and without a usage description that call does not
   prompt — **it terminates the process**. It had never fired only because
   camera access is owner-blocked, so no device run had reached it. macOS was
   already complete, entitlements included (`device.camera`,
   `device.microphone`, `device.audio-input`).
2. `AVAudioSession` per platform, and never guessed — a failed activation
   silently stops `AVPlayer` (§9): **iOS/iPadOS** `.playAndRecord` + `.default`
   + `[.mixWithOthers, .allowBluetooth, .defaultToSpeaker]`; **tvOS**
   `.playback` + `.moviePlayback` + `[.mixWithOthers]` until a Continuity
   microphone is attached, and only then `.playAndRecord`. `.moviePlayback`
   with `.playAndRecord` is invalid on every platform (OSStatus -50), and
   `.defaultToSpeaker` does not exist on tvOS. Restore the previous category
   on close.
2a. **§6.2 was implemented only in the HARNESS** (audited 2026-09-17, and the
   fourth rule in this section found that way). Every product path that starts
   the Studio — `StudioPlayerContainer_iOS`, tvOS's `DetailView`,
   `StudioSession` on the Mac — touched no audio session at all; the only code
   honouring this rule was `StudioLab`. So on iOS the show began with the
   session still in `.playback` left by ordinary playback, which **cannot
   record**: the documented `.playAndRecord` never happened and a mic tap would
   have captured nothing. Now in `StudioEngine.raiseAudioSessionForShow()`,
   beside §6.3's idle timer, with the previous category restored on stop —
   which the harness never did, so a Studio session used to leave the whole app
   in `.playAndRecord`, routing the next film on a phone to the receiver
   instead of the speaker.
3. `UIApplication.isIdleTimerDisabled` while live — set in **`StudioEngine`**,
   on iOS AND tvOS, guarded on `canImport(UIKit)` and never on a platform
   name. This is not a nicety: tvOS's five-minute screen saver takes the
   display and **invalidates the VideoToolbox session**, which killed a soak
   at 291 seconds (§9). The rule was written here from the start and
   implemented only in the test harness, behind `#if os(iOS)` — so it reached
   neither tvOS nor the product. The Studio is a foreground experience and
   says so if backgrounded (a background session ends the show with an end
   card, never a frozen frame).
4. Network: the publisher runs on its own queue; back-pressure drops
   **video** frames first and never audio (viewers forgive a frame, not a
   gap in the host's voice). See §6.4a for the budget, which is a
   LATENCY and not a byte count.

### §6.4a The back-pressure budget is measured in SECONDS, because a send queue IS the delay (binding)

The cap past which video starts yielding is
`RTMPPublisher.queueLatencyBudgetSeconds` (**1.5 s**) of the show's own
bitrate, set by the engine at publish time — not a constant.

**Why.** It was 2 MB, a number with no recorded reason, and §8.6 measured what
that means: against a 400 kbps uplink carrying a 2.5 Mbps program the backlog
climbed to 1.39 MB over seven seconds and the cap was **never reached**, so not
one frame was dropped while the publisher went on handing over 30 fps. At
2.5 Mbps, 2 MB of backlog is **6.4 seconds** of accumulated delay: the
broadcast has stopped being live long before the rule meant to protect it
engages, and every one of those queued frames is stale by the time it lands.
A queue depth is a latency, so the budget has to be expressed as one; it also
has to scale, since the same byte count is three seconds at one bitrate and
half a second at another.

**How to apply**: set it from the bitrates (`setQueueBudget`), never from a
literal. The floor of 150 kB exists so a very low-bitrate stream still has room
for a keyframe, which is several times the size of a P-frame.

**And the signal is real**: `queuedBytes` counts bytes handed to
`NWConnection` and not yet completed, which works because Apple's documented
behaviour is that `contentProcessed` is **deferred** once the connection's send
buffer passes its high-water mark. Measured: the counter sat at 0 through the
open phase, climbed once the uplink narrowed, and returned to 0 the second it
re-opened. Roughly three seconds of the stack's own buffering is absorbed
before it moves, which is slack to expect rather than a fault.
5. Thermal: `.serious` lowers the **bitrate** and says so; `.critical` ends
   the show with the end card. See §6.5 — this used to say "halves the encode
   resolution", which would have broken the publish it was meant to save.

### §6.5 Thermal pressure lowers the BITRATE, never the resolution, and `.critical` ends the show (binding)

**Corrected 2026-09-17.** This rule previously said `.serious` "halves the
encode resolution". That is wrong, and it would have failed in the worst
way — a device under thermal load, mid-broadcast, changing the one thing an
ingest will not accept.

**Why.** An RTMP stream's format is fixed for the life of the publish.
Bitmovin's RTMP live-input requirements put it plainly: *"Codec and format
parameters, such as resolution and frame rate, must not change during the
stream"*, and a constant frame rate is *"expected and mandatory"*. A
resolution change needs a new AVC sequence header mid-stream, which is the
same class of thing as declaring a stream's tracks twice — the server accepts
the publish and the picture stops being decodable, or the platform drops it.
So resolution and frame rate HOLD for the whole broadcast; the only quality
dial that may move is the bitrate, which VideoToolbox accepts on a live
session (`kVTCompressionPropertyKey_AverageBitRate` plus
`DataRateLimits`).

**The rule.**

- `.serious` → the video bitrate steps to **60%** of the configured rate, and
  the readout SAYS so (§5: never auto-lower quality silently). Resolution,
  frame rate and the keyframe interval are untouched.
- Back to `.nominal` or `.fair` → the bitrate is restored, and that is shown
  too. A step back up the host cannot see is the same defect as a step down
  they cannot see.
- `.critical` → `endShow(reason:)`. Not a quality step: at `.critical` the
  system may terminate the app outright, and an end card the audience sees is
  better than a frame that freezes because the process died.

**How to apply**: observe `ProcessInfo.thermalStateDidChangeNotification`
rather than polling — and put the response in **`StudioEngine`**, not in a
harness or a view. The last two rules in this section that lived anywhere else
(§6.3's idle timer, §6.6's reconnect) were both written here and implemented
nowhere, and the first one killed a soak at 291 seconds. Never swallow the
`OSStatus` from the property set: a bitrate step that silently failed would
report a quality reduction that never happened.

**Already correct, checked while writing this**: the encoder's keyframe
interval is `frameRate * 2` with `MaxKeyFrameIntervalDuration = 2`, i.e. two
seconds, against the researched guidance that *"a keyframe interval of 2–5
seconds is typical"*. No change.
6. **A dropped connection is RECOVERED, not merely reported** (§6.6).

### §6.6 A severed link is reconnected on a bounded deadline, and the show ends honestly when it expires (binding)

§6.4 governs a link that is *congested*. This governs one that is *gone* —
the common case on domestic Wi-Fi, and the one that silently ends a broadcast
of a two-hour film at minute twelve.

**The rule.** While the engine is running and a destination was supplied, a
publisher that reaches `.failed` or `.closed` is **reconnected**: a fresh
connect + publish to the same destination, retried on a backoff
(1, 2, 4, 8, 15, 15… seconds) until a **60-second deadline** expires. The
readout says **RECONNECTING** with the attempt count while it runs. When the
deadline expires the show **ends** — the end card, the same as
`.critical` thermal — and never sits pretending to be live.

**Why 60 seconds, and why a deadline at all.** An ingest holds a broadcast
open for a grace window and finalises it when the window expires: Mux's
configurable *reconnect window* defaults to **60 s** for standard latency and
**0 s** for its low-latency modes, and YouTube's documented behaviour is a
grace window of roughly a minute or two after which the broadcast ends. So
reconnecting is worth doing and worth doing FAST, and after about a minute
there is usually nothing left to reconnect TO — a client that keeps trying
past the window is reconnecting to a stream the platform has already
finalised, and telling the host it is live. The deadline is the honesty.

**Twitch's one-session rule works in our favour here.** Twitch accepts a
single active RTMP session per key and a new connection displaces the old
one, so a reconnect cannot collide with our own half-dead session. It also
means a reconnect must never run in parallel with a live one — one attempt
at a time, or we kick ourselves off.

**Four pieces of per-connection state must be rebuilt, and one must NOT be.**

- `transactionID` returns to **0**, so the new `connect` is transaction **1**.
  This is Decision 127's bug waiting to happen a second time: YouTube
  hardcodes that number, and two other servers echo whatever they are sent,
  so a reconnect that forgets it would fail on YouTube alone.
- `outChunkSize` and `inChunkSize` return to **128** — the only size a
  server assumes before it is told. An inbound size is not an outbound one.
- The **sequence headers go again** (`avcC`, `AudioSpecificConfig`): they are
  per-publish, and a server that never receives them accepts the publish and
  never identifies the track — which looks exactly like a network fault
  (Decision 129).
- The reconnected stream **begins with a keyframe**: the encoder is asked for
  one (`kVTEncodeFrameOptionKey_ForceKeyFrame`) and inter-frames are dropped
  until it arrives. Otherwise a rejoining viewer and the server's recording
  have nothing decodable while the stream looks live.
- **The timestamp base is KEPT.** `startTime` is not reset, so timestamps
  continue across the gap rather than restarting at zero. Two reasons: audio
  and video share that base, and re-basing both identically is precisely the
  Android §6.2h A/V-skew bug re-invited; and a server appending to the same
  asset within its reconnect window would otherwise see time run backwards.
  The gap appears as a gap, which is what it is.

### §6.1 Signing in — binding, and the two platforms are NOT the same

The app is a **public client**: it ships to devices, so it can hold no client
secret. That single fact determines both flows, and they are different
because the platforms differ, not because we chose differently.

- **YouTube / Google** — authorization code + **PKCE (S256)** through
  `ASWebAuthenticationSession`. `access_type=offline` + `prompt=consent`, or
  Google returns no refresh token and a host is signed out mid-show. The
  redirect is a custom scheme, and it is the **bundle identifier**, not the
  reversed client id: Google documents both, but a URL scheme must be declared
  in `Info.plist` at BUILD time and the reversed client id is not known until
  someone pastes a client id. `ASWebAuthenticationSession` refuses to start
  without the declaration.
- **Twitch** — the **Device Code Grant**, because Twitch's own documentation
  for public clients offers only the implicit grant or the device flow and
  says nothing about PKCE (checked 2026-09-17). Implicit returns **no refresh
  token**, so a host would re-authorise every few hours; the device flow
  returns one, and is the same code path on a television and a phone. Its
  refresh tokens are **one-time-use** — each refresh returns a new one and the
  old one dies, so a refresh that is not SAVED signs the host out.
- **Tokens live in the Keychain**, `…AfterFirstUnlockThisDeviceOnly`, never
  synchronised, never logged, never written to disk in plaintext. The stream
  key rule (§5) applies to tokens too.
- **tvOS**: `ASWebAuthenticationSession` exists from tvOS 16, but
  `presentationContextProvider`, `prefersEphemeralWebBrowserSession` and
  `cancel` are all `API_UNAVAILABLE(tvos)` — read from the tvOS 27 header. The
  television presents the flow itself and there is no anchor to hand it. **Not
  yet exercised on the glass**, because it cannot be until a client id exists.
  If the TV's own screen turns out to be unusable, the fallback is Google's
  device flow, which supports exactly the `…/auth/youtube` scope we need —
  but it requires a **client secret**, so it costs a third string and a
  secret embedded in the app. That is why PKCE is first.
- **No credential is a STATE, not an error.** With no client id the go-live
  sheet says sign-in is not set up in this build, names whose job it is, and
  greys out Go Live. It never offers a button that fails somewhere a host
  cannot see.

## §6.2 — Android (Phase 3), researched 2026-09-17

The same architecture, with **GLES doing Core Image's job**. Every Apple piece
has a direct Android counterpart, which is the finding: Android needs no
different design and — per Decision 127 — no third-party encoder either.

| Apple | Android |
|---|---|
| `AVPlayerItemVideoOutput` (film frames) | ExoPlayer rendering to a `SurfaceTexture` (external OES texture) |
| `AVCaptureVideoDataOutput` (camera) | CameraX / Camera2 to a second `SurfaceTexture` |
| Core Image `ProgramRenderer` | a GLES program compositing both plus overlays **straight into `MediaCodec`'s input `Surface`** |
| `MTAudioProcessingTap` (film audio) | **`TeeAudioProcessor`**, installed via `DefaultRenderersFactory.buildAudioSink` → `DefaultAudioSink(DefaultAudioProcessorChain(...))` |
| `AVCaptureAudioDataOutput` (mic) | `AudioRecord` |
| VideoToolbox H.264 / AudioToolbox AAC | `MediaCodec` AVC + AAC |
| `Network.framework` + TLS | `Socket` / `SSLSocketFactory` |
| `RTMPPublisher` (ours) | the same publisher, ported to Kotlin |

**The one place Android is BETTER.** Compositing into the encoder's input
`Surface` is **zero-copy**: the GPU writes the composed frame where the
encoder reads it, with no pixel readback at all. The Apple path renders
through Core Image into a `CVPixelBuffer` that VideoToolbox then consumes.
So the 8.71 ms iPhone / 10.70 ms Apple TV render figures are an upper bound
for what a comparable Android device should need, not a target to fear.

**The one place it is worse, and it is why the audio tap was researched
first.** There is no `MTAudioProcessingTap` equivalent that is *obviously* the
answer; `TeeAudioProcessor` is, and it is the documented one — Media3's own
guidance is that wrapping the `AudioSink` is NOT the recommended way to
intercept decoded PCM, and `ForwardingAudioSink` is the fallback only where a
legacy constraint forbids the processor. Getting that wrong means either
memory corruption or GC stalls in the audio path.

**Checked and rejected: Media3's composition pipeline.** `CompositionPlayer`,
`Transformer` and the `VideoCompositor` (2x2 grids, picture-in-picture
layouts, the new Lottie overlay module) look like exactly this feature and are
not: they compose **media items** for preview and file **export**. Nothing in
1.8–1.10 accepts a LIVE camera as a composition input or encodes a composed
output in real time. The library we already depend on has the words "compositor"
and "picture-in-picture" in it and still does not do this; write the GLES
program.

**Already in the project**: Media3 1.9.4 with `media3-effect` and
`media3-transformer` in the version catalog, `minSdk` 29 on the Google flavour
(23 on Amazon, Decision 100/115 — so the Studio is a **Google-flavour
feature**; Fire TV has no camera and Fire tablets are out of scope for Phase 3).

### §6.2a — The Android publisher, and what is proved so far (2026-09-17)

`android/.../studio/RtmpPublisher.kt` is a direct port of the Swift
publisher — a port and not a rewrite, because every non-obvious constant in it
was bought with a measurement against the real ingests (connect as transaction
1, the full ffmpeg-shaped connect object, `tcUrl` without a default port,
chunk size negotiated after connect). It is plain Kotlin/JVM over sockets, so
it runs from a desktop unit test against a local `mediamtx` long before a
phone is involved, exactly as the Swift one was first proven.

**PROVED — the control plane.** Against mediamtx, with `AW_RTMP_WIRE=1`
printing every inbound message:

```
<- type=5  Window Acknowledgement Size
<- type=6  Set Peer Bandwidth
<- type=1  Set Chunk Size  0x00010000 (65536)
<- type=20 _result ... NetConnection.Connect.Success "Connection succeeded"
<- type=20 _result ... (createStream → stream id 1)
<- type=20 onStatus ... NetStream.Publish.Start "publish start"
```

The handshake, the AMF0 encoding, `connect`, `releaseStream`, `FCPublish`,
`createStream` and `publish` are all accepted by a real server.

**NOT PROVED — the media plane, and the test is RED for it.** mediamtx never
lists the path as ready, which means it cannot identify the tracks from the
FLV tags we send. Four tests pass, one fails, and the failing one is correct.

**The bug this found was in the INSTRUMENT first, and that is the part worth
keeping.** The original harness asserted `publisher.health.state ==
"publishing"` — *our own optimism*, set the moment we stopped waiting for a
reply. All seven tests passed while the server logged nothing but `opened`
then `closed: EOF`: it had never accepted a publish at all. That is the same
failure as the Swift destination test that counted any socket close as success
and printed PASS for five ingests while YouTube failed at the handshake
(§9). The assertion is now the **server's own API** — does mediamtx list
`live/androidtest` as a ready path — which is the one thing here that cannot
lie, and it went red immediately.

Two further instrument fixes fell out of chasing it, both real:

- **The server's chunk size is not ours.** Reading replies with the outbound
  4096 desynchronises the parser the moment we raise it, and the symptom is
  not a parse error but an EOF, because the next byte read as a basic header
  is really payload. `inChunkSize` is now tracked separately and updated from
  the server's Set Chunk Size, as the Swift publisher already did.
- **Hand-written media is not media.** A fake NAL of zero bytes gets the
  publish accepted and the path never ready, so the honest assertion was
  unreachable. The fixtures are now a REAL x264 keyframe and a REAL AAC-LC
  frame generated by ffmpeg (`RealH264.kt`, `RealAac.kt`), and the
  AudioSpecificConfig describes the frames actually sent — the first version
  declared stereo while sending mono.

**The byte-level comparison, done (2026-09-17).** Reasoning about the framing
twice produced nothing, so the question was made observable instead:
`tools/rtmp_proxy_record.py` records the client→server stream of anything that
publishes through it, and `tools/rtmp_bisect.py` **replays a capture verbatim**
to the server. The replay is accepted or refused exactly as the live client
was — which is the whole trick, because the failure now reproduces offline
with no client, and two captures can be SPLICED at a message boundary.

Five runs halved the space each time:

```
ffmpeg preamble + our media                 FAILED
our preamble + ffmpeg media                 WORKED
our preamble + our metadata + ffmpeg media  WORKED
our sequence headers + ffmpeg frames        WORKED
ffmpeg sequence headers + our frames        FAILED
```

**So everything up to and including the sequence headers is correct**, and
independently confirmed: our connect/releaseStream/FCPublish/createStream/
publish decode to the same AMF0 values as ffmpeg's with the same transaction
ids 1–5; our `onMetaData` parses cleanly, 229 of 229 bytes, nine valid
properties; and our video sequence header is **byte-identical** to ffmpeg's
(`17000000000142c00dffe100186742c00dd90141fb011000`).

**CORRECTION, next session — that conclusion was wrong, and the publisher was
right all along.** The paragraph that stood here said "the fault is in the
frame messages alone". It is withdrawn. Marked rather than deleted, because a
wrong conclusion that was reasoned to carefully and written down confidently
is worth seeing (Decision 121).

The bisect kept narrowing until the splices stopped making sense: re-emitting
**ffmpeg's own bodies** with our framing failed, with every variable —
chunk-stream id, absolute vs delta headers, timestamps, interleaving — tried
and eliminated. So the next thing to doubt was the instrument, and the control
that settled it was truncating the KNOWN-GOOD stream:

```
ffmpeg's full original stream            WORKED
ffmpeg's first 80 original frame messages FAILED
ffmpeg's first 20                         FAILED
ffmpeg's first 6                          FAILED
```

**mediamtx does not declare a path ready on the first frames.** Every splice I
had been running was ~60–80 messages, i.e. about a second — below whatever
the server wants before it commits. The publisher's frames were never the
problem; my harness was starving it, and each "FAILED" was measuring the
length of the burst rather than the correctness of the bytes.

With the test sending 300 frames instead of 30, all eight pass, and the server
says so in its own words:

```
[path live/androidtest] stream is available and online, 2 tracks (H264, MPEG-4 Audio)
[RTMP] [conn ...] is publishing to path 'live/androidtest'
[path live/videoonly]   stream is available and online, 1 track (H264)
```

**So the Android publisher is PROVED end to end against a real server** — the
handshake, AMF0, the full command sequence, metadata, both sequence headers,
and interleaved H.264/AAC frames. The video-only line also confirms the
`declareAudio` fix: a publisher that does not advertise a track it will never
send gets a one-track path instead of hanging.

**And it runs on real Android hardware.** `RtmpDeviceTest` is an instrumented
test — the JVM one proves the protocol, this proves it survives a device's own
network stack and socket timing, which is a different question and the one
that caught this project before (Decision 082: a LocalMediaServer passed every
Mac gate and failed on the device).

```
Dongle R 4K (Google TV, API 34)     publishesFromTheDevice  PASS
AFTKRT (Fire TV Stick 4K Max, API 30) publishesFromTheDevice PASS

[RTMP] [conn 10.0.0.55:54098] opened
[path live/devicetest] stream is available and online, 2 tracks (H264, MPEG-4 Audio)
[RTMP] [conn 10.0.0.55:54098] is publishing to path 'live/devicetest'
```

It skips rather than fails when no server is reachable, because a red result
must mean the publisher is broken and never that a laptop was asleep
(Decision 107). The Pixel 8a was not reached this session — its adb-over-TLS
pairing has expired and needs re-pairing on the phone.

**The lesson is the one this feature keeps re-teaching, from the other side.**
Twice before, a harness said PASS while nothing worked. This time a harness
said FAIL while everything worked. Both are the same fault — an instrument
that was never itself checked — and the fix is the same: before believing a
verdict, run the control that should obviously produce the opposite one. The
truncated known-good stream took two minutes and would have saved most of a
session.

### §6.2b — The Android encode path, on real hardware (2026-09-17)

`StudioVideoEncoder.kt` + `StudioGl.kt`: MediaCodec H.264 configured with an
**input Surface**, and an EGL context whose surface IS that input surface. The
program is drawn by GLES and the GPU hands the result straight to the encoder
— **no readback**, which is the place §6.2 says Android is cheaper than Apple.

**Proved on a Google TV (API 34), end to end, and checked against the SERVER'S
OWN RECORDING** rather than our own opinion of it (Decision 127):

```
[path live/androidencode] stream is available and online, 1 track (H264)
[path live/androidencode] [recorder] recording 1 track (H264)

ffprobe: codec_name=h264  width=1280  height=720
centre pixel RGB = (2, 87, 160) -> normalised (0.008, 0.341, 0.627)
```

**The green channel is the proof.** The GLES clear used green = **0.35**
exactly, and the recorded frame decodes to **0.341** — the difference is
RGB→YUV420 conversion and H.264 quantisation. A black frame would have
published just as happily, and that is the failure this catches: a wrong EGL
config or a missing presentation time produces a stream that connects, is
accepted, identifies its track, and carries nothing.

**Three Android-specific traps, written down because each is silent:**

1. **`EGL_RECORDABLE_ANDROID` (0x3142)** must be in the config attributes, or
   the driver may pick a config the encoder cannot consume — a black stream
   rather than an error.
2. **MediaCodec emits Annex-B; RTMP wants AVCC.** Start codes must become
   4-byte big-endian lengths. A server fed Annex-B accepts the publish and
   never identifies the track, which looks exactly like a network fault.
3. **The frame's timestamp comes from `eglPresentationTimeANDROID`**, in
   NANOSECONDS — the only place that unit appears in this pipeline. A frame
   swapped without one is encoded at time zero.

And the avcC record is **built by hand** from csd-0/csd-1, which arrive in the
output format rather than in a buffer; Apple hands it over ready-made. The
test asserts the two bytes a malformed record gets wrong —
`configurationVersion = 1` and `lengthSizeMinusOne = 3` (0xFF).

### §6.2c — A REAL FILM through the Android chain (2026-09-17)

`StudioProgramGl.kt`: ExoPlayer decodes into a `SurfaceTexture`, GLES samples
it as an **external OES texture** and draws it aspect-fit into MediaCodec's
input surface. Proved on the Google TV, and judged from the server's own
recording — a 1280×720 frame carrying an intertitle from *The Kiss of Death*
(1916), not a colour and not black.

**It was black first, and the test passed anyway.** That is the finding. Four
defects, every one silent:

1. **`SurfaceTexture.setDefaultBufferSize` is not optional.** A
   `SurfaceTexture` not attached to a View has no size, so the decoder renders
   into a buffer that is not the film. Everything else succeeds — frames
   arrive, `updateTexImage` works, MediaCodec encodes, the server accepts and
   records the stream. A perfectly healthy broadcast of nothing.
2. **`updateTexImage()` does NOT fail when there is no new frame** — it
   re-presents the previous one. Using its return value as "a frame arrived"
   measures nothing, which is exactly how the black run reported a first frame
   it had never received. Only `setOnFrameAvailableListener` knows.
3. **That listener needs an explicit `Handler`.** The no-Handler overload
   wants a `Looper` on the calling thread and a render thread has none, so the
   callback never fires — and "no frames" then looks identical to a film that
   will not play. First real run after the fix: 0 frames. Second: 26.
4. **The sampler uniform must be bound** (`glUniform1i(sTexture, 0)`), and an
   external texture needs `samplerExternalOES` with the
   `GL_OES_EGL_image_external` extension declared. A plain `sampler2D`
   compiles and samples nothing.

**Throughput on that dongle is poor and is NOT claimed as a measurement**:
26 film frames and 39 encoded in 25 seconds, pulling an mp4 over the network
on a TV stick. The test's bar is deliberately modest because it asks "does the
film reach the encoder", not "how fast" — asserting a number the test was
never shaped to produce is how a green suite starts lying. A real throughput
figure belongs on a phone, driven by the frame-available callback rather than
a sleep loop.

**Known and deliberately left**: the film's aspect is passed in by the caller
(the test hardcodes 4:3). In the product it must come from ExoPlayer's own
video size, or a 16:9 film gets pillarboxed as though it were 4:3.

### §6.2d — The whole program composited on Android (2026-09-17)

One GLES pass now draws film, corner tile and lower third into MediaCodec.
Verified on the Google TV from the server's own recording: the lower third
renders **The Kiss of Death / 1916 · Victor Sjöström / PUBLIC DOMAIN —
PUBLISHED 1916, BEFORE 1930** with its marquee rule, and the corner tile sits
bottom-right carrying its own moving picture.

**The tile's source is a SECOND FILM, not a camera** — a deliberate
substitution, not a shortcut. Neither television on this bench has a camera,
and from the renderer's side CameraX, Camera2 and a second ExoPlayer are the
same thing: a producer rendering into a `SurfaceTexture`. What is under test
is the COMPOSITE — two external textures, z-order, the tile's rect, a blended
overlay above both. Swapping the real camera in is a change of source, not of
pipeline.

**What this frame does NOT prove**: all three layers lit at once. The film was
on a dark shot in the single frame the recorder captured, so the film layer is
black there; it was proved separately in §6.2c. Saying so rather than
implying more is the point.

**A PRODUCT fix came out of chasing the instrument.** The recorder kept
logging "recording" then "recording stopped" and writing **no file**. The
cause is not a recorder quirk: **a broadcast must BEGIN with a keyframe.**
Until one arrives, a viewer who joins and a server that is recording have
nothing decodable — the stream is live and the picture is absent.
`StudioVideoEncoder.requestKeyframe()` asks MediaCodec for one
(`PARAMETER_KEY_REQUEST_SYNC_FRAME`) the moment publishing starts, and the
recording appeared immediately. Every device test now does it. The same
reasoning explains why a mid-stream `ffmpeg` reader reports "Output file does
not contain any stream": the AVC sequence header is sent once, which is the
§9 lesson arriving on a second platform.

**Two Android drawing traps, both silent:**

- **A Bitmap's origin is top-left; GL's is bottom-left.** An overlay sampled
  with the film's texture coordinates arrives upside down, so the overlay quad
  gets its own flipped coordinates.
- **Premultiplied alpha.** A `Bitmap` from `Canvas` is already premultiplied,
  so the blend is `GL_ONE, GL_ONE_MINUS_SRC_ALPHA`; using `GL_SRC_ALPHA`
  darkens every antialiased edge.

**And the §6.2c aspect gap is closed**: the film's aspect now comes from
ExoPlayer's `onVideoSizeChanged` (including `pixelWidthHeightRatio`), not a
constant. The scrim behind the lower third is sized to the TEXT rather than
the full width — the full-width band is a defect the Apple side shipped and
then fixed by looking at it (§9).

### §6.2e — The film's AUDIO, tapped and broadcast (2026-09-17)

`StudioFilmAudioTap` + `StudioAacEncoder`: `TeeAudioProcessor` copies decoded
PCM out of ExoPlayer, MediaCodec turns it into AAC, and the publisher sends it
as a real second track. The tap is installed by overriding
`DefaultRenderersFactory.buildAudioSink` — Media3's own guidance is that
wrapping the `AudioSink` is NOT the way to intercept PCM, because
`TeeAudioProcessor` guarantees the buffer lifecycle and a hand-rolled wrapper
does not.

**Proved from the server's own recording**, which is the only place the
question can be settled:

```
stream 0: h264 1280x720
stream 1: aac  48000 Hz  stereo
mean_volume -16.8 dB   max_volume -2.7 dB
```

**The bar was deliberately not "an audio track exists".** A correctly plumbed
SILENCE satisfies that, and silence is exactly what a broken tap produces — so
the tap reports its PEAK and the test insists the film was actually heard.

**Two of my own assertions were wrong before the code was**, and both are the
same mistake in different clothes:

1. **Judging a soundtrack on its first fraction of a second.** The first run
   asserted on ~10 buffers and saw peak 0.005 — the film's fade-in, not a
   broken tap. Waiting for 120 buffers gives a real reading. This is the §6.2a
   lesson again: a burst measures the burst.
2. **Hardcoding 44.1 kHz** because that is what the Apple side happens to mix
   at. The film is **48 kHz**, and the engine must follow the SOURCE — the AAC
   encoder is built from `tap.sampleRate`, so its AudioSpecificConfig then
   describes the frames actually sent, which is the rule §6.2a was written for.
   The test now asserts a plausible RANGE, not a number.

**Two RTMP requirements MediaCodec does not volunteer**: raw AAC frames rather
than ADTS (a 7-byte ADTS header inside an FLV audio tag makes the track
undecodable while everything still "works"), and the AudioSpecificConfig,
which arrives as `csd-0` and must be published before any frame. An
ADTS-configured encoder produces no `csd-0` at all, which is the cheap check.

**A harness note worth keeping**: Gradle reported FAILED while the device log
said `run finished: 1 tests, 0 failed` — `ActivityManager: Failure reporting
to instrumentation watcher`. The run had succeeded and the RESULT could not get
home. Read the device's own verdict before believing the build's.

### §6.2f — The rights gate on Android, and a guard that the two agree (2026-09-17)

`studio/StudioRights.kt` is a port of `Studio/StudioRights.swift`, sentence for
sentence, and the wording is load-bearing: a wrong call does not degrade a
screen, it puts a real person's channel at risk of a copyright strike.

**Getting there meant carrying the verdict through the Android data plane
first.** `CatalogItem` had `year` and `contentType` but no `rightsBucket`, so
the gate could not have worked at all. The column now rides the lite select
behind a `hasRightsBucketColumn` probe — the same guard `playable` already
needed, because a shipped APK may still be reading a cached schema-1 catalog.
Absent column → null → **refuse**.

**Two copies of a safety-critical decision drift**, and the drift that matters
is not a crash: it is one platform quietly allowing a film the other refuses,
or two hosts being told different reasons for the same verdict. So
`tools/test_studio_rights_parity.py` compares the Swift and Kotlin sources
directly — the tier sets, the forbidden content types, and every per-bucket
sentence character for character — and checks both against the buckets
`audit_rights.py` can actually emit:

```
the same buckets are explained on both          PASS
every shared bucket has the IDENTICAL sentence  PASS
the guaranteed tier matches                     PASS
the strict tier matches                         PASS
the never-broadcast content types match         PASS
every bucket the audit emits has an Apple sentence    PASS
every bucket the audit emits has an Android sentence  PASS   (24 buckets)
no Android sentence leaks its own bucket name   PASS
```

**Negative-controlled, both ways** (Decision 120): with one Android sentence
reworded to "This film is probably fine, go ahead" and the guaranteed tier
quietly widened to include `safe_cc`, the test names both faults and fails.
A guard that cannot fail proves nothing — and a silently widened tier is
exactly the change that would ship a copyright strike.

Plus `StudioRightsTest` on the decision itself, 8/8: age clears, an unknown
verdict refuses, an age claim with no supporting year refuses, television and
commercials never broadcast whatever their rights say, and **every refusal is
a sentence a person can read** — over 40 characters, ending in a full stop, and
never containing its own bucket name, which is the defect that reached a user
once (`renewal_zone_bw`).

### §6.2g — The assembled engine, and two bugs only assembly could show (2026-09-17)

`studio/StudioEngine.kt` — one render loop driving film, overlay, both
encoders and the publisher, reporting health once a second, with the show's
own state (`LIVE` / `NOT SENDING` / `STOPPED`) rather than the transport's.
Rules: **ANDROID-DESIGN §9** (a–g), written first and grounded in §5.1's
existing "we add overlays only; never a parallel transport".

Every piece under it had already been proved separately on hardware
(§6.2b–e). **Both bugs the assembly found were invisible in the pieces**, and
that is the whole argument for testing the assembly as its own thing:

1. **`Dispatchers.Default` is a THREAD POOL.** An EGL context belongs to the
   thread that made it current, and a pool dispatcher may resume a coroutine
   on a different thread after every `delay()`. First assembled run:
   `IllegalStateException: eglMakeCurrent failed`. The loop now owns a
   dedicated single thread. The header comment already said "one render
   thread" — and then used a pool, which is the same class of mistake as a
   rule that lives only in a harness.
2. **A stream's tracks are declared ONCE, at publish.** The engine published
   video-only because the AAC config had not arrived yet, then began sending
   audio a second later, and mediamtx closed the connection: *"received a
   packet for audio track 0, but track is not set up"*. A track that shows up
   after publish is not a late track, it is a protocol error. The engine now
   waits for every config it will ever carry — bounded at 8 s, so a film with
   no audio goes out video-only rather than holding the broadcast forever, and
   once it has gone out video-only the audio encoder is torn down so nothing
   can send to a track that does not exist.

**Verified on the Google TV**, with the engine's OWN health as the assertion
rather than any counter the test kept: `showState == "LIVE"`, no problem
reported, and the server's recording carrying

```
stream 0: h264   start_time 0.000000
stream 1: aac    start_time 0.000000
mean_volume -16.4 dB   max_volume -2.7 dB
```

**Not yet measured on Android**: A/V alignment as a number. The Apple side has
10 ms over 15 s (§9); here the starts agree at 0.000000 and an early segment
logged *"sample of track 2 received too late"* during ramp-up, which is a
question rather than an answer. Audio timestamps come from BYTES CONSUMED and
video from the frame counter — two clocks with a shared origin only by
construction, so this deserves a measurement of its own rather than a claim.

### §6.2h — A/V alignment on Android: 47 ms out, diagnosed and corrected (2026-09-17)

The number the last section refused to claim, measured properly — and it was
**wrong**, which is why it was worth measuring.

**The instrument.** `StudioSyncDeviceTest` publishes a signal it CONTROLS
rather than a film's own content (Decision 075): once a second, one WHITE
frame is drawn at the same instant a full-scale 1 kHz burst is fed to the
audio encoder, both stamped from one clock, with black and silence between.
`tools/measure_av_sync.py` reads brightness per video frame and RMS per audio
frame out of ffmpeg's own filters, pairs each flash with its nearest burst,
and reports the median over all of them — a single pairing can be wrong, a
median over eight cannot be wrong in the same direction by accident.

**Before:**

```
androidsync-185637   median +50.5 ms   spread 21.0 ms   6 markers
androidsync-185704   median +45.0 ms   spread  5.0 ms   4 markers
```

Audio consistently ~47 ms LATE, with a small spread — a constant offset, not
drift. And 2048 samples at 44.1 kHz is **46.4 ms**, which is AAC-LC's usual
two-frame priming: the encoder does not produce the samples it was handed, so
audio carrying an INPUT timestamp arrives late against video carrying a frame
timestamp. MP4 carries priming in an edit list; **FLV has nowhere to put it**,
so the only place to correct it is the timestamp.

**After** subtracting the priming delay in `StudioAacEncoder`:

```
androidsync-190001   median +11.0 ms   spread 21.0 ms   7 markers
androidsync-190150   median  +4.5 ms   spread 21.0 ms   8 markers
```

Comparable to the Apple side's 10 ms over 15 s (§9), and well inside the
40 ms bar the analyser enforces.

**The analyser lied once first, and the tell was a COUNT, not a number.**
Between markers the signal is pure zeros, so `astats` reports `-inf`; a median
over those is `-inf`, a midpoint against it is `-inf`, and every audio frame
therefore counted as a burst. The first run found **16 "bursts" against 6
flashes** and still printed a confident `+50.5 ms`. The number happened to be
right, which is worse than being wrong — it would have been believed for the
wrong reason. The threshold is now absolute (−40 dBFS), and the analyser
**refuses to measure** when the flash and burst counts disagree by more than
two, which it duly did on a short tail segment in the very next run.

### §6.2i — The Android entry point and its refusal (2026-09-17)

`StudioController` is the Android counterpart of the Apple `StudioSession`,
and it exists for the same reason: Detail decides to go live, the PLAYER is
where the film and the surfaces are, and on Android those are two
destinations in one nav graph.

Detail's overflow now carries **one** item — "Watch Together…" — not Apple's
submenu, per ANDROID-DESIGN §9.2: there is no GroupActivities equivalent
here, so the name means the world half only and half a verb is not a verb.
Choosing it applies the rights gate and either opens the player or raises a
dialog carrying the gate's own sentence plus the policy. Never a greyed-out
row (§5), and deliberately **no fallback to ordinary playback** — a host who
asked to broadcast has not asked to watch alone.

`StudioControllerTest`, 7/7 on the decision itself: an eligible film arms and
carries its provenance line; a refused film does **not** arm, says why in a
readable sentence, and never leaks its bucket name; a missing verdict refuses
(the schema-1 case); television refuses whatever its rights say; an age claim
with no supporting year refuses; and the audio tap is handed only to the film
that was actually armed. The whole Android unit suite is 34/34, and the
cross-platform gate parity still holds.

**What is NOT verified, and the distinction matters**: how any of this LOOKS.
The Detail surface I changed is the PHONE one, and the only Android hardware
on this bench is two televisions, which run the `ui/tv` surfaces instead. The
decision is tested; the appearance is not, and it stays unverified until the
Pixel 8a's adb-over-TLS pairing is renewed — which is a one-time thing on the
phone itself.

### §6.2j — The readout on the glass, and the platform difference it exposed (2026-09-17)

§9.4's health readout and §9.3's bottom sheet now live over the shared
`PlayerScreen` — shared is the useful word: `TvAppRoot` pushes the same
composable, so unlike the phone-only Detail entry this COULD be verified on
the Google TV, and was. `aw_studio_item <archiveID>` arms the Studio and opens
the player, the same convention as `aw_start_route`, and it goes **through the
rights gate** — a verification hook that skipped the gate would be testing
something the product cannot do.

On the television the readout draws correctly: the state, encoded fps, render
milliseconds, Controls and End, with the dot grey rather than red.

**And it said `OFF`, which is the honest answer and the finding.** The engine
never started producing, and the reason is a platform difference this feature
had not yet met:

> **On Apple, `AVPlayerItemVideoOutput` is a TAP — the player keeps its own
> display and the Studio reads frames beside it. On Android,
> `Player.setVideoSurface` is EXCLUSIVE.**

`PlayerScreen` points ExoPlayer at `PlayerView`'s surface, so the engine's
film `SurfaceTexture` is never fed and `runLoop` sits in its
wait-for-film-frames loop forever. No exception, no error in logcat — just a
readout correctly reporting `OFF` while everything around it looked fine.
That the readout said `OFF` rather than pretending is the one part of this
that worked as designed.

**The fix, and it is a design choice rather than a patch.** The player must
render into the ENGINE's texture, and the engine must then draw the composed
program to two EGL window surfaces sharing one context — MediaCodec's input
surface and `PlayerView`'s. The consequence is that the host sees **the
program** rather than the bare film, which is consistent with §9.1 (the Studio
is this player with overlays) and is arguably better than the Apple
arrangement: a host watching what their audience is watching cannot be
surprised by it. Not yet built.

### §6.2k — The dual-surface render: the host sees the PROGRAM (2026-09-17)

Built and verified on the Google TV. `StudioGl` now carries a second window
surface sharing one context: MediaCodec's input surface and the host's screen.
The player renders into the engine's texture, the engine paints the composed
program onto a `SurfaceView` above `PlayerView`, and the host sees **film,
lower third and camera tile — the same frame the audience gets**. `PlayerView`
stays beneath, still owning the transport (§5.1/§9.1); it simply has no video
of its own to show.

That is a genuine improvement on the Apple arrangement rather than a
workaround for it: a host watching what their audience is watching cannot be
surprised by it.

**Two defects, both found by looking at the television:**

1. **`glViewport` belongs to the SURFACE, not the context.** Two window
   surfaces of different sizes (1280×720 and 1920×1080) share one context, and
   the viewport is context state that survives `eglMakeCurrent` — so the
   display pass inherited the encoder's viewport and drew the entire program
   into the **bottom-left 1280×720 corner** of the screen. It is now queried
   from the surface on every `makeCurrent`.
2. **The camera tile drew as an empty black rectangle** over the film, on
   every device without a camera — which is every television (§9.6).
   `layoutShowsCamera` is the host's INTENT; the tile now also requires the
   camera to have actually delivered a frame, which is the FACT.

Three lifecycle traps handled on the way, each a black screen if missed: a
`SurfaceView` is destroyed and recreated on every window change, so a stale
`EGLSurface` must be released and the engine told; an EGL surface may only be
created on the context's thread, so the handover is a flag the render loop
picks up rather than a call from the UI thread; and `filmSurface` is created
**once** rather than by a `get()` that wraps the texture afresh on every read,
which would hand the player a different object each time and leak the rest.

**A cost this exposes: the dongle cannot hold 30 fps.** The readout showed
**11 fps at 43.5 ms per frame** against a 33.3 ms budget — over budget, and
the first Android number that is. Whether that was the dongle or the dual
pass is answered in §6.2l below, and the guess in this paragraph's first
draft ("rendering twice costs roughly twice") was wrong.

### §6.2l — The second pass is cheap; the dongle is slow (2026-09-17)

The question §6.2k left open, answered on the hardware that raised it — the
same device, the same film, the same program, run with and without a display
surface. A controlled experiment beats a correlation (Decision 075), and this
one needed no second device.

```
encoder-only      37.4 / 37.5   mean 37.4 ms
encoder+display   53.0 / 29.7   mean 41.4 ms
second pass       +3.9 ms
```

**The dual pass is not the problem. The dongle is.** A SINGLE pass already
costs 37.4 ms against a 33.3 ms budget, so this device could not hold 30 fps
even drawing once. The Apple floor renders the whole program in 10.70 ms.

**And the +3.9 ms should not be read as precise**: the two-pass runs were
53.0 and 29.7 ms, a spread far wider than the delta itself, while the
one-pass runs agreed to 0.1 ms. The honest statement is that the second pass
is SMALL — smaller than the run-to-run variance — and nothing more.

**The first version of this measurement said the opposite**, and the mistake
is worth more than the number. It ran one-pass then two-pass, on the reasoning
that putting the cheaper case first would avoid flattering it. It did the
opposite: the cold run absorbed the warm-up and the result was "encoder-only
57.1 ms, encoder+display 40.3 ms" — the two-pass case apparently **faster**,
which is not a finding but an ordering artifact. A result that contradicts
physics is a result about the instrument. Warm-up is a variable like any
other: the test now discards a first run and interleaves the rest.

**What this does NOT license.** It does not say the Studio is fast enough on
Android — it says the bottleneck is this dongle's GPU and decoder, not the
architecture. A phone is the measurement that would settle whether the feature
ships well on Android, and there is still no phone on this bench.

### §6.2m — The Android TV entry, both branches on the glass (2026-09-17)

`TvDetailScreen` had no Watch Together entry at all — the phone Detail got one
and the television, which is a separate surface, did not. It has one now, and
a TV host reaches the Studio without a dev hook.

**Both branches verified on the Google TV**, which is more than the phone
entry has managed:

- **The entry**: "Watch Together" sits in the action row beside Version, with
  the broadcast icon. One item, not a submenu — ANDROID-DESIGN §9.2, because
  there is no GroupActivities equivalent here.
- **The refusal**: *His Girl Friday* (1940, `presumed_pd`) draws "This film
  cannot be streamed" with the gate's own sentence — *"This film is probably
  in the public domain but nothing proves it"* — followed by the policy. A
  genuinely instructive case: a famous film that reads as public domain and
  cannot be proved so.

The refusal was reached by D-pad rather than a hook: DOWN from Play lands on
the second row's leftmost item, which is the entry. Deterministic, unlike
counting presses across a row (the reason `aw_start_route` exists at all).

**Still ahead on Android**: a real camera, the PHONE Detail entry's
appearance, and a phone-class render measurement — all three wanting the same
Pixel.

### §6.2n §6.4 ported to Android, where the gap was worse than on Apple (2026-09-17)

`RtmpPublisher.kt` wrote every frame **synchronously to a blocking socket**,
and `StudioEngine` calls it from the one GL render thread. So a narrow uplink
did not shed frames — it BLOCKED the render loop, stalling the composite, the
encoder drain and the host's own view of the film. Apple at least had a queue
to overflow; here congestion propagated backwards into rendering. Nothing
dropped anything, and `RtmpHealth.videoFramesDropped` could only ever read 0.

Now: media goes onto a queue drained by one writer thread, with §6.4a's budget
(`setQueueBudget`, the same 1.5 s constant), video inter-frames yielding past
it and audio never. Only the setup path writes directly, and it has finished
before the thread starts, so there are never two writers. A message is framed
WHOLE in memory first, because interleaving two half-written messages is not a
corrupt frame a server complains about — it is a desynchronised chunk stream,
which reads as an EOF.

Proved against a real `mediamtx` through `tools/rtmp_throttle_proxy.py`
(`RtmpBackPressureTest`, 400 kbps against a 2.5 Mbps program):

| | value |
|---|---|
| cap / peak queued | 474 kB / **476 kB** — the policy pins the queue at the cap |
| video dropped before / during | **0** / 64 |
| **audio delivered** | **425 of 425 offered** |

All 8 `RtmpPublisherTest` cases still pass with 0 skipped, so the transport
survived the rewrite — including the case that asks the SERVER whether the path
is ready rather than trusting our own state.

**Three things this cost, all worth recording:**

1. **`close()` used to discard the queue**, which truncates the end of a
   broadcast by up to the whole latency budget of already-encoded media. It
   now flushes first, bounded, so a stop cannot hang on a link already gone.
2. **Asynchronous sends made an existing test racy.** `RtmpPublisherTest`'s
   "nothing was written" assertion read `bytesSent` immediately after sending;
   it won that race on a loopback socket until the queue existed, then failed
   honestly. `flush()` exists for this, and the test uses it.
3. **Two wrong diagnoses in a row, on the same number.** The test reported 11
   audio frames in its worst second, which read exactly like a stall. First
   theory: `MutableList<Byte>` boxing every byte (~300 kB of garbage a second)
   — fixed it, and the number did not move. Second theory: the harness was
   bucketing a partial second — fixed that too, and it still did not move. The
   answer was that the number never measured what its name claimed: it counts
   the HARNESS's iterations, which also encode and sleep. The delivered-audio
   assertion — 425 of 425 — is the one that carries the promise, and it was
   passing all along. The boxing fix is kept on its own merits with **no
   throughput claim attached**, because none was measured.

**Still NOT ported to Android**: §6.5 (thermal) and §6.6 (reconnect).

### §6.2o §6.5 ported to Android (2026-09-17)

`PowerManager.getCurrentThermalStatus()` (API 29, which is exactly the google
flavour's minSdk) polled once a second in the render loop, and
`MediaCodec.setParameters` with `PARAMETER_KEY_VIDEO_BITRATE` as the dial.
Mapping, from Android's own definitions: **SEVERE (3)** is "severe throttling
where UX is largely impacted", so it is the counterpart of Apple's `.serious`
and steps the bitrate to 60%; **CRITICAL (4) and above** — CRITICAL, EMERGENCY,
SHUTDOWN — end the show, because that is where the platform itself starts
stopping things.

**Android binds the dial harder than Apple.** The format is configured
`BITRATE_MODE_CBR`, so the codec tracks the target. On Apple the same step
moved the wire only 7% until `DataRateLimits` came down from 2× to 1.15×
(§9.y); there is no equivalent knob to get wrong here.

**Two structural choices worth the words.** The status is **injected** as
`thermalStatus: () -> Int` rather than read in the engine: the engine holds no
`Context`, and a device cannot be made hot on cue — so the seam a harness needs
is the same one the platform needs, and the `PowerManager` call lives in
`PlayerScreen` where the Context is, guarded on API level rather than on the
flavour (this file compiles into the amazon flavour at minSdk 23 too). And the
DECISION is a pure function, `StudioEngine.thermalAction(...)`, which the loop
CALLS — not a second copy — so it can be tested without a GL context or a
codec. `StudioThermalTest`, 6/6: the step, its idempotence, restore-only-when-
stepped, END_SHOW for every status from CRITICAL up, an unknown future status
above SHUTDOWN still ending the show, and SEVERE never ending it (a broadcast
that stops because a phone got warm is a worse bug than a lower bitrate).

**Also fixed here, and it was latent**: `stop()` guarded on
`compareAndSet(true, false)`, so a loop that ended ITSELF — which §6.5's
critical path does — made `stop()` a no-op, leaving the encoder, the publisher,
both surfaces and the GL context alive after the show was over. `stop()` now
tears down after a self-exit, `StudioController.pollHealth()` performs it, and
`endedReason` OUTLIVES the health reset so a surface can say why.

**What is NOT proved**: the wiring on a device. The decision is tested on the
JVM and both flavours compile; nothing has yet driven a real `PowerManager`
into a real encoder on the Google TV. §6.6 (reconnect) is still unported.

### §6.2p §6.6 ported to Android — the last unported rule (2026-09-17)

A dropped connection used to end an Android broadcast silently, exactly as it
did on Apple until §6.6 was written: the readout said OFFLINE and nothing
acted.

Now `RtmpPublisher.reconnect()` rebuilds the same publish, and
`StudioEngine.superviseTheConnection()` drives it on the same schedule as
Swift's — backoff 1/2/4/8/15 s, a 60-second deadline, one attempt at a time
(Twitch permits a single active session per key and a new connection displaces
the old), then `END_SHOW` with a reason rather than a readout that says
RECONNECTING over a stream the platform finished minutes ago. `RECONNECTING`
outranks `OFFLINE` in `showState`, because a rebuild in flight is a pause and
not an ending.

**The supervisor is NOT on `renderDispatcher`**, and that is the Android-only
hazard: the backoff sleeps up to fifteen seconds at a time, and the render
dispatcher is the single thread carrying the composite, the encode and the
host's display. Recovering there would freeze the picture for exactly as long
as it waited.

**And one thing Apple had to decide, Android gets for free.** §6.6 keeps the
timestamp base deliberately on the Swift side, because audio and video share it
and re-basing is the §6.2h A/V-skew bug re-invited. Here the timestamps come
from the ENCODERS, so they continue across the gap on their own — there is
nothing to preserve and nothing to get wrong.

Proved against a real `mediamtx` through `tools/rtmp_sever_proxy.py`, with the
assertion that matters being the SERVER's — does it call the path ready
*again*?

| | control (no reconnect) | §6.6 |
|---|---|---|
| server saw the stream again | **false** | **true** |
| publisher state | `failed` | `publishing` |
| reconnects | 0 | **1** |

The control is the point: without it the test would pass on a server that never
noticed the cut. Full Kotlin suite after the change: **42 passed, 0 skipped,
0 failed** across eight suites — the transport survived the reset, including
the case that asks the server rather than trusting our own state.

**All three rules are now on Android.** What is still unproved there is the
WIRING on a device for §6.5 and §6.6: the decisions and the transport are
tested, nothing has yet driven a real `PowerManager` or a real severed Wi-Fi
link into a running engine on the Google TV.

### §6.2q §6.6 on the GLASS, and the defect only a device could find (2026-09-17)

Driven through the **shipping app** on a Google TV (Dongle_R_4K, Android 14),
publishing to a `mediamtx` on the Mac via `tools/rtmp_sever_proxy.py`. Film:
*Battleship Potemkin* (1925), a real `safe_pd_age` item, chosen off the
device's own catalogue so the rights gate had to pass it.

To make this possible at all, a **debug-only** bench destination was added
(`--es aw_studio_dest` / `--es aw_studio_key`, `DeepLinks.pendingStudioDest`).
Until now the Android engine ran with `destination = null` in the app, so every
transport claim on this platform came from a JVM harness and nothing had ever
published from the product. **It is gated on `BuildConfig.DEBUG` and must stay
that way**: a release build honouring an intent extra like this would let any
app on the device launch ours with a destination of its choosing and redirect a
host's broadcast.

**The first device run FAILED, and it should have.** The app published
correctly — path ready, 5.17 MB ingested — the proxy severed the link at 25 s,
and the stream never came back. The JVM test for the very same rule passed.

**Why**: the supervisor was launched on the CALLER's `CoroutineScope`, which is
a Compose `LaunchedEffect` and therefore the **main** dispatcher, while
`reconnect()` does blocking socket I/O — which Android answers with
`NetworkOnMainThreadException`. The JVM test passed because it called
`reconnect()` from its own test thread and never exercised the dispatcher the
app actually uses. **A harness can prove the logic and still say nothing about
where the logic runs.**

And it was invisible because `catch (_: Exception)` **discarded the reason**, so
every attempt failed identically and logcat held nothing. That is the same
mistake as the swallowed `OSStatus` that hid the 291-second stall. The catch now
records `reconnectFault` on the health readout.

Fixed (`Dispatchers.IO`) and re-run on the same device:

| t | mediamtx |
|---|---|
| 15–30 s | `live/awbench` ready, bytes → **5.17 MB** |
| 25 s | proxy severs `conn 1` |
| 35 s | path **gone** |
| 40 s | path **ready again** — the proxy logs `conn 2: open` |
| 40–75 s | bytes climbing continuously → **9.45 MB** |

So the shipping app rebuilds a severed link on real hardware and the server
goes on ingesting. Teardown: app force-stopped, TV volume restored to what it
was, proxies and server stopped, the pulled catalogue copy deleted.

**§6.5's device wiring is still unproved** — a real `PowerManager` reaching a
real encoder needs a genuinely hot device or a debug override, and the bench
door does not cover it.

### §6.2r §6.5 on the GLASS, through the REAL platform API (2026-09-17)

No app-side override was needed, and that is the point. Android exposes
`adb shell cmd thermalservice override-status <n>`, which sets **and locks**
the status the platform itself reports — so `PowerManager` answers SEVERE for
real, `PlayerScreen`'s supplier reads it for real, the engine decides, and
`MediaCodec` is re-parameterised. Measured on a Google TV through the shipping
app, with mediamtx's own byte counter as the witness. Film: *Sherlock Jr.*
(1924).

| phase | wire rate (the SERVER's counter) |
|---|---|
| real status NONE (SoC 60.9 °C) | **2604 kbps** |
| `override-status 3`, device reports `Thermal Status: 3` | **1462 kbps** — **44% lower** |
| `override-status 4` (CRITICAL) | **path gone from mediamtx** — the show ended |
| `reset` | `IsStatusOverride: false; Thermal Status: 0` |

§6.5 asks for a step to 60%, i.e. a 40% reduction; the wire shows 44%. The
whole chain is real: platform status → `PowerManager` → the injected supplier →
`thermalAction` → `setBitrate` → the bytes a server counted.

**A caution for anyone repeating this**: `override-status` LOCKS the status, so
`cmd thermalservice reset` must run whatever happens — it is in a `finally` in
the harness, and the run verifies `IsStatusOverride: false` afterwards. Leaving
a borrowed television convinced it is overheating would be its own small
version of the film left playing in someone's living room.

**Both Android device gaps are now closed.** §6.4's back-pressure is proved
from the JVM against a real server, and §6.5 and §6.6 are proved on the glass
through the shipping app.

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

**Run them with one command**: `tools/test_studio_all.sh` (add `--soak` for
§8.3's ten minutes, `--strict` to make skips fail). It starts one `mediamtx`
for every transport case, generates the saturating clip the bitrate cases need
once, and prints a summary.

**It counts SKIPS separately and says so**, because the server-facing Kotlin
cases skip silently without a local server and were doing exactly that for a
whole session (§6.2n): *a skip is not a pass*, and a runner that folded them
together would be the most expensive kind of green.

**The full configuration passes** (2026-09-18, `--soak --strict`): every case
run, no skips tolerated, and no processes left behind.

    8.1 rtmp publish             PASS
    8.4 rtmp reconnect           PASS
    8.5 thermal                  PASS
    8.6 back-pressure            PASS
    test_studio_rights_parity    PASS
    test_studio_rights_coverage  PASS
    Kotlin suites                PASS   pass=46 skip=0 fail=0
    8.3 ten-minute soak          PASS
    pass=53 skip=0 fail=0
    SUITE RESULT: PASS

The soak inside that run: 18013 frames encoded, 18013 sent, memory +5.0 MB,
peak send queue **25 kB of the 1149 kB cap (2%)** — §6.4a's budget staying well
clear on a healthy link, which is what the soak exists to check.

`--strict` justified itself on its second run. The soak brings its own
`mediamtx` — two 1080p servers at once got the first `--soak` attempt killed
for memory pressure — so the shared one is stopped before it; but with the soak
running mid-suite, the six server-facing Kotlin cases then found nothing to
publish to and skipped. `--strict` called that FAIL; the default reporting
would have called it "PASS (with skips)". **The soak therefore runs LAST**,
after everything that needs the shared server, and nothing follows it.

The script's summary is the authority on what actually ran — the list below
says what each case IS.

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
3. A ten-minute soak at 1080p30: no dropped-frame growth after the first
   minute, thermal state never `.serious`. `tools/test_studio_soak.swift` runs
   it against a real server and asserts the negative case as well — that the
   send queue never reaches §6.4a's cap and §6.6 never fires on a healthy
   link. Device runs: the iPhone 12 and an Apple TV (**Fireplace is off
   limits**, and it is the only 2nd-gen box, so the hardware FLOOR needs a
   window the owner offers).
4. `tools/test_rtmp_reconnect.swift` — §6.6 on a real server: publish to a
   local `mediamtx`, SEVER the link mid-stream, and assert from the server's
   OWN recording that media resumes. The negative control is the same run with
   reconnection disabled, which must NOT resume — without it the test passes on
   a server that simply never noticed.
5. `tools/test_studio_thermal.swift` — §6.5 on the **real `StudioEngine`**
   (the four Studio files compile standalone against a local `mediamtx`), driven
   through `overrideThermalState`. Needs a **saturating** film: the harness
   prints the ffmpeg recipe and takes it as `AW_THERMAL_CLIP`.
6. `tools/test_studio_backpressure.swift` + `tools/rtmp_throttle_proxy.py` —
   §6.4 on the real engine: a proxy narrows the uplink mid-show so the
   publisher discovers congestion through its OWN send buffer. Asserts that the
   queue crosses the cap ONLY while throttled, that video is what yields, that
   audio advances in **every** second of the congestion, and that video
   recovers — by RATE, never by totals across windows of different lengths.

### §6.4 — Chat: Twitch needs NO credential, YouTube needs the host's (2026-09-18)

Chat was listed as *"renderer done, platform chat pending OAuth"*. That is true
of YouTube and **false of Twitch**, and the difference is the whole finding.

**Twitch reads anonymously.** The historical IRC interface accepts
`NICK justinfan<digits>` with **no password and no account**. Verified against
`tmi.twitch.tv` with no credential of any kind:

    :tmi.twitch.tv CAP * ACK :twitch.tv/tags twitch.tv/commands
    :tmi.twitch.tv 001 justinfan80596 :Welcome, GLHF!
    :tmi.twitch.tv 376 justinfan80596 :>

So the Twitch half of chat was never owner-blocked. `StudioChatTwitch` reads it
today: TLS to `irc.chat.twitch.tv:6697`, the `tags`/`commands` capabilities (which
is what carries `display-name`, `color` and the message `id`), `PRIVMSG` into
`StudioOverlay.ChatLine`, `USERNOTICE` as an event, `PONG` on every `PING` — an
unanswered ping ends the connection within minutes and the symptom is a chat
that simply stops. It **reads only**: it never sends, never authenticates, and
so cannot be mistaken for the host speaking.

**Why IRC and not EventSub.** Twitch now prefers EventSub
(`wss://eventsub.ws.twitch.tv/ws`, subscriptions created over Helix against the
session id in the welcome frame) and publishes a migration guide away from IRC.
But `channel.chat.message` requires the `user:read:chat` scope from a signed-in
user and **EventSub has no anonymous mode** — on this build it can read nothing
at all. Decision 128's rule again: take the flow the platform actually offers a
client of OUR type, not the newer one. When sign-in exists EventSub becomes the
better path, and everything above `ChatLine` is unchanged either way.

**YouTube is genuinely blocked**, and its shape is worth recording now:
`liveChatMessages.list` needs `liveChatId` + `part`, is quota-metered against
the 10,000 units/day default, returns `pollingIntervalMillis` — **the server
dictates the cadence, so a client must not invent one** — and pages
oldest-to-newest via `nextPageToken`. Its history is bounded by the FIRST
request: a reader joining late cannot recover what came before, which matters
for a show that starts its chat overlay mid-film.

**Proved** (`tools/test_studio_chat_twitch.swift`): nine parser assertions
against real IRCv3 shapes — escaped tag values (`\s`), a message containing
colons (most links do), a bare nick with no display name, a one-character
trailing parameter, a line with none — then the live transport, then real
traffic: **12 messages in 20 s from a live channel, every line with an id and an
author, buffer capped at 200.** The harness counts and never prints message
text: strangers' chat should not land in a log to prove a parser works.

**And one wrong turn, recorded because it is the session's own lesson.** The
first live run read 0 messages and reported "the channel was quiet". I doubted
that, found the read loop re-armed through an actor hop, and changed it — then
the numbers came back **identical**. The control I should have run first (a raw
socket on the same channel at the same moment) then showed 0 messages and 12
raw lines: exactly what the client had reported. The stream had ended between
probes. The client was right all along, the re-arm-in-the-callback is a better
`NWConnection` pattern and is kept on that basis, and **it is not a fix for
anything** — no throughput claim attaches to it.

### §6.4a — Chat IN the program, from the server's own recording (2026-09-18)

The reader existed and nothing called it. §4's promise is not a sidebar the
host reads — it is that **a viewer sees the chat in the broadcast** — so
`StudioSession` now starts the Twitch reader alongside the show and pushes the
tail of it through `setOverlay` once a second. Pushed rather than mutated in
place, so the renderer's id-keyed cache decides what needs rasterising: the
same eight ids arriving again cost a comparison, not a redraw.

Driven through the Mac product path with a bench destination and
`AW_STUDIO_CHAT=<channel>`, published to a local `mediamtx`, and a frame pulled
back out of **the server's own recording** — 1920×1080, 54.6 s:

| in that one frame | |
|---|---|
| the film | a *Battleship Potemkin* intertitle, full frame |
| **live Twitch chat** | **eight lines composited INTO the program**, newest at the bottom, each author in their own Twitch colour, long messages wrapped, an emoji rendered |
| the lower third | *Battleship Potemkin · 1925 · Sergei Eisenstein* + PUBLIC DOMAIN — PUBLISHED 1925, BEFORE 1930 |
| the camera tile | bottom-right |

The session log reported `carrying 8 line(s); received 13 joined=true` while it
ran. So the whole chain is proved on a product path: anonymous Twitch read →
`ChatLine` → overlay → Core Image composite → H.264 → RTMP → a server's
recording. No credential was involved at any point.

**And looking at it found a real defect that no counter would have.** The chat
column sits over the film, and a silent film's INTERTITLES are large bright
white text — the per-line scrim behind each message is not strong enough to
carry it, so several lines are hard to read exactly where a silent film is at
its brightest. Counting messages says the feature works; a frame says it is
not yet legible. **Fixed, and it was not a design decision after all.** I recorded this as one,
then found the renderer had already settled it a day earlier for the lower
third, in its own words: *"white type over an arbitrary film frame is only
legible if something guarantees the ground — and a scrim does it"*, with a fix
made on the glass when that scrim's top edge sat at 0.39 alpha and was
unreadable. Chat had per-line pills at **0.68** alpha, which over a near-white
intertitle leaves an effective ground of about 0.32 — 21 pt white type on mud.
Applying a principle the codebase has already established is not a new
decision, so the pills now hold **0.88** (events **0.92**), and they still HUG
their text rather than blacking out a column: the film showing through around
the messages is the design, and only the ground under type needed fixing.

Re-verified from a second recording over the same film: the type reads crisply
where the film is brightest. **And that run proved the event path with real
data** — a genuine Twitch subscription arrived mid-run and rendered in marquee
orange through `USERNOTICE` → `isEvent`, which until then had only been checked
against a synthetic line.

## §9 — Measurements (filled in as they are taken)

**How this section works** (the same rule Decision 092 set for `DECISIONS.md`,
for the same reason): §9 holds the measurements that describe the CURRENT
state of the evidence. Older ones are moved to
`docs/watch-together-measurements.md` **verbatim** — moved, never edited, never
summarised in place — and this file keeps a pointer to them. A measurement is a
record of what a machine did on a day; rewriting one to be shorter destroys the
only thing it was for.

Phase 0 and the pre-§6 device work now live in that archive:
the publisher against mediamtx + ffprobe, decode/composite/encode at 1080p30,
the audio path, the real ingest hosts with no credential, the overlay and
go-live surfaces on the glass, the rights gate on device, and the platform
clients. **→ `docs/watch-together-measurements.md`**

### §9.nnn The Google client is REGISTERED — and the checks that could not exist before it (2026-09-18)

The owner asked for the client ids to be created in Chrome rather than by hand
("I would like you to have these to help test all platforms"). **YouTube is
done.** A Google Cloud project with YouTube Data API v3 enabled, an OAuth
client of type **iOS** with bundle id `app.archivewatch.tvos`, written to the
gitignored `Secrets.xcconfig` and confirmed invisible to git. The id was read
out of the DOM rather than off the screen, because at the zoom that made it
legible an `l` and a `1` were the same glyph — **a credential read by eye is a
credential guessed.**

**Twitch is NOT done, and the blocker is the account, not the form.** The
registration was filled correctly (public client, Broadcaster Suite, an HTTPS
redirect — Twitch refuses `http://localhost`, so §6.1's suggestion does not
apply there) and refused twice, each time naming a different account gate:
first *"user must have a verified email to perform this action"*, then, once
the owner verified one, *"user must have two factor auth enabled"*. Both are
the owner's to clear. Neither error appears until **Create** is pressed, so
there is no way to discover them by reading the form.

**What the real id makes testable.** `test_studio_signin.swift` (§8.2) sends
deliberately invalid credentials to the real endpoints, and that is the right
test to have while no account exists — but it is structurally blind to one
defect class: a request the platform accepts in general and refuses for OUR
registration. A `redirect_uri` the client does not declare, a client of the
wrong type, a project whose API is not enabled. Every one of those surfaces as
an opaque error inside `ASWebAuthenticationSession`, on the owner's own
account, mid-flow.

`tools/test_studio_registered.swift` (§8.9) asks the registered client four
questions, each paired with the control that should produce the opposite
answer:

    authorize, real client + real redirect   HTTP 200, a 1,260,810-byte consent page
    CONTROL: client id mangled               refused (invalid_request)
    CONTROL: redirect the client omits       refused (invalid_request)
    token, real client + junk code           invalid_grant, NOT invalid_client

The last line is the whole point. The same request with a fake id returns
`invalid_client` (that is 8.2); with the real one it returns `invalid_grant` —
the code is the only thing wrong, so the client, the redirect and every
required field were accepted. And the two controls are what make the 200 mean
something: without them "Google served a page" is satisfied by any page.

It **skips** (exit 2, never a pass) where `Secrets.xcconfig` carries no id, and
skips where only one platform is configured rather than reporting a full run
over half the evidence. No client id is printed — a client id is not a secret,
but this output is pasted into commit messages and design docs, and one rule
for credential-shaped strings is cheaper than an exception (§5).

**A defect the registration exposed on the way.** §9.lll moved `GoLiveRequest`
and `StudioGoLive.destination` into `StudioPlatforms.swift` so iOS and macOS
could share them. Those types reach `Catalog.Item` and `StudioLayout`, which
are APP types — and `StudioPlatforms.swift` is compiled standalone by 8.2 and
8.7, which have no app. **Both cases stopped compiling the moment they moved**,
and the suite would have reported them as FAIL rather than silently, which is
the only reason this is a footnote. They now live in `StudioGoLive.swift`: a
file the harnesses compile may depend only on Foundation. This is §6.2n's rule
again — a harness's file list is a silent second copy of the module's
dependency graph — and it now bites in both directions.

**And an instrument that lied by not running at all.** Two `xcodebuild`
invocations wrapped in `timeout 540` returned nothing and were read as "no
errors". `timeout` is not on macOS; the shell exited 127 and the build never
started. Both were rerun without it (`** BUILD SUCCEEDED **`). The family is
§9.nn's: a command that cannot run produces the same empty output as a command
that ran clean.

### §9.fff The lip-sync stimulus: instrument built and verified (2026-09-18)

§9.eee established that Android's two tracks do not drift apart and said
plainly that this is not the same as being IN SYNC — packet timestamps cannot
show whether the same instant of film carries the same PTS in both tracks. That
needs a stimulus. This is the attempt, and it is **incomplete**.

**Built and verified: the instrument.** A 120-second clip — black with a
full-frame WHITE FLASH and a 1 kHz BEEP at the same instant, every five
seconds. Checked against itself before being trusted with anything:

    brightness   two states only: YAVG=16 (black), YAVG=235 (flash)
    flashes at   0, 5, 10 s
    beeps at     5.0156, 10.0078 s   (silence_end)

Flash and beep coincide within ~16 ms in the source, so any larger offset in a
recording of the BROADCAST is the Studio's, not the clip's.

**Built: the door.** `--es aw_play_url <url>` plays that clip instead of
resolving an archive id, DEBUG-gated for the reason the bench destination is —
honouring it in a release build would let any app make the player fetch
anything.

**NOT RUN: the measurement.** Two attempts, two different causes, both now
understood and neither yet fixed:

1. **Over HTTP from the Mac** — `ExoPlaybackException: Source error`, and the
   Python server's log shows the only fetch came from the Mac itself
   (10.0.0.90, my own curl), never from the device. The Google TV cannot reach
   a Python server on the Mac; macOS's firewall is the likely cause, and the
   curl that "proved" the clip was served proved only that the Mac can reach
   itself. **A reachability check from the wrong host is not a reachability
   check.**
2. **From a file pushed to the device** — same `Source error`, different
   reason: `PlayerScreen` builds `DefaultMediaSourceFactory(httpFactory)`, an
   HTTP-only data source factory, so a `file://` URI is handed to
   `OkHttpDataSource`, which cannot open a file.

**RESOLVED in §9.ggg**: the override now uses a `DefaultDataSource.Factory`
so `file://` resolves locally, the clip plays (first film frame at **1.3 s**
against ~13 s for a network film), and the measurement ran.

(And `-v error` swallowed `volumedetect` and `metadata=print` again while
verifying the clip, exactly as §9.nn recorded and as the memory says. Knowing
the trap did not stop me walking into it; only re-running without it did.)

### §9.mmm macOS can go live — the surface built under Rule B13g (2026-09-18)

§9.ccc found the Mac unable to broadcast at all; §9.lll made the credential path
shared; the owner approved **Rule B13g** ("Yes proceed with your plan"). This is
the surface.

**A menu command, per B13g**, beside the existing ones rather than in a new
top-level Broadcast menu, and **disabled with no film playing**. Both are the
CONSERVATIVE readings of the two questions B13g left open, taken because the
approval did not answer them, and both say so at the point of decision:
inventing a menu is the larger claim, and §B13a makes the Studio the player in a
production mode, so a broadcast of nothing is not a state the engine can serve.

**The same sheet as iOS §8.9**, using the request types that became shared in
§9.lll — the film, the rights refusal in a sentence, where it goes, how it
looks, the policy, and §3.4a's warning. §B13c's reasoning is why: it already
chose mirroring over invention, so a host who learned the iPhone knows the Mac.

**Seen on the glass** (window capture, app running, film playing): the sheet
carries the film with its provenance line in marquee orange, the platform
picker, **the unconfigured sign-in state** ("Signing in to YouTube is not…"),
the pre-filled title, privacy, layout, the policy sentence and the §3.4a
warning. Go Live is greyed, which is Decision 128's rule working: a build with
no client id cannot publish, and the sheet says why rather than failing inside
the auth boundary.

**What is wired and what is not.** On commit the sheet resolves the destination
through `StudioGoLive.destination(for:film:)` and hands it to
`StudioSession.armDestination`, which now prefers a real destination over the
`AW_STUDIO_DEST` diagnostic door. **That path cannot be exercised until the
client ids exist** — by design, since Go Live is greyed without them — so it is
compiled and unrun, and this entry does not claim otherwise.

**The REFUSED state, also seen on the glass.** §9.mmm showed the sheet for a
film the gate keeps; a surface is only finished when its refusal is looked at
too. With `SPACE 1999 S1E8 "Dragon's Domain"` (television, 1975) the same sheet
reads:

> **This film cannot be streamed**
> Television and commercials are not offered for streaming — their rights have
> not been audited.
> Only films published before 1930 can be streamed — age is the one
> public-domain claim nobody can dispute, and a stream goes out under your own
> account.

with **Go Live greyed**. That is §2.3 working on the Mac: the sentence teaches
why a 1975 television episode is different from a 1921 film, where a disabled
button teaches nothing.

**Instrument note against myself**: the first window capture used AppleScript's
reported bounds and caught part of my own terminal beside the app. The bounds
were right; the terminal was IN FRONT of the window. `screencapture -R` takes a
region of the SCREEN, not of a window, so whatever overlaps is captured too —
activate the app first. No personal data — it was my own session — but it is not the precise
window-only capture `mac_screenshot_window_only` asks for, and the bounds a
window reports are not the region `screencapture -R` will take.

### §9.lll The credential path is SHARED at last — and tvOS needs a rule of its own (2026-09-18)

§9.ccc found that `YouTubeLive` and `TwitchLive` were constructed in exactly one
file in the whole project, so tvOS and macOS could not broadcast at all. The
cause was smaller than it looked and worse than it sounded: **`GoLiveRequest`,
`GoLivePlatform` and `YouTubePrivacy` were all declared inside
`GoLiveSheet_iOS.swift`, behind `#if os(iOS)`** — so no other platform could even
EXPRESS a go-live request, let alone resolve one.

The request types and the resolver now live in shared code as
`StudioGoLive.destination(for:film:)`. iOS delegates to it and behaves
identically. **Verified by building all three Apple targets** — macOS, tvOS and
iOS — because the two files edited are iOS-only and a tvOS build would never
have compiled them.

**A correction to §9.ccc's framing.** That entry said macOS needed a go-live
surface and implied tvOS only needed the call site. Reading tvOS's actual path:
after the rights gate, the configuration check and §3.4a's confirmation, the
menu simply sets `studioFilm = film`. **It has no way for a host to choose a
platform, a title or a privacy setting** — iOS collects all three in its sheet.
So tvOS needs its own binding rule for that surface, exactly as macOS needed
§B13g, and building one without it would be inventing product on a television at
six in the morning. tvOS-DESIGN has no such rule yet.

**What this unblocks**: the moment either platform has an approved surface, the
destination is one call away, and its request shapes are already proved against
the real endpoints by §8.7. What it does NOT do is make either platform able to
broadcast today — that still needs a surface, and iOS still needs the owner's
client ids.

### §9.kkk Stamping video from the frame's own clock made it WORSE, and the change was reverted (2026-09-18)

§9.jjj measured the render instant trailing the frame's own timestamp by
30-527 ms and concluded that stamping video from `SurfaceTexture.timestamp`
would remove both the offset and the jitter. It was implemented with the care
that entry asked for — the frame's clock where it advances, a monotonic floor
where it does not, because a paused film returns the same frame and an RTMP
timeline must never stand still.

**The measurement disagreed.**

| | A/V offset (flash vs beep) |
|---|---|
| render-time stamping | **-174 ms** |
| frame's own timestamp | **-295 ms** (-287, -298, -345, -302, -263, -276) |

**Worse by ~120 ms, and in the direction the model forbids.** `frameTs` is
EARLIER than the render instant, so video timestamps should have moved earlier
and CLOSED a gap in which audio already leads. They did the opposite. The
offsets are steady across all six events rather than growing, so the monotonic
floor is not quietly dominating either — that was the first thing checked.

So the model behind §9.jjj is wrong somewhere, and the honest statement is that
**the remaining ~182 ms is not simply "video stamped late by the render lag"**.
Two candidates, neither tested and neither claimed: `SurfaceTexture.timestamp`
for a decoder frame may be the RELEASE time ExoPlayer scheduled for display,
which already carries the player's own A/V alignment and would be double-counted
by our subtraction; or the relationship between that clock and the audio tap's
sample count is not the simple one assumed.

**Reverted**, with the measurement recorded beside the line that survived, the
same way §9.rr's pacing change was. A fix whose reasoning is clean and whose
test disagrees does not get to stay on the strength of the reasoning — that is
the whole discipline, and it costs more when the reasoning is one's own.

**Where this leaves Android's A/V**: audio leads video by ~174 ms measured
(~182 ms true), down from 712 ms. The audio-side correction in §9.iii is real
and stands. The video side is OPEN, and now with one hypothesis eliminated by
experiment rather than by argument.

### §9.jjj Separating detector bias from video latency — and the render lag is JITTER, not an offset (2026-09-18)

§9.iii left ~174 ms of A/V error and said the first job was separating the
detectors' own bias from the video path's real latency, rather than correcting
them together. Both are now measured.

**The detector bias is +8 ms.** Running the same flash and beep detectors over
the SOURCE clip, where the two are simultaneous by construction, any offset they
report is theirs:

| | flash | beep |
|---|---|---|
| source | 5.000, 10.000, 15.000, 20.000, 25.000, 30.000 | 5.016, 10.008, 15.000, 20.016, 25.008, 30.000 |

Mean +8 ms, quantised in 8 ms steps. So the broadcast's measured -174 ms is a
TRUE -182 ms: correcting for bias makes the error slightly larger, not smaller,
and the whole remainder belongs to the video path.

**The video path's lag shares the right clock — and is not a constant.**
`SurfaceTexture.timestamp` is in the `nanoTime` timebase (checked, not assumed),
so it can be used directly. How far the RENDER instant trails the frame's own
timestamp, sampled once a second:

    +66.1 ms   +53.0 ms   +54.7 ms   +165.3 ms   +29.8 ms   +527.0 ms

**30 to 527 ms, mean ~149.** So stamping video at render time does not merely
shift the timeline by a fixed amount — it adds JITTER of up to half a second.
The flash test did not show that because a flash spans three source frames and
the detector takes the first bright one, which smooths exactly this.

**Why that changes the fix.** Stamping video with the frame's own timestamp
would remove both the offset and the jitter, which is better than subtracting a
constant. But it needs care the constant would not: when the film is PAUSED no
new frame arrives, `updateTexImage` returns the same frame, and its timestamp
does not advance — so repeated frames would carry identical timestamps, and an
RTMP timeline must not go backwards or stand still. The correct shape is the
frame's timestamp where it advances, with a monotonic floor where it does not.

**Not implemented here**, deliberately: that is a change to the timestamp of
every video frame in a live broadcast, and it deserves its own tick with the
flash-and-beep measurement run against it, rather than the tail of one that has
already changed the audio side.

### §9.iii The sink lead corrected: 712 ms → 174 ms, and the prediction held (2026-09-18)

§9.hhh measured the audio tap running **0.565 s ahead of playback** and
predicted that correcting it would leave about **147 ms** of the 712 ms error
(the video path's own latency plus detector bias). This is the correction and
its measurement.

**The correction uses THIS pipeline's number, not a constant.** The surface is
the only place that can see both the tap's sample clock and
`player.currentPosition`, so it measures the lead each second and reports it;
the engine adds it to the AAC encoder's start offset. A hardcoded 0.565 would
be wrong on the next device, and a device whose sink buffers differently would
be silently mis-corrected.

**It is applied BEFORE a single audio frame is sent.** Stepping an audio
timeline mid-stream is the one thing a live stream must never do. Applying it
before the publish is safe precisely because nothing has gone out yet — frames
drained earlier are dropped, so the first frame that actually ships already
carries the corrected offset. The publish now waits for a lead sample the way it
waits for the AAC config, behind the same deadline, so a pipeline that never
reports one still goes out uncorrected rather than never going out.

**And the measurement runs in every build, not just DEBUG** — only the log line
is debug-gated. A correction that existed solely in a debug build would fix the
broadcast nobody watches.

| | audio (beep) | video (flash) | offset |
|---|---|---|---|
| 1 | 4.714 | 4.907 | **-193 ms** |
| 2 | 9.706 | 9.881 | -175 ms |
| 3 | 14.698 | 14.851 | -153 ms |
| 4 | 19.714 | 19.898 | -184 ms |
| 5 | 24.706 | 24.858 | -152 ms |
| 6 | 29.698 | 29.887 | -189 ms |

**-712 ms → -174 ms**, and the predicted residual was 147 ms. Agreeing to 27 ms
is the part worth keeping: the model is understood rather than the symptom
patched, and the next correction can be aimed rather than guessed.

**STILL OUT OF TOLERANCE, and said plainly.** Audio still leads video by
~174 ms where ITU's guidance for audio-leads-video is about 45 ms. Better by
4.1x and not yet right. The remaining error is the video path — a frame is
stamped when it is RENDERED, which is after `SurfaceTexture` handed it over and
after GLES composited it, so video is late relative to its own content.
`SurfaceTexture.getTimestamp()` carries the frame's own presentation time and is
the obvious next instrument; part of the 174 ms is also detector bias (the flash
test takes the first BRIGHT frame, `silencedetect` a threshold crossing), and
separating those two is the first job, not correcting them together.

### §9.hhh Hunting the 0.7 s: the tap and playback advance together, and the instrument was masked by RESUME (2026-09-18)

§9.ggg measured audio leading video by ~0.7 s and named a hypothesis: the
`TeeAudioProcessor` taps PCM on its way INTO the audio sink — audio the player
has not played yet — so the tap runs ahead of playback by the sink's buffer
depth. Testing that before fixing anything, because a fix aimed at the wrong
cause is how a 0.7 s error becomes two errors.

The test compares the tap's own sample clock against the player's playback
position, once a second, where both are in scope:

    playback=112.204 s  tap=43.073 s  playback-tap=+69.131 s
    playback=119.259 s  tap=50.109 s  playback-tap=+69.150 s

**The difference is pinned at +69.14 s, ±15 ms over the run** — and that is not
a latency. It is the film's RESUME POSITION: the app restored watch history for
the armed film and began the overridden clip about 69 s in, while the tap counts
from zero. The instrument measured the resume offset, not the sink's lead, and
the quantity being hunted is three orders of magnitude smaller than the thing
masking it.

**What it does establish, and it is not nothing**: the tap's sample clock and
the player's playback position advance at IDENTICAL rates — ±15 ms over eight
seconds. So whatever causes §9.ggg's 0.7 s is a CONSTANT pipeline offset, not
anything that drifts, which agrees with the six flash/beep pairs spanning only
66 ms. A constant offset is the easier kind to fix and the easier kind to get
wrong by guessing.

**The next measurement is specific**: clear the film's resume position (or start
the clip at zero) so the tap and the playback clock share an origin, and the
residual difference IS the sink's lead.

**RUN, and the hypothesis is CONFIRMED.** Arming a film with no watch history
(so resume is zero) gives tap and playback a shared origin:

    playback=47.906 s  tap=48.483 s  playback-tap=-0.577 s
    playback=49.933 s  tap=50.480 s  playback-tap=-0.547 s
    playback=53.954 s  tap=54.520 s  playback-tap=-0.566 s

**The tap runs 0.565 s AHEAD of playback** (mean over seven samples, spread
31 ms). `TeeAudioProcessor` sits on the way INTO the audio sink, so it sees —
and timestamps — PCM that the player will not make audible for another half
second.

**It accounts for most of §9.ggg's error, and not all of it.** End-to-end the
broadcast is 0.712 s out; the sink lead is 0.565 s. The residual ~0.147 s is
the video path's own latency (SurfaceTexture → GLES → encoder, all of which
happens after the frame's content was current) plus the detectors' own bias —
the flash test picks the first BRIGHT frame and `silencedetect` reports a
threshold crossing, and each rounds in the same direction. **Two causes, one
measured directly and one inferred**, which is worth stating before anyone
corrects 0.712 s with a single number and calls it solved.

(A smaller thing worth recording: `aw_play_url` inherits the ARMED FILM's resume
position, because the door overrides the URI and nothing else. Harmless for a
sync clip, and confusing exactly once.)

### §9.ggg Android's broadcast is 0.7 SECONDS out of sync — and a crash on the way to finding out (2026-09-18)

§9.fff built the flash-and-beep clip and could not play it. Two fixes later the
measurement ran, and it found the thing every timestamp analysis had missed.

**Fix 1 — the override could not open a local file.** `PlayerScreen` builds
`DefaultMediaSourceFactory(httpFactory)`, an HTTP-only data source, so a
`file://` URI went to `OkHttpDataSource` and failed as
`ExoPlaybackException: Source error` — which reads exactly like a network
problem and is not one. The override (and only the override) now uses
`DefaultDataSource.Factory`. The clip's first frame then arrived in **1.3 s**
against ~13 s for a film fetched from archive.org (§9.tt).

**Fix 2 — a CRASH in the catalog, and it belongs to this feature.** The app
died on the main thread:

    SQLException: Error code: 25, message: column index out of range
      at CatalogDatabase.liteFromRow(CatalogDatabase.kt:665)

Line 665 is `rightsBucket`, added for Watch Together's rights gate (schema 2).
The SQL asks `hasRightsBucketColumn` when the query is BUILT; the row reader
asked it again when each ROW was READ — and the app swaps the bundled schema-1
seed for the downloaded schema-2 catalog in between (§Decision 053's first-paint
rule). A 17-column query then had its rows read expecting 18. **A flag that
describes the DATABASE cannot be used to describe a QUERY that was built
earlier.** The reader now takes the answer the SQL committed to.

**THE MEASUREMENT.** Flash and beep are simultaneous in the source (within
~16 ms, §9.fff). In the recorded broadcast:

| | audio (beep) | video (flash) | offset |
|---|---|---|---|
| 1 | 4.403 | 5.086 | **-683 ms** |
| 2 | 9.396 | 10.145 | -749 ms |
| 3 | 14.388 | 15.133 | -745 ms |
| 4 | 19.403 | 20.106 | -703 ms |
| 5 | 24.396 | 25.097 | -701 ms |
| 6 | 29.388 | 30.079 | -691 ms |

**A viewer HEARS the beep about 0.7 seconds before SEEING the flash.** The
offset is constant across all six pairs (spread 66 ms), not growing — which is
precisely why §9.eee's "the tracks do not drift apart" was true and still not
sync, and why that entry refused to claim sync. ITU's tolerance for audio
leading video is about 45 ms; this is fifteen times that, and it would be
obvious on any film with dialogue.

**This is OPEN, not fixed.** The likely mechanism: video is stamped with the
wall clock at RENDER time, which is after the frame's content was current — the
film texture arrives, is composited, and is stamped only then — while audio is
stamped from a sample count that began when the AAC encoder did. Video is
therefore late relative to its own content by roughly the render-and-encode
latency. Stamping video with the FILM's presentation time rather than the
render instant is the shape of the answer; a fixed audio delay would paper over
it and would be wrong the moment the pipeline's latency changed.

**What this vindicates**: §9.eee's insistence that packet timestamps prove
"the tracks do not drift apart" and NOT "the tracks are in sync". Both tracks'
timestamps were internally consistent the whole time. Only a stimulus with a
known simultaneous event could show that they described different moments.

### §9.eee Android's first ten-minute soak: the drift is BOUNDED, and the residual offset is not yet understood (2026-09-18)

Every A/V measurement after §9.qq's clock fix ran for 87-117 seconds. The
product is a feature-length FILM, so the only number that matters is what
happens over an hour — and a residual of -315 ms over 117 s, if linear, is
about -9.7 s over an hour and -18 s over two. That would defeat the feature
outright. Apple has had a ten-minute soak since §8.3; Android had never had one.

**Ten minutes on the Google TV**, product path, `mpegts` recording, measured by
packet PTS:

    video   555.8 s, 6971 packets (12.5 fps)
    audio   555.2 s, 23882 packets
    A/V     START +1544 ms | END +1011 ms | DRIFT -533 ms over 9.3 min

**The drift is sublinear and CONVERGING, not runaway.** At the short-run rate
this window would have drifted about -1,500 ms; it drifted -533 ms, and the
offset CLOSED from 1,544 to 1,011 ms rather than opening. The two tracks'
durations agree to 0.6 s over 9.3 minutes. So the answer to the question that
mattered is: **a feature-length film does not desynchronise by tens of
seconds.**

**What this does NOT establish, and must not be read as establishing.** The
residual ~1.0-1.5 s is the difference between the tracks' FIRST timestamps,
which is the AAC encoder starting after video began. Whether audio and video
for the SAME instant of film carry the same PTS — true lip sync — is a
different question, and packet timestamps cannot answer it. That needs a
STIMULUS: a flash and a beep at a known moment, recovered from the recording,
which is how §6.2's +4.5-11 ms was measured in the harness. Until that is run
on the product path, the honest claim is "the tracks do not drift apart", not
"the tracks are in sync".

**And the frame rate is unchanged at duration**: 12.5 fps over ten minutes,
against 12-15 in the short runs — so the software encoder's ceiling (§9.uu) is
steady rather than degrading, and nothing thermal or memory-shaped creeps in
over ten minutes.

### §9.ddd The credential path's request shapes, proved before there is a credential (2026-09-18)

Decision 128 proved the SIGN-IN flows before any client id existed, by sending
deliberately invalid credentials to the real endpoints: a platform that rejects
the CREDENTIAL has accepted the REQUEST. It stopped there. `YouTubeLive.prepare`
and `TwitchLive.prepare` — the code that runs the instant the owner pastes two
strings — had never had their requests looked at by anything.

`tools/test_studio_live_shapes.swift` applies D128's method to that half.
**13 checks, 0 failures.**

- **Twitch's ingest list is fully verifiable today**, because it needs no
  credential: an ingest server is returned, it is **RTMPS** rather than RTMP,
  the `{stream_key}` placeholder is stripped, and the backup is a different
  server.
- **YouTube answers 401 with an auth body**, not 400 with a field complaint —
  so the liveStreams/liveBroadcasts request is shaped in a way the API accepts.
- **Twitch helix answers the same way.**
- **Controls first** (§9.oo's rule, that a control which cannot fail is not one):
  a request that must succeed, one that must fail, and an assertion that the two
  answers DIFFER. They run on `URLSession` directly rather than our own `HTTP`,
  because a control that depends on the code under test cannot testify about it.

**The one failure was in the TEST, and it is worth keeping.** The harness first
asserted the ingest host ends in `twitch.tv`. It does not: Twitch serves ingest
from **`live-video.net`** (`ingest.global-contribute.live-video.net`), and
`twitch.tv` is only the API host. The code was right and the expectation was
invented — so the check now names both domains, with the reason, because
somebody "fixing" that host to `twitch.tv` would break every Twitch broadcast.

**And both credential harnesses were outside the runner.** Neither
`test_studio_signin.swift` nor this one was in `tools/test_studio_all.sh` —
exactly §9.aaa's condition, a test that exists and therefore does not get run.
They are now **8.2** and **8.7**; both need only a network, no account, no
server, no device. **Verified inside the runner**, not merely registered:
a plain run reports `8.2 sign-in shapes PASS` and `8.7 live-platform shapes
PASS` at `pass=54 skip=1 fail=0` — the one skip being the soak, which the
runner refuses to call a pass ("a SKIP is not a PASS. 1 case(s) did not run").
The arithmetic agrees with the last green run: 53 with the soak, minus the
skipped soak, plus these two.

(And building it repeated §9.aaa's own mistake once more: the first compile
omitted `StudioPlatformAuth.swift`, which `StudioPlatforms.swift` depends on.
The file list bites whoever writes one, including the person documenting that
file lists bite.)

### §9.ccc Only iOS can actually reach YouTube or Twitch — the television cannot (2026-09-18)

§9.bbb closed Decision 127's YouTube unknown, so its other one — the Twitch
CATEGORY — was next. The category turned out to be wired properly:
`TwitchLive.setChannel` resolves a category NAME to a `game_id` before setting
it, and deliberately does not let a failed category fail the title. Following
that wire to its other end found something much larger.

**`YouTubeLive(` and `TwitchLive(` are constructed in exactly ONE file in the
whole project**: `iOS/StudioPlayerContainer_iOS.swift`, inside
`private func destination()`. That function is the entire route from an OAuth
token to a real stream key.

| platform | sign-in surface | fetches a stream key |
|---|---|---|
| iOS | yes | **yes** |
| tvOS | uses `StudioPlatformAuth` only for `anyConfigurationProblem` — to say sign-in is not set up, and refuse | **no** |
| macOS | none at all | **no** |

**So on the Apple TV and the Mac there is no code that could broadcast to
YouTube or Twitch, with or without the client ids.** Both can publish to the
diagnostic `AW_STUDIO_DEST` and nowhere else. Everything else on those
platforms is real and proved — the engine, the composite, the overlays, the
rights gate, the health readout, the publisher, §6's five runtime rules, the
ten-minute soak — which is exactly why the gap survived: **every part that
could be measured was measured, and the one part that needed a credential
nobody had was never reached.**

This matters more than a missing function, because Decision 127's central
argument is the TELEVISION as the studio — tvOS 17 lending the Apple TV an
iPhone's camera and microphone through Continuity. That case cannot happen
today.

**The CLIENTS are shared; only the CALL SITE is iOS-only** — which makes the
Apple side smaller than "build a credential path". `StudioPlatforms.swift` and
`StudioPlatformAuth.swift` are the only Swift files that touch
`googleapis.com`, `api.twitch.tv` or `id.twitch.tv`, and both are shared code
every Apple target already compiles. What tvOS and macOS lack is a surface that
CALLS them, not the ability to.

**Android lacks both.** Kotlin contains **zero** references to those hosts: no
OAuth, no platform client, and `StudioController` sets
`streamKey = if (benchDest != null) benchKey else ""`. So an Android host can
publish to the bench destination and nowhere else, and **the owner's two client
ids would not change that** — they are read by Swift code Android does not
have. PARITY said the ids were the blocker for every platform; they are the
blocker for iOS.

**What each platform actually needs is different, and worth stating
separately:**

- **macOS** needs only the code. `ASWebAuthenticationSession` works there, so
  the auth flow, the credential fetch and a go-live surface are all
  straightforwardly buildable. There is no go-live affordance on the Mac at
  all today — the Studio is started by the harness door.
- **tvOS** needs the code AND carries Decision 128's unproven risk:
  `presentationContextProvider`, `prefersEphemeralWebBrowserSession` and
  `cancel` are `API_UNAVAILABLE(tvos)`, so how that flow presents on a
  television cannot be known until a client id exists. Twitch's device-code
  flow is fine there; YouTube's is the open question.

**Not built here**, deliberately: the credential path is untestable without the
owner's client ids, a Mac go-live surface is a design question that
`docs/macOS-DESIGN.md` governs rather than something to improvise at 4am, and
writing three platforms' worth of unverifiable code is how the previous
untested claims got made. The honest move is to say plainly what is missing and
let it be scheduled.

### §9.bbb The 50-subscriber rule does NOT apply to us — an open risk in Decision 127, closed (2026-09-18)

Decision 127 left two platform unknowns, and the dangerous one was **"the
50-subscriber rule for API streams"**: if YouTube required 50 subscribers to
stream, a new channel could complete every setup step and still be unable to
broadcast. That is the kind of thing worth knowing BEFORE the owner invests an
evening in client ids.

**It is a MOBILE rule.** From YouTube's own mobile-requirements page: *"At
least 50 subscribers"*, listed among requirements that page holds specifically
for streaming from the YouTube app on a phone. The general eligibility page
names no subscriber minimum at all, and points mobile streaming at that
separate document.

**Watch Together Studio is not a mobile stream.** It publishes RTMP as an
ENCODER (Decision 127), which is the same path OBS takes, so the rule does not
reach it — a phone running our app is still an encoder, because what YouTube
gates is the app you stream FROM, not the device you hold.

**What the encoder path does require**, from the general eligibility page:

- **verify the channel**,
- **no live-streaming restrictions in the past 90 days**,
- be at least 16.

**And one thing to plan around rather than discover**: the mobile-requirements
page lists a **potential 24-hour wait** when live streaming is first enabled on
a channel. The general page did not mention it, so the precise scope is
uncertain — but a day's delay on first activation is cheap to plan for and
expensive to meet by surprise on the evening somebody wants to broadcast.
Enable it a day ahead.

**Twitch's side is still unverified** for the same reason as §9.ww: its
requirements live behind a JavaScript portal that will not render to a fetcher.
Twitch has no equivalent subscriber gate as far as our own testing shows — the
ingest accepted our stream with an invalid key long before any account existed
— but that is evidence about the INGEST, not a quotation of a policy.

### §9.aaa Three §8 cases had not compiled for a whole session, and only the suite noticed (2026-09-18)

Fifteen ticks of changes — the audio tap, both clocks, the publisher's hot
path, the handshake threading, encoder selection, profile — were each verified
on hardware as they were made. None of that is the same as running the suite,
and running it found something none of the individual checks could:

    8.5 thermal        FAIL  did not compile
    8.6 back-pressure  FAIL  did not compile
    8.3 soak           FAIL  did not compile
    pass=50 skip=0 fail=3   SUITE RESULT: FAIL

The error was not in any of tonight's work:

    StudioEngine.swift:385: error: cannot find type 'StudioChatTwitch' in scope

Those three cases are exactly the ones that compile `$ENG`, and the chat reader
moved INTO the engine when chat stopped belonging to one surface (§6.4). The
harness file lists did not move with it, so **8.3, 8.5 and 8.6 have not
compiled since that commit** — through every tick that followed, including the
ones that changed the very code those cases exercise. 8.1 and 8.4 kept passing
because they never compile the engine.

**The lesson is about the shape of the harness, not the bug.** A hand-written
file list is a SECOND, SILENT COPY of the module's dependency graph, and a
source move updates one copy and not the other. Nothing warns; the case simply
stops compiling, and a suite that is not run cannot say so. `--strict` did its
job the moment it was asked — which is an argument for running the whole suite
after a run of changes, not only the test nearest the change.

Fixed by giving the three cases `$CHAT`, with the reason recorded beside the
variable so the next source move has a chance of updating it.

**And there was a THIRD copy.** Each harness documents its own `swiftc`
invocation in its header — the command a person runs when they want to drive
one case by hand — and all three listed the same four files with **zero**
mentions of `StudioChatTwitch.swift`. So anyone following the documented
command hit precisely the error the suite hit. Those headers are now fixed too.

Three copies of one dependency graph: the module's own, the runner's variables,
and the prose in each harness. Two of them drifted the moment a file moved, and
neither could say so.

**Compiling the directory instead of naming its files looks feasible** — every
Studio source's platform-specific import is guarded (`#if canImport(UIKit)` in
`StudioEngine`, `StudioLab` and `StudioPlatformAuth`; `#if os(tvOS)` in
`StudioContinuity`), so a macOS build of `Studio/*.swift` should work. That is
a reading, not a compile, and it stays a reading until it can be checked
without perturbing a ten-minute soak that is measuring encoder throughput on
the same machine.

**The re-run is GREEN: `pass=53 skip=0 fail=0`** under `--strict --soak`, with
the three repaired cases genuinely exercised rather than counted. §8.3's soak:
18,011 frames encoded and 18,011 sent over ten minutes, peak send queue 24 kB
of a 1,149 kB cap (2%), thermal nominal, no encoder or pool faults, 29 fps at
worst after the first minute. Memory grew **4.7 MB** (71.5 → 76.2, peak 85.8)
where the last recorded soak grew 12.8 MB and peaked at 112.3. **A second
soak, after 8.2/8.7 joined the suite, grew 4.0 MB (71.1 → 75.1, peak 86.0)** —
so two consecutive runs sit near 4 MB against a recorded 12.8. That is more
than one reading and still NOT attributed: nothing in tonight's Apple changes
obviously accounts for it (the allocation fix was Kotlin; this harness is
Swift), and the honest description is a consistent difference with no known
cause rather than an improvement anyone earned.

**But the cadence matters more than the structure.** The list was wrong for a
whole session and the suite said so within seconds of being asked. No amount of
restructuring helps a suite nobody runs, and a suite that IS run catches a
stale list whatever shape it has. The durable fix is running the whole thing
after a run of changes — which is how this was found.

### §9.zz The level was over-declared, and not asking fixed it (2026-09-18)

§9.yy noticed an inconsistency between the platforms: Apple's `AutoLevel`
declares **4.0** for 1080p30, which is what that stream actually needs, while
§9.xx's Android change requested the HIGHEST level a codec advertises and so
declared **5.0 for a 720p30 stream**. This dongle advertises exactly one level
per profile (`p2l16384`, Level 5), so the only route to an honest level was to
stop asking for one.

The reason a level was set at all is the standard caution that some encoders
ignore a profile arriving without one. That caution was worth testing rather
than obeying:

| | requested | stream carries |
|---|---|---|
| with `KEY_LEVEL` | profile=2, level=16384 | `Main`, level **50** |
| **without** | profile=2 only | `Main`, level **41** |

**The profile still takes, and the level becomes accurate.** 4.1 is what
720p30 requires; 5.0 was a claim about a stream we are not sending. Apple
reaches the same place by a different route — `AutoLevel` — so both platforms
now declare what they actually send.

If some future encoder does ignore a profile that arrives without a level, the
cost is a lower profile on that device, not a broken broadcast — and the
existing fallback still drops the profile entirely rather than failing to
configure. A caution worth testing is not a caution worth keeping unmeasured.

### §9.yy What Apple actually SENDS, checked against YouTube's published spec — and two instruments that disagreed (2026-09-18)

§9.xx found Android requesting an H.264 profile it could not have and being
told nothing. The same question had to be put to Apple, which asks for
`kVTProfileLevel_H264_High_AutoLevel` and had never had its output checked.

**Apple's request is honoured, and its level is honest.** Read from the
server's own recording of the macOS product path:

| | Apple sends | YouTube publishes |
|---|---|---|
| profile | **High** | not specified |
| level | **4.0** — accurate for 1080p30 | — |
| resolution / pixel format | 1920x1080, yuv420p | — |
| keyframe interval | **2.00 s** mean, **2.00 s** max, 20 gaps | **2 s**, "do not exceed 4" |
| audio | AAC-LC, 128 kbps stereo | AAC, 128 kbps stereo |
| achieved video bitrate | 3.06 Mbps against a 6 Mbps target | — |

Two things worth keeping from that table. `AutoLevel` picked **4.0**, which is
what 1080p30 actually needs — next to the Android change in §9.xx, which
requests the HIGHEST level a codec advertises and so declared 5.0 for a 720p30
stream. Apple demonstrates the better practice: an accurate level, chosen by
the encoder. And the achieved bitrate is HALF the target, which is correct
rather than alarming: a bitrate is a ceiling, not a floor (§9), and a grainy
monochrome silent film gives the encoder little to spend it on.

**TWO INSTRUMENTS DISAGREED ABOUT THE KEYFRAMES, AND THE FIRST ONE WAS WRONG.**
Counting container PACKET flags said **one keyframe in 1,226 packets over 41
seconds** — which would have been a serious defect, since a viewer joining a
stream with no periodic IDR has nothing decodable until the next one. Counting
FRAMES by `pict_type` said 21 I-frames, evenly spaced at exactly 2.00 s. The
packet flags simply are not marked through mediamtx's TS remux.

The rule this adds to the family: **when a measurement implies a serious
defect, measure it a second way before believing it.** The cost of the second
check here was one command; the cost of acting on the first reading would have
been a day chasing a keyframe bug that does not exist. Prefer `-show_frames`
`pict_type` over packet flags for this question.

### §9.xx Android asked for a profile it could not have, and was told nothing (2026-09-18)

`StudioVideoEncoder` carried a promise in a comment: *"Baseline keeps every
ingest and every cheap decoder happy; the Apple side uses High, and matching
that is a later measurement."* This is that measurement, and the first result
was that the experiment itself does not work the way it looks.

**Requesting High changed nothing, and said nothing.** Setting
`KEY_PROFILE = AVCProfileHigh`, rebuilding and running produced a stream still
carrying `profile=Constrained Baseline`, at an identical 12-13 fps. No error,
no warning. **Android silently ignores a profile the encoder does not have**,
so a change that compiles, installs, runs and appears in the logs can still be
no change at all — and the unchanged frame rate would have read as "High is
free" if the stream had not been checked.

**What the encoder actually advertises**, enumerated through
`getCapabilitiesForType(...).profileLevels`:

    c2.android.avc.encoder:  p1l16384, p65536l16384, p2l16384
    OMX.google.h264.encoder: p1l16384, p65536l16384, p2l16384

Decoded: Baseline (1), Constrained Baseline (65536) and **Main (2)**. There is
no High (8) on this device at all, which is why the request evaporated.

**So the encoder now asks for the best profile the CHOSEN codec advertises** —
High, else Main, else Baseline — with `KEY_LEVEL` alongside it, because some
encoders ignore a profile that arrives without one. Verified on the glass
rather than in the log:

| | requested | stream carries | fps |
|---|---|---|---|
| before | Baseline | `Constrained Baseline`, level 41 | 12-13 |
| asking High (inert) | High | `Constrained Baseline`, level 41 | 12-13 |
| **now** | `profile=2 level=16384` | **`Main`, level 50** | 12-14 |

**Main costs nothing measurable here and is a real gain**: it brings CABAC
entropy coding in place of Baseline's CAVLC, which is better compression at the
same bitrate — the picture a viewer gets improves without asking more of the
host's uplink. On a phone, whose hardware encoder should advertise High, the
same code will take High and match the Apple side at last.

**One judgement recorded rather than hidden**: the level requested was the
highest the codec advertises for that profile (5.0 here) — conservative for
ACCEPTANCE, and an over-declaration of what a 720p30 stream needs.
**Measured and changed in §9.zz**: the level is no longer requested at all, and
the encoder picks an accurate 4.1.

### §9.ww The encoder settings audited against what the platforms actually publish (2026-09-18)

The Studio exists to reach YouTube and Twitch, and its encoder parameters had
never been checked against either platform's published requirements. They are
now, and the audit changed one plan and flagged one decision.

**YouTube's official live-encoder page fetched cleanly** and specifies:
keyframe interval **2 s** ("do not exceed 4 seconds"), **CBR**, audio **AAC at
128 kbps stereo**, and video **4 Mbps at 720p30** / **10 Mbps at 1080p30** for
H.264.

**Twitch's could NOT be read, and no substitute was accepted.**
`help.twitch.tv`'s guidelines page is a JavaScript portal that returns a CSS
error to a fetcher, and `link.twitch.tv/BroadcastingGuidelines` redirects
straight back to it. Search returns plenty of third-party blogs quoting profile
and B-frame settings; **none of them is Twitch**, and encoder parameters are
not worth setting from a blog. Twitch's requirements remain UNVERIFIED here,
and the one thing that matters most — that it accepts our stream — was already
proved against the real ingest with an invalid key (§9).

**What we send, measured against what YouTube publishes:**

| | Apple | Android | YouTube |
|---|---|---|---|
| resolution / fps | 1920x1080 @30 | 1280x720 @30 | — |
| video bitrate | 6 Mbps | 4 Mbps | 10 Mbps @1080p30, **4 Mbps @720p30** |
| audio | AAC 128 kbps stereo | AAC 128 kbps stereo | **AAC 128 kbps stereo** |
| keyframe interval | 2 s | 2 s | **2 s**, never over 4 |
| H.264 profile | High | Baseline → **Main** (§9.xx) | not specified |

Android's 720p30 at 4 Mbps is EXACTLY YouTube's recommendation; both platforms'
audio and keyframe settings match it exactly.

**THE PLAN THIS AUDIT KILLED.** YouTube's table says CBR, Apple uses
`AverageBitRate` plus a `DataRateLimits` hard cap, and the obvious move was to
switch to `kVTCompressionPropertyKey_ConstantBitRate`. The SDK header says not
to, in as many words:

> `kVTCompressionPropertyKey_ConstantBitRate` is intended for legacy content
> distribution networks which require constant bitrate, and **is not intended
> for general streaming scenarios**.

So the average-plus-cap shape we already have is what Apple recommends for
exactly this job, and the change was not made. Reading the framework's own
header beat following the platform's table.

**THE DECISION THIS AUDIT FLAGS, for the owner rather than for me.** Apple
sends 1080p30 at **6 Mbps** where YouTube recommends **10**. That is not a
defect — YouTube accepts it and 6 Mbps at 1080p is a common encoder setting —
but it is 60% of the recommendation, and the three ways to close it are all
trade-offs somebody else should pick: raise to 10 Mbps and demand a 10 Mbps
sustained UPLINK from the host's home broadband; drop Apple to 720p and match
Android exactly at YouTube's own number; or keep 1080p at 6 Mbps deliberately
as the middle. The uplink is the host's, so the choice is not the Studio's to
make silently.

### §9.vv Apple's encoder IS the hardware one — asked, because Android's was not (2026-09-18)

§9.uu found the Android Studio encoding in software for its entire life,
because `createEncoderByType` returns whatever the platform lists first. The
same question had to be put to Apple, where `VTCompressionSessionCreate` is
called with `encoderSpecification: nil`.

**The SDK says nil is already the right answer** — read from the headers on this
machine rather than from memory:

- `kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder` —
  *"CFBoolean, Optional, **true by default**"*
- `kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder` —
  *"CFBoolean, Read; assumed false by default"*
- all three hardware keys: `macos(10.9), ios(17.4), tvos(17.4)`, against this
  project's deployment target of **26.0** on every Apple platform, so they are
  unconditionally available.

So nil already means "hardware if there is one", and Apple never had Android's
defect. **But that is a fact about the DEFAULT, not about this session**, and
the Android ceiling was believed for days on exactly that species of reasoning.
So it is now read and reported rather than assumed.

**Measured on the macOS product path** (Apple M3), the health line carries it:

    state=LIVE fps=30 queued=0 vsent=917 vdrop=0 asent=1316 ... hwenc=true

Hardware, 30 fps, nothing dropped — next to Android's software encoder at 13 fps
on a dongle with no hardware encoder at all.

**`Require…` is deliberately NOT set.** It fails session creation outright on a
machine with no hardware encoder, and for this feature a slow broadcast beats
no broadcast: the Android dongle proves such devices exist and still want to
take part.

**tvOS is now READ, on the glass** (Apple TV 4K 3rd gen, 2026-09-18). The
DEBUG readout during a forced Studio run:

    ● NOT SENDING  1,598 kbps
    audio: Playback/MoviePlayback active
    encoder: hardware
    ⚠ The show is being made but not sent anywhere — no destination is set.

**`encoder: hardware`** — so the television matches the Mac's `hwenc=true`, and
Apple's two measured platforms both use the hardware encoder where Android's
dongle has none (§9.uu). The same screenshot carries §6.2's audio-session state
and §5's no-destination sentence, both rendering correctly at ten feet.

**And the CONFIGURATION refusal was verified first, by accident.** Without
`AW_STUDIO_TV_FORCE` the television answers with *"Streaming is not set up yet
— Signing in to YouTube or Twitch is not set up in this build yet… their client
ids in Secrets.xcconfig."* That is Decision 128's "a missing credential is a
STATE" on a real screen, which had never been photographed either.

**iOS remains unread.** `StudioHealth` now carries
`encoderIsHardware` so every surface can show it, and the tvOS readout prints
`encoder: hardware` / `encoder: SOFTWARE` in DEBUG — on the GLASS, because the
machine-readable health line is gated on a bench destination a television
cannot reach (owner item 8a). Reading it on the Bedroom Apple TV is the next
step; until then the Apple result is macOS's alone.

### §9.uu The Studio has been encoding in SOFTWARE — and this dongle has no other option (2026-09-18)

§9.rr attributed the ~13 fps ceiling to `eglSwapBuffers` blocking on the
encoder's input-surface queue. That was reasoning, not measurement. Two
instruments settled it: a split of `drawOnce` into its phases, and a log of
which codec `MediaCodec` actually handed us.

    video encoder=c2.android.avc.encoder  hardwareAccelerated=false
    draw split: tex=1.5  gl=25.8  swapEnc=1.1  swapDisp=2.4  ms/frame

**The swap is not the blocker.** It costs 1.1-2.5 ms. The GL draw costs
20-34 ms and is the whole ceiling. §9.rr's sentence naming `eglSwapBuffers` has
been corrected in place; what it got RIGHT was that the flat sleep was slack
rather than cost, which the pacing experiment had already proved.

**And the Studio has been encoding in software the entire time.**
`MediaCodec.createEncoderByType` returns the first codec the platform lists for
the type and is not promised to be hardware; on this device it returns
Android's generic C2 software AVC encoder.

**Selecting a hardware encoder explicitly changes nothing here, because there
is no hardware encoder to select.** Enumerated through the same API the
selector uses:

    candidate c2.android.avc.encoder  hw=false  fits1280x720=false  maxW=1808 maxH=1808
    candidate OMX.google.h264.encoder hw=false  fits1280x720=false  maxW=1808 maxH=1808

Two candidates, both software. The device (`Dongle R 4K`, board `YQB`) is a
PLAYBACK device: hardware decoders, no hardware video encoder. **So ~13 fps is
a real hardware floor for this class of dongle, correctly attributed at last**
— not the GPU, not our pacing, not the swap. Decision 129's "a Google TV dongle
needs 37.4 ms a frame" was measured on a device that cannot encode in hardware
at all, which is worth knowing before that number is read as an architecture
verdict.

The encoder is now chosen explicitly — a hardware AVC encoder if the platform
has one, the platform's own choice otherwise, with `configure` as the test and
a release-and-try-next on refusal. On this dongle it correctly finds nothing
and falls back, so the show still goes out; on a phone it should find one.

**The instrument also caught a bug in the fix itself.** The first version gated
candidates on `videoCapabilities.isSizeSupported(width, height)` — and that
returns **false** for 1280x720 on the very encoder that is encoding 1280x720 at
that moment (with `maxW`/`maxH` both 1808). As a filter it would have silently
rejected a good HARDWARE encoder on a phone and fallen back to software with no
explanation. The gate is gone; `configure` decides.

**What is NOT established**: whether the 26 ms GL draw would shrink behind a
hardware encoder. A software encoder consumes the input Surface by reading it
back, which can make the driver charge for it inside the draw — plausible, and
untestable on a device with no hardware encoder. **That measurement needs the
Pixel 8a** (owner item 8), which makes the phone pairing the gating step for
Android performance rather than a nice-to-have.

### §9.tt The twelve seconds before a broadcast are the FILM, not the Studio (2026-09-18)

§9.ss closed by listing four things that might account for the ~12 s between
the run loop starting and the first published packet. Rather than optimise any
of them, they were timed — the same move that paid in §9.rr and §9.ss.

    0.000 s  run loop begins
   13.226 s  first film frame              <- 13.23 s
   13.413 s  3 film frames, warm-up done   <- 0.19 s
   13.416 s  encoder avcC ready            <- 0.003 s
   13.418 s  first film PCM                <- 0.002 s
   13.594 s  handshake started             <- 0.18 s
   13.664 s  AAC config ready              <- 0.07 s
   14.255 s  PUBLISHING (audio declared)   <- 0.66 s

**13.2 of the 14.3 seconds is ExoPlayer fetching the film's first frame.**
Every mechanism suspected in §9.ss is negligible: the AAC config takes 70 ms,
so §6.2's 8-second deadline has never once been reached; the three-frame
warm-up costs 190 ms; the encoder's `avcC` is there in 3 ms; and the handshake,
now off the render thread, is 660 ms. **The Studio's own contribution to
starting a broadcast is about one second.**

**Confirmed on a second film**, because one measurement of a network fetch is
an anecdote:

| film | first film frame | everything after it |
|---|---|---|
| *The Four Horsemen of the Apocalypse* (1921) | 13.23 s | **1.03 s** |
| *The Cabinet of Dr. Caligari* (1919) | 9.74 s | **1.07 s** |

The film's first frame varies by seconds between titles; the Studio's own cost
does not move.

So the honest framing is not "the Studio opens slowly" but "the film takes
thirteen seconds to start, and the broadcast waits for it" — which is the
playback-latency question Decision 077 already governs (*a film starts within
30 seconds, or falls back to a copy that can*), not a Studio defect. §9.ss's
closing paragraph said otherwise and has been corrected in place.

**The product option this leaves open, deliberately NOT built here.** A
broadcast could publish immediately over a holding slate and let the film join
when it arrives, so an audience that is already waiting sees something within a
second. The blocker is §6.2 rather than effort: a stream's tracks are declared
once, at publish, and the AAC config cannot exist until the film's PCM does —
which is the same 13 seconds. Declaring audio from a DEFAULT 44.1 kHz stereo
config before the film's real format is known would allow it, at the cost of
resampling whatever the film turns out to be. That is a real design decision
with a real cost, not a tidy-up, so it is written down rather than taken.

### §9.ss The RTMP handshake came off the render thread — every broadcast used to open stalled (2026-09-18)

§9.rr's breakdown caught one second that looked nothing like the others:

    fps=1   draw=16.3  drain=2306.5  audio=0.6  chat/s=44.0 ms

That is the publish. `RtmpPublisher.publish()` is a TCP connect plus four AMF
round trips, and it was called inline from the render loop — so **every
broadcast began with 2.3 seconds during which the program rendered one frame**.
The thread that owns the GL context, the film texture and the encoder's input
surface was sitting in a socket read. On a slower network, or a real ingest
across the internet rather than a server on the LAN, that stall is longer.

**The handshake now runs on its own daemon thread**, and the render thread
adopts the finished publisher on a later iteration. Three details make it safe
rather than merely asynchronous:

- **Everything the worker needs is captured on the render thread** before it
  starts — `avcC`, the audio config, the stream config — so the worker touches
  no engine state while the loop keeps mutating it.
- **The adoption happens on the render thread**, because `published` is read by
  the video drain and the per-second block, and §6.2d's opening keyframe request
  belongs with the adoption rather than with the socket.
- **A failed handshake releases the in-flight flag** so the next iteration
  retries, instead of stranding a show with no destination for ever; and a
  handshake that completes *after* the show ended has its socket closed, or it
  leaks one that nothing else will ever touch.

**Measured on the Google TV, before and after:**

| | before | after |
|---|---|---|
| the publishing second | `drain=2306.5`, **fps=1** | no spike, **fps 12-15** |
| steady state | 11-13 fps | **12-15 fps** |
| A/V drift | +395 ms / 87 s | **-315 ms / 117 s** |

§6.2d still holds: the first video packet in the recording carries the keyframe
flag and the first frame decodes, so a viewer joining at the start has a
picture.

**What this did NOT fix**: the first video packet still sits at **11.8 s** on
the show clock. This entry originally guessed that time was spread across app
launch, film buffering, the warm-up and §6.2's wait for the AAC config.
**§9.tt measured it instead, and it is almost entirely ONE of those**: the
film's first frame. Everything the Studio itself does adds about a second.

### §9.rr The dongle's 10.5 fps was mostly BOXING — and the pacing fix that measurement refused (2026-09-18)

§9.qq left the Google TV delivering 10.5 fps and called it a hardware-floor
question. It was not, or not mostly. The loop has five phases and a total says
nothing about which one owns the time, so the first move was a DEBUG per-second
breakdown (`AWSTUDIOPERF`), not another guess.

**What it found, per frame, against a 33.3 ms budget for everything:**

    fps=10  draw=22.0  drain=16.5  audio=29.0   chat/s=39.6 ms
    fps=9   draw=45.3  drain=4.6   audio=28.7   chat/s=0.2 ms

**The video and audio SEND paths cost more than the GPU did.** Both built their
FLV tag as `mutableListOf<Byte>()` then `addAll(data.toList())` — and
`toList()` on a `ByteArray` **boxes every byte**. A 50 kB keyframe allocated
fifty thousand `Byte` objects, on the render thread, every frame. Replaced with
a plain `ByteArray` and `System.arraycopy`:

| | before | after |
|---|---|---|
| video drain | 16.5 ms/frame | **2.3-5.2 ms** |
| audio drain | 29.0 ms/frame | **5.0-14.6 ms** |
| program | 9-10 fps | **12-13 fps** |
| A/V drift | -720 ms / 100 s | **+395 ms / 87 s** |

The drift improved as a side effect, which fits §9.qq: a render loop that is
faster drains the AAC codec more often, so less PCM is refused and fewer
samples go missing. The setup paths (handshake, connect, sequence headers)
still use `toList()` and are left alone — they run once.

**Then a hypothesis, and the measurement refused it.** The loop ends with an
unconditional `delay(1000 / frameRate)`, and the arithmetic looked decisive:
~44 ms of work plus a flat 33 ms sleep is 77 ms, which is exactly the 12.9 fps
being measured. Replacing it with "sleep only the REMAINDER of the budget"
should have given ~22 fps. It gave 12-14 — and `draw` expanded from ~27 ms to
~65 ms, absorbing precisely what the sleep had been.

**So the ceiling is downstream.** The sleep was never additive, it was slack —
the loop already runs at the rate the encoder can consume frames.
**CORRECTED IN §9.uu**: this entry went on to name `eglSwapBuffers` as the
place that blocks, which was a guess and is wrong. Measured, the encoder swap
costs ~1.5 ms a frame and the GL draw costs ~26 ms. The comment that
was already there — *"a tighter loop only burns battery: the encoder cannot
take frames faster than it encodes them"* — was right, and the change was
reverted with the measurement recorded beside it. **An arithmetic model that
explains a number exactly is still a hypothesis**; this one predicted 22 fps
and reality said 13.

**Two things remain open:**

- **~13 fps is the dongle's real composite-plus-encode throughput at 720p.**
  That IS a hardware-floor question, now properly attributed rather than
  assumed. The remaining per-frame cost is `draw` at ~30-38 ms, which includes
  the blocking swap.
- **The publish handshake blocks the render thread for 2.3 seconds**
  (`drain=2306.5` on the publishing second, fps=1). A broadcast's opening
  seconds are spent stalled, and the handshake has no business on the thread
  that owns GL.

### §9.qq Android's two clocks, fixed — a frame counter pretending to be a clock, and a sample clock that did not count what it dropped (2026-09-18)

§9.pp measured a +19.6 s A/V split on the Android product path and blamed
MediaCodec's Surface clock. **That diagnosis was wrong**, and the grep that
produced it was scoped to a file that does not contain the call. `StudioGl`
sets the presentation time deliberately. The actual pair of causes:

**Cause 1 — video time was a frame COUNTER, not a clock.**

    g.swap(frame * 1_000_000_000L / frameRate)

Frame N was stamped at N/30 s regardless of when it was actually drawn. Audio,
stamped from its sample count, tracks real time exactly. So the two agree only
while the renderer holds the nominal rate — and this Google TV does not: the
same run measures **10.5 fps**. A stream whose video clock advances at a third
of real time while its audio advances at real time desynchronises without
bound, and the frame counter HID the true rate by asserting 30 fps whatever
happened. Both tracks now count real nanoseconds from one `showStartNanos`.

**Cause 2 — the sample clock did not count what it threw away.**

    if (index < 0) return          // full; drop rather than stall
    ...
    pcmBytesIn += take             // only ACCEPTED bytes move the clock

The comment beside it argues that a sample clock cannot drift, which is true
only if nothing is ever dropped. When the codec input was full the PCM was
discarded and the clock never advanced past it, so the audio timeline fell
behind real time by exactly the amount dropped — permanently, and invisibly.
It now counts OFFERED bytes and exposes `droppedBytes`, which turns a growing
desync into one brief gap: a listener forgives a gap, and a desync never stops
being one.

**Measured on the Google TV, `The Four Horsemen of the Apocalypse`, by packet
PTS from an `mpegts` recording:**

| | A/V at start | A/V at end | drift over the run |
|---|---|---|---|
| before | — | — | **+19,613 ms** split |
| one show clock | +1,163 ms | -1,926 ms | **-3,089 ms** / 110 s |
| + offered-byte clock | +1,439 ms | +719 ms | **-720 ms** / 100 s |

27x better, and the offset now CLOSES across the run instead of opening.
macOS on the same instrument is 0 ms and needed no change.

**Two things stay OPEN, both now visible only because the clocks are honest:**

- **A residual -720 ms over 100 s (0.7%).** The audio clock is still the
  FILM's timeline (its decoded sample count) while video is now wall-clock, so
  a rebuffer or a player running fractionally off real time shows up as drift
  rather than as a gap. The fix is to resync the sample clock to the show
  clock when the error exceeds a threshold — stamping audio by arrival time
  outright would import the jitter the sample clock exists to avoid.
- **10.5 fps on the dongle.** Decision 129 measured 37.4 ms a frame drawing
  once; a real broadcast with audio, chat and publishing is far worse. This is
  a hardware-floor question, not a clock one, but it was concealed for as long
  as the timestamps were synthetic.

### §9.pp OPEN: Android's two clocks — a +19.6 SECOND A/V split that only became visible once audio existed (2026-09-18)

§9.mm wired the film's audio into the Android product path for the first time.
The very next measurement of that path shows video and audio arriving on
**unrelated timelines**. Measured from mediamtx's `mpegts` recording by packet
PTS (the container's own `start_time`/`duration` fields are not trustworthy
here and were discarded):

| | first video PTS | first audio PTS | offset |
|---|---|---|---|
| macOS product path | 0.000 s | 0.000 s | **0 ms** |
| Google TV product path | 20.000 s | 39.613 s | **+19,613 ms** |

The same run recorded 1,673 video packets over 55.7 s on the Mac against 77
video packets over 2.5 s on the Google TV, from a 75-second broadcast whose
path counter showed ~20 MB received — mediamtx's muxer wrote only the fraction
it could place on a coherent timeline. A second, independent capture (a direct
RTMP FLV copy) showed the same disagreement in the same direction: video
starting 6.5 s after audio, with the two tracks' durations 26 s apart.

**The diagnosis is two clocks that were never introduced to each other.**

- **Audio** is stamped from its own sample count —
  `pcmBytesIn * 1_000_000 / (sampleRate * channels * 2)`, minus the AAC
  priming delay. Deliberately drift-free, and it starts at 0 when the AAC
  encoder starts.
- **Video** is stamped `frame * 1s / frameRate` — a FRAME COUNTER.

**CORRECTION (§9.qq)**: this entry first blamed MediaCodec's Surface clock and
said nothing called `eglPresentationTimeANDROID`. Both were wrong — the grep
behind that claim was scoped to a filename that does not carry the call.
`StudioGl.swap()` sets the presentation time deliberately; what it was handed
was a frame counter. The real cause is in §9.qq.

Neither is wrong on its own; they simply do not share an origin. `RtmpPublisher`
carries a comment saying the Kotlin side needs no timestamp base "unlike
Apple" — that belief is the bug, and Apple's `startTime` base is exactly what
keeps its two tracks at 0 ms.

**Why nothing caught it until now**: with no audio on the product path
(§9.mm), a single consistent video clock is fine whatever its origin — every
earlier Android run was video-only, so there was no second timeline to
disagree with. Decision 129's +4.5–11 ms alignment was measured in a harness
that fed the encoder directly, where both tracks shared a base. **Turning the
audio on is what made the defect observable, which is the argument for
§9.mm's fix twice over.**

**NOT YET FIXED.** The shape of the fix is one show clock feeding both: stamp
the encoder surface with `eglPresentationTimeANDROID(display, surface,
now - showStart)` and offset the audio's sample clock by
`audioStart - showStart`, so both count from the same instant. Until then, an
Android broadcast to YouTube or Twitch should be assumed to desync; the picture
and the sound have been proved to arrive, and their RELATIONSHIP has not.

### §9.oo The bench was broadcasting the owner's ROOM — and the control that finally ran refuted the tick before it (2026-09-18)

§9.nn ended with a debt: the claim that a muted program publishes silence had
been *read off one line of code*, never run. Running it broke two things open.

**The control refused to agree.** With the film fader muted, the program's
audio came back at mean -43.4 dB against the unmuted run's -41.8 dB —
unchanged. A mute that changes nothing means the thing being muted was never
there.

**It was the MICROPHONE.** `StudioSession` attaches a mic tap whenever macOS
has granted audio permission, and `micMuted` defaults to false with
`micGain 1.0`. So every Mac bench broadcast was carrying whatever could be
heard near the owner's Mac — published to a local server AND written into a
recording on disk. The level in §9.nn was room tone. **This is the same
mistake as the full-desktop screenshot (§9, `mac_screenshot_window_only`): the
instrument reaching past the thing it was pointed at, on the owner's own
machine.** The ~88 MB of affected recordings were deleted; their audio was
neither analysed nor relayed.

**The fix is that a bench run never carries the room.** `AW_STUDIO_MAC` now
mutes the mic unless `AW_STUDIO_MIC=1` asks for it deliberately, and the
harness audio state is applied inside `StudioSession.start` where the engine is
KNOWN to exist. The first attempt set it from the launch door one line after
`play()`; the engine is built asynchronously, so `engine?.setAudio` was a no-op
on nil and the "control" tested nothing. **A control that cannot fail is not a
control** — it has to be able to produce the opposite verdict, and this one
could not even reach the dial.

**Then the matrix, one variable at a time, mic muted throughout:**

| run | film | film fader | measured |
|---|---|---|---|
| A | *Dr. Mabuse* (1922) | open | **-91.0 dB** (digital silence) |
| B | *The Four Horsemen of the Apocalypse* (1921) | open | **-19.4 dB** mean, -4.0 dB peak |
| C | *The Four Horsemen of the Apocalypse* | **muted** | **-91.0 dB** (digital silence) |

B against C is the control that was owed: one variable, -19.4 → -91.0. The film
fader does silence the program, now measured rather than read. And A is not a
defect — *Dr. Mabuse*'s derivative is a silent print with no audio track, which
`FilmAudioTap.attach` reports as `false` by design, because a silent film is a
real case in this catalog and must never be reported as a failure. Choosing it
for §9.nn's measurement is what let the mic masquerade as the film.

**What stands after the correction**: Apple's product path does carry the
film's audio (run B, unambiguous with the mic muted), and §9.nn's structural
point is unchanged — `StudioEngine.attachFilm` attaches the tap in the same
method that installs the video output, so Apple never had Android's hole. What
does not stand is §9.nn's NUMBER, which was the room.

**The standing rule this adds**: when a measurement can have more than one
source, mute every source but the one under test before believing the number.
A level is not evidence of WHAT is making it.

### §9.nn Apple does NOT have Android's audio hole — but the Mac bench door muted the PROGRAM, and `-v error` hid the answer twice (2026-09-18)

§9.mm found that every Android broadcast published with no audio track,
because the tap was offered by film id at go-live and called from nowhere. The
same question had to be asked of Apple, since Decision 127's A/V numbers came
from the same kind of run.

**Apple is clean, and for a structural reason.** `StudioEngine.attachFilm`
attaches the film tap itself, in the same method that installs the video
output — so a surface that gets the PICTURE has necessarily attempted the
AUDIO. All three product surfaces call it (`StudioSession` on macOS,
`StudioPlayerContainer_iOS`, `DetailView` on tvOS). Android's version asked a
controller for the tap at go-live, which nothing did. **Proved, not read**: on
the macOS product path mediamtx reported `tracks: [H264, MPEG-4 Audio]` with
2,357 audio frames sent. **CORRECTED IN §9.oo**: the level quoted here
originally (-41.8 dB) was the MICROPHONE — the owner's room — not the film,
and *Dr. Mabuse* is a silent print carrying no audio track at all. The film
audio is real and is measured properly in §9.oo with the mic muted.

**The real defect was in the instrument, and it silenced the thing under
test.** `StudioSession.muteFilmForHarness()` did two things under one name:

    localPlayer?.isMuted = true                       // the ROOM
    Task { await engine?.setAudio(filmMuted: true) }  // the PROGRAM

The second takes the film fader to zero in the program mix
(`fg = (filmMuted ? 0 : filmGain) * duckGain`). So **every broadcast the Mac
bench door ever produced went out with the film silent**, and no Apple
product-path audio had been measured through it — the door that exists to
prove the program is right was quietly removing part of the program. The two
are different things wearing one word: the owner's speakers are protected by
the LOCAL player's mute, which is the one that drove a film to every HomePod
for an hour (§9); the film fader is what the audience hears and is no business
of a harness. Now `muteLocalMonitorForHarness()`, and it mutes the room only.

**And the measurement lied twice on the way, the same way both times.**
`ffmpeg -v error ... -af volumedetect` prints NOTHING: volumedetect writes its
statistics at INFO level, so `-v error` suppresses exactly the lines being
grepped for. That read as "the audio track decodes to zero samples", which was
then confirmed by a second consumer doing the same thing, and briefly looked
like a serious product defect — an AAC track declared but undecodable, which
would have been Apple's parallel to §9.mm. Dropping `-v error` showed
4.86 million samples and a normal level. **A silent instrument is not a
negative result**; when a tool prints nothing, check its verbosity before
believing the absence.

Two smaller traps recorded with it: mediamtx's **fMP4 parts do not decode
standalone** (audio failed on every one, on both platforms, while a direct
RTMP capture of the same publisher decoded cleanly) — record `mpegts` when the
audio is the thing being measured; and an RTSP pull with `-c copy` and no
`-map` came back video-only, which is ffmpeg's stream selection, not a missing
track.

### §9.mm The Android chat port, driven on a television — and the audio track no Android broadcast has ever carried (2026-09-18)

`StudioChatTwitch.kt` had been written, compiled and marked **"never driven on
a device"** rather than given a green tick. Driving it on the Google TV found
three faults, and only the first was the one being looked for.

**The channel was chosen on evidence, not hope.** A previous run read 0
messages and the cause turned out to be a channel that had gone quiet, so the
target is now picked by a raw anonymous-IRC probe first: of eight large
channels joined for 25 s, seven were silent and one was carrying ~1 message a
second. That one was used. Counts, never transcripts — strangers' words are
not our evidence.

**Fault 1 — the channel could never have arrived.** The controller read
`System.getenv("AW_STUDIO_CHAT")`. An Android app launched by `am start`
inherits the **zygote's** environment, so that reads nothing on a device while
working perfectly in a unit test. It is now an intent extra, `aw_studio_chat`,
beside the doors that already existed. Unlike `aw_studio_dest` it is NOT
DEBUG-gated: naming a public channel to READ grants nothing and sends nothing,
where the destination decides where a broadcast GOES.

**Fault 2 — chat drew over the lower third, seen only on the glass.** The
chat column's floor was `height - unit * 9`; the lower third's scrim top is
`baseY - unit * 2.6 * lines - unit * 2`. At 720p those are 558 and 472, so the
two newest pills sat **on top of the film's title** — the one thing the lower
third exists to say. Two numbers describing one edge will always drift, so
there is now one expression, `lowerThirdTop(height, hasProvenance)`, and both
drawers read it. Apple was checked for the same defect against its own
recorded frame and is clear: its floor is a fraction of the frame that lands
above its stack.

**Fault 3 — the one worth the trip. Every Android broadcast has gone out with
NO AUDIO TRACK.** mediamtx reported `tracks: [H264]` and nothing else. The
film was not the reason: `ffprobe` on the Archive's own derivative shows a
44.1 kHz AAC track that was there the whole time.

`StudioController.audioTapFor(archiveID)` — the function that hands the engine
the film's audio — **was called from nowhere.** The tap class, the AAC
encoder, the priming-delay correction and Decision 129's measured A/V
alignment all existed; the wire from the player to the tap did not. The engine
behaved correctly given no tap: §6.2's rule is that a stream's tracks are
declared once at publish, so it waited for an AAC config, timed out, and
published video-only rather than committing a protocol error.

**Why the wire was missing is the lesson.** A Media3 audio processor belongs
to the `AudioSink` chain, and that chain is fixed at `ExoPlayer.Builder`
time. Asking for the tap when the host goes live is too late to reach
anything — the only moment it can be installed is when the player is BUILT,
long before anyone has decided to broadcast. An API whose only correct call
site is far away from the feature it serves is one that will be left
unconnected, and it was; it also means Decision 129's A/V numbers were a
harness measurement, never a product-path one. This is the same shape as the
§6.2/§6.3 rules that lived only in `StudioLab` on Apple (§9.bb, and
Decision 130).

So the tap is now installed on every playback, and its idle path was rewritten
to earn that: two atomics and a strided peak scan read straight out of the
buffer with absolute gets, allocating a `ByteArray` only while a broadcast is
actually listening. It is gated at SDK 29 for the reason the thermal read
beside it is — the Studio is google-only (Decision 129) and this file compiles
into the amazon flavour at minSdk 23, which keeps Media3's default sink
untouched.

**Measured after the fix**, one run, `The Four Horsemen of the Apocalypse`
(1921, a film this feature had not been driven on before):

| | |
|---|---|
| tracks | `H264` + `MPEG-4 Audio` (44.1 kHz stereo) |
| audio level | mean **-19.7 dB**, peak **-3.7 dB** over 3,973,120 samples (45.05 s) |
| chat | 8 pills in frame, wrapped, clear of the lower third |
| legibility | held over a bright intertitle (§6.4a's case) |

Not silence, not clipping, and the picture proves the fix in the same frame as
the audio measurement — one run, not two stitched together.

**Still true after this**: the §6.4a alphas are Apple's numbers, chat
re-renders only when the line ids change, and YouTube chat remains
owner-blocked on a client id. What changed is that Android's half is now
evidence rather than compiled code.

### §9.ll One command for §8, and three faults it found in itself first (2026-09-17)

§8 listed six tests across Swift, Kotlin and Python and there was **no way to
run them together** — each had its own `swiftc` invocation, its own server, its
own prerequisites. Tests that cannot be run in one command do not get run.
`tools/test_studio_all.sh` starts one `mediamtx`, generates the saturating clip
once (a bitrate is a ceiling, not a floor — §9.y), runs everything and prints a
summary:

    8.1 rtmp publish             PASS
    8.4 rtmp reconnect           PASS
    8.5 thermal                  PASS
    8.6 back-pressure            PASS
    8.3 ten-minute soak          SKIP   not run without --soak
    test_studio_rights_parity    PASS
    test_studio_rights_coverage  PASS
    Kotlin suites                PASS   pass=46 skip=0 fail=0
    pass=52 skip=1 fail=0
    SUITE RESULT: PASS (with skips)

**It took three runs, and all three faults were in the runner:**

1. **A stale proxy failed a good test.** 8.6 reported "video never actually
   yielded" — true of a run that had never been throttled, because a previous
   harness's proxy had survived a Swift `exit(0)` (which skips `defer`) and was
   forwarding at full rate. It passes standalone. Every case now gets a clean
   slate: *a suite that perturbs its own cases is worse than no suite.*
2. **The Kotlin row printed PASS over `pass=0 skip=0 fail=0`.** The counts file
   was written one directory above where it was read, so 46 cases were also
   missing from the totals. Zero parsed results now reports **FAIL** — a green
   row over no data is the most expensive kind of green, and this script exists
   to prevent exactly that.
3. **Then my own fix killed the suite silently.** `swift_case` re-enabled
   `set -e`, and a `pkill` matching nothing exits non-zero — so the run aborted
   mid-8.4 **and still reported exit 0**, because piping through `tail` replaces
   the status. Errexit is gone (the script is `set -u` only; it must report
   every case, not stop at the first surprise), cleanup is `|| true`, and the
   result is now PRINTED as well as returned.

**The rule it enforces is the session's own**: a SKIP is not a PASS. Four
Kotlin cases skip silently without a local server and did so for a whole
session (§6.2n), so skips are counted separately, named, and `--strict` makes
them failures.

**The soak's own result, run standalone** (2026-09-18, after the first
`--soak` attempt was killed by the system for memory pressure — the shared
server was recording every case to disk for no reader):

| over 10.0 minutes at 1080p30 / 6000 kbps | |
|---|---|
| frames encoded / sent | **18012 / 18012** — none dropped |
| audio frames · pushed | 25819 · 363 MB |
| memory | 71.3 → 76.9 MB (**+5.6 MB**, flat at ~83 MB from minute two) |
| peak send queue | **39 kB** of §6.4a's 1149 kB cap (**3%**) |
| fps at worst after minute one | 29 |
| thermal · pool failures · reconnects | nominal · 0 · 0 |

Nine assertions, all green. Memory grew LESS than the 12.8 MB of §9.aa's run
because no second server was recording alongside it — which is the memory fix
showing up in the measurement it was made for.

**And `--strict` had a bug that reading found and running never would have.**
It printed `SUITE RESULT: PASS (with skips)` and only THEN evaluated
strictness and exited 1, so the spoken line contradicted the exit status on
exactly the runs the flag exists for. The printed line exists *because* a
caller's pipe replaces the status, so it is the line that has to be right. The
verdict is now computed once and then spoken. That is discipline 11 found
inside the mechanism written to enforce discipline 11.

### §9.kk §5's adaptive step had no surface on ANY platform (2026-09-17)

Audited straight after §9.jj, and it corrects §9.jj: **`qualityNote` was
written by both engines and rendered by nothing.** The only reader anywhere was
the diagnostic log line added in §9.ff. So the sentence existed, fired at the
right moment, said the right thing — and no host on any platform could see it.
§5's *"never auto-lower quality silently — an adaptive-bitrate step is shown as
it happens"* was unsatisfied, and a run that read the note out of a log had been
mistaken for proof that it was satisfied. That is this session's recurring
fault with my own name on it.

Now rendered by all four: the tvOS readout and the macOS panel (before their
generic thermal sentences, because "sent at 3600 instead of 6000 kbps" tells a
host what changed and "getting hot" does not), the iOS capsule's warning list,
and Android's `problem` — which reaches both its §9.4 readout and its §9.3
sheet.

**The restore announcement is transient, the degraded state is not.** "Back to
full quality" is an announcement; left up it would sit there for the rest of
the show reading like a warning. Apple clears it after 8 s through an
actor-isolated method (a detached `Task` touching `health` is a Swift 6 error);
Android uses an expiry timestamp checked in the per-second block, because that
code runs inside the render loop and has no scope to launch from — and a
timestamp cannot leak a task.

**What is proved.** Android's `problem` is pure logic and is tested —
`StudioProblemTest`, 4/4: the step is what the host is told, the restore is
shown too, a live show with no note reports no problem, and a note never masks
a stalled encoder.

**And then the first attempt to see it on a television showed the design was
wrong.** Folding the note into `problem` gave it ONE slot, and with the tvOS
dev door running without a destination the state sentence correctly won it —
"no destination is set" is the more important thing to say. But the two facts
are independent: a device can be hot *and* have nowhere to send. So on tvOS and
macOS the note now has **its own line**, which is what §4's "health is never
hidden" actually asks for; the one-chip-only rule stays where it came from, the
iPhone capsule, which truncates.

Seen on an Apple TV 4K 3rd gen, 2026-09-17 — both lines at once:

> ● **NOT SENDING**  3,080 kbps
> ⏱ The device is running hot, so the picture is being sent at 3600 kbps instead of 6000 kbps.
> ⚠️ The show is being made but not sent anywhere — no destination is set.

So §5's adaptive step is now on a screen, and the run that proved it is also
the run that proved a single slot would have hidden one of two true things.

### §9.jj §6.5's RETURN journey (2026-09-17)

The step down had been measured (§9.gg) and the restore had not — a single
injection can only ever prove half of the rule. The Mac door now takes a
**sequence** (`AW_STUDIO_THERMAL=serious,nominal`,
`AW_STUDIO_THERMAL_AT=20,45`), which is what a return journey needs.

On the macOS product path, from the app's own per-second line:

| samples | |
|---|---|
| 19 | `kbps=6000 thermal=nominal` |
| 25 | **`kbps=3600 thermal=serious`** — the step |
| 31 | **`kbps=6000 thermal=nominal`** — the restore |

Both sentences were produced — and here is the correction this write-up
needs: they were read from the **diagnostic log**, not from anything a host
can see. `qualityNote` is written by both engines and rendered by **no
surface on either platform** (audited the following tick). §5's "an
adaptive-bitrate step is shown as it happens" is therefore NOT satisfied by
this run; what is satisfied is that the engine produces the right sentence at
the right moment:

- *"The device is running hot, so the picture is being sent at 3600 kbps
  instead of 6000 kbps."*
- *"Back to full quality 6000 kbps."*

§6.5 wrote that requirement down as **"a step back up the host cannot see is
the same defect as a step down they cannot see"** — and on the evidence of this
run the host could see NEITHER. Both directions are observed in the engine;
neither was on a screen. Fixed in §9.kk.

**§6.5 is therefore complete on Apple**: step down (§9.gg), restore (here), and
`.critical` ending the show with a reason a host reads (§9.gg, §9.hh).

### §9.ii §6.6's EXPIRED DEADLINE, finally exercised — and the backoff schedule read off a real run (2026-09-17)

Every reconnect test until now succeeded **on the first attempt**, so two
things had never run: the 60-second give-up, and the `RECONNECTING` state
itself (recovery was always instant).
`AW_PROXY_STAY_DOWN=1` makes `tools/rtmp_sever_proxy.py` sever connection 1 and
then REFUSE every later one — accept-then-close, so attempts fail fast and the
backoff runs its real shape instead of being paced by connect timeouts.

On the macOS product path:

| | |
|---|---|
| LIVE | 19 one-second samples, `reconnects=0` |
| **RECONNECTING** | attempts **1→7**, dwelling **1, 2, 4, 8, 15, 15, 15 s** |
| proxy | `conn 2`–`conn 8`: REFUSED (stay-down) |
| outcome | **"The broadcast ended — the connection could not be restored within 60 seconds."** |

The dwell times are §6.6's schedule read off a real run rather than asserted
from the source, and they sum to **exactly 60 seconds** — the deadline landing
where the rule says it should, with `min(back, remaining)` keeping the last
15-second wait from overshooting it.

So the whole of §6.6 is now observed on a product path: the rebuild (§9.ee),
the RECONNECTING state, the bounded schedule, the give-up, and the sentence a
host reads afterwards (§9.hh).

### §9.hh A show that ends itself now says why on every Apple surface — and the title that disagreed with it (2026-09-17)

§9.gg recorded that `endedReason` was written by the engine and read by
nothing on Apple, and fixed it on the Mac only. tvOS and iOS now consume it
too: the television reuses its existing alert, the phone its existing
"Could not go live" alert — the host's question is the same either way, *why
am I not live?*

Verified on the Bedroom Apple TV 4K (3rd gen) by injecting `.critical` into
the real engine (`AW_STUDIO_THERMAL=critical`, DEBUG only — tvOS has no
platform override, so the seam is the only route):

> **The broadcast ended**
> The device became too hot to keep broadcasting.

...over *Sherlock Jr.* still playing, which is §3's rule holding: the film is
never gated on the broadcast.

**The first attempt got the body right and the TITLE wrong**, and only the
glass showed it. The alert's title was a **two-state Bool** — film or
configuration — so an overheated television was announced as **"Streaming is
not set up yet"**. A wrong title tells the viewer something false, which is
what the comment above that alert already says about the film/configuration
split; a third real state had simply arrived and a Bool cannot describe three.
Replaced with `StudioRefusalKind { film, configuration, ended }`, and the
`.ended` body drops the "The broadcast ended —" prefix the title now carries.

### §9.gg §6.5 on the macOS PRODUCT path, and the reason nobody could read (2026-09-17)

macOS has no equivalent of Android's `cmd thermalservice override-status`, so
the engine's own seam is the only route to §6.5 here — which is what the seam
was written for. `AW_STUDIO_THERMAL=serious|critical` with
`AW_STUDIO_THERMAL_AT=<seconds>` (DEBUG only) injects it into the real engine
behind the real app.

**The step lands on cue**, read from the app's own per-second line:

| second | |
|---|---|
| … 20–24 | `kbps=6000 thermal=nominal` |
| 25 (injection) | **`kbps=3600 thermal=serious`** — §6.5's 60% |
| 26… | holds at 3600 |

And `.critical` **ends the show**: `state=OFF`, and mediamtx reports **no
paths** — the publish is gone, not idling.

**The wire could NOT corroborate the step, and the reason is §9.y's lesson
recurring.** *Nosferatu* is a low-motion silent that encodes at roughly
1 Mbps, so it never approaches EITHER ceiling — 6000 or 3600 — and the server's
rate is unchanged by the step. A bitrate is a ceiling, not a floor. The
Android proof measured a 44% drop on the wire because that run used a
saturating clip; this one is an app-side measurement and is described as one.

**A real gap found by doing this, and fixed**: `endedReason` was written by the
engine and read by **nothing on Apple**. §6.5 says `.critical` "ends the show
with the end card" and §5 says health is never hidden — but a Mac host whose
broadcast ended saw only `OFF`, with no reason anywhere. Android already
surfaced it through its controller. `StudioSession`'s pump now turns it into
the host-visible refusal and verifies:

    [AWSTUDIOENDED] The broadcast ended — the device became too hot to keep broadcasting.

**Still not surfaced on tvOS or iOS.** Only `StudioSession` (the macOS driver)
consumes `endedReason`; the television and the phone would still show a show
that simply stopped.

**And an instrument fault that cost two runs**: Swift's `print` goes to stdout,
and stdout to a PIPE is fully buffered — so terminating the app before the
buffer filled lost everything it had said. Two runs reported "zero health
lines" from an app that was working perfectly. Diagnostics now write to
**stderr**, which is unbuffered. An instrument that can silently lose its own
output is worse than none.

### §9.ff §6.4 on the macOS PRODUCT path — after the throttle was fixed to withhold READS (2026-09-17)

§6.4 had been proved on Apple only from the standalone harness, never through
the shipping app. Driving the Mac's own path exposed a defect in the
INSTRUMENT first.

**The first run looked like a clean pass and proved nothing.** The server saw
the intended ~400 kbps, and the app reported `queued` near zero, `vdrop=0`
throughout, and 30 fps unbroken. Both were true, because
`tools/rtmp_throttle_proxy.py` did `recv(65536)` from the client at **full
speed** and throttled only the FORWARD to the server. The excess buffered in
Python, so from the app's side the link was never slow: it was a server-side
rate limit, not client-side congestion.

**Real back-pressure comes from NOT READING.** The token bucket now sizes each
`recv`, and with no tokens the loop sleeps *without reading* — the client's send
buffer fills, which is exactly what defers `NWConnection`'s `contentProcessed`
and makes `queuedBytes` climb. Re-run against the shipping Mac app, 6 Mbps
program throttled to 400 kbps, cap 1.15 MB:

| phase | queued | video sent | video dropped | audio sent |
|---|---|---|---|---|
| open | ~0 | +30/s | **0** | +43/s |
| throttled | pinned **1.08–1.40 MB** | **frozen** (486 → 508 over 18 s) | **0 → 492** | **+43/s throughout** |

So the picture yields and the voice does not, on the product path rather than
in a harness.

**And the evidence is a LOG, not a screenshot.** `StudioSession`'s pump now
prints one machine-readable health line a second in DEBUG when a diagnostic
destination is set — state, fps, queued, video sent/dropped, audio sent,
reconnects, thermal, audio session. It exists because the numbers §6.4 turns on
are not on the panel at all, and because a full-screen capture on the owner's
own Mac takes in whatever else they have open. Server-side evidence answers
"did it arrive"; this answers "what did the app decide".

**Android re-checked with the corrected instrument** and the tick-52 result
stands rather than being an artifact: cap 474 kB, peak queued 478 kB, 0 drops
before / 64 during, **audio 420 of 420 delivered**. The old proxy's incidental
read-blocking had been enough there; it was not enough at 6 Mbps.

### §9.ee §6.6 on the macOS PRODUCT path (2026-09-17)

The Mac is the only Apple device where a real publish can be driven end to end
with no owner grant: loopback needs no Local Network permission (§9.dd), and a
`.custom` destination needs no client id. Driven through the product's own
path — `AW_STUDIO_MAC=1` arms the Studio and plays, bounded at 95 s and muted,
which is the door's own design after the Apple TV incident — with
`tools/rtmp_sever_proxy.py` cutting the link at 25 s. Film: *Sherlock Jr.*
(1924).

Server-side evidence, which is the part that counts:

| t | mediamtx `live/awmac` |
|---|---|
| 5–20 s | ready, bytes → **1.32 MB** |
| 25 s | proxy severs `conn 1` |
| 25 s | **`bytesReceived` resets to 249 kB** — a NEW publish; proxy logs `conn 2: open` |
| 31–82 s | climbing continuously → **3.29 MB** |

So §6.6 recovers on the macOS product path, not merely in a harness. The byte
counter resetting is the cleanest proof available that the server accepted a
second publish rather than the first one limping on.

**The readout at the moment of the cut said `OFFLINE`**, with "The connection
to the platform is down." — not `RECONNECTING`. That is accurate rather than
wrong: `showState` checks `publisher.isReconnecting`, which is set inside
`reconnect()`, and the supervisor polls once a second — so between the link
dying and the first attempt starting there is a sub-second window where the
host sees OFFLINE, and RECONNECTING follows. Recovery here was fast enough that
RECONNECTING was never caught on a still. Worth knowing before anyone reads a
single screenshot as the whole state machine.

### §9.dd The iOS product path can now be driven — and iOS's Local Network gate stops it reaching a bench server (2026-09-17)

Everything measured on the iPhone so far came from **`StudioLab`**, a debug
screen that configures its **own** audio session and its own destination. So
the PRODUCT path had never run on a phone, and §6.2's iOS branch — the one that
has to RECORD, where tvOS only ever needs `.playback` — had never been read
there.

Two pieces were built for it:

- `AW_STUDIO_IOS=<archiveID>` with `AW_STUDIO_DEST` starts the real Studio
  through the product's own container, gated on the rights audit exactly as the
  go-live sheet is. A `.custom` destination needs no client id, which is what
  makes this possible before the owner registers one.
- The container draws `audioSessionState` in DEBUG **below** the health
  capsule, not inside it — that capsule already truncates on a small phone
  when a warning chip joins it.

**And then iOS refused, for a reason Android had no equivalent of.** Pointing
the phone at `rtmp://10.0.0.90:19351` put the app on the **Local Network**
privacy prompt — *"Allow ArchiveWatch to find devices on local networks?"* —
and mediamtx saw no path at all. Android's identical bench door worked because
Android has no such gate.

**Not taken on the owner's behalf.** Granting local-network access on someone's
own phone is their decision, and a harness refuses a prompt rather than
answering it. The app was terminated, which took the prompt off their screen.

**And `NSLocalNetworkUsageDescription` was deliberately NOT added to the
shipping `Info.plist`.** The product does not do local networking: a real
broadcast goes to YouTube or Twitch over the public internet and needs no such
permission. A usage string in the shipping app for a debug-only harness path
would be a claim about the app that is not true, and App Review would rightly
ask about it. **So this is a harness limitation, not a product one.**

Left unread, with a precise unblock: §6.2's iOS `.playAndRecord` outcome on a
device. It needs either one tap of *Allow* on that prompt (owner), or the real
client ids, after which the destination is a public host and the gate never
appears.

### §9.cc §3.4a READ at iPad width, and a scroll hook to make that possible (2026-09-17)

§3.4a has said since it was written that the warning "is shown on the
pre-broadcast surface — the iOS go-live sheet". It was built there, and it had
never been LOOKED AT on iOS or iPadOS: in the KEEP state it sits below the fold,
so a screenshot of the sheet was not a screenshot of the warning. That is the
same shape as verifying a rule by absence.

`AW_GOLIVE_SCROLL=warning` (verification hook, no-op in production) scrolls the
Form to the §3.4a section, whose scroll id is shared with the hook so the two
cannot drift apart. On an **iPad Pro 12.9-inch**, *La Passion de Jeanne d'Arc*
(1928, `safe_pd_age`), the paragraph is complete and legible at regular width,
with the warning triangle: an automatic copyright matcher can interrupt or end a
stream even when the rights are clear, a silent film's modern recorded score may
still be under copyright, and the app checks the film's age but cannot check a
platform's matcher.

The same scroll also put the rest of the sheet on the glass for the first time
at this width: Privacy/Unlisted, the "nothing can be published to YouTube from
this build" footer sitting under the not-configured row, "How it looks" with
Layout = *Film with you in the corner*, and §3.4's policy line.

**iPhone 15 Pro, same build**: the sheet renders correctly **in landscape** — a
phone geometry not previously checked — and shows the REFUSAL state, because a
freshly installed catalogue carries no rights verdicts yet. The hook is guarded
on `refusal == nil` and correctly did not fire. The iPad behaved identically on
its first launch and became a KEEP a few minutes later once the catalogue
updated, so this is the gate failing safe rather than a defect.

**Re-checked once that catalogue had updated**: the 15 Pro reaches the KEEP
state and shows §3.4a's paragraph in full, in landscape, above the Layout row
and §3.4's policy line. So the warning has now been read on **three**
geometries — a television (§8.8's one-time confirmation), an iPad at regular
width, and a phone in landscape.

### §9.bb §6.2's audio session, on an Apple TV (2026-09-17)

§6.2 was moved out of the harness and into `StudioEngine` in the same session
it was found there, and until now it had only been COMPILED. It is the rule
whose failure is silent — a failed activation stops `AVPlayer` dead (§9) — so
compiling is not evidence.

**The problem with verifying it at all**: success looks like nothing. No error
message meant nothing was known. So `StudioHealth.audioSessionState` now
records the category actually in force, and the tvOS readout draws it **in
DEBUG builds only** (a host has no use for it). Positive evidence instead of an
absence.

On the Bedroom Apple TV 4K (3rd gen), *Nosferatu* (1922):

| run | readout |
|---|---|
| normal | **`audio: Playback/MoviePlayback active`**, 708 kbps, film playing |
| `AW_STUDIO_BAD_AUDIO=1` | **`audio: FAILED: Resource not available`**, 994 kbps, film playing |

So the engine puts tvOS in exactly the category §6.2 specifies, and the readout
is a real discriminator rather than a constant.

**The control's result is narrower than it looks, and the difference matters.**
`AW_STUDIO_BAD_AUDIO=1` asks for `.playAndRecord` with `.moviePlayback` — the
combination §6.2 names as invalid everywhere — and tvOS REFUSED it, which
confirms the rule on hardware and gives the real message: **"Resource not
available"**, not a bare OSStatus -50. But the film kept playing in the control
too, because a REFUSED category change leaves the previous working one in
force. So this control proves the combination is invalid and that our category
is the one in effect; it does **not** reproduce §9's stall, which came from a
failed *activation* (`.playAndRecord` on tvOS before a Continuity microphone
port exists) rather than from a rejected category. Reproducing that needs a
Continuity pairing, which is owner-blocked.

Teardown: terminated by pid, and the box powered back off because it was off
before the run.

### §9.aa The §8.3 soak, re-run after §6.4/§6.5/§6.6 (2026-09-17)

`tools/test_studio_soak.swift`, ten minutes at **1920×1080@30, 6000 kbps**,
against a real `mediamtx`. Framed negatively on purpose: on a healthy link
nothing should happen.

| over 10.0 minutes | |
|---|---|
| frames encoded / sent | **18010 / 18010** — none dropped |
| audio frames | 25783 |
| pushed | 363 MB |
| peak send queue | **25 kB** of §6.4a's 1149 kB cap (**2%**) |
| memory | 71.6 → 84.4 MB, flat at ~91 MB throughout, peak 112.3 |
| reconnects / encoder faults / pool failures | **0 / 0 / 0** |
| fps at worst after the first minute | 29 |
| thermal | nominal throughout |

**What it was run to answer.** §6.4a cut the back-pressure budget from a flat
2 MB to 1.5 s of the show's bitrate. If that were too tight, a host on a
healthy link would lose frames for no reason — the fix for a rule that never
fired would have become a rule that fires when it should not. At 6 Mbps the cap
is 1149 kB and the queue peaked at 25 kB: two per cent, so the budget has room
to spare on a good link while still being a latency rather than a byte count.

**18010 sent against 18010 encoded also re-proves §9.z's other find**: 59 of
those would have been dropped at the start before the opening keyframe was
asked for.

**And the memory question is settled by plateau, not by a threshold.** A
95-second smoke run showed 30.5 → 77.1 MB and that looked like a leak; over ten
minutes it is flat at ~91 MB from minute two onward. Warm-up, not growth —
which is why the harness logs `phys_footprint` every second rather than
comparing two endpoints. The 291-second stall was misdiagnosed as a memory leak
for hours before an instrument showed the footprint flat.

### §9.z Back-pressure: the promise holds, the threshold did not, and every broadcast opened two seconds blind (2026-09-17)

`tools/test_studio_backpressure.swift` on the real `StudioEngine`, with
`tools/rtmp_throttle_proxy.py` narrowing a 2.5 Mbps program's uplink to
**400 kbps** for 11 s. §6.4 holds:

| | before | while throttled | after |
|---|---|---|---|
| peak send queue | 4 kB | **515 kB** (cap 474 kB) | 0 kB |
| video frames dropped | **0** | 48 | 0 |
| video rate | 30 fps | **1 fps** at worst | **30.1 fps** |
| audio frames in the worst second | — | **43** (≈43 expected) | — |

So the picture yields and the voice does not — which is the whole promise —
and video recovers the moment the uplink does.

**Two product defects, both found by this harness, neither visible any other
way:**

1. **The cap could not fire.** §6.4a now carries the reasoning: 2 MB was
   6.4 seconds of latency at this bitrate, the queue peaked at 1.39 MB, and
   nothing was ever dropped. The budget is now 1.5 s of the show's bitrate.
2. **Every broadcast opened with 59 dropped video frames — two full seconds
   blind.** A fresh publish starts in `droppingUntilKeyframe`, the IDR from the
   avcC probe is consumed rather than sent, and every frame the ticker produces
   after it is a P-frame until the 2 s GOP boundary. The reconnect path had
   asked for that keyframe since §6.6 was written; **the path every broadcast
   takes had not.** One line, and the count went 59 → 0. Worth sitting with:
   the fix existed in the codebase and was wired only to the rare path.

**Three instrument faults, in the family this session keeps meeting:**

- the cap was read BEFORE `engine.start()` computed it, so the harness printed
  the pre-configuration default, failed, and buried a correct result — the
  drops were already in its own table;
- recovery was judged by TOTAL frames across a 9-second congested window and a
  6-second recovered one (223 vs 150) and declared "video did not recover"
  while the table showed 1 fps against 30. Rates, not totals;
- the audio claim is asserted per SECOND, not in total, because a total hides a
  four-second silence inside a healthy-looking sum.

### §9.y Thermal pressure: the rule was wrong, and the dial that enforces it was loose (2026-09-17)

`tools/test_studio_thermal.swift`, driving the **real `StudioEngine`** against a
real `mediamtx`, asserted from the server's own recording.

§6.5 said `.serious` should "halve the encode RESOLUTION". It was implemented
nowhere, which is the only reason it never broke a broadcast: an RTMP stream's
format is fixed for the life of the publish, so the documented response would
have destroyed the stream it was meant to protect. Corrected to the bitrate,
which is the one dial that may move. Measured:

| | nominal (target 4000 kbps) | `.serious` (target 2400) |
|---|---|---|
| mean over 7 s | **2893 kbps** | **1959 kbps** |
| mean video packet | 11534 B | 7997 B — **31% smaller** |
| resolution / frame rate | 1280×720 @ 30 | **unchanged**, as the rule now requires |

`.critical` ends the show with a reason (`endShow`), verified in the same run.

**The finding worth keeping: `AverageBitRate` alone barely works.** The first
honest run stepped the target from 4000 to 2400 kbps and the wire went from
**3.6 Mbps to 3.3 Mbps — a 7% drop where 40% was asked for**. Per-second
buckets showed no convergence at all, just a 2.8/3.9 Mbps oscillation on the
2-second GOP. `AverageBitRate` is a soft VBR target over a long window; what
actually BINDS is `DataRateLimits`, and ours sat at **twice** the average, so
it never bit. At 1.15× the step lands. `H264Encoder.dataRateCapFactor` is now
one constant used by both the start path and `setBitrate`, because a thermal
step that tightened a cap the start path had left loose would have made the
two paths disagree about what the bitrate means.

**Two instrument faults, both of which produced a PASS:**

1. **The first run had no film**, so the program was a static black frame
   compressing to ~58-byte packets. A bitrate is a **ceiling, not a floor**:
   nothing was pressed against it, so lowering it changed not one byte, and the
   test "passed". The harness now requires a high-entropy clip
   (`testsrc2` blended with noise, ~20 Mbps) and SKIPs with the recipe if it is
   missing.
2. **`guard ma < mb`** passed on 58.4 B vs 58.3 B while printing "0% smaller"
   — a float comparison standing in for a measurement. It now demands a real
   margin (>15%).

And a smaller one: `encodedFramesPerSecond` is a delta since the last
`refreshHealth()`, so calling it once after nine seconds reported **"270 fps"**.
The harness refreshes once a second, which is the counter's contract.

### §9.x A severed link, recovered — and three instruments that lied on the way (2026-09-17)

`tools/test_rtmp_reconnect.swift` + `tools/rtmp_sever_proxy.py`, against a real
`mediamtx`, asserted from the server's OWN recording. §6.6 holds:

| | control (no reconnect) | §6.6 |
|---|---|---|
| segments recorded | 1 | 2 |
| seconds recorded | **5.1** (of a 22 s program cut at 6 s) | **18.9** |
| publisher at the end | `closed` | `publishing`, 1 reconnect |
| reconnected | — | **on attempt 1**, 6.0 s in |
| post-cut A/V offset | — | **0.02 s** |

The forced keyframe lands **one frame** after the reconnect (frame-level trace,
`AW_STUDIO_DIAG=1`): 842 B against ~200 B for the inter-frames around it.

**The point of the control.** Without it this test passes on a server that
never noticed the cut. With it, the same run with recovery switched off has to
die at the cut — and it does, at 5.1 s.

**Three instrument faults, each of which produced a green or a wrong red:**

1. **The assertion judged `segs.last`** and passed while the resumed segment
   carried a 1.64 s A/V offset — mediamtx had written a short third segment at
   close and the check read that one. It now judges **every** segment after the
   first. An instrument that chooses which sample to judge will eventually
   choose the wrong one.
2. **The harness's own readiness probe ate the sever.** A "is the port
   listening?" TCP connect became connection 1, so the proxy cut the probe and
   the publisher was never severed — the CONTROL arm recorded a full clean
   stream. The proxy now counts only connections that actually send bytes: *a
   test instrument must not be visible to the test.*
3. **A wrong diagnosis, corrected only by a frame-level diagnostic.** The A/V
   assertion fired at 1.63 s and "the reconnect did not open on a keyframe" was
   the obvious reading. The trace showed the keyframe arriving correctly one
   frame in. The real cause was the harness encoding **one AAC frame per video
   frame** — 23.2 ms of audio against 33.3 ms of video, ~10 ms of drift a
   frame, 1.63 s after 160 frames. It presents as an A/V offset ONLY once a
   server re-bases on a republish, which is why §8.1 never saw it and why
   §8.1's assertions (codec, resolution, sample rate) still pass over it. The
   tone is now paced to the video clock.

   Worth keeping as the shape of the thing: the assertion was RIGHT to fire and
   the first explanation was wrong, and only an instrument said so — the same
   lesson as the 291-second soak.

**Also found, NOT fixed:** §6.5's rule that `.critical` thermal state ends the
show **is implemented nowhere**. `thermalState` is reported as a string and
nothing acts on it. This is §6.3's idle timer again — a rule written in this
document and implemented in no product path. `StudioEngine.endShow(reason:)`
now exists (§6.6 needed it), so the wiring is small; it has not been done or
measured, and until it is, a `.critical` broadcast keeps going.
