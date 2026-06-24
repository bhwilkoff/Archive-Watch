#if os(macOS)
import Foundation
import SQLite3

// The subtitle CUE index for the text→supercut (#9, docs/macOS-DESIGN.md §5/§6). Search a phrase
// and find every moment across the public-domain catalog where it is SPOKEN, then assemble those
// moments into an EDITABLE timeline of candidates (Rule 5a — never a one-tap finished cut).
//
// This is the QUERY LAYER + a SAMPLE index (real human caption VTTs parsed into cues); the full
// `subtitle.sqlite` is built in CI by tools/build_subtitle_index.py over the whole /subs corpus,
// with the SAME `cues` schema, so swapping in the published index is just changing the file.
// Word-level isolation (Rule 6b — SpeechTranscriber timing validated against the caption text)
// is the refinement; v1 is line-level: the clip is the spoken CUE that contains the phrase.

let SQLITE_TRANSIENT_SUB = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct SubtitleCue: Identifiable, Hashable, Sendable {
    let id: String
    let archiveID: String
    let sourceURL: URL
    let startSeconds: Double
    let endSeconds: Double
    let text: String
    let title: String

    var durationSeconds: Double { max(0.4, endSeconds - startSeconds) }
    var timecode: String { String(format: "%d:%02d", Int(startSeconds) / 60, Int(startSeconds) % 60) }

    /// A clip of the spoken line, padded slightly so the line isn't clipped at the edges.
    var proxyClip: ProxyClip {
        let pad = 0.25
        let inS = max(0, startSeconds - pad)
        return ProxyClip(catalogItemID: archiveID, sourceURL: sourceURL,
                         sourceRange: TimeRange(startSeconds: inS, durationSeconds: durationSeconds + pad * 2),
                         label: "\(title): \(text.prefix(28))", posterFrameSeconds: startSeconds, title: title)
    }
}

@MainActor
final class SubtitleIndex {
    private var handle: OpaquePointer?

    nonisolated private static var dir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CreationStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    nonisolated static var sampleURL: URL { dir.appendingPathComponent("subtitle-sample.sqlite") }
    /// The full-corpus CI index (tools/build_subtitle_index.py), downloaded from subtitle-index.
    nonisolated static var indexURL: URL { dir.appendingPathComponent("subtitle.sqlite") }
    nonisolated static var bestURL: URL {
        FileManager.default.fileExists(atPath: indexURL.path) ? indexURL : sampleURL
    }

    init?(path: URL) {
        guard sqlite3_open_v2(path.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle); return nil
        }
    }
    isolated deinit { sqlite3_close(handle) }

    /// Cues whose text contains the phrase (LIKE for the sample; the CI index adds FTS5). Ordered
    /// so a SHORTER cue (a tighter quote of the phrase) ranks first.
    func search(_ phrase: String, limit: Int = 200) -> [SubtitleCue] {
        let q = phrase.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let sql = """
            SELECT id,archiveID,sourceURL,startSeconds,endSeconds,text,title FROM cues
            WHERE text LIKE ?1 ORDER BY (endSeconds-startSeconds) ASC LIMIT \(limit)
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, "%\(q)%", -1, SQLITE_TRANSIENT_SUB)
        var out: [SubtitleCue] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func str(_ i: Int32) -> String { sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "" }
            guard let url = URL(string: str(2)) else { continue }
            out.append(SubtitleCue(id: str(0), archiveID: str(1), sourceURL: url,
                                   startSeconds: sqlite3_column_double(stmt, 3),
                                   endSeconds: sqlite3_column_double(stmt, 4),
                                   text: str(5), title: str(6)))
        }
        return out
    }

    /// Frame-accurate range of `run` (a word sequence) from the forced-aligned `words` table
    /// (build_word_index.py, Phase B), searched near `nearSeconds`. nil if no word index / no match
    /// — the composer then falls back to its proportional estimate. The table may be absent.
    func wordRange(archiveID: String, run: [String], nearSeconds: Double) -> TimeRange? {
        guard !run.isEmpty,
              sqlite3_exec(handle, "SELECT 1 FROM words LIMIT 1", nil, nil, nil) == SQLITE_OK else { return nil }
        // pull the film's words around the cue, then find the contiguous run.
        let sql = """
            SELECT word, startSeconds, endSeconds FROM words
            WHERE archiveID=?1 AND startSeconds BETWEEN ?2 AND ?3 ORDER BY startSeconds
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, archiveID, -1, SQLITE_TRANSIENT_SUB)
        sqlite3_bind_double(stmt, 2, nearSeconds - 3)
        sqlite3_bind_double(stmt, 3, nearSeconds + 12)
        var words: [(String, Double, Double)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let w = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            words.append((w, sqlite3_column_double(stmt, 1), sqlite3_column_double(stmt, 2)))
        }
        let target = run.map { $0.lowercased() }
        guard words.count >= target.count else { return nil }
        for s in 0...(words.count - target.count) where (0..<target.count).allSatisfy({ words[s + $0].0 == target[$0] }) {
            let start = max(0, words[s].1 - 0.1)
            let end = words[s + target.count - 1].2 + 0.12
            return TimeRange(startSeconds: start, durationSeconds: max(0.2, end - start))
        }
        return nil
    }

    var cueCount: Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT count(*) FROM cues", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }
}

