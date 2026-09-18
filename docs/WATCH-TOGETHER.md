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

### §9.tttt The tee is DELETED: the Studio PULLS its audio by film position (2026-09-18)

Owner, after watching §9.rrrr and §9.ssss go by: *"There have to be better ways
of doing this audio routing and syncing. Can you do some more research before we
continue to burn cycles on this?"* Right on both counts.

**The constraint that produced the mess.** `AVPlayerItemVideoOutput` exists and
works with HLS; there is no `AVPlayerItemAudioOutput`. The audio counterpart is
`MTAudioProcessingTap`, which does not work with HLS at all — the remote asset
reports zero tracks — and Decision 106 forces tvOS onto HLS. So the television
has picture but no sound by construction, and everything built since was
scaffolding around that hole. iOS and macOS are unaffected: they use the tap.

**What was wrong with the tee.** It handed the Studio whatever the HTTP segment
route happened to fetch. That felt free — those bytes are already in hand — and
it was the wrong SCHEDULE: the player BUFFERS, so the frames ran 75-125 s in
front of the picture. Correcting that afterwards took a playhead push, a priming
fetch, a drop rule and a hold rule, and still only reached +0.23 s while
discarding 1,682 packets and stalling 2,786 times.

**What replaced it.** The Studio now PULLS, asking the server for the audio at a
FILM POSITION and keeping a 12-second window ahead of the picture, 8 seconds at
a time. Sync stopped being a correction applied afterwards and became a property
of what gets requested. Measured on the same box, same film:

    AWPULL first frames=475 asked=1520.7 firstAt=1517.9 delta=-2.75
    AWSYNC audioFilmPos=1573.59 playhead=1573.36 offset=+0.23 queued=11.5 ooo=0 dropped=99 held=123
    AWSYNC audioFilmPos=1678.20 playhead=1677.98 offset=+0.22 queued=18.2 ooo=0 dropped=99 held=235

| | tee + correction | position pull |
|---|---|---|
| offset | +0.23 s | +0.22 s |
| queued ahead | 150-280 s | 11-18 s |
| dropped | 1,682 and climbing | 99, flat after startup |
| held | 2,786 | 235 |

The drop/hold stays as a SAFETY NET rather than the mechanism, and `dropped`
staying flat is now the evidence that the puller is keeping its side of the
bargain — a rule that fires constantly is load-bearing, one that fires once at
startup is a guard.

**Alternatives weighed and not taken.** `AVSampleBufferRenderSynchronizer` with
an `AVSampleBufferAudioRenderer` and an `AVSampleBufferDisplayLayer` is Apple's
documented answer when AVPlayer cannot give you what you need, and it would make
sync exact by construction — but it replaces the tvOS playback path wholesale:
buffering, seeking, the caption engine (Decisions 068/072), the AirPlay swap
(051) and resume. Recorded here as the destination if frame-accurate control is
ever wanted; not worth that blast radius for this. A second reader for audio
only was rejected on Decision 071's own finding, that a second player races the
main audio render on tvOS, and it doubles decode on the 2nd-gen floor.

**A void run worth keeping.** One attempt measured nothing:
`filmHasAudio=false sourceHasAudio=false` — Soul-Fire is a silent upload with no
score, so the Studio correctly found nothing to carry and never started. The
standing rule to vary test content collided with what this test needs; an
audio-sync run needs a film whose audio track has been MEASURED, not merely a
different film.

**Still open**: +0.22 s is above the ~45 ms at which audio leading video is
noticeable. It is now a fixed pipeline latency — the mixer's ring plus encode —
rather than an alignment artifact, which makes it the next tractable target.

### §9.ssss The 75 seconds are GONE — +0.23 s, and two main-actor stalls found on the way (2026-09-18)

§9.rrrr measured the television's audio 75 seconds in front of its picture.
Aligned, on the product path, same box:

    AWPRIME frames=1682 fromSeconds=474.1 firstAt=470.8 delta=-3.31
    AWSYNC  audioFilmPos=539.75 playhead=539.52 offset=+0.23 queued=281.0 dropped=829  held=2727
    AWSYNC  audioFilmPos=644.54 playhead=644.30 offset=+0.24 queued=156.4 dropped=1682 held=2786

**+75 s to +0.23 s, and FLAT** across the run. ITU's tolerance for audio leading
video is about 45 ms and this is 230 ms, so it is not yet good — but it is a
quarter of a second rather than a minute and a quarter, and it no longer grows.

Two halves, and neither works alone. The playhead is PUSHED to the decoder,
which releases a packet when the picture reaches it instead of when the network
delivered it; and priming fetches the audio under the CURRENT picture directly,
because that segment was fetched before the sink existed and the tee will never
offer it again. Alignment without priming is 75 s of silence.

