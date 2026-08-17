# Research: watch-state sync architecture (2026-08-17)

Commissioned after the owner reported devices disagreeing on history/watched
state despite the hand-rolled CloudKit sync. Full agent findings, condensed;
sources at bottom. Feeds the playback-quality program's sync track.

## Recommendation: CKSyncEngine, per-item records, custom zone

The hand-rolled four-fixed-record design cannot converge on tvOS by
construction:
- It has NO push path. CKDatabaseSubscription only tracks CUSTOM zones —
  the fixed records live in the default zone (chosen to dodge the CKQuery
  queryable-index trap), so no subscription can ever fire for them.
- tvOS loses foreground the moment the user goes Home or the TV sleeps; the
  60s timer stops; nothing wakes the app. "Device B stale" is the expected
  behavior of the trigger design, not a merge bug.
- Whole-blob LWW loses concurrent edits: watch film X on ATV A and film Y on
  iPhone simultaneously → one device's ENTIRE progress map wins.

CKSyncEngine (iOS/tvOS 17+, WWDC23) supplies exactly the missing pieces:
auto-created subscriptions + push-triggered fetch while frontmost, server
change tokens (cheap on-activation fetch), retry/scheduling. Realistic
convergence: seconds-to-~15s frontmost; on-launch otherwise (pause on ATV A,
walk to ATV B, launch → converged before the Detail screen). Simulator gets
no CloudKit pushes — device-only verification.

SwiftData+CloudKit mirroring REJECTED for this app: bans @Attribute(.unique)
(archiveID keys), fails silently on violations, unforceable opaque scheduler,
no "Sync Now"/status surface, negative 2026 production reports specifically
citing flaky Apple TV syncing (mjtsai "Leaving CloudKit").

Production gotchas (Selig 2026): persist engine stateSerialization to disk;
ALWAYS store per-record CKRecord system-field metadata or face constant
conflict errors; one engine per database; let the engine self-schedule.

### Migration sketch
1. One custom zone AWSyncZone; per-item records: Favorite:{archiveID},
   Progress:{archiveID}, Playlist:{uuid}, PlayEvent:{deviceID}:{ts}.
   Real record deletions replace tombstone blobs (keep tombstone semantics
   only for "unwatch" overrides).
2. serverRecordChanged handler = existing merge functions, requeue.
3. Cutover: first launch reads the four legacy records once, merges, writes
   per-item records; leave legacy records for older builds; delete later.
4. Keep: sign-in gating, entitlementConfigured, Last-sync/Sync-Now UI
   (fetchChanges() IS Sync Now).

## Merge semantics verdict
- Favorites: current union+tombstone is a textbook OR-set — keep (simplifies
  to record-exists/record-deleted with per-item records).
- Resume position: LWW right, granularity wrong → per-item LWW by modifiedAt
  (deviceID tiebreak). "completed" merges by OR, never LWW.
- Play history/counts: LWW is WRONG. Append-only PlayEvent union (immutable
  {archiveID, date, secondsWatched} per event; merge = set union). Count and
  last-watched are DERIVED. Compact old events client-side.
- Playlists: per-playlist LWW by modifiedAt is the industry norm — keep.

## History vs Watched UX (the Trakt model = the standard)
- History = chronological log of dated PLAY EVENTS; a title may repeat;
  entries individually deletable.
- Watched = DERIVED per-title state (played-to-completion at least once, OR
  manual override); shown as a checkmark/badge on tiles + a Detail toggle —
  NOT a separate content list. "Mark unwatched" clears flag + resume, never
  deletes history.
- Continue Watching = progress-derived, third and separate.
- Confusion arises exactly when apps present overlapping lists that conflate
  state/event/progress claims — the fix is one derivation direction, not one
  list.

## Google Drive appDataFolder notes (Android/web plane)
- drive.appdata = non-sensitive scope: no verification/CASA audit needed.
- PUBLISH the OAuth consent screen to Production (no review needed for
  non-sensitive scopes) — in Testing status refresh tokens die every 7 days.
- Browser PWA: ~1h access tokens, no refresh token → sync-on-open model, not
  standing credential. Authorized origins must include https://archivewatch.org.

## Key sources
CKSyncEngine WWDC23 10188 · christianselig.com/2026/01/cksyncengine ·
mjtsai.com/blog/2026/05/21/leaving-cloudkit · CKDatabaseSubscription docs ·
apple/sample-cloudkit-privatedb-sync · hackingwithswift SwiftData+iCloud ·
fatbobman CloudKit model rules · Apple forums 682861 (latency), 23121 (tvOS
push) · ryanashcraft.com hand-rolled-sync postmortem · Trakt/Firecore sync
docs · Google Drive appdata guide · unipile.com 7-day testing-token limit
