import CloudKit
import SwiftData

// #11 (Decision 022): cross-Apple-TV sync of Favorites, Playlists, and Watch
// Progress via the CloudKit PRIVATE database (keyed to the user's iCloud account;
// Sign in with Apple provides identity).
//
// #11b (this file): DELETION PROPAGATION + LIVE SYNC.
//  - Deletion: a removed Favorite (or Playlist) used to RESURRECT on the next
//    pull, because pull was union-only and local SwiftData keeps no record of a
//    deletion. Now every delete writes a `Tombstone` (key + time); tombstones
//    sync both ways and are APPLIED before data, so a deletion beats a stale
//    cloud copy. A re-add newer than the tombstone clears it (last-writer-wins).
//  - Playlists merge by `modifiedAt` recency (the old count-based merge could
//    never shrink a list, so removing an item never propagated).
//  - Live: sync now fires on foreground, after each edit (debounced via
//    SyncNudge), and on a short timer while active — not just at launch.
//
// GATED by `CloudSync.entitlementConfigured`; no-ops without it or an available
// iCloud account. See docs/runbooks/cloudkit-setup.md.
enum CloudSync {
    // ENABLED (#11). The entitlements (ArchiveWatch.entitlements) declare the
    // CloudKit container below, so a build that signs successfully carries the
    // entitlement and CKContainer(identifier:) does NOT trap; account/availability
    // are handled defensively at the call sites (accountStatus guards).
    //
    // REQUIREMENT for sync to actually move data on device: the App ID must have
    // the iCloud(CloudKit) capability with container `iCloud.app.archivewatch.tvos`
    // (Xcode → Signing & Capabilities → iCloud → CloudKit → this container).
    // If a device build CRASHES on launch after this flip, that capability/
    // container is not provisioned on the App ID — add it, rebuild.
    static let entitlementConfigured = true
    static let containerID = "iCloud.app.archivewatch.tvos"
}

@MainActor
final class CloudKitSyncService {
    static let shared = CloudKitSyncService()
    private init() {}

    private var isSyncing = false

    private var database: CKDatabase? {
        guard CloudSync.entitlementConfigured else { return nil }
        return CKContainer(identifier: CloudSync.containerID).privateCloudDatabase
    }

