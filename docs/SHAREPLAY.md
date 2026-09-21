# SharePlay — Watch Together

**Binding.** Every change to Watch Together on tvOS, iOS or macOS must trace
to a rule here. The feature spans three platforms sharing one service, and
every defect it has had so far came from one platform quietly diverging from
the others. When something feels wrong, fix this document, then fix the code.

Companion to Decision 098. Implementation lives in
`ArchiveWatch/ArchiveWatch/Services/WatchTogether.swift` (shared) plus a
per-platform entry point and join router.

---

## 1. Why this app is an unusually clean fit

The catalog is public domain, served by archive.org, identical for every
participant, with no account, no DRM and no regional licensing. **There is no
access check to write.** If a peer has the app, they can play the film. Most
SharePlay integrations spend their complexity on entitlement checks; ours
spends it on identity and resilience instead.

## 2. The three invariants

### 2.1 Identity is the archiveID, never the URL

Every title plays through a private `aw-stream://` URL (Decision 072), so two
participants almost never hold the same URL — and may not even hold the same
archive.org copy, since Decision 077 can fall back to a different one mid-film.

`AVPlayerPlaybackCoordinatorDelegate.playbackCoordinator(_:identifierFor:)`
answers with the **archiveID**, which is stable across both the custom scheme
and a copy swap. Apple documents this exact case: the delegate exists "to
establish identity of two items created from different URLs".

When the archiveID is unknown the delegate returns a fresh UUID — deliberately.
That means "this is not the same content", and a group that refuses to sync is
strictly better than one that syncs two different films.

**Never** answer with the URL, the file name, or anything derived from the copy
currently in hand.

### 2.2 The listener starts at LAUNCH, not at catalog-ready

`WatchTogether.listen()` must be attached to a view that exists from the first
frame. "Move this call to Apple TV" **cold-launches** the app, and gating the
listener behind `store.isReady` left nobody listening during the loading screen
— the app was still reading a ~74 MB catalog while the system tried to hand the
session over.

Resolving the **film** may wait for the catalog. Joining the **session** may
not.

Corollary: routing a join must be keyed on the catalog version as well as the
id (`.task(id: store.dbVersion)`), not `onChange` alone. `onChange` only fires
for changes it was present for, so a session arriving during a cold launch —
exactly the continuation case — sets `pendingJoin` before the router exists and
is never seen.

### 2.3 A stalled member suspends the group

Archival streams stall. That is the entire reason Decisions 021/031/034/077
exist, so a stall here is routine, not an edge case. A stall must
`beginSuspension(for: .stallRecovery)` so the group **waits** rather than
drifting, and end that suspension when `isPlaybackLikelyToKeepUp` returns.

This is driven centrally from `WatchTogether.attach`, never by each player.
It was previously a public method **nothing called on any platform** — every
player got a coordinator and none of them ever suspended it.

The stall observer binds `object: nil` plus an identity check, not
`object: item`. The item is replaced on a Decision-077 copy fallback, and an
observer bound to the item seen at attach time goes quiet on exactly the swap
that follows a bad stall.

## 3. Never coordinate the caption scout

Live captions run a second, **muted** player ahead at 2× (Decisions
058/069/072). Coordinating it would drag the whole group to 2×. Only the main
player is ever passed to `attach`. Captions stay a local concern on every
device — two participants may legitimately have different caption states.

## 4. This is NOT the AirPlay situation

Decision 051: AirPlay requires the **receiver** to fetch the media itself, so a
private scheme is unusable there and we swap in a published URL.

Coordination exchanges only **rate and time**. Each participant loads its own
asset locally, through whatever loader it likes. Do not "fix" SharePlay by
reaching for the AirPlay URL swap — they solve opposite problems.

## 5. Platform entry points

| | tvOS | iOS | macOS |
|---|---|---|---|
| Listen at launch | `ContentView` | `RootView_iOS` | `RootView_macOS` |
| Start a session | Detail autoplay menu | Detail menu | Detail Share menu |
| Start the **call** | ✗ unavailable | `SharePlayStarter_iOS` | `SharePlayStarter_macOS` |
| Join routing | `IntentInbox.playItem` | `routeSharePlayJoin` | `routeSharePlayJoin` |
| Attach coordinator | `DetailView` | `PlayerView_iOS` | `PlayerWindow_macOS` |