**TWO MAIN-ACTOR STALLS, and the same tell found both.** The app kept
broadcasting for three and a half minutes while its diagnostic log stopped dead
at 31 s — encoder threads live, every main-actor line gone. A hang and a crash
look identical in a log that simply ends, so the difference had to be measured:
mid-run log pulls at 60/120/180 s plus a screenshot. Causes: priming was
`await`ed inline on the main-actor path (~15 sequential ranged GETs behind the
server's serial queue), and the drop loop called `removeFirst()` in a `while`,
which is O(n^2) over a burst-fed backlog WHILE HOLDING THE DECODER'S LOCK — with
a 10 Hz time observer on the MAIN queue waiting on that same lock. Priming is
now detached, the drop is one pass, and the observer runs at 4 Hz on its own
queue.

**A control that became wrong when the design changed.** `outOfOrderBursts`
caught §9.rrrr's units error because a pure tee's bursts must chain. Priming
deliberately breaks that chain, so a non-zero count became the NORMAL case and
the refusal fired on every healthy run. The mapping's control moved to AWPRIME's
`delta` — this route is ASKED for audio at a known film time and must answer at
it — which checks against a value known outside the arithmetic. A control has to
be wrong only when the thing it guards is wrong.

**Still open, and the reason the architecture is being reconsidered rather than
extended**: 230 ms is above the 45 ms threshold; `dropped=1682` and
`held=2786` say the decoder is discarding and stalling constantly to hold the
line; and `queued` sits at 150-280 s, so the tee is still delivering minutes
ahead of what is wanted. That is a lot of machinery to hold a quarter second.

### §9.rrrr THE TELEVISION'S AUDIO IS 75 SECONDS AHEAD OF ITS PICTURE (2026-09-18)

§9.qqqq closed the drift question and said in as many words that equal stream
durations are a DRIFT proxy, not a lip-sync measurement, because a constant
offset is invisible to it. That was not a hedge. **The constant offset is 75
seconds.**

    audioFilmPos=608.04  playhead=528.83  offset=+79.21  queued=49.2  ooo=0
    audioFilmPos=707.43  playhead=634.54  offset=+72.90  queued=54.1  ooo=0

Positive means audio is AHEAD. Every tvOS broadcast this feature has made —
including the 8m16s soak whose 15 ms was reported the same morning — has sent
the film's sound about a minute and a quarter in front of its picture.

**The cause is the thing `FilmAudioDecoder`'s own header warned about.** The
tee is fed by the player's BUFFERING, not by playback. At go-live the queue is
empty and the first packet it is ever handed comes from the BUFFER HEAD, which
on a local server sits 75-125 s in front of the playhead. A FIFO drained at
real time then preserves that lead for the life of the show. The decoder paces
itself correctly and starts in the wrong place, which is why every rate-shaped
measurement passed.

**NO STIMULUS CLIP WAS NEEDED, which is worth keeping.** Android needed a
flash-and-beep clip (§9.fff) because nothing in its pipeline knew film time.
Apple's tee already addresses every AAC packet by film sample index, and
`FilmAudioBridge`'s comment had said for a session that this is so the decoder
"can hold them and release what the show clock actually asks for". The decoder
dropped the argument on the floor. Reading a value the system already carried
turned a two-day instrument job into an afternoon.

**THE INSTRUMENT WAS WRONG FIRST, AND ITS CONTROL CAUGHT IT.** The first run
printed offsets of -102 s to -464 s. An MP4 `sample` of a sound track is one
AAC FRAME of 1024 PCM samples, and `firstSample` counts FRAMES; it was read as
a PCM count and had `j * 1024` added to it, which pins every position under
7.5 s. The counter that caught it was `outOfOrderBursts` — every burst must
continue where the last ended — which climbed to 89 where a sound mapping
requires 0. An independent check then disproved the number outright: RMS-envelope
correlation of the recording's opening 30 s against every later 30 s window
showed distinct audio throughout, so the broadcast was NOT replaying the film's
start. **The readout now REFUSES to report an offset while `ooo > 0`**, the way
`measure_av_sync` refuses a flash/burst count mismatch rather than averaging
through it. A number that survives its own control is worth something; one that
does not was never evidence.

**Not a parity gap, and that was checked rather than assumed.** The tee and
decoder are `#if os(tvOS)`. iOS and macOS have their own `DetailView` and take
film audio through `MTAudioProcessingTap`, which is inline with rendering and
therefore aligned by construction. This defect belongs to the television alone.

**What the fix cannot be.** A fixed delay would paper over it and be wrong the
moment the buffer depth changed — the same reasoning §9.ggg used to refuse a
fixed audio delay on Android. The audio must be released BY FILM TIME against
the playhead, which also needs priming: the segment covering the current
playhead was fetched before the show began and the tee will never hand it over
again.

### §9.qqqq The hardware FLOOR, soaked: 1080p30 held, and ~15 ms of drift over eight minutes (2026-09-18)

Both things §9.pppp left open, closed by one run — on the Apple TV 4K **2nd
generation**, the Studio's hardware floor, which the owner freed up and on which
none of this work had ever run. Every performance figure in this feature until
now came from the faster 3rd-gen box.

Eight minutes and sixteen seconds, Blood and Sand, published to a local mediamtx
and read back from ITS recording:

    video   h264 1920x1080   30.000 fps   duration 496.033 s
    audio   aac 44100 stereo              duration 496.048 s
    mean_volume -17.2 dB      max_volume 0.0 dB

**1080p30 holds on the floor**, with the full pipeline — composite, encode,
publish AND the new audio decoder — on the slower hardware.

**Drift: 15 milliseconds over 496 seconds**, or 0.003%. The two tracks span the
same wall time to within a frame and a half, so neither starved nor ran ahead
cumulatively. The self-pacing decoder does what it was built to do over a long
run, not merely a three-minute one.

**What that number is NOT, said plainly.** Equal stream durations are a DRIFT
proxy, not a lip-sync measurement: a constant offset between picture and sound
would be invisible to it, because both tracks would still span the same time. It
proves the clocks do not diverge; it does not prove they agree. Android needed a
flash-and-beep clip to find a **0.7-second constant lead** that every timestamp
analysis had called healthy (§9.ggg), and that measurement has no equivalent
here yet. Calling this "A/V verified" would repeat exactly the error that cost
the Android port two rounds.

**Instrument notes.** The first attempt produced nothing: the box was asleep, the
launch was refused, and the script cheerfully reported "mid-run shot taken" for a
screenshot of an idle television — a capture succeeding says the DEVICE
responded, never that our app was on screen. Waking it needed the Companion
identifier (`atvremote scan` prints it, and pyatv already held credentials);
addressing the box by IP alone resolves to its AirPlay audio endpoint and
silently answers about the wrong service. The unit was returned to
`PowerState.Off` afterwards, because it was found that way.

### §9.pppp THE TELEVISION HAS SOUND: -91.0 dB → -17.6 dB, measured from the server's recording (2026-09-18)

The repair is done and the number that defined it has moved.

    before:  mean_volume -91.0 dB   max_volume -91.0 dB   (digital silence)
    after:   mean_volume -17.6 dB   max_volume   0.0 dB

Read from mediamtx's own recording of a broadcast published by the Apple TV, not
from anything this app says about itself. The teed source measured -17.9 dB
(§9.oooo), so the wire is within 0.3 dB of what went into it.

**The last link, `FilmAudioDecoder`, and the two things it had to get right:**

  - **It paces itself.** The tee is fed by the player's BUFFERING — 378 seconds
    of audio in 90 (§9.nnnn) — while the mixer's ring holds one second.
    Decoding on arrival would overflow it and then starve, which is the
    two-clock failure that cost the Android port two rounds. Compressed frames
    queue (cheap: ~4 MB for six minutes) and a pump decodes one AAC packet per
    20 ms tick, so the decode runs at real time no matter how the bytes arrive.
    The readout shows it working exactly as designed: `frames=17548` teed
    against `decoded=7308` — the decoder deliberately behind the burst.
  - **It supplies samples, never timestamps.** PCM goes into the SAME ring the
    `MTAudioProcessingTap` writes to where it can attach, so nothing downstream
    can tell the two sources apart, and the engine's single show clock still
    stamps both tracks (§9.qq).

**The whole repair, in the order it actually happened**: a silent film hid the
defect for weeks (§9.jjjj); the cause was HLS vending no asset tracks, confirmed
against outside sources (§9.kkkk); a second reader over the source was rejected
for a second full download, and a whole-file rendition was built and measured
too slow (§9.llll, §9.mmmm); the tee out of the segment route cost nothing
because those bytes were already being fetched (§9.nnnn); and the bytes were
proved to be the film's audio BEFORE a decoder was built on them (§9.oooo).
Four designs, three of them wrong, and every one of them was eliminated by a
measurement rather than by argument.

**Still open**: the decoder starts where playback has reached and runs at its own
rate, so long-run drift against the picture is unmeasured — the Android port
needed an explicit correction for exactly this (§9.iii), and a feature-length
soak is the test. And every performance figure in this feature still comes from
a 3rd-generation Apple TV; the 2nd-gen Fireplace unit, the hardware floor, is
now available and has never run any of it.

### §9.oooo The teed bytes ARE the film's audio — measured before a decoder was built on them (2026-09-18)

The tee delivers compressed AAC and the mixer wants PCM, so a decoder sits
between them. Before building it, the cheaper question: **are these the right
bytes at all?** A decoder fed the wrong frames fails in ways that look like
decoder bugs, and this repair has already had two designs rejected.

So the sink wrote the teed frames as ADTS and the file was pulled off the Apple
TV and handed to ffmpeg — an instrument with no stake in our answer:

    codec_name=aac  sample_rate=44100  channels=2  duration=286.4 s
    mean_volume: -17.9 dB     max_volume: 0.0 dB

**Real sound**, against the **-91.0 dB** the television currently broadcasts.
12,282 frames, 3.5 MB, decoding cleanly.

**The comparison, stated exactly.** The source over the same 286-second span
reads **-13.6 dB mean / 0.0 dB max**. Peaks match; means differ by 4.3 dB — and
that is expected, not a defect: the tee begins wherever playback had reached
when the Studio started, so the two windows cover different parts of the film.
Saying "it matches the source" would have been the easy sentence and the wrong
one; what is proved is that the bytes carry the film's audio, not that they
carry the same 286 seconds.

**Two faults found on the way, both mine, both in the instrument:**

  - The first sink took one concatenated blob and split it evenly by frame
    count. **AAC frames are variable-size**, so that divides exactly almost
    never and the dump would have been empty — a silent instrument reporting
    on a silent defect. The bridge now delivers one `Data` per frame, which the
    decoder needs anyway: an AAC packet is only decodable whole.
  - The ADTS profile field is AOT-1, so AAC-LC is `1`; writing `0` labels the
    stream Main, and ffprobe read the dump back as `aac (Main)`. ffmpeg decodes
    either, so the mislabel never showed in a number and was wrong in the file
    regardless. Corrected.

What remains is now genuinely only decode-and-schedule: AAC frames to PCM,
released against the show clock from the time-indexed buffer §9.nnnn established
is required, into the mixer. The bytes are no longer in question.

### §9.nnnn The tee RUNS — and it is paced by BUFFERING, not by playback (2026-09-18)

§9.mmmm's design, built and measured on an Apple TV. `FilmAudioBridge` is
attached when the tap fails and the film has sound, and `serveHLS`'s segment
route hands over the audio sample bytes it has already fetched:

    AWAUDIO    filmHasAudio=false playedTracks=0 sourceHasAudio=true path=m3u8
    AWAUDIOTEE frames=338    bytes=94232
    AWAUDIOTEE frames=2719   bytes=757760
    AWAUDIOTEE frames=4689   bytes=1306701
    AWAUDIOTEE frames=9153   bytes=2550510
    AWAUDIOTEE frames=16296  bytes=4540677
    AWAUDIOTEE frames=16296  ... (unchanged for the next four samples)

**It works, at zero extra network cost**, and the counters read zero with no
sink attached, which is the control.

**AND IT CORRECTS §9.mmmm.** That entry said the audio would arrive "in playback
order, paced by playback, because it IS the audio being played". The first half
is true. **The second half is wrong**, and the measurement says so plainly:
16,296 AAC frames is 16,296 × 1024 / 44,100 ≈ **378 seconds of audio**, and it
arrived in about ninety. Then the counter sat still for a minute. The player
fetches segments in BURSTS far ahead of the playhead and stops when its buffer
is full, so the tee is paced by BUFFERING, not by playback.

The consequence matters more than the correction: a consumer that fed the mixer
as bytes arrived would push six minutes of sound into a live show in ninety
seconds and then starve for a minute. That is the §9.qq failure shape — two
clocks, one of them accidental — and it would have been very hard to see once
decoded audio was involved, because everything would have looked busy.

**So the bridge must be a time-indexed buffer, not a pipe**, and it now carries
the audio track's `firstSample` index with every delivery. That makes each
fragment addressable by FILM time, so the decoder can hold frames and release
what the show clock asks for. The engine keeps the clock: the tee supplies
position, never timestamps.

This is the third design and the first that measures well, and it was the
measurement — not the reasoning — that found the flaw in it. The reasoning had
already convinced itself.

### §9.mmmm The whole-file build is the wrong SHAPE — the server already holds the audio it plays (2026-09-18)

The parallelised rendition was run on the Apple TV. It **started and did not
finish** in 250 seconds:

    AWAUDIOFILE starting key=117d8062b85e3345
    (no completion line)

That distinction only exists because §9.llll added a start marker — before it, a
hang and a probe that never ran produced the identical evidence: nothing. The
marker paid for itself on its first run.

**Why it is slow is structural, not a tuning problem.** An interleaved mp4 stores
~2 s of audio (~22 kB at 89 kb/s) between ~2 s of video (~900 kB at 3.7 Mb/s),
so consecutive audio runs sit ~920 kB apart. The merge threshold is 256 kB, so
they cannot coalesce — and raising it far enough to bridge them pulls the video
in between, which is the entire film. **The request COUNT is irreducible: one
per fragment, ~2,200 for a feature.** Concurrency helps and cannot fix it, and
leaning harder on it runs into this project's own finding that archive.org
rate-limits an IP on main-host storms (`creation_studio_connection_discipline`).

**And the shape is wrong even if it were fast.** Building a whole film's audio
before going live delays the broadcast by minutes. A host presses Go live and
waits. Nothing about the feature wants that.

**The right answer was already in the building.** `serveHLS`'s `.segment(i)`
route fetches the audio sample bytes for every fragment — it has to, to mux the
fragment the player is about to consume. So while the film plays, this app is
ALREADY downloading exactly the audio the Studio needs, at exactly the moment it
is needed, through the same pinned session with Decision 031/034's failover.
The Studio does not need to fetch the audio. It needs to be handed what the
server already has.

That gives, for free, the property the whole-file design would have had to
engineer: the audio arrives in playback order, paced by playback, because it IS
the audio being played. It also removes the second download entirely — the cost
of the repair becomes zero extra network.

**What it must still get right** is the clock, which is where Android went wrong
twice (§9.qq): the segment route yields SAMPLES, and the engine already has one
show clock that stamps both tracks. The tee supplies bytes and never timestamps.

Two designs were built and measured before this one — a second reader over the
source (rejected on a second full download), and the whole-file rendition
(measured too slow, and wrong-shaped besides). Both are recorded rather than
deleted, because the reason each failed is what points at this one.

### §9.llll The audio-only rendition, built — and a probe that took the diagnostics down with it (2026-09-18)

§9.kkkk's design, implemented: `LocalMediaServer.writeAudioOnlyFile(forKey:to:)`
filters the parsed `Movie` to its `"soun"` track and runs the EXISTING
`initSegment` / `plan` / `fragment` path over it. No new muxing code — the
fragmenter already models every track by handler because it must, to interleave
them — and only the audio sample ranges are ever fetched.

**The first version did not finish, and the way it failed is the lesson.** It
issued one ranged GET per fragment, in order: a 74-minute film at 2-second
fragments is ~2,200 sequential round trips. Worse, the probe calling it runs
BEFORE the rest of `runStudio`'s diagnostics, so a blocking build took them down
too — the log came back with only `[AWCAP]` caption lines and **no Studio
markers at all**. That absence is what identified the blocking call: a probe
that hangs looks exactly like a probe that never ran, and the only thing
separating them was noticing that a line logged on every previous run had gone.

**Merging across fragments is not available**, which is worth stating so the
next person does not try it: audio samples are interleaved with video chunks, so
a gap threshold wide enough to bridge two audio runs pulls the film with it. The
request COUNT is the cost, not the byte count — so the round trips now overlap
in batches of eight instead of shrinking.

**And Swift 6 forced the right shape.** Passing the `Movie` into the task group
was rejected as a sending-closure data race. The fix — only byte ranges and
`Data` cross the boundary, muxing stays serial — is better than what was there:
fragments can no longer be written in completion order rather than sequence,
which is a corruption this file would not have detected until something tried to
play it.

**NOT VERIFIED.** It compiles for tvOS; it has not yet produced a file on the
device, and the claim that matters — that the result is a real asset which vends
an audio track — is untested. The measurement is already defined: Blood and Sand
(1922) reads **−15.1 dB** at source, so the rendition must too, and then the
wire must, which is the pass/fail for the whole repair.

### §9.kkkk The HLS audio limitation is confirmed from outside, and the fix has to come from our own remuxer (2026-09-18)

§9.jjjj measured the cause on the device. Before building a fix, the same claim
asked of the world, because an architecture change rests on it
(`feedback_research_before_fixes`):

> MTAudioProcessingTap does not work with HTTP Live Streaming … the remote
> AVAsset always has zero tracks.

Independent of our measurement and identical to it. It is a longstanding
AVFoundation limitation with **no official solution**, and the only workaround
practitioners report is recording the speakers with the microphone — useless on
a television, and a thing this project would refuse anyway (§3.3 on screen
capture is the same principle).

One detail from that research explains the exact shape of our defect: **the
video counterpart, `AVPlayerItemVideoOutput`, DOES work with HLS.** So on tvOS
the picture arrives and the sound does not, from one asset, which is precisely
what the recording showed.

**Options considered, and why the obvious ones fail:**

  - *Play a progressive MP4 on tvOS instead.* Decision 106 exists because tvOS 27
    loses the audio of a non-fragmented mp4 **locally** — the viewer in the room
    would hear nothing. Trading the broadcast's audio for the room's is not a
    fix.
  - *A second `AVAssetReader` on the source URL.* Works, and costs a second full
    download of a feature film to obtain a ~90 kb/s audio track, because range
    requests over an interleaved mp4 pull video bytes too.
  - *`AVSampleBufferRenderSynchronizer` driving playback ourselves.* The
    architecturally correct answer for a studio — both tracks from one read —
    and a rewrite of the playback path that Decisions 021, 054, 067 and 106 all
    sit on. Not proportionate to one missing track.

**The fix follows from something this project already owns.** `MP4Fragmenter`
parses the source's `moov` and models every track with its handler (`"vide"` /
`"soun"`) and sample tables — it already knows exactly where the audio samples
are, because it must, to interleave them into fragments. So the audio can be
served as its own small rendition by `LocalMediaServer`, and read by an
`AVAssetReader` over a real asset that **does** vend tracks, at the cost of the
audio bitrate alone rather than the film's.