    /// Best-effort two-way sync. Never throws to the caller — sync must never
    /// block the app. No-ops without the entitlement or an available iCloud
    /// account. Reentrancy-guarded so overlapping triggers (foreground + timer +
    /// post-edit) don't run concurrently.
    func sync(_ context: ModelContext) async {
        guard let database, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let status = try await CKContainer(identifier: CloudSync.containerID).accountStatus()
            guard status == .available else { return }
            // 1. Deletions first — learn them both ways, then apply locally so a
            //    deleted item is never re-pushed below.
            try await pushTombstones(context, database)
            try await pullTombstones(context, database)
            try await applyTombstones(context, database)
            // 2. Data (tombstone-aware).
            try await pushFavorites(context, database)
            try await pullFavorites(context, database)
            try await pushPlaylists(context, database)
            try await pullPlaylists(context, database)
            try await pushProgress(context, database)
            try await pullProgress(context, database)
            try context.save()
        } catch {
            // best-effort
        }
    }

    /// Account deletion (App Review 5.1.1(v)): purge ALL of this user's records
    /// from the CloudKit private database. Returns true on success — and also when
    /// CloudKit isn't configured/available (nothing is stored, so deletion is
    /// vacuously complete). Best-effort; never throws to the caller.
    func deleteAllCloudData() async -> Bool {
        guard let database else { return true }   // not configured -> nothing stored
        do {
            let status = try await CKContainer(identifier: CloudSync.containerID).accountStatus()
            guard status == .available else { return true }   // no account -> nothing of ours stored
            for type in ["Favorite", "Playlist", "WatchProgress", "Tombstone"] {
                let ids = try await allRecords(database, type).map(\.recordID)
                if !ids.isEmpty {
                    _ = try await database.modifyRecords(saving: [], deleting: ids)
                }
            }
            return true
        } catch {
            return false
        }
    }

    private func allRecords(_ db: CKDatabase, _ type: String) async throws -> [CKRecord] {
        let (matches, _) = try await db.records(matching:
            CKQuery(recordType: type, predicate: NSPredicate(value: true)))
        return matches.compactMap { try? $0.1.get() }
    }

    // MARK: Tombstones (deletion propagation)

    private static func tombstoneRecordName(_ key: String) -> String {
        // CKRecord names disallow ':' — keys are "fav:<id>" etc.
        "tomb-" + key.replacingOccurrences(of: ":", with: "~")
    }

    private func pushTombstones(_ ctx: ModelContext, _ db: CKDatabase) async throws {
        let local = (try? ctx.fetch(FetchDescriptor<Tombstone>())) ?? []
        guard !local.isEmpty else { return }
        let records = local.map { t -> CKRecord in
            let r = CKRecord(recordType: "Tombstone",
                             recordID: CKRecord.ID(recordName: Self.tombstoneRecordName(t.key)))
            r["key"] = t.key as CKRecordValue
            r["deletedAt"] = t.deletedAt as CKRecordValue
            return r
        }
        _ = try await db.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
    }

    private func pullTombstones(_ ctx: ModelContext, _ db: CKDatabase) async throws {
        let local = (try? ctx.fetch(FetchDescriptor<Tombstone>())) ?? []
        let byKey = Dictionary(local.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for rec in try await allRecords(db, "Tombstone") {
            guard let key = rec["key"] as? String else { continue }
            let when = (rec["deletedAt"] as? Date) ?? .distantPast
            if let existing = byKey[key] {
                if when > existing.deletedAt { existing.deletedAt = when }
            } else {
                ctx.insert(Tombstone(key: key, deletedAt: when))
            }
        }
    }

    /// Apply every tombstone to local data: delete an item whose own timestamp is
    /// at-or-before the tombstone (it was deleted last). If the item is NEWER than
    /// the tombstone it was re-added, so clear the tombstone (locally + in cloud)
    /// so it stops trying to delete the live item. Also purges the now-stale cloud
    /// DATA record so an older client can't resurrect it.
    private func applyTombstones(_ ctx: ModelContext, _ db: CKDatabase) async throws {
        let tombstones = (try? ctx.fetch(FetchDescriptor<Tombstone>())) ?? []
        guard !tombstones.isEmpty else { return }
        let favs = (try? ctx.fetch(FetchDescriptor<Favorite>())) ?? []
        let favByID = Dictionary(favs.map { ($0.archiveID, $0) }, uniquingKeysWith: { a, _ in a })
        let lists = (try? ctx.fetch(FetchDescriptor<Playlist>())) ?? []
        let listByID = Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let progress = (try? ctx.fetch(FetchDescriptor<WatchProgress>())) ?? []
        let progByID = Dictionary(progress.map { ($0.archiveID, $0) }, uniquingKeysWith: { a, _ in a })

        var deleteDataIDs: [CKRecord.ID] = []
        var clearTombstoneIDs: [CKRecord.ID] = []

        for t in tombstones {
            let parts = t.key.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let (kind, id) = (parts[0], parts[1])
            // returns true if a live item exists that is NEWER than the tombstone
            // (re-added) -> the tombstone should be cleared.
            func resolve(itemTime: Date?, delete: () -> Void, dataRecordName: String) -> Bool {
                if let itemTime {
                    if itemTime > t.deletedAt { return true }          // re-added -> clear tombstone
                    delete()                                            // stale local copy -> remove
                }
                deleteDataIDs.append(CKRecord.ID(recordName: dataRecordName))
                return false
            }
            var reAdded = false
            switch kind {
            case "fav":
                let f = favByID[id]
                reAdded = resolve(itemTime: f?.addedAt,
                                  delete: { if let f { ctx.delete(f) } },
                                  dataRecordName: "fav-\(id)")
            case "pl":
                let p = listByID[id]
                reAdded = resolve(itemTime: p?.modifiedAt,
                                  delete: { if let p { ctx.delete(p) } },
                                  dataRecordName: "pl-\(id)")
            case "wp":
                let w = progByID[id]
                reAdded = resolve(itemTime: w?.lastWatchedAt,
                                  delete: { if let w { ctx.delete(w) } },
                                  dataRecordName: "wp-\(id)")
            default:
                continue
            }
            if reAdded {
                ctx.delete(t)
                clearTombstoneIDs.append(CKRecord.ID(recordName: Self.tombstoneRecordName(t.key)))
            }
        }
        let toDelete = deleteDataIDs + clearTombstoneIDs
        if !toDelete.isEmpty {
            _ = try? await db.modifyRecords(saving: [], deleting: toDelete)
        }
    }

    private func tombstoneMap(_ ctx: ModelContext) -> [String: Date] {
        var m: [String: Date] = [:]
        for t in (try? ctx.fetch(FetchDescriptor<Tombstone>())) ?? [] { m[t.key] = t.deletedAt }
        return m
    }

    // MARK: Favorites (union, tombstone-aware)

    private func pushFavorites(_ ctx: ModelContext, _ db: CKDatabase) async throws {
        let favs = (try? ctx.fetch(FetchDescriptor<Favorite>())) ?? []
        guard !favs.isEmpty else { return }
        let records = favs.map { f -> CKRecord in
            let r = CKRecord(recordType: "Favorite",
                             recordID: CKRecord.ID(recordName: "fav-\(f.archiveID)"))
            r["archiveID"] = f.archiveID as CKRecordValue
            r["addedAt"] = f.addedAt as CKRecordValue
            return r
        }
        _ = try await db.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
    }

    private func pullFavorites(_ ctx: ModelContext, _ db: CKDatabase) async throws {
        let existing = Set(((try? ctx.fetch(FetchDescriptor<Favorite>())) ?? []).map(\.archiveID))
        let tombs = tombstoneMap(ctx)
        for rec in try await allRecords(db, "Favorite") {
            guard let aid = rec["archiveID"] as? String, !existing.contains(aid) else { continue }
            // Don't re-add something deleted after this cloud copy was written.
            let addedAt = (rec["addedAt"] as? Date) ?? .distantPast
            if let deletedAt = tombs["fav:\(aid)"], deletedAt >= addedAt { continue }
            ctx.insert(Favorite(archiveID: aid))
        }
    }

    // MARK: Playlists (last-writer-wins by modifiedAt)

    private func pushPlaylists(_ ctx: ModelContext, _ db: CKDatabase) async throws {
        let lists = (try? ctx.fetch(FetchDescriptor<Playlist>())) ?? []
        guard !lists.isEmpty else { return }
        let records = lists.map { p -> CKRecord in
            let r = CKRecord(recordType: "Playlist",
                             recordID: CKRecord.ID(recordName: "pl-\(p.id)"))
            r["playlistID"] = p.id as CKRecordValue
            r["name"] = p.name as CKRecordValue
            r["archiveIDs"] = p.archiveIDs as CKRecordValue
            r["createdAt"] = p.createdAt as CKRecordValue
            r["modifiedAt"] = p.modifiedAt as CKRecordValue
            return r
        }
        _ = try await db.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
    }

    private func pullPlaylists(_ ctx: ModelContext, _ db: CKDatabase) async throws {
        let local = (try? ctx.fetch(FetchDescriptor<Playlist>())) ?? []
        let byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let tombs = tombstoneMap(ctx)
        for rec in try await allRecords(db, "Playlist") {
            guard let id = rec["playlistID"] as? String,
                  let name = rec["name"] as? String else { continue }
            let ids = (rec["archiveIDs"] as? [String]) ?? []
            // createdAt is the fallback when an old cloud copy predates modifiedAt.
            let cloudMod = (rec["modifiedAt"] as? Date) ?? (rec["createdAt"] as? Date) ?? .distantPast
            if let existing = byID[id] {
                // Recency wins — so a removal (shorter list, newer time) propagates.
                if cloudMod > existing.modifiedAt {
                    existing.name = name
                    existing.archiveIDs = ids
                    existing.modifiedAt = cloudMod
                }
            } else {
                if let deletedAt = tombs["pl:\(id)"], deletedAt >= cloudMod { continue }
                let p = Playlist(id: id, name: name, archiveIDs: ids)
                p.modifiedAt = cloudMod
                ctx.insert(p)
            }
        }
    }

    // MARK: Watch progress (last-writer-wins by lastWatchedAt)

    private func pushProgress(_ ctx: ModelContext, _ db: CKDatabase) async throws {
        let records = ((try? ctx.fetch(FetchDescriptor<WatchProgress>())) ?? []).map { w -> CKRecord in
            let r = CKRecord(recordType: "WatchProgress",
                             recordID: CKRecord.ID(recordName: "wp-\(w.archiveID)"))
            r["archiveID"] = w.archiveID as CKRecordValue
            r["positionSeconds"] = w.positionSeconds as CKRecordValue
            r["durationSeconds"] = w.durationSeconds as CKRecordValue
            r["lastWatchedAt"] = w.lastWatchedAt as CKRecordValue
            if let s = w.seriesID { r["seriesID"] = s as CKRecordValue }
            if let e = w.episodeTitle { r["episodeTitle"] = e as CKRecordValue }
            return r
        }
        guard !records.isEmpty else { return }
        _ = try await db.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
    }

    private func pullProgress(_ ctx: ModelContext, _ db: CKDatabase) async throws {
        let local = (try? ctx.fetch(FetchDescriptor<WatchProgress>())) ?? []
        let byID = Dictionary(local.map { ($0.archiveID, $0) }, uniquingKeysWith: { a, _ in a })
        let tombs = tombstoneMap(ctx)
        for rec in try await allRecords(db, "WatchProgress") {
            guard let aid = rec["archiveID"] as? String else { continue }
            let pos = (rec["positionSeconds"] as? Double) ?? 0
            let dur = (rec["durationSeconds"] as? Double) ?? 0
            let when = (rec["lastWatchedAt"] as? Date) ?? .distantPast
            if let existing = byID[aid] {
                if when > existing.lastWatchedAt {
                    existing.positionSeconds = pos
                    if dur > 0 { existing.durationSeconds = dur }
                    existing.lastWatchedAt = when
                }
            } else {
                if let deletedAt = tombs["wp:\(aid)"], deletedAt >= when { continue }
                ctx.insert(WatchProgress(archiveID: aid, positionSeconds: pos,
                                         durationSeconds: dur,
                                         seriesID: rec["seriesID"] as? String,
                                         episodeTitle: rec["episodeTitle"] as? String))
            }
        }
    }
}

// MARK: - Deletion helpers + live-sync nudge

@MainActor
enum SyncNudge {
    /// Record a deletion so it propagates (and survives a stale cloud copy), then
    /// kick a debounced sync. Call this INSTEAD of a bare modelContext.delete for
    /// synced models.
    static func recordDeletion(_ key: String, in ctx: ModelContext) {
        // Merge with any existing tombstone for this key (keep latest time).
        let all = (try? ctx.fetch(FetchDescriptor<Tombstone>())) ?? []
        if let existing = all.first(where: { $0.key == key }) {
            existing.deletedAt = Date()
        } else {
            ctx.insert(Tombstone(key: key))
        }
        try? ctx.save()
        nudge(ctx)
    }

    private static var pending: Task<Void, Never>?

    /// Debounced push/pull after a local edit (~2 s) so rapid edits coalesce.
    static func nudge(_ ctx: ModelContext) {
        guard CloudSync.entitlementConfigured else { return }
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return }
            await CloudKitSyncService.shared.sync(ctx)
        }
    }
}
