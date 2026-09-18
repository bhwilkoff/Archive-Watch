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
3. A ten-minute soak at 1080p30: no dropped-frame growth after the first
   minute, thermal state never `.serious`. `tools/test_studio_soak.swift` runs
   it against a real server and asserts the negative case as well — that the
   send queue never reaches §6.4a's cap and §6.6 never fires on a healthy
   link. Device runs: the iPhone 12 and an Apple TV (**Fireplace is off
   limits**, and it is the only 2nd-gen box, so the hardware FLOOR needs a
   window the owner offers).
6. `tools/test_studio_backpressure.swift` + `tools/rtmp_throttle_proxy.py` —
   §6.4 on the real engine: a proxy narrows the uplink mid-show so the
   publisher discovers congestion through its OWN send buffer. Asserts that the
   queue crosses the cap ONLY while throttled, that video is what yields, that
   audio advances in **every** second of the congestion, and that video
   recovers — by RATE, never by totals across windows of different lengths.
5. `tools/test_studio_thermal.swift` — §6.5 on the **real `StudioEngine`**
   (the four Studio files compile standalone against a local `mediamtx`), driven
   through `overrideThermalState`. Needs a **saturating** film: the harness
   prints the ffmpeg recipe and takes it as `AW_THERMAL_CLIP`.
4. `tools/test_rtmp_reconnect.swift` — §6.6 on a real server: publish to a
   local `mediamtx`, SEVER the link mid-stream, and assert from the server's
   OWN recording that media resumes. The negative control is the same run with
   reconnection disabled, which must NOT resume — without it the test passes on
   a server that simply never noticed.

## §9 — Measurements (filled in as they are taken)

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

### The tvOS rules, and two conflicts that had to be faced (2026-09-17)

Reading `docs/tvOS-DESIGN.md` before building the tvOS surface — the same
discipline that improved the iOS shape — turned up two rules the Studio
appeared to break. Neither could be quietly ignored.

1. **§10.2 said "No external auth."** That is a real rule with a real purpose,
   stated in its own text: *no funnel* — sign-in is optional for browsing and
   playback and gates only sync. The Studio's YouTube/Twitch sign-in is a
   different kind of thing: it is not identity for Archive Watch, it authorises
   publishing to the viewer's **own** channel, it appears only after the viewer
   has chosen to broadcast a specific film, and it changes nothing about
   browsing, playback, favorites or sync. §10.2 now says "no external auth
   **for identity**", and new **§10.2a** states the distinction and the rule
   that still holds: *the app never asks who you are in order to show you a
   film.*
2. **§13 listed "Live/linear broadcast" as out of scope.** That gap is about
   *receiving* — we do not become a TV tuner. *Producing* one is the opposite
   direction and is in scope as of Decision 127. The line now says which.

New **§8.8** puts the Studio where iOS §8.8 puts it: the **player plus
overlays** (§3.7 + §8.1), never a §3.6 mode. It also binds the three things the
SDK taught us — the picker is full-screen and **one-time**, the microphone is
an audio-session port, and **no camera is not an error** (a paired phone can be
asleep or carried away mid-show; the program continues film-only and says so).

And a assumption corrected on the way: **`ASWebAuthenticationSession` IS
available on tvOS 16+** (checked in the tvOS 27 SDK). I had expected to need
the OAuth device-code flow for a television; one auth path serves both
platforms, and on tvOS the system hands off to a nearby device rather than
asking anyone to type on a remote.

### The tvOS surface (2026-09-17)

**The entry point is the transport menu, not Detail** — and that turned out to
be better than the iOS flow rather than a compromise. tvOS Detail's action row
already carries seven buttons inside a 1100pt cap (an eighth truncates the
Play label), which is why SharePlay lives in the player's menu. The Studio
joins it as one `UIMenu` named **Watch Together** with *With friends…* and
*With the world…*. The viewer is already watching when they decide to bring
the world in, and §8.8's Studio IS this player plus overlays — so nothing is
presented over anything, and no cover is pushed.

A refusal is an **alert with the sentence plus the policy**, never a missing
menu item.

`StudioTVHealth` is the ten-foot readout, and it is deliberately not the
phone's capsule shrunk or stretched:

- **34pt state, 30pt bitrate, 29pt problem line** — §4's 29pt floor is a
  minimum, not a target, and nobody leans in to read a bitrate on a
  television.
