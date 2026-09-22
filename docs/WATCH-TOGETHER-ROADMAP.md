# Watch Together Studio — what to build next

*Written 2026-09-22 from the owner's ask: "research OBS/StreamYard features
(particularly those available on MacOS) that match well with the scope we are
trying to tackle in the Watch Together studio (multiple video and audio feeds,
more sophisticated scene switching, etc) and then put together a work list."*

This is a PROPOSAL list, not a plan of record. Nothing here is built. Items
marked **OWNER** need a decision before any code, because they cross a rule
this project wrote down deliberately.

---

## 0. The baseline, so nothing here re-proposes what exists

| | state |
|---|---|
| Video feeds | film + ONE camera. Five placements (Rule 8.8e) + host framing (tile rect, zoom, pan — macOS only, §D14a) |
| Audio feeds | THREE — film (`MTAudioProcessingTap`), microphone, and a named app's audio (`AudioHardwareCreateProcessTap`, proved on Chrome 2026-09-22). Per-channel fader, mute, meter; one auto-duck |
| Overlays | lower third (3 toggleable lines), 4 cards (3 fixed + free text), Twitch chat |
| Output | ONE RTMP destination. Size / fps / bitrate; hardware encoder |
| Preview | FILM and STREAM panes, the stream drawn from the engine's own buffer |
| Sync | rooms (§11) — joining on 7 surfaces, hosting on macOS |

**§D0's standing refusals** — scenes as a general graph, filters and effects,
recording to disk, transitions. Two of the four are revisited below, because
the owner's ask names things that touch them; the other two still look right.

---

## 1. THE BIG ONE — guests' faces, with no relay and no running cost

**Capture the call app's WINDOW with ScreenCaptureKit, beside the audio we
already tap from it.**