// MARK: - WebVTT parsing

enum VTTParser {
    /// (startSeconds, endSeconds, text) cues from WebVTT/SRT text.
    static func cues(_ vtt: String) -> [(Double, Double, String)] {
        var out: [(Double, Double, String)] = []
        let blocks = vtt.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let tIdx = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[tIdx].components(separatedBy: "-->")
            guard parts.count == 2, let a = seconds(parts[0]), let b = seconds(parts[1]) else { continue }
            let text = lines[(tIdx + 1)...].joined(separator: " ")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if !text.isEmpty, b > a { out.append((a, b, text)) }
        }
        return out
    }
    private static func seconds(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? s
        let comps = t.replacingOccurrences(of: ",", with: ".").split(separator: ":").map { Double($0) ?? 0 }
        switch comps.count {
        case 3: return comps[0] * 3600 + comps[1] * 60 + comps[2]
        case 2: return comps[0] * 60 + comps[1]
        default: return nil
        }
    }
}

// MARK: - Sample index builder (real cues; the CI tool builds the full corpus)

enum SubtitleIndexBuilder {
    private static let publishedURL = URL(string:
        "https://github.com/bhwilkoff/Archive-Watch/releases/download/subtitle-index/subtitle.sqlite.zz")!

    /// Ensure a cue index exists: download the full-corpus CI index if published, else synthesize
    /// the on-device sample. Same `cues` schema either way (StockIndex pattern).
    @MainActor
    static func ensureIndex(store: AppStore) async {
        if await downloadPublishedIndex() { return }
        await buildSampleIfNeeded(store: store)
    }