`GroupActivitySharingController` — the system sheet that picks people and
**places the call** — exists on UIKit (iOS 15.4+) and AppKit (macOS 13+), and
**not on tvOS at all** (checked in the 27.0 SDK). Its shape differs by kit:

- UIKit: a `UIViewController` presented modally; `result` read after dismissal.
- AppKit: an `NSViewController` presented with `presentAsSheet`; `result` is an
  async property that can simply be awaited — no dismissal delegate.

tvOS therefore explains the situation instead of offering it. Which leads to:

## 6. "Watch Together" must never silently play the film alone

`prepareForActivation()` answers `.activationDisabled` when the user is not in
a call. That is **ordinary, not an error**.

The outcome type is a three-case enum (`started` / `needsCall` / `cancelled`),
not a Bool, because a Bool cannot say *why* nothing happened — and "nothing
happened" is the one outcome a viewer must never be left with. On `needsCall`,
iOS and macOS present the system sharing sheet; tvOS shows an alert telling the
viewer to start a FaceTime call first.

Playback begins **only once a session is live**. Never fall through to solo
playback from a Watch Together action.

## 7. The initiator is not a joiner

An activation we started also arrives back through `sessions()`. Without
`locallySharedArchiveID`, the initiator re-routes to the film it is already
watching and restarts it. Only a joiner gets routed.

Everything after that point — state observation, `join()` — applies to both,
which is why the skip is scoped to routing rather than being an early return.

## 8. Requirements checklist for any new Apple platform

1. `com.apple.developer.group-session` in that platform's entitlements.
2. GROUP_ACTIVITIES capability on the App ID (portal-only; the ASC API can
   read it but not set it).
3. `listen()` on a view present from the first frame.
4. A join router keyed on the catalog version.
5. `attach(player:archiveID:)` on **every** player build — a player rebuilt by
   the Decision-077 fallback brings a new coordinator that must be re-attached.
6. A share entry point that handles all three `ShareOutcome` cases.

## 9. Verified

End to end on real hardware, 2026-09-01 (owner): call started from the iPhone
app via the sharing controller, film in sync on the iPad, and the session
surviving a continuation to the Apple TV once §2.2 was fixed.

**Not yet verified:** behaviour under a genuinely throttled network (§2.3's
suspension path), and the tvOS "start a call first" alert on the glass.

## SharePlay is COORDINATION, never media (measured 2026-09-20)

Asked whether a SharePlay call could be broadcast to YouTube/Twitch alongside
the film, the answer is no, and the framework states it plainly: grepping the
whole `GroupActivities` module interface for
`audio|video|camera|microphone|stream|media` returns ONE token, and it is a
presentation hint (`BroadcastOptions.mirroredVideo`).

The three channels are `GroupSessionMessenger` (app-defined messages,
reliable or unreliable), `GroupSessionJournal` (file attachments), and
`SystemCoordinator` (spatial templates and participant STATE). `Participant`
is an identifier. **FaceTime's audio and video are system-owned and are not
exposed to the app hosting the activity** — a privacy boundary, not a gap.

**CORRECTED 2026-09-20, same day**: the paragraph above is about FaceTime's
call media, and SharePlay is not FaceTime — a `GroupSession` needs no call at
all. What SharePlay will not do is hand you another participant's CAPTURED
audio. What it will do is carry whatever bytes an app sends:
`GroupSessionMessenger.send(_ value: Data, to:)`, constructible with
`DeliveryMode.unreliable`. **Guest voice is therefore buildable on the session
this app already has** — each app captures its own microphone and sends
frames, every app mixes what it receives, and the host mixes them into the
programme as well. `docs/WATCH-TOGETHER.md` §9.wwwww has the shape and the one
measurement it depends on.

