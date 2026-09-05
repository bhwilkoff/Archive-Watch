---
name: androidtv-compose-focus
description: Compose-for-TV patterns for Archive Watch's Android TV / Google TV / Fire TV build — the tv-material-only dependency rule (TvLazy* was REMOVED), the runtime UiModeManager branch (never a fork or flavor), the focus contract (scale+ring+lift, imperative initial focus, multi-keycode select), the Google quality gates (TV-ML/MT/LB/BN/PS/G6/G1), the TV-NP conflict that forces MediaSession off on TV, and the Fire TV zero-GMS rule. Invoke before building or changing ANY Android TV surface, focus behavior, manifest declaration, or TV playback path.
---

# Android TV (Compose) — focus, compliance, and the traps

Binding spec: `docs/TV-DESIGN.md` §6 (mechanics) + §3 (focus contract).
Strategy: **Decision 047**. Backlog: `docs/TV-PLATFORM-BACKLOG.md` Phase 2.

The Android TV build is **not a port**. The data layer, repositories, routes and
player engine are shared verbatim with the phone app; only composables differ.

## The dependency rule (gets people wrong immediately)

**Depend on `androidx.tv:tv-material` ONLY.**

`tv-foundation` and every `TvLazyRow` / `TvLazyColumn` / `TvLazyVerticalGrid` /
`rememberTvLazyListState` were **removed** once their behavior merged into
`compose-foundation` 1.7.0-beta02. Use the standard `LazyRow` / `LazyColumn` /
`LazyVerticalGrid`. Most tutorials and blog posts online are stale on this — if
you see `TvLazy*`, the source predates the migration.

## TV is a RUNTIME BRANCH — never a fork, never a flavor

```kotlin
fun Context.isTelevision(): Boolean {
    val ui = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
    if (ui?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) return true
    // Fire OS reports UI_MODE_TYPE_NORMAL on some devices — fall back to the
    // feature flags the launcher itself keys on.
    return packageManager.hasSystemFeature("android.software.leanback") ||
           packageManager.hasSystemFeature("android.hardware.type.television")
}
```

Resolved **once** in `MainActivity`, provided as `LocalIsTelevision`, and used to
pick `TvAppRoot` vs `AppRoot`. One `applicationId`, one AAB, one launcher
activity. Forking re-introduces exactly the divergence Decision 028 forbids.

