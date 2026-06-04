# CloudKit + Sign in with Apple setup (#11, Decision 022)

The code for cross-Apple-TV sync ships **gated off** so the simulator build stays
clean (accessing `CKContainer` without the entitlement traps). To turn it on, the
owner does these one-time steps on a Mac with the Apple Developer account, then
verifies on real Apple TVs.

## 1. Capabilities (Xcode → target ArchiveWatch → Signing & Capabilities)
- **+ Capability → Sign in with Apple.**
- **+ Capability → iCloud** → check **CloudKit** → add container
  **`iCloud.com.bhwilkoff.archivewatch`** (must match `CloudSync.containerID` in
  `Services/CloudKitSyncService.swift`).
- These also need enabling on the App ID in the Apple Developer portal (Xcode's
  automatic signing usually does this).

## 2. Flip the gate
In `ArchiveWatch/ArchiveWatch/Services/CloudKitSyncService.swift`:
```swift
enum CloudSync { static let entitlementConfigured = true   // was false }
```
With the gate off, `AccountStore` (Sign in with Apple) still works in the UI; only
the CloudKit calls no-op.

## 3. Verify on device (two Apple TVs on the same iCloud account)
- Settings → Account → **Sign in with Apple**.
- Favorite a title / make a playlist / watch a few minutes on TV A.
- On TV B (signed into the same iCloud account), relaunch — those should appear.
- CloudKit Dashboard (icloud.developer.apple.com) shows the `Favorite` /
  `Playlist` / `WatchProgress` record types in the **private** database.

## What v1 sync does (and doesn't)
- Two-way on launch + after sign-in: Favorites (union), Playlists (upsert by id,
  larger-wins merge), WatchProgress (last-writer-wins by `lastWatchedAt`).
- **Deletions don't propagate yet** (no tombstones) and there's no live
  push-notification refresh — those are #11b. Records are fetched in one page
  (fine for personal-scale libraries; add cursor pagination if a user's saved set
  grows past a few hundred).

## Why this shape
Decision 009 said "no accounts; all state local." Decision 022 reverses the
"all-local" half: Apple-native auth only (no third-party), sync is **optional**
and gates nothing but itself, and the data lives in the user's own private
CloudKit DB (we never see it). See `DECISIONS.md` 022 and `docs/tvOS-DESIGN.md`
§10.2.
