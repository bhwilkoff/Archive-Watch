#if os(iOS) || os(macOS)
import SwiftUI

// Kids / Cartoon Mode pool logic — shared by the iOS CartoonView and the macOS
// CartoonView so they can't drift (the iOS copy's own TODO asked to unify this).
// A kid-safe COLOR-leaning cartoon surface (never silent, scary subjects filtered,
// Decision 025 color flags). Mirrors the tvOS AppStore kids pool; keep them in step.
@MainActor
enum KidsContent {
    static func cartoonPool(_ store: AppStore, limit: Int = 250) -> [Catalog.Item] {
        let scary = ["horror", "war", "nightmare", "death", "ghost story", "macabre"]
        let pool = store.browse(contentType: "animation", sort: .popular, limit: 600).filter { it in
            guard it.videoURLParsed != nil, it.hasDesignedArtwork else { return false }
            if it.isSilentFilm == true { return false }
            let blob = (it.genres + it.subjects).map { $0.lowercased() }
            if blob.contains(where: { g in scary.contains(where: g.contains) }) { return false }
            return true
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
        let scary = ["horror", "nightmare", "macabre"]
        let pool = store.browse(contentType: "animation", sort: .popular, limit: 1500).filter { it in
            guard it.isSilentFilm != true, it.hasDesignedArtwork, it.videoURLParsed != nil else { return false }
            let g = (it.genres + it.subjects).map { $0.lowercased() }
            return !g.contains { x in scary.contains(where: x.contains) }
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
            pool.filter { it in
                let blob = (it.genres + it.subjects + [it.title]).map { $0.lowercased() }.joined(separator: " ")
                return words.contains { blob.contains($0) }
            }
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