That is the next piece of work, and it is written down before it is built so the
reasoning can be checked rather than inferred from a diff. What it must get
right is the part Android got wrong twice (§9.qq): the reader and the player are
two clocks, and the engine already has ONE show clock that stamps both tracks —
the reader supplies samples, never timestamps.

### §9.jjjj tvOS broadcasts have NO AUDIO — HLS vends no tracks, and a silent film hid it for weeks (2026-09-18)

The owner asked for an audio test. It found that **every tvOS broadcast has gone
out silent**, and the reason every earlier check missed it.

**The measurement.** Blood and Sand (1922), a scored silent whose source reads
**mean −15.1 dB**, broadcast from the Apple TV to a local mediamtx. The
recording, read back:

    mean_volume: -91.0 dB      max_volume: -91.0 dB
    astats:  Peak level -inf   RMS level -inf

`max == mean` is a single repeated sample: digital silence. The AAC track is
present with the right rate and channels, carrying nothing.

**Why nobody saw it.** Three instruments agreed and all three were blind:

  - the readout says `audio: Playback/MoviePlayback active`, which describes the
    audio SESSION, not the content;
  - the server reports `recording 2 tracks (H264, MPEG-4 Audio)`, which is true
    of a silent track;
  - **every tvOS test used a silent film.** Crossroads (1928), the title used
    for the go-live work, is itself digitally silent at the source (−90.3 dB),
    so an empty audio track looked exactly correct.

**The cause, measured on the device rather than reasoned:**

    AWAUDIO filmHasAudio=false playedTracks=0 sourceHasAudio=true
            scheme=http path=m3u8

`FilmAudioTap.attach` needs an `AVAssetTrack` to hang an `AVMutableAudioMix` on.
Decision 106 plays the film on tvOS as **HLS** from the LocalMediaServer (tvOS 27
loses the audio of a non-fragmented mp4), and **an HLS asset vends no asset
tracks** — `loadTracks(withMediaType: .audio)` returns an empty array. So the
tap declines, and `attach` returns `false`.

**And `false` meant two opposite things.** The call site's own comment says "a
film with no audio track is a REAL case in this catalog (silent cinema), so a
false return is recorded, never treated as a failure" — which is correct for a
silent film and catastrophic for a film whose audio we simply cannot reach. One
boolean carried both, so the second was invisible. macOS and iOS play a
progressive MP4 through the resilient loader, whose asset DOES vend tracks,
which is why their audio was measured working and the television's never was.

**Fixed in this change: the two are separated.** `filmAudioProblem(sourceHasAudio:)`
asks the SOURCE whether the film has sound at all, and only then calls the tap's
refusal a problem. The readout carries it above the dropped-frames note, because
an audience that hears nothing is worse off than one seeing a few dropped
frames. A genuinely silent film still says nothing, which is right.

**NOT fixed yet: the audio itself.** Separating the cases makes the failure
visible; it does not put sound on the wire. The options are a second reader over
the source's audio track timed to the player's clock (the muted-scout shape of
Decision 071), or a playback path on tvOS that vends tracks — and the second
runs straight into Decision 106, which exists because the alternative has no
audio at all locally. That is the next piece of work.

### §9.iiii THE FIRST REAL BROADCAST — an Apple TV went live on Twitch, and the uplink is the next problem (2026-09-18)

The owner: *"These are testing accounts. Feel free to broadcast as you see fit
for testing."* So the thing this feature was built for finally happened.

**Signed in first.** A tvOS door (`AW_TWITCH_SIGNIN=1`) runs the same two calls
the sign-in row makes and logs only what a host would be shown — the
verification URI and the user code, never the device code or the token (§5).
The owner authorised it, and the television reported `AWTWITCH signed in`. Read
back afterwards:

    AWYT twitch account=licbhwilkoff
    AWYT twitch readiness=READY

**Then it went live.** The door learned to commit to a real platform, behind the
SAME three gates the button is behind — configured, signed in, and readiness
`.ready` — so it cannot reach a channel the product itself would refuse.

Evidence from Twitch, not from us: the channel page showed a **LIVE badge on
licbhwilkoff** while the show ran, and **Offline** once it stopped. The
television's own readout during it:

    ● LIVE  4,340 kbps
    audio: Playback/MoviePlayback active
    encoder: hardware
    ⚠ Dropping frames — the connection is struggling

**And that warning is the finding.** §6.4's back-pressure rule fired within the
first two minutes, on BOTH broadcasts (4,340 and 4,208 kbps). Every previous
measurement of this publisher was against a mediamtx on the LAN, which never had
to cross the internet — so the first contact with a real ingest immediately
found what a local server structurally could not. The Studio asks for 1080p30 at
6 Mbps; this house's uplink to Twitch does not hold ~4.2 Mbps of it. That is
either the uplink or Twitch's ingest, it is not yet known which, and the next
measurement is to find out rather than to guess — the honest options are a lower
target bitrate, 720p, or an adaptive step that §5's readout already has the
vocabulary for.

**The provenance line is now TRANSIENT**, on the owner's note: *"While I like the
lower third overlay, the Public Domain status is not something anyone would
actually want to live on the top of their stream."* Right, and it is their
stream's face. §2's argument is that a viewer can LEARN where the film came
from, which twenty seconds of lower third does in the ordinary broadcast idiom;
a badge that never leaves is branding. Title and subtitle stay; the fuller
statement still travels in the platform's description.

**NOT VERIFIED, and said plainly**: the twenty-second clear is built and builds,
and the only capture taken during the verification run was at 95 s — by which
time the line had already gone. That is consistent with it working and is not
evidence of it, because the line was never seen PRESENT and then ABSENT in one
run. The late capture failed. It needs one more broadcast with captures either
side of the mark.

### §9.hhhh The token was on the WRONG CHANNEL — nineteen of them, and the app would have broadcast to the default (2026-09-18)

The owner, reading §9.zzz's report that live streaming was not enabled:
*"Live streaming is already enabled on the youtube account and you should be
able to drive the other two items on chrome. Why do you need my intervention to
run the tests?"*

Both halves landed, and the first one was a real defect.

**They were right, and so was the probe.** Driven in Chrome: `youtube.com/features`
redirects to Studio for channel `UCGNBrxdpR4ujnMWO4_OQgyA` — **"Learning is
Change", 865 subscribers**, full of public-domain films. The token the app holds
resolves to `UCtPDkIGiSWSb5N8hNdaPizg` — **"Ben Wilkoff", no subscribers**.
Different channels. Live streaming is enabled on the one the owner uses and is
not enabled on the one OAuth landed on, so both statements were true at once and
the message could not tell them apart.

**And it is worse than two.** The account's own channel list shows **NINETEEN
channels**, including an **"Archive Watch"** channel (@ArchiveWatchApp) which is
almost certainly the intended destination. `channels.list?mine=true` returns the
account's DEFAULT, so with nineteen candidates the app was not merely imprecise —
**a broadcast would have gone out on the wrong channel**, under the host's own
name, and nothing on the screen would have contradicted it.

The only reason this was caught is §9.yyy's closing change: the sign-in row
naming the ACCOUNT rather than the fact of one. That line was added because
"signed in" is a storage fact and a host deserves to know whose channel they are
about to appear on. It has now paid for itself once.

**What can be fixed in the app, and what cannot.** Google offers its channel
chooser at CONSENT time; there is no API by which an app switches a host's
channel afterwards (`managedByMe` is a content-owner facility, not this). So the
honest action is to name what the token got and say how to change it, which the
blocked message now does:

    Live streaming is not enabled on “Ben Wilkoff”. If you meant a different
    channel, sign out and sign in again to choose it — this account can own
    several. Otherwise turn it on at youtube.com/features.

**On the second half of the owner's question, which was fair.** Checking a
setting and reading a channel list were never theirs to do; those were mine, and
doing them found this. Two of the three items had been parked as "owner-gated"
when only one of them was. The one that genuinely is: publishing the OAuth
consent screen asks Google for a **passkey re-authentication** of
`ben.wilkoff@minerva.edu` — a biometric identity challenge on the owner's own
device — and completing an authentication challenge on someone's behalf is not
something to do whatever the authorisation.

**A related fact worth recording**: the Cloud project sits under a
`@minerva.edu` account while the YouTube channels are personal. That is a
plausible reason an organisation policy is demanding the passkey, and it is also
worth confirming that the OAuth client and the channel are reachable from one
another before the first real broadcast.

**And an instrument note.** The first attempt at this fix failed its own
assertion (the message had been shortened in §9.zzz, so the anchor did not
match) — and the build in the same command still said `BUILD SUCCEEDED`, because
it had compiled unchanged code. A green build proves the tree compiles, never
that an edit landed.

