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

> **REMOVED 2026-09-24** (owner: "Delete unused code that you don't think we
> need"). Decision 131 settled guest voice the other way — people use the call
> they already have, and the host's Mac taps it — so no guest voice travels
> through this app, and `StudioVoiceProbe`, `StudioVoiceCodec` and
> `StudioVoiceRoom` (with §8.18-§8.20) were deleted. They remain in git history
> should that ever change. The paragraph below is kept as it was written.

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

### §11.2a NOBODY IS EVER ASKED TO DO ANYTHING

Stated plainly because the wording elsewhere invited the opposite reading:
**every correction in §11.3 is applied by the app, silently, with no prompt
and no instruction to a viewer.** A guest whose host pauses sees the film
pause. They are not told to pause it, and their transport controls are
disabled anyway (§11.6, host-only control).

`StudioSyncClient.correction()` RETURNS a value rather than calling
`pause()` itself, and that is a testing boundary, not a product one: a player
is `AVPlayer` on three platforms, `ExoPlayer` on Android and a `<video>`
element on the web, so a type that knew about any of them could not be
exercised without one. §8.31 proves the whole host-to-guest chain against a
real Worker with no device in the loop precisely because of that split. The
platform layer is a thin caller that applies what it is handed — the same
shape as `StudioCameraStall` and `StudioLayout`, where the rule is a value
and the platform is a caller.

Where this feature DOES address a person, it is deliberate and the owner
chose it: the film ending says so and offers a card rather than throwing one
up, because "the stream should only end when the person streaming it decides
that it should end". That is a HOST decision about their own broadcast. A
guest's playhead is not a decision, it is bookkeeping, and bookkeeping is the
app's job.

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

### §11.6 DECIDED — the host controls the film, and a link is the whole join

*Owner, 2026-09-21: "Given that it is only being streamed from MacOS, I think
the host is the only one that should be able to control start/stop/pausing of
the movie. However, how does the host launch the movie and sync up the other
apps? How does it get triggered (and how does it keep checking)?"*

**1. Only the host controls the film.** Guests' transport controls are
disabled in a room, with a sentence saying why rather than a dead button
(Decision 128's rule). The reason is the audience: a guest pausing the film
pauses what YouTube is receiving, and the person answerable for that broadcast
is the host.

**1a. What that became on Apple and the web (2026-09-23).** The player's own
controls STAY — volume, captions and full screen belong to the guest, and
disabling a native transport is not something `AVPlayerView`, `AVPlayerViewController`
or a `<video>` element can do selectively. Instead a guest's own pause or
scrub is answered AT ONCE (it used to wait for the next poll, up to 10 s)
and the player says, for three seconds, **"The host controls the film."**
That line is one of exactly three a guest ever sees, drawn by
`StudioRoomNotice` on macOS, iOS and tvOS, by `StudioSyncFollower.notice` in
the Android player, and by `#player-note` on the web:
that one; **"The host ended the room."** (the film keeps playing — it is the
guest's now — but they are no longer in step and must be told); and the
join-failure sentence, since a failed join otherwise plays the film alone
and looks like success. Nothing is said while a guest is simply in step.

**2. Launching is one write and one link.** The host is already playing a film
on the Mac. Starting a room writes the first state record and produces:

    https://archivewatch.org/together/#<roomID>-<filmID>

No accounts and no server-side room creation (Decision 009) — the id is random
and the record is created by the first write. The same shape
`docs/PLAYLIST-SHARING.md` already uses, and for the same reason: **it has to
open for somebody with no app at all**, so the web is a real client and not a
consolation.

**3. The call does the inviting, and that is the whole trick.** The host pastes
the link into the Zoom/Meet/FaceTime chat they are already in. The app never
learns who the guests are, never holds an address book, and never sends an
invitation — which is the same move §10 makes with voice, applied to the join.
Everyone on a phone, a television or a browser opens the link and lands in the
film at the host's position.

**4. "How does it keep checking" — and the poll IS the clock sync.** A guest
polls `GET /together/<roomID>` every 2 s. The response carries the state record
AND the server's own time; the client measures the round trip around that same
request. So §11.2's offset estimate and the state fetch are **one call, not
two** — the clock costs no extra traffic at all, and every poll refreshes it.

Between polls the client extrapolates (§11.1), so the poll is only correcting
drift and catching changes. A pause reaches a guest within one interval, and
§11.3's rate-nudge absorbs the rest.

The host WRITES only on a real state change, plus a keep-alive touch every
30 s so a guest can tell a quiet room from an abandoned one. Measured against
the free tier: four guests for two hours is ~14,400 reads and ~270 writes,
against D1's millions of reads and 100k writes a day.

**Backoff, because a still room should cost nothing.** If the record's
`generation` has not moved for a minute, the poll slows to 10 s; any change
snaps it back to 2 s. A film nobody is touching is the common case in a
two-hour watch.

### §11.8 WATCHING ON A DIFFERENT DEVICE FROM THE ONE YOU ARE CALLING ON

*Owner, 2026-09-21: "I think that works if they are joining the call from the
same device that they are watching the movie on. But, how would it work if
they join the call from one location but want to use a different device to
'join' the movie. Is there a way that we could allow for that easily?"*

**Yes, and nothing in §11.1–§11.3 has to change**, which is worth saying
first: the sync layer never assumes the device watching the film is the device
on the call. A room is a record; anything that can poll it can be in it. The
only thing missing is a SECOND DOOR into the room, because a link opens on the
device that receives it.

**The second door is a spoken code.** The room carries a short,
human-pronounceable code — **four** Crockford Base32 characters (the alphabet
drops I, L, O and U; a mistyped I or L becomes 1 and a mistyped O becomes 0,
so every spelling a listener might produce reaches the same room) — shown
wherever the host started it and on any joined device.

    Watch Together ▸ Join a room ▸  C A 1 1

That is deliberately not a link and not a QR. **You are already on a call with
these people**, and the cheapest transport for six characters between humans
who are talking to each other is talking. "The code is CALIG7" needs no
copy-paste, no second screen, and no way to mis-send it — and it is the same
insight §10 and §11.6 already rest on: the call is carrying things for us, so
let it.

This is also a pattern this project has already settled. Decision 119: *a
television hands over a link as a CODE* — because typing a URL with a remote
is miserable and a short code is not. The same reasoning, in the other
direction.

**What it means in practice**: a guest is on Zoom on their laptop, hears the
code, and types it into Archive Watch on their Apple TV. Their laptop is not
in the room at all — it is only carrying voice. The television polls the room,
extrapolates, and stays in step with everyone else. The two halves of "With
Friends and the World" are on two different devices for that person, and
neither half knows or cares.

### §11.9 FOUR CHARACTERS, AND WHERE "JOIN A ROOM" GOES ON EACH PLATFORM

*Owner: "Do we need a 6 digit code or could we get away with 4 (shorter is
easier)? Can we build that out on every platform with a logical place to put
it (Settings? Library?)"*

**Four.** The risk is not how many codes exist, it is the chance a random
guess lands on a room somebody is actually in:

| live rooms | 4 chars | 6 chars |
|---|---|---|
| 10 | 1 in 104,857 | 1 in 107,374,182 |
| 1,000 | 1 in 1,048 | 1 in 1,073,741 |
| 10,000 | 1 in 104 | 1 in 107,374 |

A free archival-film app has single-digit concurrent rooms, and one keystroke
fewer on a remote is worth more than headroom nobody will use. **The threshold
is ~1,000 concurrent rooms**; past that this becomes 5 or 6, and it is one
constant (`StudioRoom.codeLength`). Two things keep the live set small and are
not optional: a code is checked against LIVE rooms when issued, and a room
expires when its host stops.

AirPlay and Chromecast use four DIGITS because they are scoped to a network or
to proximity. These rooms are global, which is why the alphabet is 32 wide
rather than 10 — four Base32 characters carry as much as six digits.

### §11.10 JOINING IS NOT HOSTING — an amendment to Decision 132

**Decision 132 gates the Watch Together entry on
`canHostWatchTogether()` — a camera AND a microphone — and that rule is right
for HOSTING and wrong for JOINING.** A television has neither and is the BEST
device to join from: it is the big screen in the room, and the owner's own
case is a guest on a call on their laptop who wants the film on the TV.

So the gate splits:

| | needs a camera + mic | why |
|---|---|---|
| **Host a show** | yes (Decision 132 unchanged) | "a broadcast with no camera and no microphone is not watching together" |
| **Join a room** | **no** | a joiner contributes nothing to the programme; they are watching in step |

This does not weaken Decision 132's reasoning, it scopes it. Its sentence was
about a HOST offering a broadcast nobody is in. A guest on a television is in
somebody else's show, and the conversation is on the call they are already on.

**Where the entry goes**, and the rule is that it is a PEER of watching, never
a setting:

| platform | place |
|---|---|
| **macOS** | the existing **Watch Together** sidebar section — a "Join a room" button beside "Open the Studio" |
| **tvOS** | a **Watch Together** sidebar row. The most likely joining device in the house deserves a visible one, not a Settings page |
| **iOS / iPadOS** | the Watch Together row on the Library/More surface, per `iOS-DESIGN` |
| **Android phone** | beside the existing Watch Together entry |
| **Google TV / Fire TV** | a sidebar row — newly ALLOWED by §11.10 above, where Decision 132 had removed the entry entirely |
| **web** | the link, and a **Join a room** entry on Library opening a code field on `/together/` (built 2026-09-25) |
| **Roku** | a menu row; codes are why Decision 119 exists on this platform |

**NOT Settings.** Settings is where you change how the app behaves; joining a
room is a thing you DO, and burying it would repeat the mistake the owner
already caught with the Studio ("it seems to lack the ability to set a
destination... it just starts playing the movie").

**The entry field** is four characters, uppercased as typed, with the
confusable mapping applied live so a host reading "oh" and a guest typing O
never diverge. On tvOS it is focus-driven (Rule 8.8's ten-foot constraints),
and the host's own code is displayed large enough to read aloud across a room.

**A QR stays worth having** for the one case a code is worse at: a phone
joining from a television that is already in the room. The encoder exists
(Decision 119) and the payload is the same join URL.

**And a QR stays worth having for the one case a code is worse at**: a phone
joining from a television that is already in the room. The QR encoder exists
(Decision 119) and the payload is the same join URL.

### §11.11 The transport, WRITTEN and NOT DEPLOYED (2026-09-21)

`worker/src/together.js` + `worker/schema-rooms.sql`. It goes into the Worker
that already exists for the privacy counter, on the D1 that is already bound
to it — **the sync transport needs no infrastructure of its own**, which is
most of why it fits the $0 constraint rather than merely being cheap.

Three routes and one table:

    POST /together/new      → { code, serverTime }
    GET  /together/<code>   → the state record + the server's own clock
    POST /together/<code>   → the host publishes; { end: true } deletes

**Deliberate, and each would be easy to get wrong:**

- **The GET returns `serverTime` in the same response as the state.** The
  client measures the round trip around that one request, so §11.2's offset
  estimate costs no extra traffic — the poll IS the clock sync. A separate
  time endpoint would double the request count for nothing.
- **The generation is bumped by the SERVER**, never sent by the client, so two
  hosts cannot disagree about it and a client cannot freeze it by sending the
  same number twice.
- **A code is checked against LIVE rooms before it is issued** (insert, catch
  the UNIQUE violation, retry). This is one of the two things that make four
  characters safe rather than merely short — the risk is a guess landing on a
  live room, so the live set is what has to stay small.
- **Ending a room DELETES it.** A room that lingers is a row saying what
  somebody watched, and nothing here may outlive the watching — the same
  posture as the counter sitting beside it. Stale rooms are swept on read.
- **Nothing about people is stored**: no account, no id, no IP, not even a
  count of who is in the room. A row says what the film is doing, and the only
  way to see it is to know a code somebody read to you.

**§8.29 asserts the Worker and the app normalise a code IDENTICALLY.** Two
implementations of one rule is the classic way this breaks: if Swift maps a
heard "oh" to 0 and the JavaScript does not, a guest who types what they heard
reaches a different room, and the failure reads as "the code doesn't work"
with nothing to point at.

**PROVED AGAINST A RUNNING WORKER, NOT JUST PARSED** (§8.30, 20 assertions).
`wrangler dev --local` with a real D1 behind it, driving the real HTTP:

- a room is created, read back, updated and ENDED, and ending it makes the
  room **404 rather than flagged** — a room that lingers is a row saying what
  somebody watched;
- an archive id full of dashes survives the round trip;
- `atServerTime` comes back in SECONDS — a unit change at the boundary is how
  a sync bug gets written;
- **a code typed the way it was HEARD reaches the same room**: the generated
  code's 1s and 0s retyped as I and O resolve to the same row, which is the
  whole point of §11.8 and the one thing two implementations could disagree
  about;
- the SERVER owns the generation — a client sending `generation: 12345` is
  ignored and the row advances by one — with a control asserting a second
  write advances it again, since a constant would otherwise satisfy it.

**DEPLOYED 2026-09-21**, on the owner's say-so. The table was created with
`d1 execute --remote` and the Worker shipped with `wrangler deploy`.

**THE WORKER IS NOT ON archivewatch.org, and every client had that wrong.**
That host is GitHub Pages; the Worker answers at
`archivewatch-pulse.benwilkoff.workers.dev`, which is where the privacy
counter has always posted (`AW_BEACON_ORIGIN` in watch.js). The Swift, Kotlin
and browser clients were all pointed at the site, which would have reached
Pages and 404'd on every route — caught by looking at what is actually
deployed rather than at what the name suggested, and not by any test, because
all of them pass a base URL in.

Smoke-tested against the LIVE Worker, including the thing sharing the
deployment:

    the privacy counter still answers          HTTP 204
    a room is created                          {"code":"R0JX","hostKey":…}
    it reads back with the server's clock      generation 1
    a guest with only the code tries to write  HTTP 403
    the host writes with the key               HTTP 200
    the host ends it                           {"ended":true} → 404

And the app clients against that same live Worker: §8.31 (Swift) and §8.33
(Kotlin) both pass end to end — a host opens a room, a guest joins BY THE
CODE AS HEARD, the host pauses, and the guest's player is told to pause.

### §11.12 WHAT TIDBITS TRIVIA ALREADY KNEW (2026-09-21)

*Owner: "Is there anything we can learn from the way that we build Tidbits
Trivia rooms that keep everyone in sync across platforms?"*

Yes, and one of the three was a real hole in this design.

**1. A code that is read aloud cannot also be the credential.** Tidbits
separates a 4-letter room CODE from a 6-digit PIN, and says why on its own
screen: *"The PIN is on the host screen, not the projector — the room code
alone cannot drive the show."*

**A CORRECTION TO A FIRST READING OF THIS, from the owner: "The host is the
only one that moves the room on Tidbits. The projector is just a different
surface."** That is right, and the first version of this section implied
otherwise — it read as though Tidbits had guests who might otherwise drive
the show, and the PIN existed to stop them. It does not. Tidbits has ONE
host and several SURFACES: a laptop that runs the show, a projector that
displays it, and a phone acting as the host's own remote. The PIN
authenticates the host's OTHER DEVICE, and it exists because the code is on
a projector where a roomful of people can read it.

The security property is the same either way, and is what carried across:
**being able to SEE the code must not be the same as being able to drive.**
Whether the person who sees it is a guest or a stranger in the room is not
the point; the point is that a credential displayed on a wall is not a
credential. What was wrong was the role structure, not the lesson.

Archive Watch had exactly that hole. §11.6 decided hosts alone control the
film and **the transport enforced nothing**: any guest who heard a code could
POST a pause to somebody's live broadcast. `POST /together/new` now returns a
`hostKey` alongside the code — returned ONCE, to the creator, never by a read
— and every write requires it. §8.30 asserts a guest with the code and no key
is refused, a wrong key is refused, the room is unchanged by the attempt, and
a GET never carries the key.

Ours is a long random token rather than six digits, because no human ever
types it: only the host's own app holds it. Tidbits needs a TYPEABLE PIN
because the host drives from a second device and has to enter it there; our
host drives from the machine that made the room, so the key never has to
leave it.

**That difference is worth keeping in view**, because it names a thing we
have not built: a host's own second surface. In Tidbits the phone-as-remote
SENDS verbs, which is why it needs the PIN. In Archive Watch a host's second
device would only FOLLOW, which is indistinguishable from a guest joining —
so nothing is needed today. If a host ever wants to drive the film from
their phone while the Mac produces the broadcast, the key is what that
device would need, and it would have to become typeable or transferable.

**2. Four characters, independently arrived at.** Tidbits' rooms are
4-letter codes with a 4–8 character rule in its database rules. §11.9 reached
four from the guess-odds table. Two apps, the same answer, for the same
reason: it gets read aloud.

**3. Firebase gives PUSH where we poll — and we are not taking it.** Tidbits
uses Firebase Realtime Database with anonymous auth and live listeners, so a
change reaches every device immediately rather than within a poll interval.
That is genuinely better for latency, and it is the right choice THERE: a
trivia round is a fast, turn-taking game where a two-second lag is the whole
experience.

It is the wrong choice here, for reasons that are about this project rather
than about Firebase:

- **Decision 127**: this project ships zero third-party packages,
  deliberately, and Firebase means an SPM dependency on three Apple platforms
  and a Gradle one on Android — a second concurrency model and an upstream we
  do not control, in a Swift-6-strict project.
- **A film is not a trivia round.** What we sync is play, pause and seek —
  tens of events in two hours. §11.3 already absorbs a poll interval with a
  3% rate nudge that nobody can see. Tidbits cannot absorb latency that way
  because its state changes *are* the experience.
- **The counter is already there.** D1 on the existing Worker costs no new
  infrastructure, which is most of why this fits $0 rather than merely being
  cheap.

**Worth revisiting if** a mode ever needs sub-second agreement — a shared
scrub bar, say, or reactions. Firebase RTDB also has a REST + server-sent
events interface usable from plain `URLSession` with no SDK at all, which
would be the way in if that day comes.

### §11.13 ROOMS EXIST TO SERVE A LIVE STREAM, and a surface says only what THIS device can do

*Owner, 2026-09-21, answering whether a plain room should be hostable
everywhere: "I think it really only makes sense for people to coordinate calls
across platforms for the purpose of a live stream. I don't want to confuse the
issue, so let's make it super clear what 'Watch Together' means on each
platform (to the user). You shouldn't advertise features that don't exist on
the platform you are currently on, but you should definitely be able to share
what the current platform can do."*

**So hosting stays where the broadcast is.** A room hosted with no broadcast
would be cross-platform "With Friends" by another route, and that is a fourth
thing wearing a name Decision 131 binds. It is not built and should not be:
the room exists so the people in a call can watch in step with a show that is
going out, and without the show it is a different product.

**And this SHARPENS Decision 131.** 131 said a surface must state which of the
three a device can do *and why it cannot do the others*. The owner's rule is
narrower and better: **do not put a feature in front of somebody who cannot use
it.** An explanation of something unavailable is still an advertisement for it,
and on a device that will never gain the hardware it is a list of things this
box is worse at. 131's reasoning still holds for a capability a device COULD
have and currently lacks — an unconfigured sign-in, a camera not yet permitted
— which is Decision 128's rule and unchanged.

**`WatchTogetherHere` is the mechanism, and it is a TYPE rather than a
paragraph per platform.** Five surfaces each describing the feature in their
own words is five chances to promise something that is not there. A surface
asks what is true and renders only that:

| | With Friends | With the World | …and the World | Join a room |
|---|---|---|---|---|
| macOS | ✅ | ✅ | ✅ | ✅ |
| iOS | ✅ | ✅ | 🚫 no process tap | ✅ |
| tvOS | 🚫 no `GroupActivitySharingController` | ✅ via a Continuity iPhone | 🚫 | ✅ |
| Android, web, TV boxes | 🚫 | 🚫 | 🚫 | ✅ |

The 🚫 rows are what the TABLE records; they are what a surface must NOT say.
A television's Watch Together screen now opens with what an Apple TV can
actually do and never mentions the two it cannot.

### §11.14 THE HOST CHOOSES THE COPY (2026-09-26)

Owner: *"The host chooses the video that all Watch Together participants
should be watching. There should be no way to choose the wrong one via the
four digit code."*

A room carries `copy`, `<archive item>/<file name>` — the exact file the
host's player is showing — beside `filmID`. Every guest plays THAT file: the
Worker stores it (`normalizeCopy`), and each platform builds
`https://archive.org/download/<item>/<file>` itself from the same rules
(Swift `StudioRoomCopy`, Kotlin `StudioRoomCopy`, web `Together.copyURL`), so a
room can never send a guest's player anywhere but archive.org.

**Why it matters, measured**: one title can hold several copies — its own
item's transfers and, since Decision 040 merges re-uploads, other uploads'
files — and they are not the same length (Keaton's two Scarecrows are 55 s
apart). A guest syncing to the host's POSITION on another copy is on another
timeline, and every correction lands on the wrong frame.

**How it is enforced**: every Apple and Android player chooses its file through
`ArchiveVersions.preferredURL`, and that answers the room's copy first while
the device is in a room for that film — over the viewer's own saved choice, and
a downloaded file of another copy is skipped. A host that predates `copy` gets
the title's DEFAULT copy, never the viewer's choice. Every join entry point
(join screens, room links, the debug doors) reads the room BEFORE the player is
built (`prime`), and the pickers say *"In a Watch Together room, the host
chooses the copy."* (Mac, iPhone, Android sheets) or are hidden (tvOS, the
in-player menus). The web plays `Together.copyURL(state.copy)`.

**Proved**: the live Worker refuses a URL to another host, a `..` escape and a
guest's write (403) and keeps the copy through an update that omits it; the web
guest played the host's non-default copy and stayed within 0.07 s of the room,
while the SAME test against the live site without this change played the
title's default and failed (the control); the Mac guest, given a conflicting
saved choice of its own, logged `AWROOMCOPY TheScarecrow1920 plays the room's
copy …/the-scarecrow/The%20Scarecrow.mp4` and synced. Roku has no room surface
yet (PARITY), so it has nothing to enforce.

The copy is set when the room opens; a host who changes copy mid-room is not
yet followed by guests (the Mac host's player is rebuilt by such a change and
the room was never carried across it either).

### §11.7 What would have to be proved before it ships

Not built, and none of this is a measurement yet. In this feature's own terms
(Decision 130) the things that would need to be shown on real devices are: the
clock offset's error bound against a known-good reference; that a 3% rate nudge
closes a 1-second gap without being audible; that a guest on a phone that loses
its network rejoins at the right place rather than at the start; and that the
free tier actually holds for a four-person two-hour film rather than in an
estimate.
