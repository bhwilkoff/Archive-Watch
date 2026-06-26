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
    var imdbID: String = ""        // film identity for de-dup across re-uploads ("" if the index lacks it)

    /// Canonical FILM key for de-duplication: the IMDb id when present, else a normalized title
    /// (lowercased, year + punctuation stripped), else the archiveID. Re-uploads / derivatives of the
    /// same film collapse to one; distinct films stay separate.
    var filmKey: String {
        if !imdbID.isEmpty { return "imdb:" + imdbID }
        let t = title.lowercased()
            .replacingOccurrences(of: "\\([0-9]{4}\\)", with: "", options: .regularExpression)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        return t.isEmpty ? archiveID : "t:" + t
    }

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

// Thread-safe + OFF the main actor: a `LIKE` scan over the full cue corpus is slow, and the
// longest-match composer fires ~O(words²) of them — doing that on the main thread beachballs the UI.
// All handle access is serialized on a private queue (@unchecked Sendable), so callers can query from
// a background task and the main thread stays responsive (the compose view shows live progress).
final class SubtitleIndex: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.bhwilkoff.archivewatch.subtitle-index")
    private let hasIMDB: Bool      // older published indexes predate the imdbID column

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
        // mmap OFF: a file corrupted under disk pressure faults an mmap'd read as EXC_BAD_ACCESS
        // (the crash signature) instead of a recoverable SQLITE_CORRUPT. busy_timeout lets a query
        // wait out the brief RW lock when ensureLookupIndex is creating the index.
        sqlite3_exec(handle, "PRAGMA mmap_size=0; PRAGMA busy_timeout=3000;", nil, nil, nil)
        // Detect the optional imdbID column (newer indexes) so search can de-dup by film identity.
        hasIMDB = sqlite3_exec(handle, "SELECT imdbID FROM cues LIMIT 0", nil, nil, nil) == SQLITE_OK
    }
    deinit { sqlite3_close(handle) }   // no concurrent access at dealloc (ARC holds self through queries)

    /// Cues whose text contains the phrase (LIKE for the sample; the CI index adds FTS5). Ordered
    /// so a SHORTER cue (a tighter quote of the phrase) ranks first.
    ///
    /// A CONFIDENCE GATE (stricter than playback) is applied: the player shows whatever caption
    /// exists, but the supercut puts the caption ON SCREEN AS TRUTH ("the catalog speaks your
    /// words"), so a wrong/hallucinated line is far more damaging here. We drop the tells of bad
    /// ASR (Decision 043): repeated-token runs ("why why why"), a low distinct-word ratio, and an
    /// impossible character-per-second rate. We over-fetch then filter so `limit` survivors remain.
    func search(_ phrase: String, limit: Int = 200) -> [SubtitleCue] {
        let q = phrase.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return dbQueue.sync {
            let imdbCol = hasIMDB ? "imdbID" : "''"
            let sql = """
                SELECT id,archiveID,sourceURL,startSeconds,endSeconds,text,title,\(imdbCol) FROM cues
                WHERE text LIKE ?1 ORDER BY (endSeconds-startSeconds) ASC LIMIT \(limit * 4)
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, "%\(q)%", -1, SQLITE_TRANSIENT_SUB)
            var out: [SubtitleCue] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                func str(_ i: Int32) -> String { sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "" }
                guard let url = URL(string: str(2)) else { continue }
                let start = sqlite3_column_double(stmt, 3), end = sqlite3_column_double(stmt, 4)
                let text = str(5)
                guard Self.isConfident(text: text, start: start, end: end) else { continue }
                out.append(SubtitleCue(id: str(0), archiveID: str(1), sourceURL: url,
                                       startSeconds: start, endSeconds: end, text: text,
                                       title: str(6), imdbID: str(7)))
                if out.count >= limit { break }
            }
            return out
        }
    }

    /// The supercut confidence gate. Returns false for captions that read as garbage/hallucinated
    /// ASR, so they never reach the supercut UI (where the caption is presented as ground truth).
    static func isConfident(text: String, start: Double, end: Double) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }
        let words = trimmed.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !words.isEmpty else { return false }
        // 1) Repeated-token run — the classic hallucination signature ("why why why why").
        var run = 1
        for i in 1..<max(1, words.count) {
            if words[i] == words[i - 1] { run += 1; if run >= 3 { return false } } else { run = 1 }
        }
        // 2) Low distinct-word ratio over a longer line (e.g. "alright alright alright …").
        if words.count >= 4, Double(Set(words).count) / Double(words.count) < 0.5 { return false }
        // 3) Impossible speech rate. Real speech is well under ~25 chars/sec; garbage cues pack
        //    many characters into a fraction of a second. Stricter than the player would ever need.
        let dur = end - start
        guard dur >= 0.3 else { return false }
        if Double(trimmed.count) / dur > 30 { return false }
        return true
    }

    /// Frame-accurate range of `run` (a word sequence) from the forced-aligned `words` table
    /// (build_word_index.py, Phase B), searched near `nearSeconds`. nil if no word index / no match
    /// — the composer then falls back to its proportional estimate. The table may be absent.
    func wordRange(archiveID: String, run: [String], nearSeconds: Double) -> TimeRange? {
        guard !run.isEmpty else { return nil }
        return dbQueue.sync {
            guard sqlite3_exec(handle, "SELECT 1 FROM words LIMIT 1", nil, nil, nil) == SQLITE_OK else { return nil }
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
    }

    /// Expand a matched cue to its FULL SPOKEN STATEMENT — the OPPOSITE of word-tightening. Walks the
    /// film's neighboring cues outward from the MATCHED cue, stopping where a sentence ENDS (terminal
    /// punctuation) or at a natural PAUSE (a silent gap between cues). The returned range ALWAYS covers
    /// the matched cue's own span `[matchStart, matchEnd]`, so the searched phrase is guaranteed to be
    /// inside the clip (owner: "the clip added to the timeline should always contain the phrase"). nil
    /// if neighbors can't be read (the caller falls back to the cue's own padded range).
    func sentenceRange(archiveID: String, matchStart: Double, matchEnd: Double,
                       maxSpread: Double = 25, maxDuration: Double = 12) -> TimeRange? {
        return dbQueue.sync {
            let sql = """
                SELECT startSeconds,endSeconds,text FROM cues
                WHERE archiveID=?1 AND endSeconds>=?2 AND startSeconds<=?3 ORDER BY startSeconds
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, archiveID, -1, SQLITE_TRANSIENT_SUB)
            sqlite3_bind_double(stmt, 2, matchStart - maxSpread)
            sqlite3_bind_double(stmt, 3, matchStart + maxSpread)
            var cues: [(s: Double, e: Double, t: String)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let t = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                cues.append((sqlite3_column_double(stmt, 0), sqlite3_column_double(stmt, 1), t))
            }
            guard !cues.isEmpty else { return nil }
            // anchor = the MATCHED cue itself: the cue whose start is closest to matchStart. (Picking
            // by "time window contains nearSeconds" mis-selected an overlapping/adjacent PREVIOUS cue,
            // building the sentence around the wrong line so the phrase fell outside the clip.)
            let anchor = cues.indices.min(by: {
                abs(cues[$0].s - matchStart) < abs(cues[$1].s - matchStart) })!
            let pause = 1.2
            func endsSentence(_ s: String) -> Bool {
                guard let last = s.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
                return ".!?".contains(last)
            }
            var lo = anchor
            while lo > 0 {
                let prev = cues[lo - 1]
                if endsSentence(prev.t) { break }            // prev ended a sentence → ours starts here
                if cues[lo].s - prev.e > pause { break }      // natural pause before this cue
                if cues[anchor].e - prev.s > maxDuration { break } // cap: captions without periods can run on
                lo -= 1
            }
            var hi = anchor
            while hi < cues.count - 1 {
                if endsSentence(cues[hi].t) { break }         // this cue ends the sentence
                if cues[hi + 1].s - cues[hi].e > pause { break }
                if cues[hi + 1].e - cues[lo].s > maxDuration { break }   // cap the clip length
                hi += 1
            }
            // Union with the matched cue's own span so the phrase is ALWAYS inside the clip, even if a
            // cap/boundary would otherwise trim past it.
            let start = max(0, min(cues[lo].s, matchStart) - 0.2)
            let end = max(cues[hi].e, matchEnd) + 0.25
            return TimeRange(startSeconds: start, durationSeconds: max(0.4, end - start))
        }
    }

    var cueCount: Int {
        dbQueue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "SELECT count(*) FROM cues", -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }
            return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
        }
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

    /// Auto-ASR captions hallucinate wrong words (Decision 039b/043) — never index them for the
    /// supercut, where the caption is presented as truth. Human/uploader sources only.
    static func isAutoSource(_ source: String?) -> Bool {
        let s = (source ?? "").lowercased()
        return s.contains("asr") || s.contains("auto") || s.contains("whisper")
    }

    /// Ensure a cue index exists: download the full-corpus CI index if published, else synthesize
    /// the on-device sample. Same `cues` schema either way (StockIndex pattern). Then ensure the
    /// archiveID index exists so per-film lookups (sentenceRange / wordRange) don't full-scan.
    @MainActor
    static func ensureIndex(store: AppStore) async {
        if !(await downloadPublishedIndex()) {
            await buildSampleIfNeeded(store: store)
        }
        await Task.detached { ensureLookupIndex() }.value
    }

    /// Add the (archiveID, startSeconds) index to the active cue DB if missing — a one-time, persisted,
    /// idempotent step. Without it, sentenceRange's per-cue `WHERE archiveID=…` scans the whole corpus
    /// (the "Clip only full sentences" latency); the index makes each lookup instant. Runs off-main;
    /// opens the cache file read-write just for the CREATE INDEX (the query handle stays read-only).
    static func ensureLookupIndex() {
        let url = SubtitleIndex.bestURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { sqlite3_close(db); return }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "PRAGMA mmap_size=0; PRAGMA busy_timeout=4000;", nil, nil, nil)
        sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_cues_aid ON cues(archiveID, startSeconds)", nil, nil, nil)
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
            $0.isClippable && ($0.captions?.contains { $0.vttURL != nil && !isAutoSource($0.source) } ?? false)
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
              startSeconds REAL, endSeconds REAL, text TEXT, title TEXT, imdbID TEXT);
            CREATE INDEX IF NOT EXISTS idx_cues_aid ON cues(archiveID, startSeconds);
            """, nil, nil, nil)
        let insert = "INSERT OR REPLACE INTO cues VALUES(?,?,?,?,?,?,?,?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insert, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        for item in captioned {
            guard let url = item.videoURLParsed,
                  let vttStr = item.captions?.first(where: { $0.vttURL != nil && !Self.isAutoSource($0.source) })?.vttURL,
                  let vttURL = URL(string: vttStr),
                  let (data, _) = try? await URLSession.shared.data(from: vttURL),
                  let vtt = String(data: data, encoding: .utf8) else { continue }
            sqlite3_exec(db, "BEGIN", nil, nil, nil)
            for (i, cue) in VTTParser.cues(vtt).enumerated() {
                guard SubtitleIndex.isConfident(text: cue.2, start: cue.0, end: cue.1) else { continue }
                sqlite3_reset(stmt)
                sqlite3_bind_text(stmt, 1, "\(item.archiveID)#\(i)", -1, SQLITE_TRANSIENT_SUB)
                sqlite3_bind_text(stmt, 2, item.archiveID, -1, SQLITE_TRANSIENT_SUB)
                sqlite3_bind_text(stmt, 3, url.absoluteString, -1, SQLITE_TRANSIENT_SUB)
                sqlite3_bind_double(stmt, 4, cue.0)
                sqlite3_bind_double(stmt, 5, cue.1)
                sqlite3_bind_text(stmt, 6, cue.2, -1, SQLITE_TRANSIENT_SUB)
                sqlite3_bind_text(stmt, 7, item.title, -1, SQLITE_TRANSIENT_SUB)
                sqlite3_bind_text(stmt, 8, item.imdbID ?? "", -1, SQLITE_TRANSIENT_SUB)
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