**Do not plan a feature on getting guest camera or microphone out of
SharePlay.** An app can coordinate what everyone watches; it cannot hear or
see who is watching. The routes that could carry guests are in
`docs/WATCH-TOGETHER.md` §9.vvvvv.

## §5 Guest voice (PROPOSED — the rule before the code)

Owner, 2026-09-20: *"I'd like to watch the movie together and be able to talk
with my friends and family while I'm doing it, and have that all streamed to
YouTube or twitch."* This is the rule written BEFORE the feature, which is
what `binding-design-doc-discipline` asks and what Android's mix controls did
not get (they were shipped and the rule written after — `WATCH-TOGETHER`
§9.uuuuu).

**§5.1 Every app captures only its OWN microphone, and sends it.** Nothing
reads anyone else's capture, because no API offers it and asking for one is
the FaceTime confusion §9.wwwww corrects. A participant's own voice leaves
their own device or it does not exist.

**§5.2 The transport is the session's own messenger, in UNRELIABLE mode.**
`GroupSessionMessenger.send(_ value: Data, to:)` carries arbitrary bytes to
every participant. A voice frame that arrives late is worthless, and
retransmitting it ahead of the next one makes the conversation worse — so
reliability is the wrong default here, unlike every other message this app
sends over that channel.

**§5.3 It is GATED ON A MEASUREMENT, not on optimism.** Apple documents the
messenger for application state and says nothing about sustained rate or
latency. `StudioVoiceProbe` sends what the real thing would send (80-byte
frames, 50 a second) and reports delivery and round trip. **Good enough is
better than 90% delivered at under 150 ms one-way**; past roughly 250 ms
people talk over each other. If the messenger misses that bar the guest
transport is ours to build, and that is a different feature at a different
cost — which is precisely why the number comes first.

**§5.4 The host mixes guests into the PROGRAMME; everyone mixes them for
themselves.** Each app plays the other voices locally so the conversation
works whether or not anyone is broadcasting. The host additionally feeds them
into the Studio mixer, where they are more inputs to something that already
exists on four platforms with 0-10 faders and a duck (Rule 8.8c and its
siblings). **Only the host publishes.** A guest's app must never open an RTMP
connection — two publishers on one broadcast is a second clock and a second
bill.

**§5.5 Echo cancellation is not optional.** The film is coming out of the same
speakers every participant's microphone is listening to, so a raw capture
source feeds the film back into the conversation on top of itself, worse with
every duck. Use the platform's voice-chat path (`AVAudioSession` voice-chat
mode on Apple, `VOICE_COMMUNICATION` on Android — `ANDROID-DESIGN` §9.14).

**§5.6 A guest's voice is never synced to the film, and the film is never
synced to a voice.** Decision 098 already keeps everyone's playback together;
conversation is live and belongs on the live clock. Any attempt to align the
two would delay one of them, and a delayed conversation is not a
conversation.

**§5.7 The practical reach, stated plainly**: this works between people who
each run Archive Watch and are in one SharePlay session. It is not a way to
put an arbitrary friend on a phone call into a broadcast, and a session cannot
be started programmatically — `prepareForActivation()` answers
`activationDisabled` with no eligible conversation, so a person chooses the
people. Two devices on ONE Apple ID cannot SharePlay each other, which also
means **§5.3's measurement needs a second person with the app**, not merely a
second device.

## §6 Can a SharePlay call be STREAMED to YouTube/Twitch? (answered 2026-09-20)

Owner, with a working iPhone-to-iPhone call: *"can you determine if this feed
can flow through to stream to youtube/twitch?"*

**The film can. The conversation cannot, and iOS says so by name.**
`AVAudioSession.h`, on activating a session while another app hosts a call —
and it names this exact scenario:

> *"Apps may activate a AVAudioSessionCategoryPlayback session when another
> app is hosting a call (to start a SharePlay activity for example). However,
> they are **not permitted to capture the microphone of the active call**, so
> attempts to activate a session with category AVAudioSessionCategoryRecord or
> AVAudioSessionCategoryPlayAndRecord will fail with error
> AVAudioSessionErrorCodeInsufficientPriority."*