    private static func downloadPublishedIndex() async -> Bool {
        let dst = SubtitleIndex.indexURL
        if let attrs = try? FileManager.default.attributesOfItem(atPath: dst.path),
           let mod = attrs[.modificationDate] as? Date, Date().timeIntervalSince(mod) < 7 * 86400 {
            return true
        }
        guard let (tmp, resp) = try? await URLSession.shared.download(from: publishedURL),
              (resp as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true else { return false }
        let zz = dst.appendingPathExtension("zz")
        try? FileManager.default.removeItem(at: zz)
        guard (try? FileManager.default.moveItem(at: tmp, to: zz)) != nil else { return false }
        defer { try? FileManager.default.removeItem(at: zz) }
        do { try CatalogRefreshService.inflate(src: zz, dst: dst); return true } catch { return false }
    }

    /// Build the sample subtitle.sqlite from a batch of captioned titles' real VTTs, if absent.
    @MainActor
    static func buildSampleIfNeeded(store: AppStore, maxFilms: Int = 60) async {
        let url = SubtitleIndex.sampleURL
        if FileManager.default.fileExists(atPath: url.path) { return }
        let captioned = store.browse(sort: .popular, limit: 1200).filter {
            $0.isClippable && ($0.captions?.contains { $0.vttURL != nil } ?? false)
        }.prefix(maxFilms)
        guard !captioned.isEmpty else { return }

        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            sqlite3_close(db); return
        }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, """
            CREATE TABLE IF NOT EXISTS cues(
              id TEXT PRIMARY KEY, archiveID TEXT, sourceURL TEXT,
              startSeconds REAL, endSeconds REAL, text TEXT, title TEXT);
            """, nil, nil, nil)
        let insert = "INSERT OR REPLACE INTO cues VALUES(?,?,?,?,?,?,?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insert, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        for item in captioned {
            guard let url = item.videoURLParsed,
                  let vttStr = item.captions?.first(where: { $0.vttURL != nil })?.vttURL,
                  let vttURL = URL(string: vttStr),
                  let (data, _) = try? await URLSession.shared.data(from: vttURL),
                  let vtt = String(data: data, encoding: .utf8) else { continue }
            sqlite3_exec(db, "BEGIN", nil, nil, nil)
            for (i, cue) in VTTParser.cues(vtt).enumerated() {
                sqlite3_reset(stmt)
                sqlite3_bind_text(stmt, 1, "\(item.archiveID)#\(i)", -1, SQLITE_TRANSIENT_SUB)
                sqlite3_bind_text(stmt, 2, item.archiveID, -1, SQLITE_TRANSIENT_SUB)
                sqlite3_bind_text(stmt, 3, url.absoluteString, -1, SQLITE_TRANSIENT_SUB)
                sqlite3_bind_double(stmt, 4, cue.0)
                sqlite3_bind_double(stmt, 5, cue.1)
                sqlite3_bind_text(stmt, 6, cue.2, -1, SQLITE_TRANSIENT_SUB)
                sqlite3_bind_text(stmt, 7, item.title, -1, SQLITE_TRANSIENT_SUB)
                sqlite3_step(stmt)
            }
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        }
    }

    /// Headless end-to-end check (AW_CS_SUPERTEST=1): build the sample index from real VTTs and
    /// run a couple of phrase searches, so the VTT parse + index + search are verified offline.
    @MainActor
    static func selfTest(store: AppStore) async {
        func log(_ s: String) { FileHandle.standardError.write(Data("AWCS SUPERTEST: \(s)\n".utf8)) }
        try? FileManager.default.removeItem(at: SubtitleIndex.sampleURL)   // fresh each run
        var t = 0; while store.randomPlayable() == nil && t < 60 { try? await Task.sleep(for: .seconds(1)); t += 1 }
        await buildSampleIfNeeded(store: store, maxFilms: 25)
        guard let index = SubtitleIndex(path: SubtitleIndex.sampleURL) else { log("no index built"); return }
        log("indexed cues = \(index.cueCount)")
        for phrase in ["love", "you", "the end", "kill"] {
            let r = index.search(phrase, limit: 5)
            log("search \"\(phrase)\" -> \(r.count) hits")
            for c in r.prefix(2) { log("   \(c.title) @\(c.timecode): \(c.text.prefix(50))") }
        }
        // Sentence composer (v2): greedy longest-match coverage of a line, missing words flagged.
        for sentence in ["I love you", "this is the end of the world", "kill the lights"] {
            let plan = SentenceComposer.plan(sentence, index: index)
            let cov = "\(plan.filter { $0.found }.count)/\(plan.count) words, \(plan.filter { $0.found }.count) clips"
            let detail = plan.map { $0.found ? "[\($0.phrase)→\($0.chosen!.cue.title.prefix(10))×\($0.candidates.count)]" : "[\($0.phrase)=GAP]" }
                .joined(separator: " ")
            log("COMPOSE \"\(sentence)\" -> \(cov): \(detail)")
        }
    }
}
#endif