**Share the data assembly, not just the data layer.** When a phone screen builds
a non-trivial payload (Home's cross-shelf dedup, for example), extract it to a
shared `remember*Payload()` and have both render it. A second copy WILL drift.

## The focus contract (`ui/tv/TvFocus.kt`)

1. **Something is always focused.** Claim it imperatively on view entry and
   **retry** — the target is usually inside a lazy list that has not composed on
   the frame the screen appears. Never rely on a default.
2. **Mark focus with scale AND ring AND lift** — at least two, never colour
   alone. Colour alone fails colour-blind viewers and washes out on a bright
   living-room panel.
3. **Accept every select keycode:** `DirectionCenter`, `Enter`, **and**
   `NumPadEnter`. OEM remotes disagree; Fire remotes can send `NumPadEnter`. A
   card answering only one reads as broken.
4. **`clickable` is not enough** — wire `onKeyEvent` too; `clickable` does not
   fire for D-pad select on every OEM remote.
5. **Keep the focused item on screen** — a row must scroll it into view, ideally
   leaving one tile of context rather than snapping it flush to the edge.
6. **Hide competing focus targets.** When a full-screen route is pushed, hide the
   nav rail — otherwise the D-pad walks into it from a detail page.

## Google quality gates — the ones that actually bite

| ID | Requirement | Trap |
|---|---|---|
| **TV-ML** | `LEANBACK_LAUNCHER` category | Without it the app is **invisible** in the launcher even when installed |
| **TV-MT** | `touchscreen` + every TV-absent feature `required="false"` | Any one left implicitly-required excludes you from the TV form factor |
| **TV-LB/BN** | 320×180 banner **containing the app name as text**, ≥160×160 xhdpi icon | The name-as-text part is easy to miss |
| **TV-PS** | `minSdk` ≤ 31 | Since Dec 2025 |
| **TV-G6** | 64-bit **and 16 KB page sizes** | **Live since 2026-08-01.** NOT automatic — depends on how each bundled native lib was linked. Measure it (`tools/audit_tv_g6.py` parses ELF PT_LOAD alignment directly, no NDK needed). A fix means a dependency bump, which has lead time. |
| **TV-G1** | AAB mandatory | |
| **TV-DB** | Back returns to launcher from the root | Do not consume Back at the root |
| **TV-PC/PP** | D-pad centre = play/pause, L/R = seek, `KEYCODE_MEDIA_PLAY_PAUSE` **toggles** | Attach keys to the player **surface**, not just the controller, so they work while the transport is hidden — which is when viewers press them |

### ⚠️ TV-NP is a conflict with shipped phone code

> "Video apps must NOT use [Now Playing / background media] controls; video must
> pause when switching out."

A `media3-session` `MediaSession` added for phone lock-screen controls is a
**quality-review failure on TV**. Gate it:

```kotlin
val mediaSession = remember(player, isTv) {
    if (isTv) null else MediaSession.Builder(context, player).build()
}
// ...and pause on ON_STOP when isTv.
```

Gate **PiP-on-leave** off too — TV-NP wants a pause, not a floating window.

## Fire TV

Fire OS is the same build with **no Google Play Services**. Archive Watch's
dependency set is GMS-free today; the standing rule is that anything
GMS-dependent — **Cast above all** — must be excluded from the Fire variant.
Guard it with `tools/audit_fire_tv_gms.py`, which checks both declared
coordinates and the compiled DEX (a transitive pull names no coordinate).

Use **Media3**, not the `amzn/exoplayer-amazon-port` (stale at ExoPlayer 2.18.7,
pre-Media3); Amazon itself now directs Fire OS 14+ developers to Media3.

## Focus defects the emulator caught (compiling never would)

1. **Two surfaces raced to claim initial focus** — the content claim scrolled
   the hero off-screen while the nav rail won the ring, so first paint showed a
   headless hero. EXACTLY ONE surface may claim it, and it is the content.
2. **The hero was unfocusable decoration** — no way to act on the thing filling
   the screen. Make it focusable and openable; that also makes it a legitimate
   initial focus target. Inset its ring by the overscan margin (artwork may
   cross that line, a resting ring may not).
3. **The nav rail was UNREACHABLE from content** — Left stopped dead at the
   leftmost tile, so tabs could not be changed by remote at all (TV-DP failure).
   Compose focus search does not cross from a `LazyRow`'s first item into a
   sibling container, and `focusProperties { exit = … }` is **not delivered
   through a lazy list** (both tried, both observed failing). Fix: a
   `CompositionLocal` carrying the rail's `FocusRequester`, and the leftmost
   tile handles Left explicitly — placed BEFORE `tvFocusable` so the focused
   tile sees the key first.


## Verification: build a harness, do not verify by eye

The single highest-leverage thing on this platform. Focus IS the interaction
model and it is **invisible to a screenshot** — in one build a screenshot showed
a perfectly-rendered EPG that could not be reached by remote at all, and
separately showed a "broken" grid that was working fine. Screenshots mislead in
BOTH directions. Compiling proves even less: `.clickable` compiles, renders
beautifully, and is simply unreachable by D-pad.

Three pieces, each of which pays for itself immediately:

1. **Route directly to any surface.** `--es aw_start_tab <tab>` and
   `--es aw_start_route <route>` intent extras. Steering by counting D-pad
   presses is unreliable — Left lands on the NEAREST item, not a fixed one — and
   will repeatedly land your checks on the wrong screen.
2. **Emit a focus trace.** A `focusTag` on the focusable modifier plus a
   `--ez aw_focus_log true` switch, logging `tile:<title>`, `rail:<label>`,
   `collection:<title>`. Verify by IDENTITY, not by pixels.
3. **Assert, don't eyeball.** A script that launches each surface, presses
   Down/Right/Down, and greps the trace for an expected pattern.

```bash
./tools/verify_tv_focus.sh              # all surfaces
./tools/verify_tv_focus.sh home browse  # a subset
```

Make these permanent facilities, not logging you paste in and rip out — you will
need them on every new surface, and the ripping-out is where regressions hide.

**"It renders" is not "it works."** Verify where a navigation LANDS, not just
that the source screen drew. A set of browse shortcuts was reported working
because the shortcuts rendered; they pushed into a completely inert grid.

## Build verification

- `./gradlew assembleDebug` — compile gate.
- Inspect the **merged** manifest (`app/build/intermediates/merged_manifest/…`),
  not the source one — merger rules can drop or alter `uses-feature` entries.
- `python3 tools/audit_tv_g6.py` and `python3 tools/audit_fire_tv_gms.py`.
- Emulator: `system-images;android-36;android-tv;arm64-v8a` + the `tv_1080p`
  device profile. **Needs real free disk** — the AVD silently hangs in QEMU
  before opening its console ports when the disk is near-full, which looks like
  a boot failure rather than a space problem.

## Testing against real content

The bundled seed and the DOWNLOADED catalog are not the same set — the dedup
pass merges same-film re-uploads, so an archiveID that exists in the seed can be
absent from the live DB and the app correctly shows "isn't in the catalog
anymore". Pick test ids from the DB the app is actually running:

```bash
adb shell "run-as <pkg> cat files/catalog.sqlite" > live.sqlite
# then query item_json for whatever the test needs (captions, downloadURL, ...)
```

## See also

- `ten-foot-detail-design` — the platform-agnostic Detail/Series/Search patterns these Compose screens render

- `docs/TV-DESIGN.md` — the binding rules any surface must cite
- `android-production-gotchas` — the data-layer/`produceState`/`dbVersion`
  discipline, unchanged on TV
- `tvos-platform-patterns` — the *principles* of ten-foot design transfer even
  though the APIs do not