- **One problem at a time, in words.** There is no touch target to tap for
  detail at ten feet, so the readout states the single most important thing
  wrong ("The film has stopped — your audience sees a still picture") instead
  of a chip that means nothing across a room.
- **Inside the 90 × 60 safe area** (§6.1). A television overscans, and a
  health readout the TV has cropped away is worse than none — the host
  believes they can see it.

`AW_STUDIO_TV=1` beside `AW_START_ITEM`/`AW_AUTOPLAY` starts the Studio on the
playing film, for the same reason `AW_START_TAB` exists: driving a transport
menu blind over a remote is focus luck, not a test. **The dev door still goes
through `StudioRights`** — a harness that skips the gate is testing something
the viewer will never run.

**Verified on the glass: the tvOS REFUSAL.** On the Bedroom Apple TV (4K 3rd
gen, tvOS 27) the alert reads *"This film cannot be streamed / This copy has
no rights verdict in the catalog on this device… / Only films published before
1930 can be streamed…"* with a focusable OK — §2.5's rule that no state is
without a focusable element applies to explanations too. It fired because that
box still held a **cached schema-1 database**, so the fail-closed rule proved
itself on a second device unprompted; and the dev door went through
`StudioRights` rather than round it, which is the whole reason it was written
that way.

**Verified on the glass: the ten-foot readout** (Bedroom Apple TV 4K, tvOS 27,
`build/qa/golive/tvos-readout2.png`) — inside the safe area, over the film:

```
● NOT SENDING   5,499 kbps
⚠ The show is being made but not sent anywhere — no destination is set.
```

**And the first capture found a real bug.** The readout originally said
**`IDLE 5,486 kbps`** — it was reporting the PUBLISHER's state as though it
were the SHOW's. With no destination the publisher never leaves `.idle`, which
is true of the publisher and a lie about the program: the engine was
compositing and encoding 5.5 Mbps at that moment. A host making a show that
goes nowhere must be TOLD that, not told nothing is happening.
`StudioHealth.showState` now answers the host's question rather than the
transport's — `OFF · NOT SENDING · CONNECTING · LIVE · OFFLINE · ENDED`, each
with a sentence where there is room for one — and both platforms read the same
words from the same place. **A number can be correct and still mislead; which
question it answers is part of its correctness.**

**Two instrument failures, recorded because they will cost the next session an
hour otherwise:**

1. *`devicectl device capture screenshot` fails outright on the Fireplace box*
   — `CoreDeviceError 3` / "The connection was invalidated" / no file written —
   while `process launch` on the same device works. It is the screenshot
   service, not the connection.
2. *A launch can come up BACKGROUNDED*, showing the Apple TV Home screen while
   the console proves the app is running and building its player. The harness
   memory already records this as the doze-window failure; a Companion press
   before launching did not cure it.

And one error of my OWN, worth more than either: I grepped a capture for its
success line, got nothing, and carried on — then read a **stale file from an
earlier capture** and reasoned about it as though it were current. The clock in
the image was the tell. A capture step must delete its target first and assert
the file exists afterwards; anything less is an instrument that lies quietly.
That is Decision 116's lesson wearing different clothes — and
`tools/atv_shot.sh` is the fix: it removes the target, captures, and REFUSES
unless a new file exists and is under a minute old. The class of error is
closed, not just this instance. Reading stale evidence and reasoning about it
as current is not a mistake care prevents; it needs an instrument that cannot
do it.

### The ten-minute soak (§8.3) — iPhone 12, 2026-09-17

```
120s  fps=30 render=9.10ms overruns=1 drops=0 thermal=nominal
240s  fps=30 render=9.12ms overruns=1 drops=0 thermal=nominal
360s  fps=30 render=9.14ms overruns=1 drops=0 thermal=nominal
480s  fps=30 render=9.14ms overruns=1 drops=0 thermal=nominal
600s  fps=30 render=9.14ms overruns=1 drops=0 thermal=nominal
SUMMARY mean=30.2fps worst=30.0fps filmFrames=18012 render=9.14ms
        overruns=1 dropped=0 thermal=nominal
```

**No drift.** Render mean is flat at 9.14 ms from two minutes onward, 18,012
film frames pulled, **0 dropped**, the single overrun is the warm-up, and the
thermal state never left nominal on the oldest phone the app supports. §8.3 is
satisfied on iOS.

### A harness that ran in someone's living room (2026-09-17)