That is `'!pri'` / 561017449 — the same error `StudioEngine` already documents
hitting on tvOS. So there are three answers, not one:

1. **The FILM streams.** `.playback` is expressly permitted during a call, and
   the Studio composites the film from its own player output, never from the
   system. Nothing about a call stops that.
2. **The HOST's own voice does not**, while the call is up. Not a gap in our
   plumbing — the platform refuses the category.
3. **The OTHER participants' voices never could**, by any route. §9.wwwww
   covers the API side; this is the same boundary stated as an audio rule.

**A defect this exposed, fixed the same day.** iOS asked for `.playAndRecord`
UNCONDITIONALLY, so in a call the activation threw and left the session
unconfigured — a broadcast that could have carried the film carried nothing,
for want of a microphone it was never going to get. It now falls back to
`.playback` and says so on the readout: *"a call owns the microphone — your
voice is not in the show."* tvOS already had this right for the Continuity
case.

**AND IT CONSTRAINS §5.** Guest voice over the messenger needs every
participant's app to record its OWN microphone — which is exactly what a live
FaceTime call refuses. So §5 is not an addition to a FaceTime watch party; it
is an ALTERNATIVE to one. Either the call carries the voices (and they cannot
be broadcast), or the app carries them over a SharePlay session started
**without** a call, from Messages — and then they mix into the programme like
any other input. That is a cleaner feature than the one originally imagined,
and it only works if nobody is on FaceTime.

## §7 If we built our own voice + sync system: the protocols (2026-09-20)

Owner: *"What protocol(s) would we use if we were going to build our own voice
and syncing system to allow for multiple participants calling in and all
having it streamed to youtube/twitch?"*

Four jobs, and they have very different costs.

| job | what it needs | what Apple gives free |
|---|---|---|
| **sync** | everyone at the same film position | **already solved** — `AVPlayerPlaybackCoordinator` + SharePlay (Decision 098), and it needs no FaceTime |
| **codec** | low-latency voice | **`kAudioFormatOpus`** in CoreAudioTypes — Apple ships an Opus encoder, so no third-party codec |
| **echo** | the film is in the same room as the mic | `AVAudioSession` voice-chat mode, `VOICE_COMMUNICATION` on Android |
| **transport** | frames between houses | **nothing.** No STUN, no ICE, no TURN in any Apple SDK |
| **egress** | the mixed programme to YouTube/Twitch | **already built** — our own RTMPS publisher (Decision 127) |

**So three of the five are already paid for, and the whole question is the
transport.**

**TOPOLOGY: a STAR through the host, not a mesh.** The host has to mix anyway —
that is what goes to RTMP — so guests send to the host, the host mixes, and
each guest gets a **mix-minus** (everyone except themselves, or they hear
their own voice back). A mesh costs N² streams to avoid a mix the host is
already computing.

**PROTOCOLS, in the order they should be tried:**

1. **Opus over `GroupSessionMessenger`, unreliable.** 20 ms frames, ~24 kbps a
   speaker, `send(_ value: Data, to:)`. **Zero infrastructure and zero NAT
   problem** — Apple carries it. Sync stays on SharePlay. The unknown is
   whether that channel sustains ~50 small messages a second at conversational
   latency; Apple documents it for application state. §5.3 gates the design on
   that number and `StudioVoiceProbe` takes it. **Mutually exclusive with
   FaceTime** (§6: a call refuses the microphone), which is fine — the app
   carries the voices instead.
2. **Opus in RTP over DTLS, on `Network.framework`.** `nw_parameters_create_secure_udp`
   gives datagrams and encryption natively. We would write: an RTP-ish header,
   a jitter buffer, packet-loss concealment (Opus has it built in), and
   **NAT traversal** — STUN gets most peers connected, and the 15-20% behind
   symmetric NAT need a **TURN relay**, which is a server with a bandwidth
   bill. That relay is the real cost of leaving Apple's transport, and it is
   the reason everyone else reaches for WebRTC.
