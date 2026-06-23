#if os(macOS)
import Foundation
import SQLite3

// The stock-shot index (Phase 3 #6 — "Storyblocks for archive.org"; docs/macOS-DESIGN.md §6).
// This is the QUERY LAYER + a SAMPLE index; the heavy CI shot-mining pipeline (PySceneDetect
// → Vision classify → MobileCLIP embeddings → the real clips.sqlite) is a later session. The
// SCHEMA here matches what that pipeline will emit (a `shots` table), so swapping in the
// published clips.sqlite is just changing the source file — the browser + query layer are
// ready now. Until then a sample index is synthesized from the catalog (real archive.org
// URLs + tags from each title's genres/subjects; shot boundaries are placeholder ranges).

let SQLITE_TRANSIENT_STOCK = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct StockShot: Identifiable, Hashable, Sendable {
    let id: String
    let archiveID: String
    let sourceURL: URL
    let startSeconds: Double
    let endSeconds: Double
    let tags: [String]
    let title: String

    var durationSeconds: Double { max(0, endSeconds - startSeconds) }

    var proxyClip: ProxyClip {
        ProxyClip(catalogItemID: archiveID, sourceURL: sourceURL,
                  sourceRange: TimeRange(startSeconds: startSeconds, durationSeconds: durationSeconds),
                  label: tags.first.map { "\(title) · \($0)" } ?? title,
                  posterFrameSeconds: startSeconds, title: title)
    }
}

@MainActor
final class StockIndex {
    private var handle: OpaquePointer?

    /// Caches/clips-sample.sqlite — the disposable sample index (swapped for the published
    /// clips.sqlite once the CI pipeline exists). Lives in Caches; never synced.
    static var sampleURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CreationStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("clips-sample.sqlite")
    }

    init?(path: URL) {
        guard sqlite3_open_v2(path.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle); return nil
        }
    }
    deinit { sqlite3_close(handle) }

    /// Shots matching a free-text query over tags + title (LIKE for the sample; the real
    /// index will add MobileCLIP/sqlite-vec semantic search).
    func query(_ text: String, limit: Int = 150) -> [StockShot] {
        let q = text.trimmingCharacters(in: .whitespaces)
        let sql: String
        if q.isEmpty {
            sql = "SELECT id,archiveID,sourceURL,startSeconds,endSeconds,tags,title FROM shots LIMIT \(limit)"
        } else {
            sql = "SELECT id,archiveID,sourceURL,startSeconds,endSeconds,tags,title FROM shots WHERE tags LIKE ?1 OR title LIKE ?1 LIMIT \(limit)"
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        if !q.isEmpty { sqlite3_bind_text(stmt, 1, "%\(q)%", -1, SQLITE_TRANSIENT_STOCK) }

        var out: [StockShot] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func str(_ i: Int32) -> String { sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "" }
            guard let url = URL(string: str(2)) else { continue }
            out.append(StockShot(
                id: str(0), archiveID: str(1), sourceURL: url,
                startSeconds: sqlite3_column_double(stmt, 3), endSeconds: sqlite3_column_double(stmt, 4),
                tags: str(5).split(separator: " ").map(String.init), title: str(6)))
        }
        return out
    }
}

// MARK: - Sample index builder (placeholder until the CI shot-mining pipeline)

enum StockIndexBuilder {
    /// Build the sample clips.sqlite from the catalog if it doesn't exist yet. Each clippable
    /// title contributes a few placeholder shots tagged with its real genres/subjects.
    @MainActor
    static func buildSampleIfNeeded(store: AppStore) {
        let url = StockIndex.sampleURL
        if FileManager.default.fileExists(atPath: url.path) { return }
        let items = store.browse(sort: .popular, limit: 120).filter { $0.isClippable }
        guard !items.isEmpty else { return }

        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            sqlite3_close(db); return
        }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, """
            CREATE TABLE IF NOT EXISTS shots(
              id TEXT PRIMARY KEY, archiveID TEXT, sourceURL TEXT,
              startSeconds REAL, endSeconds REAL, tags TEXT, title TEXT);
            """, nil, nil, nil)

        let insert = "INSERT OR REPLACE INTO shots VALUES(?,?,?,?,?,?,?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insert, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        // Placeholder shot windows; the real pipeline replaces these with PySceneDetect cuts.
        let windows: [(Double, Double)] = [(5, 13), (22, 30), (45, 53)]
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        for item in items {
            guard let url = item.videoURLParsed else { continue }
            let tags = (item.genres + item.subjects.prefix(3)).map {
                $0.lowercased().replacingOccurrences(of: " ", with: "-")
            }.joined(separator: " ")
            let maxWindows = (item.runtimeSeconds.map { $0 > 60 ? 3 : ($0 > 30 ? 2 : 1) }) ?? 2
            for (i, w) in windows.prefix(maxWindows).enumerated() {
                sqlite3_reset(stmt)
                let id = "\(item.archiveID)#\(i)"
                sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT_STOCK)
                sqlite3_bind_text(stmt, 2, item.archiveID, -1, SQLITE_TRANSIENT_STOCK)
                sqlite3_bind_text(stmt, 3, url.absoluteString, -1, SQLITE_TRANSIENT_STOCK)
                sqlite3_bind_double(stmt, 4, w.0)
                sqlite3_bind_double(stmt, 5, w.1)
                sqlite3_bind_text(stmt, 6, tags, -1, SQLITE_TRANSIENT_STOCK)
                sqlite3_bind_text(stmt, 7, item.title, -1, SQLITE_TRANSIENT_STOCK)
                sqlite3_step(stmt)
            }
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }
}
#endif