**The incident.** Verifying the tvOS surface meant launching the app on the
owner's Apple TVs with `AW_AUTOPLAY=1`. The film played **unmuted** and an
Apple TV routes audio to every HomePod in the house. It ran for about an hour
before the owner asked why movie music was playing across their home.

Two faults, and neither was carelessness in the moment:

1. **The tvOS dev door had no end.** It started the engine and polled until
   `studioFilm` went nil, and *nothing set it nil* once a screenshot had been
   taken. `StudioLab` has always had `AW_STUDIO_SECONDS` and torn itself down;
   the tvOS door was written without the equivalent.
2. **Device runs defaulted to AUDIBLE.** That default was chosen on purpose in
   the Mac harness — a muted player is the obvious way to measure silence and
   call it a working audio path (§9) — and then carried onto hardware that
   lives in a home.

**Three fixes, because an intention is not a safeguard:**

- `AW_STUDIO_TV_SECONDS` (default **180**) bounds the tvOS door, which then
  clears the film and unmutes. It cannot outlive the person using it.
- The dev door **mutes the room** (`player.isMuted = true`). It costs the
  measurement nothing real: the broadcast's film level is
  `StudioAudioMixer.filmGain`, never the player's mute (§5).
- `StudioLab` is **muted by default**; `AW_STUDIO_AUDIBLE=1` asks for sound
  and the log says so, so an audible run is always deliberate.
- `tools/atv_teardown.sh` terminates the app **by pid** (`process terminate`
  takes `--pid`, never a bundle id — a wrong flag prints usage and reads like
  success) and powers the box back off, failing loudly if it does not.

Verified: a 45-second bounded run played **silently**, showed `NOT SENDING
4,722 kbps`, and had already exited by the time teardown looked for it.

**The general rule, and it is the third time this feature has taught it:**
`atv_shot.sh` exists because care does not stop you reading a stale file;
`atv_teardown.sh` exists because care does not stop you leaving a film
playing in someone's house. When a harness reaches into the physical world,
cleanup is a step with an assertion — not a habit.

### The sign-in flows, proven before there was a client id (2026-09-17)

The owner's remaining work is pasting two strings. The risk that creates is
that every defect in the request shapes surfaces at once, on the owner's own
account, in a flow that cannot be stepped through. So everything that does not
depend on a client id was checked first — `tools/test_studio_signin.swift`,
**26 checks, all passing**. It compiles the REAL source files rather than
restating their logic.

**PKCE against an INDEPENDENT reference.** RFC 7636 Appendix B publishes a
verifier and the challenge it must produce, and the RFC predates this code, so
it cannot be a golden file of our own making (the Decision 119 rule):

    verifier   dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk
    challenge  E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM   MATCH

Plus 200 generated verifiers: all base64url-clean (no `+`, `/` or `=` — base64
produces all three and an authorization server rejects them), all 43–128
characters per §4.1, all distinct.

**The live shape checks, with deliberately invalid credentials.** This is the
part that could not be done any other way. A platform that rejects our
CREDENTIAL has accepted our REQUEST, and the two failures read completely
differently:

    POST id.twitch.tv/oauth2/device    400  {"message":"invalid client"}
    POST oauth2.googleapis.com/token   401  {"error":"invalid_client",
                                              "The OAuth client was not found."}

Neither says "missing required parameter", which is what a wrong shape earns.
**And the discriminator is negative-controlled**, because a guard on a rule's
consequence is not a guard on the rule (Decision 120): the same Google request
with `grant_type` removed answers `unsupported_grant_type` — a REQUEST fault,
and not `invalid_client`. So the check can tell the two apart.

**Four defects the screen found that no check could.** The sheet was rendered
on an iPhone 12 through `AW_GOLIVE_DEMO` on two different films (*The Wedding
March* 1915, then *Japanese Varieties* 1904):

1. **"Signing in to Youtube"** — `rawValue.capitalized`, two lines above a
   hand-written "YouTube" in the same section. A brand name is not a word to
   capitalise; `Platform.displayName` now holds each platform's own spelling.
2. **The wrench icon was accent blue.** A `Label` in a `List` takes the
   accent tint, so a statement of fact read as a button. CLAUDE.md's brand
   split reserves `#0047FF` for things you can press.
3. **The footer contradicted the row above it** — "You will be asked to sign
   in to YouTube once" sitting two lines under "Sign-in is not set up". Two
   adjacent sentences disagreeing is worse than either alone.