3. **WebRTC (libwebrtc).** The standard answer: Opus, SRTP, ICE/STUN/TURN,
   congestion control, jitter buffer and AEC in one package. It is also a very
   large third-party dependency in a project that ships **zero** by choice
   (Decision 127), brings its own build system and concurrency model, and
   still needs a TURN server. Worth it only if guest VIDEO is wanted — which
   is the one thing options 1 and 2 cannot grow into cheaply.

**THE HONEST SHAPE OF THE DECISION.** Voice-only between a handful of people
is a small feature on top of things this project already owns — an Opus
encoder from Apple, a mixer with 0-10 faders on four platforms, an RTMPS
publisher, and sync from Decision 098. What turns it into a real project is
**NAT traversal**, and option 1 is the only one that dodges it entirely. So
the order is: measure the messenger; if it carries voice, build option 1 and
own nothing; if it does not, the question becomes whether guest video is
wanted, because that is the only thing that justifies WebRTC's weight and a
relay's bill.

## §8 CROSS-PLATFORM changes the answer: SharePlay cannot do it (2026-09-20)

Owner: *"Shareplay only works on Apple Devices, so how are you going to use
that cross-platform?"*

**It cannot, and that retires §5 and §7's first option.** A `GroupSession` is
an Apple construct: no Android device and no browser can join one. So for a
watch party that includes Android or the web, SharePlay can be neither the
transport NOR the sync — `AVPlayerPlaybackCoordinator` goes with it.

**What survives unchanged, by design.** `StudioVoiceCodec` (§8.19) and
`StudioVoiceRoom` (§8.20) know nothing about the transport. They were built
first precisely so this answer could change without wasting them: packets
arrive with a participant and a sequence, and the room reorders, conceals,
mixes and mix-minuses identically whoever delivered them.

**Cross-platform means a relay, and the relay ALREADY EXISTS on this
account.** `worker/wrangler.toml` runs `archivewatch-pulse`, a Cloudflare
Worker with a D1 database, for the privacy counter. A **Durable Object with
the Hibernatable WebSocket API** is exactly a room: Cloudflare's own example
is a chat room broadcasting to every connected client, and a WebSocket client
reaches it from Swift, Kotlin and a browser alike. **Everyone connects
OUTWARD**, so NAT traversal — the expensive part of any peer-to-peer design,
and the reason WebRTC drags a TURN server behind it — simply does not arise.

**THE COST IS MESSAGE COUNT, NOT BANDWIDTH, and that is the counter-intuitive
part.** Durable Objects bill WebSocket messages as requests. Voice is 27.3
kbps a speaker, which is nothing — but at 20 ms frames it is **50 messages a
second a speaker**, which is a great many requests:

| frames per message | latency added | a 2-hour party of four | vs the free tier/day |
|---|---|---|---|
| 1 (20 ms) | 0 ms | 1,440,000 | 14.4x |
| 2 (40 ms) | 20 ms | 720,000 | 7.2x |
| 3 (60 ms) | 40 ms | 480,000 | 4.8x |
| 5 (100 ms) | 80 ms | 288,000 | 2.9x |

Total bandwidth for that party is **109 kbps**. The free plan's 100,000
requests a day is **33 minutes of one person talking** without batching. The
paid plan includes a million requests a month at a $5 minimum, then $0.15 a
million — so a two-hour party of four costs about **7 cents** in requests, and
batching two frames to a message brings it inside the included allowance
entirely for 20 ms of added latency.

**BOTH HALVES OF THAT PARAGRAPH WERE WRONG — see §9.** It said the relay
costs about $5/month, and that Durable Objects therefore need the paid plan.
They have been on the **Workers FREE plan since April 2025** (SQLite-backed).
And the free tier does not rescue the design either, for a reason the $5
framing hid completely. Corrected below rather than edited away.

## §9 A RELAY CANNOT BE $0 AT SCALE, and the reason is the daily limit is per ACCOUNT (2026-09-20)

Owner: *"It is absolutely not acceptable. The goal of this app (and all of my
apps) is for them to cost $0 to run."*

That is a hard constraint and it decides the architecture. Two corrections to
§8, the second of which matters far more than the first.

