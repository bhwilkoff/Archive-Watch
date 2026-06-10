#if os(iOS)
import SwiftUI

// Cartoon / Kids Mode (PARITY §5) — the touch port of tvOS KidsModeView: a
// kid-safe COLOR-leaning cartoon surface (never silent, scary subjects filtered,
// Decision 025 color flags). Selection logic mirrors the tvOS AppStore pool
// (unify into shared Core after the tvOS review settles — don't let them drift).

struct CartoonRoute: Hashable {}

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

struct CartoonView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var characters: [(name: String, items: [Catalog.Item])] = []
    @State private var collections: [(title: String, items: [Catalog.Item])] = []
    @State private var marathon: ChannelLineup?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Button { startMarathon() } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Play a Cartoon Marathon").fontWeight(.bold)
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background((Color(hex: "#3FA796") ?? .teal).gradient,
                                in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                ForEach(characters, id: \.name) { group in
                    shelf(title: group.name, items: group.items)
                }
                ForEach(collections, id: \.title) { group in
                    shelf(title: group.title, items: group.items)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Cartoon Mode")
        .navigationBarTitleDisplayMode(.large)
        .task(id: store.dbVersion) {
            characters = KidsContent.characters(store)
            collections = KidsContent.collections(store)
        }
        .fullScreenCover(item: $marathon) { box in
            if let player = PlayerView(lineup: box.items, startOffset: 0) {
                player.ignoresSafeArea()
            } else {
                ContentUnavailableView("No cartoons available", systemImage: "tv.slash")
            }
        }
    }

    private func startMarathon() {
        let pool = KidsContent.cartoonPool(store)
        guard !pool.isEmpty else { return }
        marathon = ChannelLineup(items: pool, startOffset: 0)
    }

    private func shelf(title: String, items: [Catalog.Item]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3).fontWeight(.semibold).padding(.horizontal)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(items.prefix(20)) { item in
                        Button { router.openDetail(item) } label: { PosterTile(item: item) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
    }
}

#endif