4. **Go Live was still pressable** with no client id, and would have failed
   inside `StudioPlatformAuth`. It is now disabled — which is not §5's
   unexplained disabled control, because the reason is on screen directly
   above it.

### The Apple TV ten-minute soak FAILED at 293 seconds (2026-09-17)

§8.3 is **not** satisfied on tvOS. The run is worth reading in full because
what broke is not the number, it is the instrument:

```
 43s  fps=30 film=25 enc=30 render=7.70ms overruns=31  drops=0 kbps=5389 thermal=nominal
120s  fps=31 film=26 enc=30 render=7.54ms overruns=75  drops=0 kbps=6294 thermal=nominal
240s  fps=31 film=26 enc=30 render=7.60ms overruns=144 drops=0 kbps=5347 thermal=nominal
292s  fps=32 film=27 enc=6  render=7.66ms overruns=165 drops=0 kbps=298  thermal=nominal
293s  fps=35 film=29 enc=0  render=7.66ms overruns=166 drops=0 kbps=2    thermal=nominal
360s  fps=31 film=25 enc=0  render=7.64ms overruns=166 drops=0 kbps=2    thermal=nominal
600s  fps=31 film=25 enc=0  render=7.58ms overruns=166 drops=0 kbps=2    thermal=nominal
SUMMARY mean=30.2fps worst=29.0fps filmFrames=15075 render=7.58ms
        overruns=166 dropped=0 thermal=nominal
```

**Encoding stopped at 293 seconds and the run reported a healthy show for the
remaining 307 — then summarised itself as a pass.** Render held 7.58 ms, the
film kept arriving at 25 fps, `drops=0`, thermal nominal. mediamtx's own log
shows the TCP connection **staying open the whole time** and closing only at
16:06:23, i.e. when the run ended — so the publisher had nothing to report
either, and `lastError` was never set. Nothing anywhere said a word.

**Why nothing knew.** Both of VideoToolbox's statuses were being discarded:
`VTCompressionSessionEncodeFrame`'s return value entirely, and its callback's
behind `guard status == noErr, let sample else { return }`. The one component
that knew what had happened threw it away, which is the §9 "two faults"
lesson arriving a third time — a program can look perfect and carry nothing.

**What changed, before any attempt at a root cause** (the repo's debugging
rule: observability first, and this is unobservable as it stands):

- `H264Encoder` records both statuses — the raw OSStatus included, because
  `kVTInvalidSessionErr` (-12903) and `kVTVideoEncoderMalfunctionErr`
  (-12361) mean different things and only one is fixable by restarting the
  session.
- `ProgramRenderer` counts pixel-buffer **pool** failures separately. An
  exhausted pool and a malfunctioning encoder present identically — frames
  stop — and need opposite fixes, so the next run will not have to guess.
- `StudioHealth` gains `encodedFramesPerSecond` (a RATE; a total that stops
  climbing is invisible to anyone not differencing it, which is precisely
  what the readout was not doing) and a new show state **`notEncoding`**,
  checked BEFORE the publisher because this is the failure that looks
  healthiest. It is deliberately cause-agnostic: it fires for an encoder
  malfunction, an exhausted pool, or anything else.
- Both readouts say it — the iOS capsule as a warning and in the sheet's
  Health section, the tvOS ten-foot readout through `showState.detail`.
- **`StudioLab` now FAILS the run at the second it happens** and can no
  longer print a passing SUMMARY over a stall.

**Not yet known**: what stops the encoder at ~293 s. It is not thermal
(nominal throughout) and not back-pressure (`drops=0`, socket open). The next
soak names its own cause, which is the point of the change above.

**Process note.** This soak began on the Fireplace Apple TV — the only 4K
**2nd generation** on the bench, i.e. the Studio's hardware floor — and the
owner stopped it: *"Stop using the fireplace tv for testing. I'm actively
watching on it now."* It was terminated on the spot and the box deliberately
NOT powered off. Both remaining Apple TVs are 3rd generation, so **the figures
above are not the floor** and must not be read as it; 7.58 ms here against
10.70 ms on the 2nd gen. A floor re-run needs a window the owner offers.

### The 291-second stall, diagnosed and fixed — and §8.3 now PASSES on tvOS (2026-09-17)

**Cause: tvOS's screen saver invalidates the VideoToolbox session.** The new
instrumentation named it on the first re-run:

```
FAIL the encoder stopped at 291s — film still arriving at 28 fps,
     fault=the encoder refused a frame (submit -12903) poolFailures=0
ENCODER framesEncoded=8768 encodedBytes=162172411 stalledAt=291
     mem=278MB avail=1820MB          (flat, every sample)
```

`-12903` is `kVTInvalidSessionErr`: the session was not struggling, it was
**gone**. Reproduced at 293 s and then 291 s — both just under the Apple TV's
five-minute default "Start Screen Saver After". tvOS takes the display, and
taking the display invalidates the compression session; every subsequent
`VTCompressionSessionEncodeFrame` returns -12903 forever.

**My hypothesis was wrong and the instrument said so.** The leading theory was
memory: 6 Mbps for 293 s is ~220 MB if anything accumulates, and
`Task { await publisher.send(video:) }` spawns one unstructured, unbounded
task per encoded frame (~73/s with audio), which looked like exactly the
right kind of mistake. Memory was **flat at 278 MB with 1.8 GB free** for the
whole run, and `poolFailures=0`. Worth recording because the plausible story
was ready before the measurement, and would have produced a real refactor of
something that was not broken.

**The fix is one line that was already a RULE.** §6.3 has said
"`UIApplication.isIdleTimerDisabled` while live" since the doc was written. It
was implemented only in `StudioLab`, and there behind `#if os(iOS)` — so the
one platform whose screen saver kills the encoder never got it, **and the real
Studio never got it on either platform**. It now lives in
`StudioEngine.start()` / `stop()`, guarded on `canImport(UIKit) && !os(macOS)`
rather than on a platform name, which is what the original guard got wrong.

**A rule implemented in the test harness is not implemented.** That is the
lesson, and it is the same shape as Decision 120's (a guard on a rule's
consequence is not a guard on the rule). The harness is where a rule gets
*exercised*; the product is where it has to *live*.

**§8.3 satisfied on tvOS** — ten minutes, Apple TV 4K **3rd** gen, the same
film and settings as the failing run so only the fix varied:

```
120s  fps=31 film=26 enc=31 render=7.96ms drops=0 kbps=6793 thermal=nominal
240s  fps=30 film=25 enc=31 render=7.95ms drops=0 kbps=5559 thermal=nominal
291s  fps=30 film=25 enc=30 render=7.98ms drops=0 kbps=1360 thermal=nominal
300s  fps=30 film=25 enc=30 render=7.98ms drops=0 kbps=2969 thermal=nominal
420s  fps=30 film=25 enc=30 render=7.99ms drops=0 kbps=1769 thermal=nominal
600s  fps=30 film=25 enc=30 render=8.01ms drops=0 kbps=5933 thermal=nominal
SUMMARY mean=30.2fps worst=30.0fps filmFrames=15096 render=8.01ms
        overruns=287 dropped=0 thermal=nominal
ENCODER framesEncoded=18144 encodedBytes=360702879 fault=none
        poolFailures=0 stalledAt=never
```

Straight through 291 s with `enc=30`, 18,144 frames encoded, 360 MB of
program, memory flat at 249 MB, render drifting 7.96 → 8.01 ms over ten
minutes (0.6%), 0 dropped. **Still not the hardware floor** — this is a 3rd
gen; the 2nd-gen run is booked for the owner's 3:00 pm MT window.

**NOT built, deliberately: recovery from a lost session.** The Studio does not
restart the encoder on -12903, and that is a scope call rather than an
oversight. The only route to a lost session we know of is the display being
taken, and §6.3 already rules that a backgrounded Studio **ends the show with
an end card** rather than limping — so the remaining case is covered by policy,
not by a restart. A mid-stream restart also means re-sending the avcC sequence
header on a live RTMP stream, which not every ingest accepts. What the Studio
now does instead is SAY so: `notEncoding` reaches both readouts within a
second.

### The camera tile's cost, measured at last — on the Mac (2026-09-17)

This was the last Phase 0 number, and it had been sitting behind a permission
grant on the iPhone and the Apple TV. It did not need to: **this Mac has a
FaceTime HD camera and a microphone, both already TCC-authorised.** The
harness's own header said "No camera: ... on the Mac there may not be one" —
written before anyone looked, which is the same failure mode as every stale
claim in this file.