**§8 said the relay costs ~$5/month. It does not.** Durable Objects moved to
the Workers **free** plan in April 2025 (SQLite storage backend only). No paid
plan is required, and the $5 was the paid plan's minimum, which this does not
need.

**But free does not save it, because the 100,000 requests a day is PER
ACCOUNT** — shared by every user of the app, not granted to each. Measured, a
2-hour film with four people talking 15% of the time at three frames a
message:

| batch | added | always-on | talk 30% | talk 15% | talk 8% |
|---|---|---|---|---|---|
| 1 | 0 ms | 1,440,000 | 432,000 | 216,000 | 115,200 |
| 2 | 20 ms | 720,000 | 216,000 | 108,000 | 57,600 |
| 3 | 40 ms | 480,000 | 144,000 | **72,000** | 38,400 |
| 5 | 80 ms | 288,000 | 86,400 | 43,200 | 23,040 |

**72,000 messages is 72% of the entire day's allowance for the whole app,
worldwide, for ONE party.** That is 1.4 parties a day before every further
party fails with an error — Cloudflare's free tier does not throttle, it
refuses. A feature that works while nobody uses it and breaks the evening it
becomes popular is a worse failure than one that costs money, because the
failure lands on the users who liked it most.

**SO THE VOICE MUST NOT TOUCH OUR INFRASTRUCTURE.** The design that is $0 at
any scale:

- **Signalling through the existing Worker**, and only signalling. A party of
  four needs perhaps twenty messages to exchange connection details — once,
  not fifty times a second. At 100,000/day that is ~5,000 parties a day, free,
  comfortably.
- **Voice peer-to-peer.** Those 72,000 messages become ZERO requests, and the
  bandwidth is the participants', not ours.
- **NAT traversal on free public STUN** (Google's, Cloudflare's). STUN is free
  and stateless; it is **TURN** that costs, and TURN is needed only for the
  minority behind symmetric NAT.

**THE CAVEAT, STATED PLAINLY BECAUSE IT DOES NOT GO AWAY**: roughly 10-20% of
peer pairs cannot connect on STUN alone, and for those there is no free fix.
They would get the film and the sync and not the conversation. "Works for most
people, fails for some, costs nothing" is the bargain every $0 peer-to-peer
app makes, and for a free app with no accounts it is the right one — but it is
a real limitation and must be said on the surface, not discovered.

It also stays genuinely cross-platform: STUN and UDP reach Swift, Kotlin and a
browser alike, which SharePlay never could (§8).

## §10 THE CALL IS NOT OUR PROBLEM — and that is the design (2026-09-20)

Owner: *"I mean, calling services like Google Meet, Zoom, Phone Calling or
other services that every device has if we wanted to separate out the calling
part from the movie playing, syncing, and streaming to youtube."*

**This dissolves everything §5 through §9 were struggling with.** Those
sections all assumed the app must CARRY the voices, and every consequence
followed from that: a transport, NAT traversal, a relay, per-message billing,
an SDK, a free-tier ceiling. If people simply use the call they already have,
none of it exists.

The app then owns three things, and it already does two of them well:

| | who |
|---|---|
| the call | **whoever they like** — Zoom, Meet, FaceTime, a phone call. Not ours |
| watching in sync | ours, cross-platform, and the only networking left |
| the broadcast | ours, built and proven (Decision 127's RTMPS publisher) |

**AND THE CONVERSATION CAN STILL REACH THE AUDIENCE**, which is the part that
looked impossible. macOS 14.2 added **`AudioHardwareCreateProcessTap`** —
Core Audio, native, no virtual audio driver — which captures a NAMED
APPLICATION's audio by bundle id (`kAudioProcessPropertyBundleID` over
`kAudioHardwarePropertyProcessObjectList`). So a host on a Mac taps the
conversation out of Zoom, or out of the browser running Meet, and mixes it
into the programme beside the film and their own microphone. The mixer, the
0-10 faders and the duck all already exist and take one more input.

This is also why the owner's earlier offer matters: *"If we need to gate it so
that this can only be initiated by a MacOS device, that is okay."* The tap is
macOS-only (`API_UNAVAILABLE(ios, watchos, tvos)`), and the host is the one
device that must be a Mac. **Everyone else watches on anything.**