### §9.gggg THE JOIN RUNS: the tvOS go-live chain reaches a real RTMP server, end to end (2026-09-18)

Every piece of the television's broadcast has been measured separately — the
surface (§9.vvv), the sign-in (§9.yyy), the readiness gate (§9.zzz), the
publisher against a bench server (§9, Phase 0), the encoder (§9.vv). **The join
had never run.** Everything past the Go live button — `request()` → `onGoLive`
→ `StudioGoLive.destination` → `StudioEngine.start(destination:)` →
`RTMPPublisher` → a server — was compiled and unrun on this platform, because
reaching it needed a platform account.

It does not. `GoLivePlatform.custom` resolves a destination with **no OAuth at
all**, which iOS has shipped since §8.9 and tvOS did not offer because a
television cannot type a URL. Under DEBUG with `AW_STUDIO_DEST` set, the surface
now offers "Bench server (debug)" beside the real platforms, and the request it
builds goes through the same resolver and the same publisher. What it skips is
the platform's key exchange — the only part that needs an account.

**The server's own account of it**, mediamtx on the Mac, publisher on the Apple
TV:

    [path awtv/bench1] [recorder] recording 2 tracks (H264, MPEG-4 Audio)
    [RTMP] [conn 10.0.0.223:60472] is publishing to path 'awtv/bench1'

`10.0.0.223` is the television, not this machine. And read back off the file
rather than trusted from the log:

    h264  1920x1080  30/1        aac  44100 Hz  stereo
    duration 143.7 s             6 I-frames in the first 12 s (one per 2.00 s)

**Full 1080p30, both tracks, keyframes at the documented 2-second cadence, from
an Apple TV, through the product's own commit path.** The recording was deleted
once it had been read — it is 72 MB of the owner's television output and there
is no reason to keep it.

**On driving the surface, and why the door exists.** The intention was to press
Go live over the remote. Four `up` presses moved no visible focus ring, and a
focus position that cannot be seen cannot be driven reliably — so the door
calls the same `request()` and the same `onGoLive` the button calls, and the
request builder was extracted to ONE definition so the two cannot diverge. It
is honest about its limit: **it proves the chain, not the button.** The button
itself is verified by capture — rendered, correctly disabled when the channel is
blocked, correctly enabled for the bench. The door refuses to fire at anything
but the bench, so it can never put a broadcast on a person's channel.

**What is left is only the key exchange.** On tvOS the chain from a host's press
to a server carrying their show is now measured; the untested inch is
`YouTubeLive.prepare` / `TwitchLive.prepare` returning a real address and key,
which needs an account and a press the owner makes.

### §9.ffff The readiness gate was on ONE surface — and the recurrence is now checked by a script rather than by eye (2026-09-18)

§9.zzz gave the go-live surface a read-only readiness question, so a host whose
channel cannot broadcast learns it before pressing anything rather than inside
four write calls whose first one creates an object on their channel. It was
wired into `GoLiveTV` — tvOS — and nowhere else. **iOS and macOS could both
still press Go Live into a channel YouTube refuses.** Found by asking, this
tick, unprompted; both are fixed here.

That is the FOURTH time this exact class has appeared in this feature:

    §9.ooo   the `configurationProblem == nil` proxy, on tvOS
    §9.ttt   the SAME proxy, still in macOS and iOS — found one surface a tick
    §9.eeee  the Android go-live confirmation wired into the PHONE Detail while
             the television's Detail went on arming straight through
    §9.ffff  this one

**Reading the diff cannot catch it.** Each fix is correct where it is applied;
what is wrong is somewhere else, and nothing in the change points at the place.
Every previous instance was caught by eye, late, and twice only because a
screenshot happened to show the unfixed surface.

So `tools/test_studio_surface_parity.sh` (§8.12) asks all three Apple surfaces
the same questions at once — do they consult `readiness(for:)`, do they gate the
commit on the answer, do they gate on a TOKEN rather than on configuration — and
fails naming the surface that is missing what its siblings have. It carries its
own control: a pattern no surface contains must be reported absent, or the greps
prove only that grep runs.

It is a SOURCE check and it is honest about that. It cannot prove a screen
behaves; it proves no surface was forgotten, which is the failure that actually
keeps happening. The behaviour is proved on the glass once per platform — tvOS
already is (§9.zzz), and these two are not yet.

**What is NOT verified, said plainly**: the blocked branch on iOS and macOS is
compile-verified and structurally identical to tvOS's, sharing
`StudioPlatformAuth.readiness(for:)`, but it has not been seen on a screen. It
cannot be until a host signs in on one of those devices — tokens are
`ThisDeviceOnly` and unsynchronised, so the Apple TV's sign-in does not reach
the phone or the Mac. That is a real gap and it is written here rather than
implied by a green suite.

### §9.eeee Android gets the SCREEN — and the rule came before the view (2026-09-18)

§9.dddd left Android with a measured auth chain, a real destination path and no
way for a host to reach either. `ANDROID-DESIGN` §9 had rules 9.1–9.10 and
nothing about signing in, so the rule was written first (§9.11) and the view
built against it, which is this repo's own discipline rather than a formality:
the rule is what stopped the screen becoming a port of tvOS's two-column layout
into an idiom where it does not belong.

**§9.11, in one line**: a QR code AND a code, shown together, token lands on
this device. Same conclusion the owner reached for tvOS, different reason —
Apple can lean on `ASWebAuthenticationSession` handing the session to a nearby
iPhone (§9.yyy) and **Android has no equivalent hand-off**, so the device flow
is the road rather than the fallback.

**What was reused rather than rebuilt**: `qrBitmap` already existed in
`TvShare.kt` (zxing, for playlist sharing) and became `internal`. A second QR
encoder in the same module would have been the thing `reuse_before_rebuilding`
exists to prevent.

**AND THE ENTRY POINT EXISTED TWICE.** `DetailScreen.kt` (phone, an overflow
row) and `TvDetailScreen.kt` (television, an action button) each armed the
Studio and pushed straight to the player. The first patch went into the phone
screen — and the device under test was the TELEVISION, which still had the old
behaviour. Caught because the capture showed a "Watch Together" BUTTON where the
patched code had an overflow menu item. This is §9.ttt's shape exactly (the same
proxy in three Apple surfaces, found one at a time), and the right move is the
one that eventually worked there: grep for every entry point before editing any
of them. Both are wired in this change.

**On the Google TV dongle**, Crossroads (1928): the confirmation carries the
film, "Sign in to Twitch", §3.4a's warning in full, and **Go live disabled**
with "Sign in above to go live. Nothing is broadcast until you press Go live."
The whole dialog fits without scrolling.

**Two instrument failures worth recording, neither fatal:**

  - `adb` crashed mid-script (`mutex lock failed`, daemon gone) and the
    screenshot came back **0 bytes**. The script printed the byte count, so it
    read as an obvious failure rather than a blank screen — the `atv_shot.sh`
    rule (refuse a capture that produced no file) paying off on a different
    platform.
  - By the time the connection was restored the dongle had idled into its
    ambient screensaver, so the recovered capture was a photograph of a
    mountain. A screenshot proves what was on the screen, never that the app
    put it there — `dumpsys window mCurrentFocus` is the check that the app is
    actually foreground, and it is now part of the run.

**What Android still lacks**: the go-live path beyond this dialog has never run
against Twitch, because nobody has signed in. The chain, the destination
resolution and the surface are each measured; the join is not, and it needs a
host with an account.

### §9.dddd Android resolves a REAL destination, and its sign-in reaches Twitch from a television (2026-09-18)

§9.cccc gave Android an auth layer. It still could not broadcast: `StudioController`
passed `destination = benchDest` and nothing else, so with no bench address the
engine composited, encoded and reported healthy while reaching nobody — §9.ccc's
shape, on the last platform still carrying it.

`TwitchLive.kt` and `StudioGoLive.kt` close it. The Swift rules port with them:
the title is set BEFORE the key is fetched (a show that opens under the previous
show's title has already misled whoever joined, where a failed key fetch costs
nothing), the ingest list is public and its first entry is Twitch's own default,
`/{stream_key}` is STRIPPED rather than substituted, and `rtmp://` is upgraded to
`rtmps://` because 443 crosses more networks than 1935. `TwitchLive.kt` contains
no logging at all, including on its error paths, where a key-bearing URL is the
natural thing to include and is exactly what §5 forbids.

**RESOLVE THEN START, off the main thread.** The engine takes its destination at
`start()` and the render loop captures it, so there is no way to adopt one later
without making the destination mutable under a running loop; resolution happens
first and the engine starts with the answer. And it happens on `Dispatchers.IO`,
because `startIfArmed` runs on Compose's main dispatcher — Decision 130's Android
lesson exactly, where a reconnect supervisor passed a JVM test and threw
`NetworkOnMainThreadException` on every attempt in the app.

**On the Google TV dongle, with the real client id:**

    AWTWITCH: open https://www.twitch.tv/activate?device-code=MXLSCMQY
              and enter MXLSCMQY

The whole Android chain — gradle property → `BuildConfig` → `StudioPlatformAuth.begin()`
→ Twitch's live device endpoint → a real user code — proved on hardware, from a
television, with nothing owner-gated. It also confirms independently what Apple
measured: Twitch's `verification_uri` already carries the user code, so a QR of
it reaches a pre-filled page.

