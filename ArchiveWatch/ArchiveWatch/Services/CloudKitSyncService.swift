import CloudKit
import Observation
import SwiftData

// #11 (Decision 022): cross-device sync of Favorites, Playlists, and Watch
// Progress via the CloudKit PRIVATE database (keyed to the user's iCloud
// account; Sign in with Apple provides the in-app opt-in).
//
// DESIGN (rewritten 2026-06-11): four FIXED-ID records of one type ("AWSync"),
// fetched directly by record ID and merged client-side — NO CKQuery anywhere.
// The previous per-item-record design pulled with
// `CKQuery(predicate: NSPredicate(value: true))`, which requires a QUERYABLE
// INDEX on `recordName` that CloudKit never creates by itself (not even in the
// Development environment). Every pull failed with "recordName is not marked
// queryable", the silent `catch` hid it, and cross-device sync NEVER worked —
// pushes succeeded, pulls returned nothing (owner report 2026-06-11). Fetching
// by record ID needs no schema indexes at all, and a single record type means
// a single one-click schema deploy to Production.
//
// Merge semantics (unchanged from #11b):
//  - Tombstones first: per-key newest deletedAt wins; an item NEWER than its
//    tombstone was re-added and clears it; otherwise the item dies everywhere.
//  - Favorites: union (tombstone-aware).
//  - Playlists: last-writer-wins by modifiedAt (so removals propagate).
//  - WatchProgress: last-writer-wins by lastWatchedAt.
// Writes use .allKeys over the just-fetched record; if two devices race, each
// still holds its local truth and the union/LWW merge re-converges on the
// loser's next cycle (60 s timer / foreground).
//
// OBSERVABILITY: lastSyncAt / lastError are @Observable and surfaced in
// Settings on both platforms — a failing sync must never be invisible again.
//
// GATED by `CloudSync.entitlementConfigured`; no-ops without it or an available
// iCloud account. See docs/runbooks/cloudkit-setup.md — note the ONE-TIME owner
// step: deploy the schema to Production (TestFlight/App Store builds talk to
// the Production environment, which never auto-creates record types).
enum CloudSync {
    static let entitlementConfigured = true
    static let containerID = "iCloud.app.archivewatch.tvos"
}

@MainActor
@Observable
final class CloudKitSyncService {
    static let shared = CloudKitSyncService()
    private init() {}

    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?

    private var isSyncing = false

    private static let recordType = "AWSync"
    private enum Blob: String, CaseIterable {
        case tombstones, favorites, playlists, progress, channels
        var recordID: CKRecord.ID { CKRecord.ID(recordName: rawValue) }
    }

    private var database: CKDatabase? {
        guard CloudSync.entitlementConfigured else { return nil }
        return CKContainer(identifier: CloudSync.containerID).privateCloudDatabase
    }

    // MARK: - Blob payloads

    private struct FavoriteEntry: Codable { var archiveID: String; var addedAt: Date }
    private struct PlaylistEntry: Codable {
        var id: String; var name: String; var archiveIDs: [String]
        var createdAt: Date; var modifiedAt: Date
    }
    private struct ProgressEntry: Codable {
        var archiveID: String; var positionSeconds: Double; var durationSeconds: Double
        var lastWatchedAt: Date; var seriesID: String?; var episodeTitle: String?
    }
    private struct TombstoneEntry: Codable { var key: String; var deletedAt: Date }
    private struct ChannelEntry: Codable {
        var id: String; var name: String
        var genre: String?; var contentType: String?; var decade: Int?
        var createdAt: Date
    }

