import Foundation

/// The rules every Cartoon Mode pool shares, tvOS (`AppStore.kidsCartoonPool`)
/// and iOS/macOS (`KidsContent`); Android's `CartoonMode` holds the same lists.
enum KidsRules {
    static let scary = ["horror", "war", "nightmare", "death", "ghost story", "macabre"]
    /// archive.org's own subjects for health and sex-education films. Typed
    /// animation, they reached a children's surface: About Conception and
    /// Contraception (1973) sat on "Things That Go" (a viewer, 2026-11-17).
    static let notForChildren = ["sex educ", "sex hygiene", "contracept", "birth control",
                                 "reproduction", "venereal", "puberty", "menstruat"]

    static func excluded(_ it: Catalog.Item, scary: [String] = scary) -> Bool {
        let blob = (it.genres + it.subjects).map { $0.lowercased() }
        return blob.contains { g in scary.contains(where: g.contains) || notForChildren.contains(where: g.contains) }
    }

    /// A shelf word matches a whole word (or its plural), never the inside of
    /// one: "race" was matching "contRACEption", "cat" "eduCATion".
    static func mentions(_ words: [String], in parts: [String]) -> Bool {
        let tokens = parts.joined(separator: " ").lowercased()
            .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        let padded = " " + tokens.joined(separator: " ") + " "
        return words.contains { padded.contains(" \($0) ") || padded.contains(" \($0)s ") }
    }
}

#if os(iOS) || os(macOS)
import SwiftUI

// Kids / Cartoon Mode pool logic — shared by the iOS CartoonView and the macOS
// CartoonView so they can't drift (the iOS copy's own TODO asked to unify this).
// A kid-safe COLOR-leaning cartoon surface (never silent, scary subjects filtered,
// Decision 025 color flags). Mirrors the tvOS AppStore kids pool; keep them in step.
@MainActor
enum KidsContent {
    static func cartoonPool(_ store: AppStore, limit: Int = 250) -> [Catalog.Item] {
        let pool = store.browse(contentType: "animation", sort: .popular, limit: 600).filter { it in
            guard it.videoURLParsed != nil, it.hasDesignedArtwork, it.isRecommendable else { return false }
            if it.isSilentFilm == true { return false }
            return !KidsRules.excluded(it)
        }
        return Array(colorEmphasized(pool).prefix(max(limit, 120)))
    }

    static func isBlackAndWhiteOrSilent(_ it: Catalog.Item) -> Bool {
        if it.isColor == true { return false }
        if it.isBlackAndWhite { return true }
        if it.isSilentFilm == true { return true }
        if let y = it.year, y < 1930 { return true }
        return false
    }

    static func colorEmphasized(_ items: [Catalog.Item], bwFraction: Double = 0.15) -> [Catalog.Item] {
        let color = items.filter { !isBlackAndWhiteOrSilent($0) }.shuffled()
        let bw = items.filter { isBlackAndWhiteOrSilent($0) }.shuffled()
        let cap = max(3, Int(Double(color.count) * bwFraction))
        return color + Array(bw.prefix(cap))
    }

    static let characterDefs: [(name: String, terms: [String])] = [
        ("Popeye",               ["popeye"]),
        ("Betty Boop",           ["betty boop"]),
        ("Porky Pig",            ["porky"]),
        ("Mr. Magoo",            ["magoo"]),
        ("Looney Tunes",         ["looney tunes", "looney"]),
        ("Felix the Cat",        ["felix"]),
        ("Daffy Duck",           ["daffy"]),
        ("Bosko",                ["bosko"]),
        ("Mighty Mouse",         ["mighty mouse"]),
        ("Casper",               ["casper"]),
        ("Mickey Mouse",         ["mickey mouse"]),
        ("Superman",             ["superman"]),
        ("Little Lulu",          ["little lulu"]),
        ("Gulliver",             ["gulliver"]),
        ("Gerald McBoing-Boing", ["mcboing"]),
        ("Bimbo",                ["bimbo"]),
    ]

    static func characters(_ store: AppStore) -> [(name: String, items: [Catalog.Item])] {
        let pool = store.browse(contentType: "animation", sort: .popular, limit: 1500).filter { it in
            guard it.isSilentFilm != true, it.hasDesignedArtwork, it.videoURLParsed != nil,
                  it.isRecommendable else { return false }
            return !KidsRules.excluded(it, scary: ["horror", "nightmare", "macabre"])
        }
        return characterDefs.compactMap { name, terms in
            let lc = terms.map { $0.lowercased() }
            let items = pool.filter { it in
                let hay = it.title.lowercased() + " "
                    + it.subjects.map { $0.lowercased() }.joined(separator: " ")
                return lc.contains(where: hay.contains)
            }
            return items.count >= 3 ? (name, items) : nil
        }
    }

    static func collections(_ store: AppStore) -> [(title: String, items: [Catalog.Item])] {
        let pool = cartoonPool(store, limit: 600)
        func byDecade(_ d: Int) -> [Catalog.Item] { pool.filter { $0.decade == d } }
        func byWords(_ words: [String]) -> [Catalog.Item] {
            pool.filter { KidsRules.mentions(words, in: $0.genres + $0.subjects + [$0.title]) }
        }
        let groups: [(String, [Catalog.Item])] = [
            ("Funny Animals",  byWords(["mouse", "cat", "dog", "rabbit", "bear", "duck", "pig", "fox", "squirrel"])),
            ("Sing-Along",     byWords(["song", "music", "sing", "musical", "jazz", "band", "melody"])),
            ("Fairy Tales",    byWords(["fairy", "tale", "prince", "princess", "king", "queen", "castle", "giant", "witch"])),
            ("Under the Sea",  byWords(["sea", "ocean", "fish", "underwater", "mermaid", "whale", "pirate", "sailor"])),
            ("Space & Robots", byWords(["space", "rocket", "planet", "moon", "robot", "mars", "martian", "future"])),
            ("Spooky Fun",     byWords(["ghost", "spooky", "haunted", "skeleton", "goblin"])),
            ("Holidays",       byWords(["christmas", "santa", "holiday", "new year", "easter", "halloween"])),
            ("Things That Go", byWords(["car", "auto", "airplane", "plane", "train", "truck", "race"])),
            ("Big Adventures", byWords(["adventure", "jungle", "island", "treasure", "explorer", "safari"])),
            ("1930s Toons",    byDecade(1930)),
            ("1940s Toons",    byDecade(1940)),
            ("1950s Toons",    byDecade(1950)),
        ]
        return groups.compactMap { name, items in
            var seen = Set<String>()
            let uniq = items.filter { seen.insert($0.archiveID).inserted }
            return uniq.count >= 6 ? (name, uniq) : nil
        }
    }
}
#endif
