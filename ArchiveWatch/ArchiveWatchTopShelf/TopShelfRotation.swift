import Foundation

// The pure half of the Top Shelf provider: decoding the published feed and
// choosing what to show this rotation window (tvOS-DESIGN §15.3).
//
// Deliberately Foundation-only — NO TVServices import — so it compiles on macOS
// and `tools/test_topshelf_rotation.swift` can exercise THIS file against the
// real topshelf.json. The Top Shelf is invisible to a simulator screenshot and
// the extension is out-of-process, so a harness over the actual shipped code is
// the only honest way to prove the shelf changes.

/// How long a row selection holds still. Long enough that the shelf never
/// reshuffles under someone browsing it, short enough that morning and evening
/// differ.
let kRotationWindow: TimeInterval = 6 * 60 * 60
let kMaxEditorialRows = 4      // + Continue Watching = 5 (§15.8)
let kMaxTilesPerRow = 8

/// A row item, normalized from either source (feed or App Group snapshot).
struct Card {
    let id: String
    let title: String
    let year: Int?
    let posterURL: URL
    let resume: Bool
    let progress: Double?
}

struct Section { let title: String; let cards: [Card] }

struct FeedPayload: Decodable {
    struct Item: Decodable { let id: String; let title: String; let year: Int?; let poster: String }
    struct Row: Decodable { let id: String; let title: String; let items: [Item] }
    struct LegacySection: Decodable { let title: String; let items: [Item] }
    /// Schema 2: pools to rotate over.
    let rows: [Row]?
    /// Schema 1 shape; still published so already-shipped builds keep working.
    let sections: [LegacySection]?
}

/// The current rotation bucket.
func rotationWindow(now: Date = Date()) -> Int {
    Int(now.timeIntervalSince1970 / kRotationWindow)
}

/// FNV-1a. Used instead of `hashValue` because Swift seeds string hashing PER
/// PROCESS — a `hashValue`-derived offset would reshuffle the shelf on every
/// single query instead of holding still for the window.
func stableHash(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in s.utf8 { h ^= UInt64(b); h = h &* 0x0000_0100_0000_01b3 }
    return h
}

/// A step that spreads `k` picks across `n` rows AND still visits every row as
/// the start slides — i.e. roughly n/k, nudged until it is coprime with n.
///
/// Taking a CONTIGUOUS slice instead looked fine in the assertions and was wrong
/// on screen: the feed's rows are published in priority order, so a contiguous
/// window of 4 eventually lands entirely in the tail and renders a shelf of
/// Prelinger + NASA + Newsreels with no marquee cinema on it at all. Striding
/// guarantees every window spans the whole priority range.
func spreadStride(n: Int, k: Int) -> Int {
    guard n > 1, k > 0 else { return 1 }
    func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
    var s = max(1, n / k)
    var guard_ = 0
    while gcd(s, n) != 1 && guard_ < n { s += 1; if s >= n { s = 1 }; guard_ += 1 }
    return gcd(s, n) == 1 ? s : 1
}

/// Pick the rows and titles for this rotation window.
///
/// The starting row advances by one per window and the picks stride across the
/// priority list, so which headings appear changes AND every shelf mixes a
/// marquee row with a deeper one. Each row's start offset then walks its own pool
/// on a per-row stride, so a row that comes back around a day later leads with
/// different films. All arithmetic on the window — deterministic within a window,
/// and debuggable.
func rotate(_ payload: FeedPayload, window: Int) -> [Section] {
    let rows: [(id: String, title: String, items: [FeedPayload.Item])] =
        payload.rows.map { $0.map { (id: $0.id, title: $0.title, items: $0.items) } }
        ?? (payload.sections ?? []).map { (id: $0.title, title: $0.title, items: $0.items) }
    guard !rows.isEmpty else { return [] }

    let start = ((window % rows.count) + rows.count) % rows.count
    let stride = spreadStride(n: rows.count, k: kMaxEditorialRows)

    var out: [Section] = []
    for i in 0..<min(kMaxEditorialRows, rows.count) {
        let row = rows[(start + i * stride) % rows.count]
        let pool = row.items
        guard !pool.isEmpty else { continue }
        let offset = Int((stableHash(row.id) &+ UInt64(bitPattern: Int64(window &* 7)))
                         % UInt64(pool.count))
        let cards: [Card] = (0..<min(kMaxTilesPerRow, pool.count)).compactMap { n in
            let item = pool[(offset + n) % pool.count]
            guard let url = URL(string: item.poster) else { return nil }
            return Card(id: item.id, title: item.title, year: item.year,
                        posterURL: url, resume: false, progress: nil)
        }
        if !cards.isEmpty { out.append(Section(title: row.title, cards: cards)) }
    }
    return out
}

/// Drop any title already shown higher up — Continue Watching wins, since it
/// carries the resume bar. Returns rows that still have tiles.
func dedupe(_ sections: [Section]) -> [Section] {
    var seen = Set<String>()
    var out: [Section] = []
    for s in sections {
        let cards = s.cards.filter { seen.insert($0.id).inserted }
        if !cards.isEmpty { out.append(Section(title: s.title, cards: Array(cards.prefix(kMaxTilesPerRow)))) }
    }
    return out
}