    // MARK: - Public API

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
            guard status == .available else {
                lastError = "iCloud account unavailable on this device."
                return
            }
            var records: [Blob: CKRecord] = [:]
            for blob in Blob.allCases {
                records[blob] = try await fetchOrNew(database, blob)
            }
            // 1. Tombstones: merge cloud+local, apply to local data, learn
            //    which were cleared by a newer re-add.
            var tombs = mergedTombstones(context, decode(records[.tombstones]!))
            tombs = applyTombstones(context, tombs)
            // 2. Data merges (tombstone-aware), updating local SwiftData.
            let favs = mergeFavorites(context, decode(records[.favorites]!), tombs)
            let lists = mergePlaylists(context, decode(records[.playlists]!), tombs)
            let progress = mergeProgress(context, decode(records[.progress]!), tombs)
            let channels = mergeChannels(context, decode(records[.channels]!), tombs)
            try context.save()
            // 3. Push the merged truth back.
            try await save(database, records[.tombstones]!, encode(tombs))
            try await save(database, records[.favorites]!, encode(favs))
            try await save(database, records[.playlists]!, encode(lists))
            try await save(database, records[.progress]!, encode(progress))
            try await save(database, records[.channels]!, encode(channels))
            lastSyncAt = Date()
            lastError = nil
        } catch {
            lastError = Self.describe(error)
        }
    }

    /// Account deletion (App Review 5.1.1(v)): purge this user's sync records
    /// from the CloudKit private database. Returns true on success — and also
    /// when CloudKit isn't configured/available (nothing stored). Best-effort.
    func deleteAllCloudData() async -> Bool {
        guard let database else { return true }
        do {
            let status = try await CKContainer(identifier: CloudSync.containerID).accountStatus()
            guard status == .available else { return true }
            _ = try await database.modifyRecords(
                saving: [], deleting: Blob.allCases.map(\.recordID))
            // Legacy per-item records from the pre-rewrite design (only ever
            // reachable by query, which needs an index that may not exist) —
            // best-effort, never blocks the deletion completing.
            for type in ["Favorite", "Playlist", "WatchProgress", "Tombstone"] {
                if let (matches, _) = try? await database.records(
                    matching: CKQuery(recordType: type, predicate: NSPredicate(value: true))) {
                    let ids = matches.compactMap { try? $0.1.get() }.map(\.recordID)
                    if !ids.isEmpty {
                        _ = try? await database.modifyRecords(saving: [], deleting: ids)
                    }
                }
            }
            return true
        } catch {
            lastError = Self.describe(error)
            return false
        }
    }

    // MARK: - Record plumbing

    private func fetchOrNew(_ db: CKDatabase, _ blob: Blob) async throws -> CKRecord {
        do {
            return try await db.record(for: blob.recordID)
        } catch let e as CKError where e.code == .unknownItem {
            return CKRecord(recordType: Self.recordType, recordID: blob.recordID)
        }
    }

    private func decode<T: Codable>(_ record: CKRecord) -> [T] {
        guard let data = record["payload"] as? Data else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return (try? dec.decode([T].self, from: data)) ?? []
    }

    private func encode<T: Codable>(_ entries: [T]) -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        return (try? enc.encode(entries)) ?? Data("[]".utf8)
    }

    private func save(_ db: CKDatabase, _ record: CKRecord, _ payload: Data) async throws {
        record["payload"] = payload as CKRecordValue
        record["modifiedAt"] = Date() as CKRecordValue
        _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
    }

    // MARK: - Merges

    private func mergedTombstones(_ ctx: ModelContext,
                                  _ cloud: [TombstoneEntry]) -> [TombstoneEntry] {
        var byKey: [String: Date] = [:]
        for t in cloud { byKey[t.key] = max(byKey[t.key] ?? .distantPast, t.deletedAt) }
        for t in (try? ctx.fetch(FetchDescriptor<Tombstone>())) ?? [] {
            byKey[t.key] = max(byKey[t.key] ?? .distantPast, t.deletedAt)
        }
        return byKey.map { TombstoneEntry(key: $0.key, deletedAt: $0.value) }
    }

    /// Apply tombstones to local SwiftData: delete items at-or-before their
    /// tombstone; an item NEWER than its tombstone was re-added, so the
    /// tombstone is dropped. Returns the surviving tombstone set, and mirrors
    /// it into local SwiftData so future local merges see the same truth.
    private func applyTombstones(_ ctx: ModelContext,
                                 _ tombs: [TombstoneEntry]) -> [TombstoneEntry] {
        let favs = dict((try? ctx.fetch(FetchDescriptor<Favorite>())) ?? [], \.archiveID)
        let lists = dict((try? ctx.fetch(FetchDescriptor<Playlist>())) ?? [], \.id)
        let progress = dict((try? ctx.fetch(FetchDescriptor<WatchProgress>())) ?? [], \.archiveID)
        let channels = dict((try? ctx.fetch(FetchDescriptor<UserChannel>())) ?? [], \.id)

        var surviving: [TombstoneEntry] = []
        for t in tombs {
            let parts = t.key.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let id = parts[1]
            var itemTime: Date?
            var deleteLocal: (() -> Void)?
            switch parts[0] {
            case "fav":
                itemTime = favs[id]?.addedAt
                deleteLocal = { favs[id].map { ctx.delete($0) } }
            case "pl":
                itemTime = lists[id]?.modifiedAt
                deleteLocal = { lists[id].map { ctx.delete($0) } }
            case "wp":
                itemTime = progress[id]?.lastWatchedAt
                deleteLocal = { progress[id].map { ctx.delete($0) } }
            case "ch":
                itemTime = channels[id]?.createdAt
                deleteLocal = { channels[id].map { ctx.delete($0) } }
            default:
                surviving.append(t)   // unknown kind — carry along
                continue
            }
            if let itemTime, itemTime > t.deletedAt {
                continue              // re-added after deletion -> tombstone dies
            }
            deleteLocal?()
            surviving.append(t)
        }
        // Mirror into local SwiftData (upsert surviving, drop cleared).
        let keep = Set(surviving.map(\.key))
        let local = (try? ctx.fetch(FetchDescriptor<Tombstone>())) ?? []
        for t in local where !keep.contains(t.key) { ctx.delete(t) }
        var localByKey = dict(local.filter { keep.contains($0.key) }, \.key)
        for t in surviving {
            if let existing = localByKey[t.key] {
                if t.deletedAt > existing.deletedAt { existing.deletedAt = t.deletedAt }
            } else {
                let m = Tombstone(key: t.key, deletedAt: t.deletedAt)
                ctx.insert(m); localByKey[t.key] = m
            }
        }
        return surviving
    }

    private func mergeFavorites(_ ctx: ModelContext, _ cloud: [FavoriteEntry],
                                _ tombs: [TombstoneEntry]) -> [FavoriteEntry] {
        let tombByKey = dictValues(tombs)
        var merged: [String: Date] = [:]
        for f in (try? ctx.fetch(FetchDescriptor<Favorite>())) ?? [] {
            merged[f.archiveID] = f.addedAt
        }
        for e in cloud {
            if let dead = tombByKey["fav:\(e.archiveID)"], dead >= e.addedAt { continue }
            if merged[e.archiveID] == nil {
                ctx.insert(Favorite(archiveID: e.archiveID))
                merged[e.archiveID] = e.addedAt
            } else {
                merged[e.archiveID] = max(merged[e.archiveID]!, e.addedAt)
            }
        }
        return merged.map { FavoriteEntry(archiveID: $0.key, addedAt: $0.value) }
    }

    private func mergePlaylists(_ ctx: ModelContext, _ cloud: [PlaylistEntry],
                                _ tombs: [TombstoneEntry]) -> [PlaylistEntry] {
        let tombByKey = dictValues(tombs)
        let local = dict((try? ctx.fetch(FetchDescriptor<Playlist>())) ?? [], \.id)
        var merged: [String: PlaylistEntry] = [:]
        for p in local.values {
            merged[p.id] = PlaylistEntry(id: p.id, name: p.name, archiveIDs: p.archiveIDs,
                                         createdAt: p.createdAt, modifiedAt: p.modifiedAt)
        }
        for e in cloud {
            if let dead = tombByKey["pl:\(e.id)"], dead >= e.modifiedAt { continue }
            if let existing = local[e.id] {
                if e.modifiedAt > existing.modifiedAt {   // recency wins -> removals propagate
                    existing.name = e.name
                    existing.archiveIDs = e.archiveIDs
                    existing.modifiedAt = e.modifiedAt
                    merged[e.id] = e
                }
            } else {
                let p = Playlist(id: e.id, name: e.name, archiveIDs: e.archiveIDs)
                p.modifiedAt = e.modifiedAt
                ctx.insert(p)
                merged[e.id] = e
            }
        }
        return Array(merged.values)
    }

    private func mergeProgress(_ ctx: ModelContext, _ cloud: [ProgressEntry],
                               _ tombs: [TombstoneEntry]) -> [ProgressEntry] {
        let tombByKey = dictValues(tombs)
        let local = dict((try? ctx.fetch(FetchDescriptor<WatchProgress>())) ?? [], \.archiveID)
        var merged: [String: ProgressEntry] = [:]
        for w in local.values {
            merged[w.archiveID] = ProgressEntry(
                archiveID: w.archiveID, positionSeconds: w.positionSeconds,
                durationSeconds: w.durationSeconds, lastWatchedAt: w.lastWatchedAt,
                seriesID: w.seriesID, episodeTitle: w.episodeTitle)
        }
        for e in cloud {
            if let dead = tombByKey["wp:\(e.archiveID)"], dead >= e.lastWatchedAt { continue }
            if let existing = local[e.archiveID] {
                if e.lastWatchedAt > existing.lastWatchedAt {
                    existing.positionSeconds = e.positionSeconds
                    if e.durationSeconds > 0 { existing.durationSeconds = e.durationSeconds }
                    existing.lastWatchedAt = e.lastWatchedAt
                    merged[e.archiveID] = e
                }
            } else {
                ctx.insert(WatchProgress(archiveID: e.archiveID,
                                         positionSeconds: e.positionSeconds,
                                         durationSeconds: e.durationSeconds,
                                         seriesID: e.seriesID,
                                         episodeTitle: e.episodeTitle))
                merged[e.archiveID] = e
            }
        }
        return Array(merged.values)
    }

    private func mergeChannels(_ ctx: ModelContext, _ cloud: [ChannelEntry],
                               _ tombs: [TombstoneEntry]) -> [ChannelEntry] {
        let tombByKey = dictValues(tombs)
        let local = dict((try? ctx.fetch(FetchDescriptor<UserChannel>())) ?? [], \.id)
        var merged: [String: ChannelEntry] = [:]
        for c in local.values {
            merged[c.id] = ChannelEntry(id: c.id, name: c.name, genre: c.genre,
                                        contentType: c.contentType, decade: c.decade,
                                        createdAt: c.createdAt)
        }
        for e in cloud {
            if let dead = tombByKey["ch:\(e.id)"], dead >= e.createdAt { continue }
            if merged[e.id] == nil {
                let uc = UserChannel(id: e.id, name: e.name, genre: e.genre,
                                     contentType: e.contentType, decade: e.decade)
                uc.createdAt = e.createdAt
                ctx.insert(uc)
                merged[e.id] = e
            }
        }
        return Array(merged.values)
    }

    // MARK: - Helpers

    private func dict<T, K: Hashable>(_ items: [T], _ key: KeyPath<T, K>) -> [K: T] {
        Dictionary(items.map { ($0[keyPath: key], $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func dictValues(_ tombs: [TombstoneEntry]) -> [String: Date] {
        Dictionary(tombs.map { ($0.key, $0.deletedAt) }, uniquingKeysWith: max)
    }

    /// Human-readable failure, with the two setup mistakes called out by name.
    private static func describe(_ error: Error) -> String {
        guard let ck = error as? CKError else { return error.localizedDescription }
        switch ck.code {
        case .notAuthenticated:
            return "Not signed in to iCloud on this device."
        case .networkUnavailable, .networkFailure:
            return "Network unavailable — will retry."
        case .invalidArguments, .badContainer, .badDatabase:
            return "CloudKit schema/container problem — has the schema been "
                 + "deployed to Production? (\(ck.localizedDescription))"
        case .quotaExceeded:
            return "iCloud storage is full on this account."
        case .permissionFailure:
            return "CloudKit permission failure — check the iCloud capability."
        default:
            return ck.localizedDescription
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