**WHAT IT COSTS: nothing.** No SDK, no relay for voice, no NAT traversal, no
per-message billing. The only traffic we carry is SYNC, which is one or two
orders of magnitude cheaper than voice — a position update on seek and pause
plus a heartbeat every ten seconds is ~2,900 messages for a four-person
two-hour film, against a free 100,000 a day. That is thirty-odd parties a day
on the Worker that already exists, rather than 1.4 (§9).

**AND IT IS MEASURED, not inferred** (§8.21, `tools/test_studio_processtap.swift`,
2026-09-20 on the dev Mac). Core Audio lists 35 audio processes, 25 of them
named by bundle id, and the call services the owner asked about are simply
THERE: `com.apple.avconferenced` (FaceTime), `com.google.Chrome` (which is
where Google Meet runs), `com.tinyspeck.slackmacgap`. A tap on a running
process delivers real PCM — 193,536 frames in four seconds, 48 kHz stereo.

**The control is the part that matters.** A tap that also caught the FILM
would put the film into the broadcast twice and feed it back into itself, so
the question is not whether we can hear the call but whether we hear ONLY the
call. Two processes played two tones at once, 440 Hz tapped and 1000 Hz not:

| | magnitude |
|---|---|
| 440 Hz — the tapped process | 0.183038 |
| 1000 Hz — a second process playing simultaneously | 0.000015 |
| isolation | **12,052:1 = 82 dB** (72-82 dB across four runs) |

The untapped process is inaudible. The design is safe, not merely possible.

The case runs under the suite's `-parse-as-library`, which is why it carries a
`@main` rather than top-level code — it compiled standalone and FAILED inside
the runner, which is the §9.lllll shape all over again: a harness that only
ever ran by hand.

**A HARNESS FAULT WORTH KEEPING**, because it is the same family as every
other one in this project: the first capture run reported `peak=0.0000` over
four full seconds and would have been written down as "macOS returns silence,
probably TCC". It was not. The probe played a SHORT sound in a shell loop, so
each `afplay` exited and the next got a new pid — the tap was on a process
that had already died, and a dead process is silent in exactly the way a
permission wall is. A twelve-second continuous tone captured immediately. The
instrument is always the first suspect (Decision 130).

**WHAT IS STILL NOT KNOWN**: what permission prompt a SHIPPING app raises.
This probe ran as a command-line tool, so TCC attributed it to the terminal,
which already carries the grants. A bundled, signed Archive Watch may show the
host a system prompt the first time — that changes what the host is TOLD, not
whether the design works, and it is measured when the call site exists.

**AND WHAT IT GIVES UP, honestly**: the audience hears the conversation, and
the guests hear each other, but the guests' VOICES are not separable inside
our mix — we get one stereo pair from the call app, not per-speaker tracks. So
no per-guest fader. Against a design that costs nothing and needs no
infrastructure at all, that is a very cheap thing to lose.

---

## §11 KEEPING THE FILM IN SYNC WITHOUT SHAREPLAY — PROPOSED (2026-09-21)

*Owner: "Have you figured out how you are going to keep the movie in sync for
everyone on the call if we aren't going to use shareplay (because it needs to
be cross-platform)?"*

§10 says sync is "ours, cross-platform, and the only networking left" and
estimates ~2,900 messages. It never says HOW. This is that, PROPOSED — no code
exists, and two of its choices are the owner's.

### §11.1 Send STATE, never the playhead

The naive design broadcasts the current position several times a second and
fails the $0 constraint immediately. The film is deterministic: given a
position, a rate and the moment that position was true, every client can
compute where the film should be now.

So a host publishes a **state record** and nothing else:

    { filmID, position, atServerTime, rate, paused, generation }

and every client extrapolates `expected = position + (now - atServerTime) * rate`
while `!paused`. A record is written only when the state actually CHANGES —
play, pause, seek, rate, end. **A two-hour film has tens of those, not
thousands**, which is what makes §10's message estimate achievable rather than
optimistic.