**TWO INSTRUMENT FAULTS ON THE WAY, both mine, both the familiar family:**

  - `am start -n app.archivewatch.android/.MainActivity` → *"Activity class does
    not exist"*. The Kotlin package is `app.archivewatch.android`; the
    applicationId is `com.archivewatch.app` (`.debug` for debug builds). **And
    the force-stop in the same script targeted that same non-existent package
    and printed "app is gone"** — a teardown reporting the all-clear about a
    package that was never running, which is the third false all-clear from a
    cleanup instrument in this session (§9.vvv's `atv_teardown.sh`, twice).
    The check now reads `pidof` for the REAL package and says STILL RUNNING
    when it finds one.
  - `logcat -s AWTWITCH:*` unquoted is expanded by zsh, which failed with "no
    matches found" and printed nothing — indistinguishable from a door that did
    not fire. The log line was there the whole time.

Neither cost more than minutes, and both would have been silent successes.

**What Android still lacks**: a screen. The auth chain and the destination path
are real and measured; there is no Compose surface yet that shows a host the QR
and the code, which is the next piece. The debug door exists precisely so the
chain could be proved before the screen, rather than the screen being written
against an unproven chain.

### §9.cccc Android gets a sign-in at last — Twitch only, because Twitch is the half that needs nobody (2026-09-18)

PARITY has said for weeks that Android "has no OAuth or platform client at all
(zero Kotlin references to googleapis.com / api.twitch.tv)". The engine,
encoder, GLES composite, RTMP publisher, rights gate and overlay were all built
and measured on real hardware; the thing that turns a token into a stream key
existed nowhere. Apple's remaining work is entirely owner-gated, so this is the
brief's own next step — *"then build out from there where possible."*

**Twitch only, deliberately.** Its Device Code Grant is a PUBLIC client with no
secret and no PKCE, and **the same client id Apple already uses works here** — a
Twitch client id is not device-specific. So Android's Twitch half needed no
registration, no owner step and no new credential of any kind.

**And the device flow is the RIGHT shape here rather than a concession.**
Android ships on phones and on televisions (Google TV, Fire TV), and a
television has no keyboard. Apple escapes that because tvOS hands the session to
a nearby iPhone (§9.yyy); Android has no equivalent hand-off, which is precisely
the case Decision 128 reserved a device flow for. What was written as Apple's
fallback is Android's main road.

**YouTube is deliberately ABSENT**, and that is the point rather than an
omission. Android cannot reuse Apple's Google client — an iOS-type client is
refused by TYPE, measured (§9.www) — and on a television it needs Google's
device grant with a client SECRET. Writing half of it would reproduce §9.ccc's
defect exactly: a capability declared somewhere no other platform could see it.
The file says so where the code would have gone.

**§6.1 on Android**: EncryptedSharedPreferences over an Android Keystore key,
which is the same promise as the Keychain made by the same kind of mechanism —
the key cannot leave the device. The manifest already carries
`android:allowBackup="false"`, so these preferences reach no Drive backup; that
was CHECKED rather than assumed, because "a restored file would be
undecryptable" is a different promise from "it is never copied". `save` uses
`commit()` and returns the result, for §9.rrr's reason: a one-time-use refresh
token whose write is dropped signs the host out at the next call.

**THE TEST FOUND SOMETHING BIGGER THAN ITS OWN SUBJECT.** Six JVM tests; two
failed, both of them faults in the instrument:

  - `org.json.JSONObject not mocked`. Android STUBS every method of its bundled
    `org.json` in JVM unit tests. `org.json` is this app's house style for
    network JSON — `OpenSubtitlesClient`, `PlaylistShare` and `ArchiveVersions`
    all use it — which means **none of that parsing has ever been unit-testable
    either**, and nobody would have found out until they wrote a test that
    needed it. `testImplementation("org.json:json")` puts the real one in.
  - Reading `errorStream ?: inputStream` before `responseCode` throws
    `IOException` on a 4xx, so the test failed on plumbing and said nothing
    about Twitch. `responseCode` first.

Both are the family this project keeps meeting: a red that is about the
instrument, not the subject. The rule holds in the cheap direction too — these
cost ten minutes because the tests were run rather than assumed.

What the tests assert: the poll discriminator by calling the PRODUCT's own
`pollOutcome` (Decision 119 — a check that restates the logic proves only that
it was copied twice), and the live endpoints' REFUSALS with no credential at
all (Decision 128), including the control that a bad token and a missing header
read differently under identical 401s.

Both flavours compile, including `amazon` at minSdk 23.

### §9.bbbb Twitch gets the same read-only readiness — and the probe must not touch the stream key (2026-09-18)

§9.zzz gave YouTube a readiness question asked with a READ, so a host learns
their channel cannot broadcast before pressing anything. Twitch now has the
same, and getting there required refusing the obvious implementation.

**The forbidden shortcut.** Twitch's readiness could be answered perfectly by
fetching the stream key: if the key comes back, the sign-in works. §5 forbids
it — "a key is never logged, never written to disk, never put in a URL this app
prints, and it does not outlive the session that fetched it" — and a readiness
probe is by definition not the session that spends it. A probe that fetches a
credential in order to check a credential has created the exposure it was
verifying.

So the check is `https://id.twitch.tv/oauth2/validate`, which returns the login,
the user id and the granted SCOPES and touches no key. It answers both questions
the surface has — whose channel, and can this sign-in do it — from one read.

**Scopes are checked against what a broadcast SPENDS, not against what we ask
for.** A token issued before a scope was added still validates; it simply cannot
do the thing. `twitchRequiredScopes` names `channel:read:stream_key` and
`channel:manage:broadcast` explicitly, so an old token is refused with a sentence
rather than failing at the fourth API call.

**Measured, with its control** (2026-09-18):

    bogus token   401 {"message":"invalid access token"}
    NO header     401 {"message":"missing authorization token"}

Both are HTTP 401. **The status discriminates nothing — the fourth endpoint in
this feature of which that is true**, after Twitch's device poll (§9.ppp),
Google's `authError` on the final URL (§9.nnn) and Google's device-code refusal
(§9.www). If those two messages read the same, the product could not tell a host
"sign in again" from a bug in its own request. Asserted in §8.9, and it needs no
credential: it asserts how REFUSALS read, which is exactly what Decision 128
means by proving the request shapes before the credentials exist.

**Both platforms now answer one question.** `StudioPlatformAuth.readiness(for:)`
and `accountName(for:)` dispatch per platform; `GoLiveTV` and `StudioSignInRow`
ask once and render once, rather than carrying a `platform == .youtube` test
each — the shape §9.ttt found repeated across three Apple surfaces.

Read off the Apple TV:

    AWYT youtube account=Ben Wilkoff
    AWYT youtube readiness=BLOCKED  Live streaming is not enabled on this channel…
    AWYT twitch  not-signed-in

— the signed-in platform names its account and reports its gate; the
signed-out one says so without erroring, which is the state the surface draws.

**What this leaves.** Twitch has neither of YouTube's two gates: no consent
screen to publish, no channel feature to enable. So the moment a host signs in to
Twitch, the go-live path is exercisable end to end for the first time — which is
the next real measurement this feature has, and the first one that puts a
broadcast on a person's account.

### §9.aaaa §6.1's Keychain promise was NOT kept on macOS — measured from inside the signed app, and fixed (2026-09-18)

§6.1 says tokens live in the Keychain under
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and are never synchronised.
§9.rrr found that unverifiable from outside the app and said so rather than
asserting it: a bare command-line harness is answered `-34018` by the
data-protection keychain, so any assertion it made would have measured its own
lack of entitlement. That refusal was correct, and it left the question open.

**Asked from inside the signed, sandboxed Mac app** (`AW_KEYCHAIN_PROBE=1`,
DEBUG only, writes under a probe account and deletes it):

    save() -> OSStatus 0
    round-trips: true
    readable from the file-based (legacy) keychain: true   accessible=<absent>
    readable from the data-protection keychain:     false
    §6.1 promise kept: NO

**The promise was not kept, and nothing anywhere said so.** `SecItemAdd`
returned `errSecSuccess`, the token round-tripped, every caller worked. macOS
routes a generic password to the FILE-BASED keychain unless
`kSecUseDataProtectionKeychain` is set, and that keychain has no concept of
`kSecAttrAccessible` — so the attribute was accepted by the API and then meant
nothing at all. A silent success is the worst shape a security promise can
have: there is no error to notice and no behaviour to observe.

**The fix** is `kSecUseDataProtectionKeychain: true` on every query — save, load
and clear. Set unconditionally rather than behind an `#if os(macOS)`: iOS and
tvOS already use that keychain, where the flag is a no-op, and one query shape
is easier to keep honest than two. `clear` additionally deletes the LEGACY copy
for one release, because a sign-out that leaves a token behind is worse than the
bug it is cleaning up after.

Re-measured with the same probe:

    readable from the file-based (legacy) keychain: true   accessible=cku
    readable from the data-protection keychain:     true   accessible=cku
    after deleting ONLY the data-protection item, a legacy copy survives: false
    kSecAttrAccessible reported: cku          (= AfterFirstUnlockThisDeviceOnly)
    kSecAttrSynchronizable reported: 0
    §6.1 promise kept: YES

**And the line that looked like a second defect was not one.** "Readable from
the legacy keychain: true" persisted after the fix, which would mean a duplicate
token sitting in the weaker store — exactly what §6.1 exists to prevent. Two
queries both returning something cannot tell one item from two, so the probe now
deletes the data-protection item ONLY and asks the legacy keychain again: nothing
survives. It is one item, and a flag-less query on macOS is answered from the
modern keychain. The check is kept in the probe, because "both saw it" will look
alarming again to whoever reads this next.

**The tvOS token survived**, which was the risk worth checking before shipping:
the Apple TV holds a real YouTube token written by the OLD query, and a changed
query that failed to find it would have silently signed the host out. Verified on
the glass — "YouTube — Ben Wilkoff" still reads back from the Apple TV after the
change.

### §9.zzz "Can this channel go live?" is a READ, asked before the button — and the answer is no (2026-09-18)

Going live on YouTube is four writes: `liveStreams.insert`, `liveBroadcasts.insert`,
bind, transition. The first creates a real object on the host's channel. So the
question "will this work?" must never be answered by trying it — and until now
that was the only way the app could answer it.

`StudioPlatformAuth.youTubeLiveReadiness()` asks with a read.
`liveBroadcasts.list?mine=true` exercises the same permission surface and
creates nothing; YouTube refuses it with `liveStreamingNotEnabled` when the
channel has never been enabled for live.

**Asked from the Apple TV with the owner's own token, the answer is BLOCKED:**

    AWYT channel=Ben Wilkoff [UCtPDkIGiSWSb5N8hNdaPizg]
    AWYT readiness=BLOCKED  live streaming is not enabled on this channel

This is exactly the trap SCRATCHPAD 7a2 flagged as a risk months of ticks ago
and never tested: **enabling live streaming for the first time can take up to 24
hours to activate.** Found at go-live time it costs the evening. Found on the
sign-in screen it costs a day's notice.

**The status is not the answer, again.** A 403 here is three different problems
— the channel was never enabled, the sign-in lacks the scope, or the token is
dead — and each needs a different sentence from the host. `error.errors[0].reason`
separates them. That is the third endpoint in this feature where the HTTP status
carries no information (Twitch's blanket 400, §9.ppp; Google's `authError` on the
final URL, §9.nnn; and now this), which has stopped being a coincidence and is
written into the doc as an expectation.

**On the surface.** `GoLiveTV` asks once the host is signed in and greys Go live
with the reason when the answer is bad. A nil answer — not asked yet, or the
call failed — deliberately does NOT block the button: a slow API must not gate a
control, and a host who presses through an unknown meets the real error anyway.
Only a KNOWN-bad answer stops them, and it stops them with something to do about
it rather than a reason code.

This is the §10.2b principle one layer in. That rule stopped a host reaching a
production mode that could never find an audience; this stops one reaching a Go
live that YouTube was always going to refuse.

**Three layout attempts, each judged by a capture.** The reason went BELOW the
buttons first and its last line fell off the bottom of the television; moved
ABOVE them, it pushed the buttons off instead; it now sits in the LEFT column,
which is what Rule 8.8b's two-column split is for — reading matter left,
controls right — and everything fits. Worth recording because the failure mode
repeats: a ten-foot column's fit cannot be reasoned about from the source, and
the screenshot is the only instrument that answers it. The sentence was also
cut from four lines to two on the way, with the long form kept in SCRATCHPAD
7a2 where length costs nothing.

### §9.yyy tvOS signs in to YouTube by handing the session to a PHONE — and two ticks were spent designing around a limitation that did not exist (2026-09-18)

The owner, after reading two ticks of "blocked on the owner": *"You seem to have
given up on streaming to YouTube. That isn't good enough. You should absolutely
be able to login to YouTube on your phone and approve a channel to stream to.
You just have to figure out the right path to do so."*

They were right, and the path already existed in the code we had shipped.

**What tvOS actually presents.** `ASWebAuthenticationSession` on an Apple TV
does not render a web page and does not ask for a password. It presents Apple's
own sheet:

    Sign in to ArchiveWatch
    [ Sign in with Apple Device ]
    You will get a notification on a nearby iPhone or iPad.

The television HANDS THE SESSION TO A PHONE. The owner signed in to Google and
approved the channel on their iPhone; the go-live surface on the TV went to
"Signed in to YouTube" and Go live became enabled. Verified beyond the screen
by a read-only `channels.list` from the Apple TV itself:

    AWYT channel=Ben Wilkoff [UCtPDkIGiSWSb5N8hNdaPizg]

— a real token, reaching the host's own channel. **No second Google client, no
client secret, no device flow.** The same `YOUTUBE_CLIENT_ID` the iPhone uses.

**This is what §9.uuu's SDK reading was telling us, and the conclusion drawn
from it was wrong.** The annotations were read correctly —
`presentationContextProvider`, `prefersEphemeralWebBrowserSession` and `cancel`
are `API_UNAVAILABLE(tvos)` — and §9.uuu even called the absences "the design".
Then §9.www reasoned: no context provider means the television presents it
itself, which means typing a Google password with a d-pad, which means we need
Google's device flow, which means a second client with a secret, which means an
owner step. Every link followed from the one before; the first link was false.
The absences are there because **the session is not on this device at all**, so
there is nothing to present it in and nothing to cancel.

**The cost.** Two ticks building `GoogleDeviceAuth`, a second credential path, a
platform-conditional client selector, a harness case — and a SCRATCHPAD owner
item telling the owner to go and register something they never needed. It was
withdrawn the same day (7a3). The code is kept, correctly scoped: it is selected
only when a TV client is configured, for a platform with no equivalent hand-off
(Android TV, later). What is NOT kept is the claim that Apple needed it.

**The rule.** §9.www ends with "on this feature, assume the discriminator is not
where the protocol says it is, and go and look." The same sentence applies one
level up and was not applied: **when the question is what a platform API DOES on
a device, put it on the device and look.** It cost one build and ninety seconds
to answer, against two ticks of designing around it. The specific trap is that
the false step was an INFERENCE sitting between two correct measurements — the
SDK annotations before it and the device-endpoint refusal after it were both
real, which is exactly what made the middle feel measured when it was not.

**A REAL gate the owner's screenshot exposed, which no amount of this would have
found.** Signing in, they had to click through *"Google hasn't verified this app
— You've been given access to an app that's currently being tested."* The
consent screen is in **Testing**, and Google's own documentation says a project
in that state is "issued a refresh token expiring in 7 days". So today the host
is signed out of YouTube WEEKLY, on every device, and nobody who is not a listed
test user can sign in at all. Publishing the consent screen and passing OAuth
verification for the sensitive `…/auth/youtube` scope (homepage, privacy-policy
URL — both already exist — domain verification, demo video; NOT the third-party
security assessment, which is restricted-scope only) is a **prerequisite for
shipping the YouTube half**, not a polish item. Twitch has no equivalent gate.

**And one thing the screen was not saying.** It read "Signed in to YouTube",
which is a Keychain fact: a token was stored. It does not say whose channel the
broadcast reaches, and one Google login can own several through brand accounts.
The row now names the destination — "YouTube — Ben Wilkoff" — from the same
read-only call, failing quietly to the old wording rather than refusing to draw.

### §9.xxx CORRECTION to §9.vvv: the pause DID hold, and the instrument that said otherwise was a byte comparison (2026-09-18)

§9.vvv reported that the tvOS go-live confirmation could not pause the film,
that the cause was not in `DetailView`, `AVPlayerContainer` or `TVAudioSession`,
and that the pause had been removed rather than shipped half-working. **The
first clause is wrong and the code was deleted on bad evidence.**

The evidence was this: two screenshots fifteen seconds apart had different
bytes. That was read as "the film advanced". It is not what it means.

Asked of the player itself instead — a KVO probe on `timeControlStatus`, with
every `play()` call site in the tvOS path marked so the log would name whichever
fired:

    AWPLAY site=containerOnAppear
    AWPLAY site=readyToPlay
    AWPAUSE calling pause() now
    AWPAUSE status=0 waiting=-          <- .paused

and then nothing, for the remaining two minutes. One transition, to paused, and
no resume. Re-run with captures alongside the probe, three of them fifteen
seconds apart: **byte-identical, same md5.**

**What actually differed in the original pair**: the first capture's background
is pure black and the second's is the film's paused still. The cover had just
been presented and the paused frame behind it had not been composited yet. Same
paused film, different compositor state — a difference of about a megabyte of
PNG, which is why the size gap looked so convincing.

So the sequence was: a real bug (the diagnostic door paused before the stream
was ready, so the readiness observer's `play()` landed after it), correctly
found and correctly fixed by waiting for `timeControlStatus == .playing` — and
then the fix was judged by an instrument that could not see it working, and
correct code was removed. The pause is restored, with a comment at the call site
saying it has been deleted once and why it should not be again.

**The rule this earns.** `instrument_must_be_invisible` and Decision 130 both say
the instrument is the first suspect; both were written about instruments that
produced false POSITIVES — a control that could not fail, a verdict that was the
opposite of the truth. This one produced a **false negative about a fix**, which
is more expensive, because the response to it is to delete work that was right.
A screenshot diff answers "did these pixels change", never "is this player
playing". When the question is about a component's STATE, ask the component:
`timeControlStatus` was available the whole time and took ten lines to read.

### §9.www Google's device flow, and the control that caught the message nobody could act on (2026-09-18)

The television's YouTube sign-in is now `GoogleDeviceAuth` — device code, QR,
phone — rather than `GoogleAuth`'s web sheet. iOS and macOS keep PKCE: on a
device with a keyboard the sheet is better and needs no secret. `StudioSignInRow`
draws one device-code surface for both platforms; the two `Pending` types are
wrapped rather than merged, because the flows differ in ways the POLLING code
must respect and only the two strings on screen are common.

**TWO GOOGLE CLIENTS, and the claim behind that MEASURED rather than cited.**
The docs say the device flow needs a client of type "TVs and Limited Input
devices". That is a claim about a credential we hold, so it is testable today.
Against the live endpoint:

    our REAL iOS client   invalid_client  "Invalid client type."
    a nonexistent id      invalid_client  "The OAuth client was not found."

So the second registration is genuinely required — the iOS client is refused
for its TYPE, not for being unknown. `clientID(for:)` is therefore
platform-conditional (`YOUTUBE_TV_CLIENT_ID` on tvOS), and so is the REFRESH:
a device-flow token can only be renewed by the client that issued it, with the
secret, so renewing one down the PKCE path would 401 on every call.

**AND THE CONTROL EARNED ITS KEEP IMMEDIATELY.** Both answers carry the SAME
`error` field. `error` alone cannot tell "you registered the wrong KIND of
client" from "you pasted the id wrong" — and those need opposite responses from
whoever is setting it up. `GoogleDeviceAuth` had been written to report the
code, so a mis-typed client would have told the owner *"Google refused the
sign-in: invalid_client"* and stopped. It now reports `error_description`, in
`begin` and in `poll`. This is the third endpoint in this feature whose status
or error code carries no information (Twitch's blanket HTTP 400, §9.ppp;
Google's `authError` living only on the final URL, §9.nnn) — **on this feature,
assume the discriminator is not where the protocol says it is, and go and
look.**

**A client id alone is no longer "configured".** `configurationProblem` now
requires the secret wherever the flow needs one. Checking only the id would
have let a television offer a sign-in Google refuses at the first request —
the same shape as §9.ooo, where a gate went green on a credential that did not
cover the path it was guarding.

**And the unconfigured state was an ABSENCE again.** `GoLiveTV` showed its
"where it goes" section only when more than one platform was configured. With
the TV client unregistered that left a screen with no destination on it at all
and YouTube simply gone, unexplained — which is precisely the defect Decision
128 names. The section is now always drawn: it states the destination when
there is no choice, and prints the configuration problem for every platform
this build cannot reach.

**§8.9 extended** and it still exits 2, honestly, because `YOUTUBE_TV_CLIENT_ID`
does not exist: the iOS-client refusal and its control are asserted TODAY,
before the credential they are about — Decision 128's "prove the request shapes
before the credentials exist", applied to a credential that has not been
created rather than one that had not yet been pasted.

**On the glass, Ben Bedroom, The Moon of Israel (1924, Michael Curtiz)** — new
content again. "Where it goes: **Twitch**", the YouTube sentence naming the
exact registration needed, the privacy row correctly absent for Twitch, and one
press reaching the QR with code `PNLLFWJY`. Teardown verified by the repaired
script AND by a second, independently written matcher.

### §9.vvv The television can go live — and the owner redirects sign-in to a QR code and a phone (2026-09-18)

**The surface Rule 8.8a describes now exists**, and with it tvOS stops being
the platform that could encode but not broadcast (§9.ccc). `GoLiveTV` collects
what a request needs — platform, title, privacy — and `runStudio` resolves a
real destination through `StudioGoLive.destination(for:film:)`, the same call
iOS and macOS make. The line it replaces was `try await engine.start(destination: nil)`.

`studioTVBroadcastProblem` shrinks to `StudioPlatformAuth.anyConfigurationProblem`.
Its second half — "going live from Apple TV is not built yet" — was true when it
was written last night and is not true now, and a refusal that outlives its
reason is the same defect §9.nnn found in its first half.

**THE OWNER REDIRECTED THE SIGN-IN, mid-tick**: *"The sign in can make use of
QR codes and signing in with a phone, but you are logging in on the TV using
that other device."*

That is a better answer than the one Rule 8.8a's SDK reading produced. §9.uuu
established that `ASWebAuthenticationSession` really does work on tvOS and that
its `API_UNAVAILABLE` annotations are the design rather than a gap — all true,
and all beside the point, because what it buys is a host typing a Google
password with a d-pad. A device flow puts the typing on the phone and leaves
the TOKEN on the television, which is what the owner described.

**Twitch needed no new field, and the measurement says why.** RFC 8628 defines
an optional `verification_uri_complete` that embeds the user code, and the
obvious move was to read it. Asked of the live endpoint with our registered
client id instead:

    POST https://id.twitch.tv/oauth2/device
    -> {"device_code": "...", "user_code": "CGZWNNTM", "interval": 5,
        "expires_in": 1800,
        "verification_uri": "https://www.twitch.tv/activate?device-code=CGZWNNTM"}

There is no `verification_uri_complete` **because `verification_uri` already is
complete**. A QR of the plain URI lands a phone on an activation page with the
code filled in. The eight characters stay on screen beside the QR: a QR is
useless to someone whose phone is in another room, and reading a code aloud is
the fallback that always works.

**What YouTube needs, read from Google's own documentation rather than assumed**
(`developers.google.com/identity/protocols/oauth2/limited-input-device`):

    client type   "TVs and Limited Input devices"  (NOT the iOS client we hold)
    device code   POST https://oauth2.googleapis.com/device/code   client_id, scope
    poll          POST https://oauth2.googleapis.com/token
                  client_id, client_secret, device_code, grant_type=...:device_code
    scopes        https://www.googleapis.com/auth/youtube IS permitted
    QR            no verification_uri_complete; the QR carries verification_url
                  and the user code is typed

So Decision 128's fallback becomes the path, and its stated cost is real and
unchanged: **this flow requires a client_secret**, which the PKCE flow
deliberately avoids. It is a second OAuth client, not a replacement for the
first — iOS and macOS keep PKCE, where a web sheet on a device with a keyboard
is the better experience. That registration is an owner step (SCRATCHPAD 7a3).

**On the glass, Ben Bedroom, The Ace of Hearts (1921, Wallace Worsley)** — new
test content per the standing rule. The first build put the primary control
**below the fold**: the capture showed everything down to the privacy row and
"Go live on YouTube" was off screen. A television has no scrollbar and no
thumb, so a viewer eight feet away cannot tell there is more — the one control
the screen exists for was the part they could not see. Rebuilt as two columns
(reading matter left, everything focusable right) and re-captured: the whole
surface fits, and `Go live on YouTube` renders correctly DISABLED with "Sign in
above to go live. Nothing is broadcast until you press Go live." underneath it.

**AND A PAUSE THAT DID NOT PAUSE, removed rather than shipped.** The first
version paused the film behind the confirmation. Two captures fifteen seconds
apart showed two different scenes. The first explanation was a race in the
diagnostic — `AW_STUDIO_TV` waited for `player != nil`, which is true long
before the stream is ready, so the readiness observer's own `p.play()` (the #5
Play Next fix) fired after the door's `pause()`. Waiting for
`timeControlStatus == .playing` fixed that race and the film still resumed.
Nothing in `DetailView`, `AVPlayerContainer` or `TVAudioSession` accounts for
it: the only two resumes either of those carries are gated on `.readyToPlay`
and on an interruption ENDING, and neither happens here.

The pause was unrequested scope — `GoLiveSheet_iOS` contains no `pause()` or
`play()` at all, so tvOS not pausing is parity — and a half-working promise in
code is worse than no promise (the §9.sss lesson about a comment claiming a
cancellation that never happened). So it is gone, and the unexplained resume is
written down here rather than smoothed over. **It is still an open question**,
and it matters beyond this screen: something on the tvOS player path resumes
playback after an external `pause()`, which is a thing the Studio's own stop
path should not be surprised by.

**AND THE TEARDOWN HAD NEVER WORKED.** `tools/atv_teardown.sh` exists because a
film was once left playing on the owner's Apple TV for an hour; its own header
says "a harness that touches someone's living room has to clean up as a STEP,
not as an intention". It greps `devicectl device info processes` for the BUNDLE
ID. That listing prints executable PATHS:

    1821   /private/var/.../ArchiveWatch.app/ArchiveWatch

`app.archivewatch.tvos` appears nowhere in it. So the grep never matched, the
script took its else branch, and it printed **"not running" about a live
process** — twice in this session, the second time while a Twitch device poll
was running against the owner's account. The app was found alive only by asking
the device with a looser pattern.

The first repair matched the path and anchored it with `$`, and reported the
all-clear about a live pid 1830, because devicectl **pads the path column with
trailing spaces**. Two different greps, the same false verdict, both of them
mine. The working form is `[[:space:]]*$`, the script now re-asks the device
after terminating and EXITS NONZERO if the process survives, and the check in
this session was repeated with a second, independently written matcher before
"gone" was believed. A cleanup instrument that cannot see its target does not
merely fail — it issues the all-clear, which is the one output that stops
anybody looking.

### §9.uuu tvOS sign-in: the SDK says yes, and the absence is the design (2026-09-18)

The owner answered Rule 8.8a's three open questions, overriding this document's
recommendation on two of them: **the title IS editable on the television**, the
`unlisted` default stays, and — *"Figure out the sign in path on the tv and
implement it"* — tvOS signs in on the television rather than pointing at a
phone.

**Read from the tvOS 27 SDK, not from memory**, because §10.2a's earlier note
recorded the restrictions and not the permissions, which made the path look
more closed than it is:

    ASWebAuthenticationSession            tvos(16.0)      available
    initWithURL:callback:completion:      tvos(17.4)      available
    - (BOOL)start                         no annotation   available
    presentationContextProvider           API_UNAVAILABLE(tvos)
    prefersEphemeralWebBrowserSession     API_UNAVAILABLE(tvos)
    - (void)cancel                        API_UNAVAILABLE(tvos)
    canStart                              absent from the list entirely

The television creates the session and calls `start()`, and the system presents
it — which is exactly WHY there is no context provider to hand it. **The
absence is the design, not a gap.** Two real costs follow, both narrow: a
started session cannot be cancelled programmatically, so a surface must not
offer a Cancel it cannot honour; and `canStart` cannot be consulted, so a
failure arrives in the completion handler rather than before the attempt.

**And the auth layer already supported all of this.** `present(url:scheme:)`
has guarded both properties with `#if !os(tvOS)` since it was written, with the
header quoted in a comment beside it. What never existed was a surface to call
it from — the same shape as everything else this week: the capability was
present and unreachable, so nobody could tell whether it worked.

`StudioSignInRow` now compiles for tvOS (`controlSize` and `textSelection` do
not exist there and are guarded; `.borderless` was already the button style,
per CLAUDE.md's standing tvOS rule). Twitch needs none of the above: its device
flow shows a code to type on a phone, which suits a television better than a
web sheet does, and it is already measured against the live endpoint (§9.ppp).

**Not yet built:** the go-live surface itself — the focus-driven confirmation
carrying the film, the platform choice, the now-editable title and §3.4a's
warning. tvOS builds green with the row available; the surface is the next
piece, and it is now unblocked because the three questions are answered.

### §9.ttt macOS can sign in — and the same proxy was in all THREE Apple surfaces (2026-09-18)

Rule B13g is approved and already says what the Mac sheet carries: *"the rights
refusal in a sentence (§2.3), the sign-in row, §3.4a's warning…"*. The sign-in
row was the one item never built, which is the whole reason §9.sss found the
Mac unable to reach a platform. This builds it — implementing an approved rule,
not inventing one.

**Moved, not copied.** `StudioSignInRow` was `#if os(iOS)` in `iOS/`; it now
lives in `Studio/`, which both targets compile, as `#if os(iOS) || os(macOS)`.
B13c's reason for mirroring rather than reinventing is exact here: a second
copy of this row would be a second chance to get the sign-in and rights copy
wrong. The only platform-specific thing in it was `Brand.primary`, which is
defined in `iOS/Design_iOS.swift`; the row now carries the brand orange
directly.

**A defect that would have bitten on the first press.** `presentationAnchor`
returned a bare `ASPresentationAnchor()` on anything that is not UIKit. On
macOS that type **is `NSWindow`**, so the auth session was being handed an
empty, never-shown window with nothing to attach a sheet to. It had never
misbehaved because it had never run — macOS had no sign-in surface to reach it
from. It now returns the key, then main, then first window.

**And the finding that matters more: the same proxy was in all three Apple
surfaces.**

    tvOS    DetailView              anyConfigurationProblem == nil    §9.ooo
    macOS   GoLiveSheet_macOS       configurationProblem   == nil     §9.sss
    iOS     GoLiveSheet_iOS         configurationProblem   == nil     here

Each says, in its own comment, that it exists so a host is never offered a
control that fails where they cannot see. Each was correct while NO client id
existed anywhere. All three went permanently nil on the same morning, for the
same reason, because of a change in a gitignored file. They were found one at a
time, in three separate ticks, each time by stumbling into the platform rather
than by looking for the predicate. **After the first one, the right move was
`grep configurationProblem` — seconds of work — and it was not made until after
the second.** A guard written against a proxy does not expire on one platform.

All three now ask whether the host is actually SIGNED IN. Because
`isSignedIn` is a Keychain read rather than observable state, the row reports
changes upward (`onSignedInChange`) instead of each sheet asking once and
keeping a stale answer — otherwise Go Live stays disabled behind a row that
says "Signed in".

**Still true after this:** nobody has signed in yet, so none of it has been seen
on the glass. The Mac's build is green and its path is complete; the last step
is a real authorization, which is the owner's to give.

### §9.sss The sign-in surfaces, read in the state they had never been in (2026-09-18)

With both ids registered, the sign-in surfaces became reachable for the first
time. Reading them in that state — no build, just reading the code paths that
could finally execute — found two defects, one of them a hole in my own fix
from three ticks earlier.

**1. "Cancel" cancelled the picture, not the work.** `StudioSignInRow` starts
the flow with `Task { await start() }` from a button action. That is an
UNSTRUCTURED task: SwiftUI cancels `.task {}` modifiers when a view goes away
and nothing at all for this one. Cancel did `pending = nil`, which hid the code
and left `completeTwitchSignIn` polling — one request every 5 seconds for the
code's full 30-minute life, **~360 requests after the host said stop**.
Dismissing the sheet did the same. The comment beside it claimed *"the sheet's
own dismissal cancels this task"*, which was never true and had never been
exercised, because no client id existed to reach it. The task is now held in
`@State` and cancelled by both Cancel and `onDisappear`; `poll` sleeps between
attempts, so cancellation lands within one interval.

**2. macOS enables Go Live for a platform it cannot sign in to — and this is
§9.ooo's defect, in the sibling I did not check.** `canCommit` read:

    return StudioPlatformAuth.configurationProblem(for: authPlatform) == nil

a fair proxy only while no client id existed anywhere. The day both were
registered it became permanently nil and Go Live switched itself on. But
**there is no macOS sign-in surface**: `signInToYouTube` and
`beginTwitchSignIn` are called from exactly one file and it is `#if os(iOS)`.
Tokens are `AfterFirstUnlockThisDeviceOnly` and unsynchronised, so a sign-in on
the host's phone does not reach the Mac either. Pressing Go Live would have
failed inside the auth boundary — the one thing §10.2b's principle says never
to offer. It now requires `isSignedIn` and says the true thing beside the
greyed control.

**This is worth more than the two fixes.** Three ticks ago the identical defect
was found on tvOS, understood, written up, and fixed — *on tvOS*. The same
predicate was sitting in the macOS sheet the whole time and I did not look,
because I had already framed it as "the tvOS gate". A guard written against a
proxy does not expire on one platform; the search should have been for the
predicate, not for the symptom. The grep that would have found it
(`configurationProblem` as a commit gate) takes seconds and was run only after
the second occurrence.

**Correction to §9.mmm.** That entry says the Mac "can go live". True only of
the CUSTOM diagnostic destination. To a platform, the Mac has never been able
to and still cannot — it lacks the surface, not the plumbing. The go-live
sheet, the request, the destination resolution and the publisher are all real
and shared; what is missing is a way to obtain a token on that machine. Marked
rather than rewritten (Decision 121).

### §9.rrr Where the tokens land: a Keychain write whose failure nobody could see (2026-09-18)

No token has ever existed, so §6.1's promise — *"Tokens live in the Keychain,
…AfterFirstUnlockThisDeviceOnly, never synchronised"* — had never been
observed. It is about to matter: both client ids are registered and the next
thing that happens is a sign-in.

**Fixed: a failure that could not be seen.** `StudioTokenStore.save` returned
**Void** and discarded `SecItemAdd`'s `OSStatus`. All three callers therefore
treated "stored" and "silently not stored" identically. The dangerous one is
the refresh path: Twitch's refresh tokens are one-time-use, so by the time the
store is asked to keep the renewed token, **Twitch has already killed the old
one**. A dropped status there signs the host out permanently, at the next call,
with nothing to diagnose. And `SecItemAdd` does fail in the field — a direct
probe on this Mac answered `-34018, a required entitlement is not present`.
`save` now returns the status and all three call sites check it, naming the
failure instead of swallowing it.

**Measured, and NOT concluded: which keychain it lands in.** On macOS a generic
password goes to the file-based keychain unless `kSecUseDataProtectionKeychain`
is set, and the file-based keychain has no concept of `kSecAttrAccessible`.
Probing the product's own path from a command-line harness:

    the file-based (legacy) keychain: true
    the data-protection keychain:     false
    kSecAttrAccessible reported:      <absent>

which looks exactly like the defect — the attribute accepted by the API and
then dropped. **It is not evidence of one.** Reaching the data-protection
keychain requires an entitlement a bare binary does not have (`-34018` again),
so an unentitled process would produce that reading even if the product were
perfect. The harness therefore reports it and refuses to judge; an assertion
that can never pass is worse than no assertion, and writing one would have
repeated §9.nnn's mistake in a new place on the same day.

**What would settle it** is the same probe running inside the signed app, where
the entitlement exists — a small diagnostic on a macOS build, not a
speculation. Until that runs, §6.1's accessibility promise is **unverified on
macOS** and is recorded here as open rather than quietly assumed. The fix, if
confirmed, is one key in three dictionaries; the reason not to apply it blind
is that with `save`'s status previously discarded, a wrong entitlement would
have turned a storage failure into a silent sign-out — which is exactly the
defect fixed above, and the order matters.

### §9.qqq §5's stream-key rule, guarded — and the guard's first run found a leak (2026-09-18)

§5 says a stream key "is never logged, never written to disk, never put in a
URL this app prints". That rule had been broken once — a key could reach a
TELEVISION SCREEN through an error string (§9, 2026-09-17) — fixed with
`redactingKey`, and then left with nothing watching it. A rule enforced by one
helper that two call sites remember to use is a rule waiting to regress.

`tools/test_studio_key_hygiene.swift` (§8.10) uses a **sentinel**: every
destination carries a key nobody could type by accident, and the test asserts
that string appears in no user-visible text. That is stronger than reading the
code, because it does not depend on knowing which paths print things — only on
the paths being exercised. It needs no network and no account: every guard it
hits throws before a connection is attempted.

**Its first run was red.** `RTMPPublisher.publish(to:streamKey:config:)` threw
`badURL(server.absoluteString)` — raw. That entry point takes the key as its
own parameter, so it reads as though no key could be in `server`; but its
callers hold a destination that carries one, because that is exactly what entry
point 1 is handed. The neighbouring guard (`no app path in ...`) had the same
shape and passed only because the URL it was given happened to have nothing to
leak — a pass for the wrong reason, sitting one line away from a real failure.
Both now redact.

The control runs FIRST and asserts the detector catches a raw destination,
because "no leak found" is also what a broken search returns (Decision 120).
The harness never prints the offending text either: a test that leaks the key
while reporting that the key leaked has not helped.

**What this says about the shape of the rule.** Redaction that depends on a
caller remembering to call a helper is a convention, not an enforcement. The
type system could carry it instead — a destination whose `description` is
redacted by construction — and that is the honest fix if this recurs. It has
not been done, because it is a wider refactor than this tick earns, and saying
so is better than implying the guard makes the design right.

### §9.ppp Twitch's device poll: every answer is HTTP 400, and the old rule polled a dead code 360 times (2026-09-18)

The registration (§9.nnn) made the device flow's POLL testable for the first
time — the loop that actually runs while a host is typing a code into
`twitch.tv/activate`. Measured against the real registration:

    begin                            200  device_code, user_code, interval 5, expires_in 1800
    poll, code not yet confirmed     400  {"message":"authorization_pending"}
    poll, a code that cannot work    400  {"message":"invalid device code"}

**Every answer is 400.** The status carries no information at all, and the
message is the only discriminator. `poll` read:

    if !message.contains("pending") && http.statusCode != 400 { throw ... }

which keeps polling on ANY 400. So a denied, expired or invalid code polled
every 5 seconds for the full 30-minute window — **360 requests against a code
that could never work** — and then reported *"The Twitch code expired before it
was confirmed"*, which is not what happened. That is precisely the behaviour
the method's own comment warns about two lines above it: *"ignoring the stated
interval is how an app gets rate-limited rather than authorised."*

`pollOutcome(message:)` now carries the rule, extracted so the harness asserts
the function the PRODUCT runs rather than a copy of it (Decision 119), and
§8.9 drives both states live: a real unconfirmed code must answer
`authorization_pending` and classify as keep-waiting; a dead one must answer
something else and classify as refused. RFC 8628's `slow_down` back-off is
honoured defensively and marked as NOT observed, because a client that ignores
it is the one that gets throttled.

**Worth noting what made this findable.** Nothing about the code looked wrong,
and no test could have caught it without a real client id: with no
registration, `begin` never returns a device code, so the poll loop had never
executed once against Twitch. The credential did not just unblock the feature —
it made a whole code path observable for the first time, and the first thing it
showed was a defect.

### §9.ooo Registering a client id opened a gate on a platform that cannot broadcast (2026-09-18)

Found immediately after §9.nnn, by asking what the new half-configured state
changes — one platform with an id, one without, which no build had ever been
in.

`StudioPlatformAuth.anyConfigurationProblem` returns nil as soon as **either**
platform is configured. That is correct for what it says it is: a surface with
no platform picker must not name one arbitrarily, so it speaks only when
neither can be signed in to. tvOS's two Watch Together gates used it as the
test of whether a broadcast could happen at all — and those are different
questions.

    DetailView.runStudio(for:)     try await engine.start(destination: nil)
    macOS RootView_macOS:43        StudioGoLive.destination(for:film:)
    iOS StudioPlayerContainer:153  StudioGoLive.destination(for:film:)

tvOS is the one product path that resolves no destination, because the surface
that would choose one is tvOS-DESIGN's **proposed** Rule 8.8a — three open
questions the doc explicitly reserves for the owner. The doc already said the
consequence plainly: *"tvOS keeps the engine, the gates, the verified hardware
encoder (§9.vv) and no way to broadcast."*

So the moment `YOUTUBE_CLIENT_ID` landed in a gitignored file, the television's
gate stopped firing and "Watch Together ▸ With the world…" would have started
the Studio, encoded 1080p30 at 6 Mbps on the hardware encoder verified in
§9.vv, and published to nothing — with no error, because nothing was wrong.
§10.2b exists to stop a host being "let into a production mode that can never
reach an audience" and it would have done the opposite.

**Fixed by asking the right question, not by building the surface.** Building
the tvOS go-live path now would be deciding Rule 8.8a's three open questions on
the owner's behalf. `studioTVBroadcastProblem` answers "can this television
reach an audience" — no, and the reason has nothing to do with credentials —
and keeps the credential sentence for the case it still describes. tvOS build
green.

**The shape worth keeping.** This is not a coding error; every line was correct
when written. It is a **guard written against a proxy**, and the proxy stopped
tracking the thing it stood for on a day when nobody was looking at tvOS at
all. The trigger was a registration in a web console. The class is the one §6
kept producing — a rule implemented as something adjacent to itself — with a
new wrinkle: **the adjacency held until an unrelated change made it false**, so
there was no moment where the code was wrong until suddenly it was.

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

**Correction, same day — TWITCH IS DONE, and the checks above were weaker than
they read.** Two things, both found by looking rather than assuming:

1. **Twitch registered.** The owner cleared the 2FA gate and the application
   was created — "Archive Watch Studio", public client, Broadcaster Suite. Its
   id came from the console URL (a machine read) with the rendered field
   agreeing, and §8.9 now asserts BOTH platforms: Twitch's device endpoint
   answers **HTTP 200 with a real `device_code`** and accepts the
   `channel:read:stream_key` scope. The device flow's first call works end to
   end against the real registration.

   Getting there cost four submissions that appeared to do nothing, because
   **`dev.twitch.tv`'s Applications page silently renders an EMPTY TABLE when
   it fails to load** — its own console says `first page loaded failsafe was
   triggered for page DevAppsListPage`, which was visible and which I read as
   unrelated noise. The app had in fact been created on an earlier attempt;
   "the list is empty" and "the list could not load" look identical. The truth
   only surfaced when a resubmission was refused with *"client name already
   exists"*. **An empty list is not evidence of absence unless the list
   loaded.**

2. **Both YouTube controls above were passing for the wrong reason.** They sent
   `code_challenge=CHALLENGE` — a literal that is not valid base64url — and
   Google validates the challenge BEFORE it looks at the client id or the
   redirect. All three cases were failing identically with "Code Challenge must
   be base64 encoded", and the assertion accepted them because the response
   body contains the substring "error"; both the success and failure pages are
   ~1 MB of script and both do. The controls could not have failed.

   Re-probed with RFC 7636's own published challenge, the discrimination is
   sharp and lives in the FINAL URL, never in the HTML — Google states the
   reason in a base64url `authError` parameter:

       real client + real redirect   -> /v3/signin/identifier      the sign-in page
       unregistered client id        -> /signin/oauth/error        invalid_client
       redirect the client omits     -> /signin/oauth/error        redirect_uri_mismatch

   The third line is the one worth having: it proves the registration carries
   our bundle id, which is the single thing no client id string can tell you.
   The harness now asserts those three landings by name. **A control written in
   the same breath as the rule "run the control that should obviously produce
   the opposite verdict" still has to be checked against that rule** — this one
   was written this morning, quoting it.

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
