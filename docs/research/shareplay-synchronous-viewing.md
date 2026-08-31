# SharePlay / synchronous viewing on Apple platforms — feasibility

*Researched 2026-08-31 against the **27.0 SDKs** shipped in Xcode-beta. Every
API claim below was read out of the installed SDK headers and swiftinterfaces,
not from memory or from documentation prose. Nothing has been run on a device.*

**Verdict: feasible, and unusually well-suited to this app.** The one thing that
killed AirPlay here does *not* kill SharePlay, and Apple documents the exact
workaround for our architecture. Estimated v1: a few days, not weeks.

---

## 1. What the SDK actually provides

| API | tvOS | iOS | macOS | Source |
|---|---|---|---|---|
| `GroupActivities` framework | 15+ | 15+ | 12+ | present in all three 27.0 SDKs |
| `GroupActivity.activate()` / `prepareForActivation()` | **15+** | 15+ | 12+ | `GroupActivities.swiftinterface` |
| `AVPlayerPlaybackCoordinator` | **15+** | 15+ | 12+ | `AVPlaybackCoordinator.h` |
| `AVPlaybackCoordinator.coordinateWithSession(_:)` | yes | yes | yes | GroupActivities extension, line 763 |
| `AVPlaybackCoordinationMedium` | 26.0+ | 26.0+ | 26.0+ | `AVPlaybackCoordinationMedium.h` |

Our deployment targets are tvOS 26 / iOS 26 / macOS 26, so **everything needed
is available with no availability gymnastics.**

### A correction worth recording

`AVPlaybackCoordinationMedium` is new in 26 and looks like the headline feature
for "watch together". **It is not.** Its own header says it coordinates
*local* players and that it is mutually exclusive with a group session:

> "The playback coordinator can either only coordinate with local players
> through an AVPlaybackCoordinationMedium or coordinate with a remote group
> session through the `coordinateWithSession` API."

So cross-device watching still goes through GroupActivities. The Medium is for
synchronising two players *in one app* (multi-angle, PiP-alongside, a
comparison view). Useful someday; not this.

---

## 2. The blocker that isn't: our custom resource loader

Decision 051 established that **video AirPlay is unsupported with a custom
`AVAssetResourceLoaderDelegate`**, and every path in this app is loader-backed
(Decision 072): `ResilientStreamLoader.makeAsset(for:)` rewrites every http(s)
URL to the private `aw-stream` scheme and attaches the delegate.

The reasonable fear is that playback coordination dies the same way. It does
not, and the reason is explicit in the delegate's own documentation:

> `playbackCoordinator:identifierForPlayerItem:`
> "Implementing this method allows the coordinator to establish identity of two
> items created from different URLs, **e.g., because one participant is using a
> local cache and the other a remote URL.**"

That is precisely our case — our item is created from `aw-stream://…` while a
peer's may be `https://…`, or a different archive.org copy entirely. We return
the **`archiveID`** and the coordinator treats the items as the same content.

The deeper reason the two features differ: AirPlay hands the *media* to a
receiver that must fetch the URL itself, which a private scheme makes
impossible. Coordination only exchanges **rate and time**; every participant
loads its own asset locally, through whatever loader it likes.

**Status: inferred from Apple's documented contract, not yet proven on
hardware.** It is the single most important thing to verify first (§6).

---

## 3. Why this app fits SharePlay unusually well

Most media apps struggle with SharePlay's requirement that *every participant
can access the content*, because of entitlements, DRM and regional licensing.
Archive Watch has none of that: the catalog is **public domain, served by
archive.org, identical for everyone, no account, no DRM**. If a peer has the
app, they can play the film. There is no access check to write.

Two further fits fall out of the API for free:

- **Stalls are a first-class concept.** `AVCoordinatedPlaybackSuspensionReason`
  includes `StallRecovery`, and the coordinator has a waiting policy
  (`suspensionReasonsThatTriggerWaiting`). Given Decisions 021/031/034/077 —
  archive.org stalls are our permanent reality — this is the difference between
  "one person buffers and everyone drifts" and "the group waits, then resumes
  together." We would begin a suspension where we currently rebuild.
- **Channels commercials are interstitials.**
  `interstitialTimeRangesForPlayerItem` plus
  `AVCoordinatedPlaybackSuspensionReasonPlayingInterstitial` map exactly onto
  the vintage-commercial breaks woven into Channels. A participant can either
  be waited for or catch up. That is a v2 prize, not v1 scope.