### §11.2 The clock is the actual problem, and the server is the reference

Two devices' wall clocks differ by seconds, so `atServerTime` is meaningless
unless everyone agrees what time it is. Each client estimates its offset
against the SERVER with Cristian's algorithm: send `t0`, the server replies
with its own `ts`, the reply arrives at `t1`, and

    offset ≈ ts − (t0 + t1) / 2        error bounded by RTT / 2

**Take the sample with the SMALLEST round trip, never the average.** The error
bound is RTT/2, so the fastest exchange is the most accurate one; averaging
mixes a good measurement with bad ones and throws away the bound. Re-sample
every few minutes — a phone that changes network changes its latency.

This is the same discipline Decision 119 applies to the encoder: measure
against an independent reference, never against ourselves.

### §11.3 Correct drift by RATE first, and seek only as a last resort

Decision 081 already settled the shape of this for captions: *a drift
correction may not rewind the captions past the viewer.* The same holds for a
film, and harder, because a seek re-buffers and is visible to everyone.

| how far off | what happens |
|---|---|
| < 150 ms | nothing. Inside human tolerance for a shared watch |
| 150 ms – 2 s | **nudge the RATE** (0.97x / 1.03x) until aligned, then restore 1.0 |
| > 2 s | seek, because rate-nudging would take a minute to close it |
| paused / play | applied immediately, never nudged |

A rate nudge of 3% is inaudible on speech and invisible on 24 fps film; it is
how every video-conferencing jitter buffer works and it avoids the one thing
viewers actually notice, which is a jump.

### §11.4 A guest who stalls CATCHES UP; the show does not wait

This is the consequence that makes it a product decision rather than a
protocol. In "With Friends and the World" the host is ALSO broadcasting to an
audience, and a stalled guest must never be able to freeze what that audience
is watching. So the host's playhead is authoritative, and a guest who buffers
rejoins ahead rather than dragging everyone back.

**That is the opposite of SharePlay's behaviour**, which pauses for the
straggler, and it is right here for a reason that does not apply to SharePlay:
SharePlay has no audience.

### §11.5 The transport, and why not the obvious one

- **NOT Durable Objects / WebSockets.** The natural fit, and it is not on
  Cloudflare's free plan. $0 is a hard constraint (CLAUDE.md), so this is
  settled by the bill, not by taste.
- **NOT Workers KV.** Free-tier writes are ~1,000/day, and worse, KV is
  eventually consistent for up to 60 seconds — which would mean a PAUSE taking
  a minute to reach a guest. Unusable for this.
- **D1 (SQLite) on the Worker that already exists.** Strongly consistent,
  free-tier limits measured in millions of reads and 100k writes a day, and
  this repo already runs a Cloudflare Worker for the privacy counter. The host
  writes on state change; guests poll every ~3 s and extrapolate between polls.
  Four guests over two hours is ~9,600 reads and ~30 writes.

A poll every 3 s sounds crude beside a socket and is exactly right here: the
clients are extrapolating continuously, so the poll is only correcting drift
and catching state changes. The visible cost of a change is at most one poll
interval, and §11.3 absorbs that.

### §11.6 What the owner has to decide

1. **Who may control the film?** Host only (simplest, matches "producing a
   show"), or anyone in the room (friendlier, and a guest pausing a live
   broadcast is a real risk). PROPOSED: host only, because the broadcast makes
   this asymmetric.
2. **Does a room need to exist before the call, or is a link enough?** A link
   carrying the film id and a room id needs no accounts (Decision 009) and no
   server-side room creation. PROPOSED: a link, same shape as
   `docs/PLAYLIST-SHARING.md` already uses.

### §11.7 What would have to be proved before it ships

Not built, and none of this is a measurement yet. In this feature's own terms
(Decision 130) the things that would need to be shown on real devices are: the
clock offset's error bound against a known-good reference; that a 3% rate nudge
closes a 1-second gap without being audible; that a guest on a phone that loses
its network rejoins at the right place rather than at the start; and that the
free tier actually holds for a four-person two-hour film rather than in an
estimate.