Decision 131's third mode ("With Friends and the World") is the one that
dissolves a problem rather than solving it: people use the call they already
have, and the app never carries guest voice — so no relay, no NAT traversal,
no monthly bill. We already capture that call's AUDIO and mix it as a third
channel. **What is missing is the picture, and macOS hands it over:**
`SCContentFilter(desktopIndependentWindow:)` captures exactly one window as a
live stream, independent of which display it is on
([Apple](https://developer.apple.com/documentation/ScreenCaptureKit/capturing-screen-content-in-macos),
[WWDC22](https://developer.apple.com/videos/play/wwdc2022/10155/)).

So the Zoom/Meet/FaceTime grid — the same thing the host is looking at —
becomes a source. That is StreamYard's whole guest experience, reached from
the opposite direction and for nothing.

- **Cost**: medium. SCK stream → `CVPixelBuffer` → the existing compositor,
  which already takes a second video source (the camera). The layout work is
  the real cost: a fourth arrangement ("film, you, and your guests").
- **Rule needed**: yes — Rule 8.8e names five placements and none of them has
  a guest tile. A new §D rule, and PARITY's "what Watch Together MEANS"
  table changes for macOS.
- **Unknown**: Screen Recording TCC for a signed, sandboxed app. Exactly the
  shape of the process-tap question, which we just answered by measuring
  rather than arguing — same method applies.
- **Watch out**: SCK's audio capture is app-level even with a window filter,
  so it would capture the same audio our process tap already does. Keep the
  process tap for sound and use SCK for picture only, or the call arrives
  twice.

## 2. Simulcast — **BUILT 2026-09-22, proved on the wire**

*Status: engine, session and macOS surface done; §8.37 publishes one encode to
two destinations and reads both recordings back —
`h264,640,360 | aac` on each, the same 151 video frames, zero dropped.*

**The design decision worth knowing.** The PRIMARY destination keeps its
meaning: it drives `showState`, §6.6's reconnect and §6.4's back-pressure,
which are rules written against one connection. Extras are BEST EFFORT — a
`try` above and a `try?` with a recorded reason below — because a dead Twitch
must not end a healthy YouTube broadcast. A failing extra is visible (it has
its own named health row) and ends nothing.

**And the feature says what it costs.** Two destinations is twice the upload,
and the readout says so in Mbps before the host presses Go Live, turning
orange when the total exceeds what this connection has actually held. That is
not hypothetical: the owner's line measured 68.3 Mbps down but 854 ms
responsiveness under load, with Twitch dropping at ~4.2 Mbps.

Original entry follows.

## 2-orig. Simulcast — one encode, several destinations

StreamYard's headline is 8 destinations at once; OBS 31 added WebRTC
simulcast. **We own the RTMP publisher**, so this is N publishers fed from one
encoder rather than N encodes: the expensive half (composite + H.264) is
already done once.

- **Cost**: small-to-medium. `StudioEngine` holds one `RTMPPublisher`; make it
  a list, fan the same encoded frames out, and aggregate health per
  destination. The go-live sheet gains a multi-select.
- **Rule needed**: small — §4's health rule means the readout must say which
  destination is struggling, not an average.
- **Honest limit**: this is UPLINK-bound. The owner's line measured 68 Mbps
  down but 854 ms responsiveness under load, and Twitch drops appeared at
  ~4.2 Mbps from bufferbloat. Two destinations at 6 Mbps is 12 Mbps up. The
  feature should SAY that, and default to warning when asked for more than the
  measured headroom.

## 3. YouTube chat on the program — **BUILT 2026-09-22, unproven on air**

*Status: code complete on macOS, iOS and tvOS; §8.36 guards the chain. What is
NOT done is a real broadcast with a real audience typing — the reader has
never seen a live `liveChatId`.*

**The reason it was missing turned out not to be the work.**
`YouTubeLive.chat(liveChatID:pageToken:)` has been written, complete and
correct, since the platform layer was built — it lists the messages, maps
them, and returns YouTube's own `pollingIntervalMillis`. **Nothing ever called
it**, and the `liveChatId` it needs was read out of `liveBroadcasts.insert`
into `StreamCredentials` and then dropped, because
`StudioGoLive.destination()` returned a bare `URL?`. The id was read and
discarded inside one function.

That is Decision 133 in its purest form — a value proved where it is WRITTEN
rather than where it LANDS — and no unit test could catch it, because both
ends pass on their own and only the chain fails. §8.36 checks the chain at
every link on every platform that can go live, and was verified by reinstating
the bug on one surface and watching it go red.

`broadcastID` was being dropped in the same breath, which is why `complete()`
has never been called. It is now carried too, and is the next small thing:
a host who ends a show leaves the YouTube broadcast open behind them.

Original entry follows.

## 3-orig. YouTube chat on the program

We render chat already (`StudioOverlay.chat`, a cached column) and read only
**Twitch**. YouTube is where these broadcasts have actually gone out, and we
already hold a YouTube OAuth token with `…/auth/youtube`.

- **Cost**: small. `liveChatMessages.list` polling, mapped onto the existing
  `ChatLine`. The renderer needs nothing.
- **Rule needed**: none — §2.2's participation argument already covers chat.
- **Why it is high value for THIS product**: the audience answering is the
  thing that makes a watch-along a shared event rather than a broadcast. It is
  the clearest learning-orientation win on this list.

## 4. Microphone conditioning — **GATE BUILT 2026-09-22**

*Status: the gate ships on macOS (§D15a, §8.38). Noise SUPPRESSION — spectral,
the other half of what OBS offers — is not built and is a bigger question:
macOS's voice-processing unit wants to own the whole input chain, which
conflicts with the tap this Studio already installs.*

The gate is off by default, the meter stays raw so a closed gate cannot be
mistaken for a dead microphone, and a gated microphone does not duck the film
— without that last one the gate would fix the echo and pull the soundtrack
down 12 dB for the whole show instead.

Original entry follows.

## 4-orig. Microphone conditioning — a noise gate and suppression

OBS ships per-source audio filters (noise gate, noise suppression, gain,
compressor). We have gain and a duck and nothing else. **The case for it here
is specific**: a host is in a room with a film playing out of speakers, so
their open microphone is picking the film up and feeding a mixed copy back
into the program.

- **Cost**: small-to-medium. macOS has voice-processing audio units; a gate is
  a few lines against the RMS we already compute per block.
- **Rule needed**: a line in §D3 — a gate that closes must be VISIBLE on the
  meter, or a host will think the microphone died.
- **Do NOT take the rest of OBS's filter set** — §D0's refusal of chroma key
  and LUTs still holds. This is not "filters"; it is making one input usable.

## 5. Staged changes — OBS's Studio Mode, our way

OBS splits into preview and program so a host can stage a change and then push
it live. Our two panes are FILM and STREAM, and STREAM is already live — there
is no staging.

- **What is actually worth staging here**: a CARD and a LAYOUT. "Get the
  intermission card ready, then take it" is a real moment; "stage a new scene
  graph" is not, because we have no scene graph (§D0).
- **Cost**: small. A pending card/layout plus a TAKE button.
- **Rule needed**: yes, and it is the interesting one — §D5 says the preview
  IS the program, precisely so what the host sees cannot diverge from what is
  sent. A staging area deliberately reintroduces divergence, so it has to be
  labeled hard. Probably a third small pane rather than changing STREAM.
- **Verdict**: worth doing AFTER 1–4. It is polish on a feature set; 1–4 are
  the feature set.

## 6. Hotkeys — **BUILT 2026-09-22**

*Status: a top-level **Broadcast** menu on macOS, verified on the glass —
every item present, every shortcut printed, every title reflecting live state.*

Eleven commands: the Studio and Go Live (moved here from File), start/stop the
preview (⇧⌘P), end the broadcast (⇧⌘E), mute the microphone (⇧⌘M), the duck
(⇧⌘D), the lower third (⇧⌘T), five cards (⌃⌘0–4) and five placements.

**A menu rather than a global hotkey, deliberately.** A menu key equivalent is
discoverable, prints its own shortcut beside it, needs no permission and
cannot collide silently with another app. A system-wide hotkey needs
Accessibility TCC and works when Archive Watch is not frontmost at all — a
real difference, and a bigger ask. These fire whenever ANY Archive Watch
window is front, which is the case this item actually named: a host looking at
the player rather than the Studio.

**This overturns Rule B13g's "inventing a menu is the larger claim"**, and the
reasoning holds in reverse: that was right when there was one command, and
with eleven, hiding them under File beside "New Project" is the larger claim.

**States are honest.** "Start the Preview" and "End the Broadcast" are
disabled with no film and no show; "My own words" is disabled until the card
has words, because §D10 says an empty custom card is never shown and a key
that raises nothing is worse than a key that is grey. Toggle titles say what
pressing them will DO — "Stop Ducking the Film" when ducking is on.

Original entry follows.

## 6-orig. Hotkeys

OBS's most-used feature by a distance, and we have none. Mute the microphone,
raise a card, switch placement, end the show — all while the Studio is not the
front window.

- **Cost**: small. `NSEvent` global monitor or a menu with key equivalents.
  The menu route is better: discoverable, and it documents itself.
- **Rule needed**: none. macOS-native and §B13g already put commands in menus.

## 7. Screen or window as a source, generally

Beyond the call window (#1) — sharing a slide, a map, a second film. For a
watch-along this is the thinnest item on the list: the film is the picture.

- **Verdict**: fall out of #1 for free, expose it only if asked for.

---

## Mobile — quick wins, in cost order

The phone is where Watch Together ships on the most devices, and its Studio
controls have fallen behind the Mac's in ways that are cheap to close. None of
these need a new rule; all of them are parity.

| # | item | cost | note |
|---|---|---|---|
| M1 | **Camera framing by pinch and drag (iOS)** | **small** | `StudioCameraFraming` is already shared Swift and the engine already honours it — the Mac needed an `NSEvent` monitor and hit-test archaeology to get scroll-to-zoom, and a phone gets pinch and drag for free as standard gestures. This is the cheapest high-value item on either list |
| M2 | Lower-third line toggles (iOS, tvOS) | small | §D15's three toggles; iOS still has the old single "Show the film's title" |
| M3 | The free-text card (iOS) | small | The ENGINE carries `Card.custom` on every Apple platform; only the editor is macOS-only. A phone keyboard is a fine place to type four lines |
| M4 | "This film has no soundtrack" (iOS, tvOS, Android) | small | §D16. Most of what the rights gate clears is silent-era, and only the Mac says so |
| M5 | "Levels appear once you start" (iOS) | small | §D16's other half — three dead meters read as a broken mixer |
| M6 | Camera / microphone pickers (iOS) | small | `StudioDevices` is shared and iOS calls none of it. A phone has front, back, ultra-wide and a Continuity mic |
| M7 | Android: the free-text card | medium | Android's `Card` is a separate Kotlin enum without the case; `StudioCardTest` pins the words across languages, so this is a real port |

**A deliberate non-item**: the Mac's drag-handle box does not port. A phone
should use pinch and drag (M1), and a television should not have this at all —
Rule 8.8c keeps that surface to two channels and a rotation.

---

## What we still refuse, and why it is not an oversight

- **Scenes as a general graph** (§D0). OBS needs them because it knows nothing
  about your content. We know there is a film, a host, guests and a card.
- **Filters and effects** (§D0). #4 is one input made usable, not a chain.
- **Transitions** (§D0). A stinger between "film" and "film with a face in the
  corner" is motion for its own sake.
- **Recording to disk** (§D0) — **OWNER**. StreamYard's multi-track local
  recording is genuinely useful and it turns a viewing app into a thing that
  makes copies of public-domain films. That is a Decision 027 rights posture
  call, not an engineering one. Worth noting the narrow version: recording the
  HOST'S OWN camera and microphone tracks, never the film, would give most of
  the post-production value and make no copy of anything archival.
- **Guests joining by link** (Decision 131). StreamYard's model needs a media
  server. Ours reaches the same place through the call people are already on,
  which is the only reason this feature costs $0 to run.
- **Virtual camera**. Being an input to Zoom inverts the product: the Studio's
  job is to broadcast a film, not to be a webcam.

---

## Suggested order

1. **#3 YouTube chat** — smallest, and the one that most changes what a
   broadcast feels like for the people watching.
2. **#2 Simulcast** — small change to a part we own, visible value.
3. **M1 + M2 + M4 + M5** — a mobile sweep; all small, all parity.
4. **#4 Microphone conditioning** — makes the existing thing usable.
5. **#1 Guests' faces via ScreenCaptureKit** — the biggest, and the one that
   finishes a feature the project has been circling for a year.
6. **#6 Hotkeys**, **#5 staged changes** — polish.

Sources:
[OBS sources guide](https://obsproject.com/kb/sources-guide) ·
[OBS Studio overview](https://github.com/obsproject/obs-studio/wiki/obs-studio-overview) ·
[StreamYard multi-guest](https://streamyard.com/blog/best-streaming-software-for-multi-guest-interviews) ·
[ScreenCaptureKit](https://developer.apple.com/documentation/ScreenCaptureKit/capturing-screen-content-in-macos) ·
[Take ScreenCaptureKit further (WWDC22)](https://developer.apple.com/videos/play/wwdc2022/10155/)
