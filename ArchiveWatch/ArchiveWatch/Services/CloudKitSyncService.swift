import CloudKit
import SwiftData

// #11 (Decision 022): cross-Apple-TV sync of Favorites, Playlists, and Watch
// Progress via the CloudKit PRIVATE database (keyed to the user's iCloud account;
// Sign in with Apple provides identity). v1 is union/upsert + last-writer-wins on
// progress; deletion propagation is #11b.
//
// GATED: every CloudKit call no-ops until `CloudSync.entitlementConfigured` is
// flipped true — after the owner adds the iCloud(CloudKit) capability + container
// in Xcode Signing & Capabilities and the Apple Developer App ID. This keeps the
// simulator build clean (CKContainer access without the entitlement traps), the
// same no-op-until-configured pattern as the Top Shelf App Group. Owner verifies
// on device. See docs/runbooks/cloudkit-setup.md.
enum CloudSync {
    // Flip to TRUE only after: (1) the iCloud(CloudKit) capability + container
    // `iCloud.app.archivewatch.tvos` exist on the App ID, AND (2) it's verified on
    // a REAL device signed into iCloud. On the simulator (and any build whose
    // entitlement isn't truly provisioned) CKContainer access TRAPS at launch —
    // that's why this stays gated. The entitlements themselves ARE configured. (#84)
    static let entitlementConfigured = false
    static let containerID = "iCloud.app.archivewatch.tvos"
}

@MainActor
final class CloudKitSyncService {
    static let shared = CloudKitSyncService()
    private init() {}

    private var database: CKDatabase? {
        guard CloudSync.entitlementConfigured else { return nil }
        return CKContainer(identifier: CloudSync.containerID).privateCloudDatabase
    }

    /// Best-effort two-way sync. Never throws to the caller — sync must never
    /// block the app. No-ops without the entitlement or an available iCloud account.
    func sync(_ context: ModelContext) async {
        guard let database else { return }
        do {
            let status = try await CKContainer(identifier: CloudSync.containerID).accountStatus()
            guard status == .available else { return }
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
            for type in ["Favorite", "Playlist", "WatchProgress"] {
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

    // MARK: Favorites (union)

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
        for rec in try await allRecords(db, "Favorite") {
            if let aid = rec["archiveID"] as? String, !existing.contains(aid) {
                ctx.insert(Favorite(archiveID: aid))
            }
        }
    }

    // MARK: Playlists (upsert by id)

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
            return r
        }
        _ = try await db.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
    }

    private func pullPlaylists(_ ctx: ModelContext, _ db: CKDatabase) async throws {
        let local = (try? ctx.fetch(FetchDescriptor<Playlist>())) ?? []
        let byID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for rec in try await allRecords(db, "Playlist") {
            guard let id = rec["playlistID"] as? String,
                  let name = rec["name"] as? String else { continue }
            let ids = (rec["archiveIDs"] as? [String]) ?? []
            if let existing = byID[id] {
                // Last-writer-wins on the cloud copy's contents if it's larger
                // (simple union-leaning merge for v1).
                if ids.count > existing.archiveIDs.count { existing.archiveIDs = ids; existing.name = name }
            } else {
                ctx.insert(Playlist(id: id, name: name, archiveIDs: ids))
            }
        }
    }

    // MARK: Watch progress (last-writer-wins by position/time)

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
        let byID = Dictionary(uniqueKeysWithValues: local.map { ($0.archiveID, $0) })
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
                ctx.insert(WatchProgress(archiveID: aid, positionSeconds: pos,
                                         durationSeconds: dur,
                                         seriesID: rec["seriesID"] as? String,
                                         episodeTitle: rec["episodeTitle"] as? String))
            }
        }
    }
}
