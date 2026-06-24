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
    nonisolated private static var dir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CreationStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    // v2: one clean shot per film + clean pipe-joined tags (the v1 sample repeated films + had
    // mangled tag tokens). Bumping the name invalidates any stale on-device v1 sample.
    nonisolated static var sampleURL: URL { dir.appendingPathComponent("clips-sample-v2.sqlite") }
    /// The real CI-built index (tools/build_stock_index.py), downloaded from the stock-index release.
    nonisolated static var indexURL: URL { dir.appendingPathComponent("clips.sqlite") }
    /// Prefer the published real index; fall back to the on-device sample.
    nonisolated static var bestURL: URL {
        FileManager.default.fileExists(atPath: indexURL.path) ? indexURL : sampleURL
    }

    init?(path: URL) {
        guard sqlite3_open_v2(path.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle); return nil
        }
    }
    isolated deinit { sqlite3_close(handle) }   // SE-0371: touch the MainActor handle natively

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
                tags: str(5).split(whereSeparator: { $0 == "|" || $0 == " " }).map(String.init), title: str(6)))
        }
        return out
    }
}

// MARK: - Sample index builder (placeholder until the CI shot-mining pipeline)

enum StockIndexBuilder {
    private static let publishedURL = URL(string:
        "https://github.com/bhwilkoff/Archive-Watch/releases/download/stock-index/clips.sqlite.zz")!

    /// Ensure a stock index exists: download the REAL CI-built index (tools/build_stock_index.py
    /// → stock-index release) if present, else synthesize the on-device sample. The real index has
    /// detected shot boundaries; the sample has placeholder windows. Both use the same schema.
    @MainActor
    static func ensureIndex(store: AppStore) async {
        if await downloadPublishedIndex() { return }       // real shots
        buildSampleIfNeeded(store: store)                  // fallback
    }

    /// Download + inflate the published clips.sqlite.zz (raw DEFLATE, Decision 019) into indexURL.
    /// Returns true on success. Skips the network if a fresh copy already exists (<7 days).
    private static func downloadPublishedIndex() async -> Bool {
        let dst = StockIndex.indexURL
        if let attrs = try? FileManager.default.attributesOfItem(atPath: dst.path),
           let mod = attrs[.modificationDate] as? Date, Date().timeIntervalSince(mod) < 7 * 86400 {
            return true
        }
        guard let (tmp, resp) = try? await URLSession.shared.download(from: publishedURL),
              (resp as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true else { return false }
        let zz = StockIndex.indexURL.appendingPathExtension("zz")
        try? FileManager.default.removeItem(at: zz)
        guard (try? FileManager.default.moveItem(at: tmp, to: zz)) != nil else { return false }
        defer { try? FileManager.default.removeItem(at: zz) }
        do { try CatalogRefreshService.inflate(src: zz, dst: dst); return true } catch { return false }
    }

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

        // ONE representative window per film (the sample's placeholder cut). The same film no
        // longer repeats as N near-identical cards (#6); the real pipeline replaces these with
        // PySceneDetect shots that genuinely differ. Tags are discrete + clean (drop sentence-
        // long subjects + punctuation), pipe-joined so multi-word tags survive the split.
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        for item in items {
            guard let url = item.videoURLParsed else { continue }
            let tags = (item.genres + Array(item.subjects.prefix(2)))
                .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count <= 22 && !$0.contains(":") && !$0.contains(";") }
                .prefix(4)
                .joined(separator: "|")
            let dur = (item.runtimeSeconds.map(Double.init) ?? 120)
            let inS = min(5, max(0, dur - 8))
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, item.archiveID, -1, SQLITE_TRANSIENT_STOCK)
            sqlite3_bind_text(stmt, 2, item.archiveID, -1, SQLITE_TRANSIENT_STOCK)
            sqlite3_bind_text(stmt, 3, url.absoluteString, -1, SQLITE_TRANSIENT_STOCK)
            sqlite3_bind_double(stmt, 4, inS)
            sqlite3_bind_double(stmt, 5, inS + 8)
            sqlite3_bind_text(stmt, 6, tags, -1, SQLITE_TRANSIENT_STOCK)
            sqlite3_bind_text(stmt, 7, item.title, -1, SQLITE_TRANSIENT_STOCK)
            sqlite3_step(stmt)
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }
}
#endif
