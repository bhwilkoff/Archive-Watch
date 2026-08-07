// Top Shelf rotation harness — asserts that the shelf actually CHANGES.
//
//   swiftc -O tools/test_topshelf_rotation.swift \
//          ArchiveWatch/ArchiveWatchTopShelf/TopShelfRotation.swift \
//          -o /tmp/ts_rotation && /tmp/ts_rotation topshelf.json
//
// The Top Shelf is invisible to a simulator screenshot and its provider runs
// out-of-process, so "it looks right" is not available as evidence here. This
// compiles the SHIPPED rotation file (not a copy of it) against the real
// published feed and checks the properties tvOS-DESIGN §15 requires — the
// failure mode being tested for is precisely the one that shipped: content that
// is stable forever rather than stable-within-a-window.

import Foundation

@main
struct TopShelfRotationTests {
static func main() {

    var failures: [String] = []
    var checks = 0

    func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        checks += 1
        if ok { print("  PASS  \(name)") }
        else {
            let d = detail()
            print("  FAIL  \(name)\(d.isEmpty ? "" : " — \(d)")")
            failures.append(name)
        }
    }

    let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "topshelf.json"
    guard let data = FileManager.default.contents(atPath: path),
          let feed = try? JSONDecoder().decode(FeedPayload.self, from: data) else {
        print("could not read/decode \(path)"); exit(2)
    }

    let pools = feed.rows ?? []
    print("feed: \(pools.count) rows, \(pools.reduce(0) { $0 + $1.items.count }) items\n")

    // --- 1. The feed itself must carry enough to rotate over.
    check("feed uses schema 2 (rows)", !pools.isEmpty)
    check("more rows published than shown", pools.count > kMaxEditorialRows,
          "\(pools.count) rows vs \(kMaxEditorialRows) shown")
    check("pools deeper than one screenful",
          pools.allSatisfy { $0.items.count > kMaxTilesPerRow || $0.items.count >= 3 },
          pools.filter { $0.items.count <= kMaxTilesPerRow }.map(\.id).joined(separator: ","))
    check("every tile has a usable poster URL",
          pools.allSatisfy { $0.items.allSatisfy { URL(string: $0.poster)?.scheme == "https" } })

    // --- 2. Stable WITHIN a window (nothing reshuffles under the viewer).
    let w = rotationWindow()
    let a = rotate(feed, window: w), b = rotate(feed, window: w)
    check("deterministic within a window",
          a.map { $0.title + $0.cards.map(\.id).joined() } == b.map { $0.title + $0.cards.map(\.id).joined() })

    // --- 3. Changes ACROSS windows — the whole point (§15.3).
    //        A full day is 4 windows; walk a month of them.
    var rowSignatures = Set<String>()
    var titleSignatures = Set<String>()
    var everyTitleSeen = Set<String>()
    for step in 0..<120 {
        let secs = rotate(feed, window: w + step)
        rowSignatures.insert(secs.map(\.title).joined(separator: "|"))
        titleSignatures.insert(secs.flatMap { $0.cards.map(\.id) }.joined(separator: "|"))
        everyTitleSeen.formUnion(secs.flatMap { $0.cards.map(\.id) })
    }
    check("row selection varies across windows", rowSignatures.count >= 4,
          "\(rowSignatures.count) distinct row sets in 120 windows")
    check("titles vary across windows", titleSignatures.count >= 20,
          "\(titleSignatures.count) distinct title sets in 120 windows")

    // Consecutive windows must differ — the owner's report was "the exact same
    // videos every single time", so adjacent sittings changing is the fix.
    let now = rotate(feed, window: w), next = rotate(feed, window: w + 1)
    check("consecutive windows differ",
          now.flatMap { $0.cards.map(\.id) } != next.flatMap { $0.cards.map(\.id) })

    // Every window must carry at least one MARQUEE row. Rows are published in
    // priority order, and a contiguous slice of 4 eventually lands wholly in the
    // tail — a shelf of Prelinger + NASA + Newsreels and no recognizable cinema.
    // The assertions all passed while that happened, so this is the check that
    // encodes what "good" actually looks like.
    let marquee = Set(pools.prefix(max(1, pools.count / 3)).map(\.title))
    var weakWindows: [Int] = []
    for step in 0..<120 where !rotate(feed, window: w + step).contains(where: { marquee.contains($0.title) }) {
        weakWindows.append(step)
    }
    check("every window includes a marquee row", weakWindows.isEmpty,
          "\(weakWindows.count)/120 windows were all deep-catalog")

    // Every published row must actually get screen time over a rotation cycle.
    var rowsEverShown = Set<String>()
    for step in 0..<(pools.count * 2) {
        rowsEverShown.formUnion(rotate(feed, window: w + step).map(\.title))
    }
    check("every published row is reachable", rowsEverShown.count == pools.count,
          "\(rowsEverShown.count)/\(pools.count) rows shown in a full cycle")

    // --- 4. The published pool is actually reachable, not just published.
    let published = Set(pools.flatMap { $0.items.map(\.id) })
    let coverage = Double(everyTitleSeen.count) / Double(max(1, published.count))
    check("rotation reaches most of the published pool", coverage > 0.6,
          String(format: "%.0f%% of %d titles reachable", coverage * 100, published.count))

    // --- 5. Shape budget (§15.8) and no repeats (§15.6 dedupe).
    for step in 0..<40 {
        let secs = dedupe(rotate(feed, window: w + step))
        if secs.count > kMaxEditorialRows { failures.append("row budget at window +\(step)"); break }
        if secs.contains(where: { $0.cards.count > kMaxTilesPerRow }) {
            failures.append("tile budget at window +\(step)"); break
        }
        let ids = secs.flatMap { $0.cards.map(\.id) }
        if Set(ids).count != ids.count { failures.append("duplicate title at window +\(step)"); break }
    }
    check("row/tile budget and no duplicate titles across 40 windows",
          !failures.contains { $0.hasPrefix("row budget") || $0.hasPrefix("tile budget")
                                || $0.hasPrefix("duplicate") })

    // --- 6. Personal rows lead and survive the merge (§15.4).
    let personal = Section(title: "Continue Watching", cards: [
        Card(id: pools[1].items[0].id, title: "resuming", year: 1950,
             posterURL: URL(string: "https://example.com/p.jpg")!, resume: true, progress: 0.4)
    ])
    let merged = dedupe([personal] + rotate(feed, window: w))
    check("Continue Watching leads the shelf", merged.first?.title == "Continue Watching")
    check("a resuming title is not repeated below",
          merged.dropFirst().allSatisfy { !$0.cards.contains { $0.id == personal.cards[0].id } })

    // --- 7. Legacy v1 feeds still render (already-shipped clients / old cache).
    let legacy = FeedPayload(rows: nil, sections: (feed.sections ?? []))
    check("v1 `sections` feed still rotates", !rotate(legacy, window: w).isEmpty)

    print("\n\(checks - failures.count)/\(checks) checks passed")
    if !failures.isEmpty { print("FAILED: \(failures.joined(separator: ", "))"); exit(1) }
    print("\nWindow \(w) renders:")
    for s in dedupe(rotate(feed, window: w)) {
        print("  \(s.title): \(s.cards.prefix(3).map(\.title).joined(separator: ", "))")
    }
    print("\nWindow \(w + 1) renders:")
    for s in dedupe(rotate(feed, window: w + 1)) {
        print("  \(s.title): \(s.cards.prefix(3).map(\.title).joined(separator: ", "))")
    }

}
}