---

## 4. Learning-orientation test (CLAUDE.md gate)

1. **Deepens understanding?** Yes, if built right. Watching a Poverty Row noir
   *with someone* and arguing about it is how a repertory house actually
   teaches; the conversation is the pedagogy. Keep the Detail context (cast,
   year, provenance) reachable during a shared session rather than shipping
   bare synced pixels.
2. **Invites participation?** Strongly. The viewer chooses the film, chooses
   the people, and shares transport control. This is the most genuinely
   participatory feature the app could ship, and it is the literal reading of
   CLAUDE.md's "connect more meaningfully".
3. **Supports agency?** Yes — it lets people do something they already want to
   do across distance, and decides nothing on their behalf. **Guardrail: no
   "people you might watch with", no algorithmic matchmaking.** Identity stays
   in Apple's FaceTime/Messages layer where the user already controls it.
4. **Clarity over cleverness?** Only if we take the boring path: adopt
   `GroupActivity`, attach `coordinateWithSession`, implement one delegate
   method. **Reject** hand-rolling sync over `GroupSessionMessenger`, and
   **reject** coordinating our caption engine across devices (§5).

Passes all four, with those two guardrails written down.

---

## 5. Real integration work, in order of risk

1. **The scout player must never be coordinated.** Live captions run a *second,
   muted* AVPlayer ahead at 2x (Decisions 058/069/072) — `makeAsset` already
   knows it as `subordinate: true`. Only the main player attaches to the
   session. Coordinating the scout would drag the group to 2x or deadlock it.
   Captions should be generated **locally per participant**, never synced.
2. **Player rebuilds must re-attach.** Decision 077 lets a stalled film fall
   back to a different copy within 30s, and the caption work rebuilds players.
   A rebuilt `AVPlayer` brings a new coordinator: it has to be re-attached to
   the session, and `identifierForPlayerItem` must keep returning the same
   `archiveID` so the group still considers it the same film. Our identifier
   choice already survives a copy swap — that is lucky, and worth not breaking.
3. **Stall handling becomes a suspension.** Today we rebuild; under coordination
   we should `beginSuspensionForReason:StallRecovery` and end it on recovery,
   so peers wait rather than drift.
4. **Entitlement + capability.** Group Activities requires the
   `com.apple.developer.group-session` entitlement. **No `.entitlements` file
   in this repo currently has it** — it must be added to the app target and
   carried through the cloud archive workflow (which is how we ship; the dev
   Mac's beta OS can't).
5. **Resume/progress semantics.** A shared session should not pollute Continue
   Watching the way channel lineups must not (the `ephemeralLineup` precedent
   from the 2026-08-12 audit). Decide deliberately: I'd persist progress for a
   shared *film* and not for a shared *channel*.

---

## 6. Recommended first experiment (before any feature work)

One question dominates everything: **does coordination actually work through
`aw-stream://`?** Prove it cheaply, on hardware, before designing UI:

- Minimal `GroupActivity` on iOS + tvOS, one hard-coded public-domain film.
- Attach `player.playbackCoordinator.coordinateWithSession(session)`.
- Implement `identifierForPlayerItem` → `archiveID`.
- Start a FaceTime call between the owner's iPhone and the Bedroom Apple TV;
  play, pause, seek from each end; watch the other follow.
- Then repeat with the network throttled, to see the stall behaviour honestly.

Per the standing directive ([[atv_external_observation_harness]]), the tvOS half
must be judged on screen capture from the paired Apple TV, not on the app's own
logs.

If that passes, the rest is ordinary work. If coordination refuses the custom
scheme, the fallback is the Decision-082 loopback proxy — which is already
built and already known to be **unreliable on tvOS**, so a failure here likely
means iOS/macOS-only SharePlay, with tvOS deferred.

---

## 7. Open questions

- Can tvOS meaningfully *initiate* a session standalone? `activate()` is
  available on tvOS 15+, but the practical flow is usually "start on iPhone,
  Apple TV joins". Needs on-device confirmation.
- Does `AVPlaybackCoordinationMedium` offer anything for Party Play (the
  existing local multi-title feature)? Probably not, but it is the one place a
  *local* medium could apply.
- Android/web have no equivalent. SharePlay would be the first deliberately
  Apple-only feature since Creation Studio (Decision 042) — that is a product
  decision, and PARITY.md would need a row saying so plainly.
