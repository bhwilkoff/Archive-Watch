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
