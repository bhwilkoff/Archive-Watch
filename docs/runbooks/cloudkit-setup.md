# CloudKit + Sign in with Apple setup (#11, Decision 022)

The code for cross-Apple-TV sync ships **gated off** so the simulator build stays
clean (accessing `CKContainer` without the entitlement traps). To turn it on, the
owner does these one-time steps on a Mac with the Apple Developer account, then
verifies on real Apple TVs.

## 1. Capabilities (Xcode → target ArchiveWatch → Signing & Capabilities)
- **+ Capability → Sign in with Apple.**
- **+ Capability → iCloud** → check **CloudKit** → add container
  **`iCloud.app.archivewatch.tvos`** (must match `CloudSync.containerID` in
  `Services/CloudKitSyncService.swift` AND the container already declared in
  `ArchiveWatch/ArchiveWatch.entitlements`). Do **NOT** use the old
  `iCloud.com.bhwilkoff.archivewatch` id — it does not match the code/entitlements
  and was the reason sync silently did nothing.
- These also need enabling on the App ID in the Apple Developer portal (Xcode's
  automatic signing usually does this).

## 2. Flip the gate — DONE
`CloudSync.entitlementConfigured` is now `true` in
`Services/CloudKitSyncService.swift`. (With the gate off, Sign in with Apple still
works in the UI but every CloudKit call no-ops — which is why saved data wasn't
syncing.) If a device build now **crashes on launch**, the iCloud/CloudKit
capability + container above is not provisioned on the App ID — complete step 1
and rebuild.

## 3. Verify on device (two Apple TVs on the same iCloud account)
- Settings → Account → **Sign in with Apple**.
- Favorite a title / make a playlist / watch a few minutes on TV A.
- On TV B (signed into the same iCloud account), relaunch — those should appear.
- CloudKit Dashboard (icloud.developer.apple.com) shows the `Favorite` /
  `Playlist` / `WatchProgress` record types in the **private** database.

## What sync does (updated #11b)
- Two-way on launch, after sign-in, **on every foreground**, **after each edit**
  (debounced ~2 s), and on a **60 s timer while active**: Favorites (union),
  Playlists (last-writer-wins by `modifiedAt` — so removals propagate),
  WatchProgress (LWW by `lastWatchedAt`).
- **Deletions propagate** via `Tombstone` records (#11b): removing a favorite or
  editing a playlist writes a tombstone that syncs to every device, so a deletion
  beats a stale cloud copy instead of resurrecting. A re-add newer than the
  tombstone clears it.
- Records are fetched in one page (fine for personal-scale libraries; add cursor
  pagination if a user's saved set grows past a few hundred).
- NOT yet: APNs push subscriptions (instant cross-device while both idle on a
  screen — the 60 s timer + foreground sync cover the realistic flow). Adding
  `CKDatabaseSubscription` + remote-notification background mode is the next step.

## #11b on-device test checklist (build 25+)
Two Apple TVs on the SAME iCloud account, both signed in (Settings → Account):
1. **Add** — favorite a film on TV A; within ~a minute (or on foregrounding B) it
   appears in Library on TV B.
2. **Delete** — un-favorite it on A; it disappears on B and does NOT come back
   (the resurrection bug this fixes). Same for removing a title from a playlist
   (the list shrinks on B).
3. **Re-add wins** — favorite it again on A; it reappears on B and stays.
4. **Progress** — watch 5 min on A; the resume point shows on B.
5. CloudKit Dashboard → private DB shows a `Tombstone` record type after a delete.
If a device CRASHES on launch: the iCloud(CloudKit) capability + container
`iCloud.app.archivewatch.tvos` isn't on the App ID — add it and rebuild.

## Why this shape
Decision 009 said "no accounts; all state local." Decision 022 reverses the
"all-local" half: Apple-native auth only (no third-party), sync is **optional**
and gates nothing but itself, and the data lives in the user's own private
CloudKit DB (we never see it). See `DECISIONS.md` 022 and `docs/tvOS-DESIGN.md`
§10.2.