A/B, same film (*The Curse of Quon Gwon*, 1916 — 1080p30, `corner` layout,
Mac15,3 / 8 cores / macOS 27.0), the camera tile at 1280x720 because the tile
is never full-frame:

```
                       render mean        runs
  no camera            6.47 / 6.62 / 6.66 ms
  camera + microphone  7.20 / 7.24 ms
```

**The camera tile costs ~0.73 ms per frame — about 11%, and 2.2% of a 33.3 ms
budget.** The claim it was standing in for ("a camera tile is a cheap
composite next to a 1080p film decode") is correct, and now has a number. 30.1
fps mean and 0 dropped frames in every run, with and without.

### The audio finding the A/B exposed, which is what made it worth running

The runs without a camera reported `padded 3316` — **twice, identically** —
and the runs with one reported `padded 0`. A number that is bit-identical
across runs and then vanishes when an unrelated device is attached is not
jitter; it is a race.

It was the mixer starting into an empty ring. The ticker runs on its own
1024/44100 s clock, which is right and is what keeps the program's audio at a
constant rate — but it began the instant `start()` was called, before the film
tap had delivered anything, so the **opening chunks of every broadcast were
padded with silence**. 3,316 samples is 1,658 frames, ~38 ms. It was zero in
the camera runs only because setting the camera up delayed the start enough
for the ring to prime.

`StudioAudioMixer.tick()` now holds off until the film has actually delivered
a packet, bounded to ~30 ticks (0.7 s) so a film with **no** audio track still
gets a running, silent program rather than waiting forever.

**And the fix is partial, which is the honest result.** After it, the same run
reports `padded 588` and `padded 1902` — down from a fixed 3,316, but no
longer deterministic, which means the remainder is *genuine jitter* in the
film tap's delivery against the mixer's fixed clock, not a startup artifact.
7–22 ms of scattered silence across 45 seconds (~0.04% of the audio).

**Not fixed further, deliberately.** The obvious next step is a real jitter
buffer — prime to three or four packets and let the cushion absorb the
variance instead of padding. That buys silence-free audio at the cost of
~70–90 ms of added audio latency, and A/V alignment was measured at **10 ms**
over 15 s (§9 above). Trading a 10 ms sync figure for a 90 ms one to remove
0.04% of inaudible padding is the wrong trade. Padding IS the jitter absorber
here, chosen over latency on purpose — written down so the next person does
not "fix" it into a lip-sync bug.

### Phase 2 begins — the Studio on macOS, and the rights gate on the glass (2026-09-17)

Rules first: **macOS-DESIGN §B13** (a–f), which is entirely consequences of
§B2a and §B3a rather than new ideas. The load-bearing one is §B13a — on macOS
the player **replaces the split view as the window root**, so the Detail view
that offered "go live" is *gone* by the time an `AVPlayer` exists. tvOS
presents its player as a cover from Detail and can hold the engine there; the
Mac cannot.

`Studio/StudioSession.swift` is the answer: one `@Observable @MainActor`
session owns the show, Detail **arms** it (applying the rights gate before
anything plays), and the player surface hands it the player it just built. It
holds one show, because a device produces one show at a time.

- **The menu is now the owner's framing, literally.** Detail's "Watch
  Together…" was SharePlay only; it is a submenu with **With Friends…**
  (SharePlay, Decision 098) and **With the World…** (the Studio, Decision
  127). A submenu, not two peer rows, because the choice a host makes is "who
  is this for", not "which feature".
- **§B13e: the camera needs an ENTITLEMENT on macOS**, unlike the phone —
  `com.apple.security.device.camera` plus `NSCameraUsageDescription`, both now
  present. Worth stating plainly: the +0.73 ms camera figure above was taken
  with an **unsandboxed command-line harness**, which is exactly why it worked
  before the entitlement existed. A sandboxed Mac app without it gets a TCC
  denial that looks like "there is no camera" — the same trap §B12 already
  records for `device.microphone`.
- **Closing the window ends the show.** A broadcast must never outlive the
  surface producing it; that is how a harness ended up playing into someone's
  living room.
- **`AW_STUDIO_MAC=1`** arms the Studio and plays, so §B13d's readout can be
  seen without clicking (§B11's own reason: SwiftUI exposes no scriptable
  menu). Bounded — 120 s default — and it mutes **both** the program's film
  bus and the local player, because those are different things and only one of
  them is what a person in the room hears.

**On the glass, and it found something.** `The Curse of Quon Gwon` (1916) on
this Mac refused with *"This copy has no rights verdict in the catalog on this
device, so it cannot be streamed. Updating the catalog may resolve it."* —
alert rendering correctly with the reason **and** the policy beneath it.

That refusal was **correct and not the expected branch**. The published DB says
that film is `safe_pd_age`, 1916, `silent-film` — fully eligible. The Mac's
*cached* DB is schema 1, so `rightsBucket` came back nil and the gate refused
an unknown verdict, exactly as §3.4 requires. That is the third platform on
which the schema-1 guard has proven itself unprompted.

The published DB was verified directly rather than assumed, since a missing
column there would gate the feature off on every device:

```
schemaVersion = 2      items columns = 32      rightsBucket present
presumed_pd 11253 · safe_pd_age 4236 · (null) 2765 · safe_gov 2648
renewal_zone 1333 · safe_archive_license 1233 · renewal_zone_bw 906
eligible for the Studio (guaranteed tier): 4210
```

4,210 — the same figure counted from `catalog.json` back when the tier was
chosen, now confirmed from the artifact the clients actually read.

### The whole chain, proved from the SHIPPING macOS app (2026-09-17)

Everything before this was measured by a harness. This is the app.

The macOS Studio published to a local `mediamtx` (`AW_STUDIO_DEST`, a
diagnostic door — never a product path) and a frame was pulled back with
ffmpeg. **The program carries all three layers**: the 1916 film aspect-fit and
letterboxed, the Mac's FaceTime camera composited as the corner tile, and the
lower third reading *The Curse Of Quon Gwon / 1916 · Marian E. Wong / PUBLIC
DOMAIN — PUBLISHED 1916, BEFORE 1930* in marquee orange.

**Why it had to be done this way.** On macOS the window shows the plain film
through `AVPlayerView`; the PROGRAM only exists as encoded bytes. No
screenshot of the app can ever show whether the camera tile and overlays are
really in the broadcast — the only honest check is to publish and look at what
comes back. It also confirms `com.apple.security.device.camera` works in the
sandbox: without the entitlement a sandboxed app finds no camera at all, which
is indistinguishable from having none (§B13e).

### The macOS control panel, and what the glass changed about it (2026-09-17)

§B13c called for "a `Form` in a sheet". Built, and then fixed twice by looking
at it:

1. **Six health rows pushed the Sound faders below the fold.** A sheet cannot
   grow past its parent window, so the controls a host actually reaches for
   mid-show were invisible on open. Health is now two compact rows — and
   nothing is hidden, because the always-on readout (§B13d) carries the state,
   the bitrate and the problem sentence. What belongs in the panel is only
   what the readout has no room for.
2. **A five-option radio group is chrome.** macOS uses a pop-up button for an
   exclusive choice of that size; the radio group cost five rows to say one
   thing. Same for the cards.

After both, everything a host needs mid-show fits without scrolling: health,
layout, and both faders with their live meters. **The microphone meter showed
a real level in the shipping app**, which is the mic path verified outside a
harness for the first time.

One shared-code fix fell out of it: `StudioLayout.label` — the user-facing
names — lived inside `GoLiveSheet_iOS.swift` behind `#if os(iOS)`, so the Mac
panel could not see it. The tempting fix is a second copy, which is exactly
how two platforms end up calling the same layout different things. It now
lives once, beside the enum it names.

### Still to measure (Phase 0 remainder)

- The camera tile's and microphone's cost **on the phone and the Apple TV** —
  still blocked on a one-time camera + microphone grant there, and on
  Continuity pairing for the TV. **Measured on the Mac** (above): +0.73 ms per
  frame. The phone number is expected to be larger and is worth having, but
  the architectural question the measurement existed to answer is answered.
- Sign-in on a TELEVISION. `ASWebAuthenticationSession` presents itself on
  tvOS with no anchor; that screen cannot be seen until a client id exists
  (Decision 128). The **not-configured** state IS built and verified (tvOS-
  DESIGN §10.2b): the transport menu says "Streaming is not set up yet" and
  names both platforms.
- A ten-minute soak on the Apple TV (§8.3). The iPhone 12's is above.

The four bullets that used to sit here — the real destinations, the audio
path, the camera tile's cost, and the iPhone soak — are measured, and their
results are the sections above. They are deleted rather than left standing
because a stale "still to do" is how Decision 121 got written.
