import SwiftUI

@MainActor
@Observable
final class AppStore {

    var featured: Featured?
    var loadError: String?

    /// Read-only SQLite catalog (Decision 017). Opened from the bundled
    /// seed.sqlite for instant first paint, then swapped to the downloaded
    /// full DB. The view layer migrates to querying this instead of holding
    /// the whole catalog in `visibleItems`.
    private(set) var db: CatalogDB?
    /// Bumped whenever `db` is swapped (seed → downloaded), so views relying
    /// on it can refresh via `.task(id:)`.
    private(set) var dbGeneration = 0

    // Decision 012: adult-content items are hidden by default on this shared
    // 10-foot device; a Settings toggle opts back in. The filter is an isAdult
    // column + WHERE clause in the DB (CatalogDB.hideAdult), computed at build
    // from featured.json.adultCollections — set on DB swap + toggle. Bumping
    // dbGeneration re-queries every db-backed view.
    var hideAdultContent: Bool = AppStore.loadHideAdultDefault() {
        didSet {
            UserDefaults.standard.set(hideAdultContent, forKey: Self.hideAdultKey)
            db?.hideAdult = hideAdultContent
            dbGeneration += 1
        }
    }
    // #4: content categories the user has hidden in Settings. Maps to the
    // CatalogDB type filter, applied app-wide. Persisted; re-queries on change.
    var hiddenCategories: Set<String> = AppStore.loadHiddenCategories() {
        didSet {
            UserDefaults.standard.set(Array(hiddenCategories), forKey: Self.hiddenCategoriesKey)
            db?.hiddenTypes = Self.contentTypes(for: hiddenCategories)
            dbGeneration += 1
        }
    }
    private static let hiddenCategoriesKey = "hiddenCategories"
    private static func loadHiddenCategories() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: hiddenCategoriesKey) ?? [])
    }
    /// A hidden "tv-series" category covers both series cards and tv-specials.
    static func contentTypes(for categories: Set<String>) -> Set<String> {
        var types = categories
        if categories.contains("tv-series") { types.insert("tv-special") }
        return types
    }

    private static let hideAdultKey = "hideAdultContent"
    private static func loadHideAdultDefault() -> Bool {
        // First launch (no stored value) → ON. Default-deny for a TV.
        guard UserDefaults.standard.object(forKey: hideAdultKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: hideAdultKey)
    }

    // #17 (tvOS-DESIGN §10.3): completed titles are hidden from Home shelves +
    // hero by default; a Settings toggle shows them again. They stay everywhere
    // else (Search/Browse/Library). Continue Watching is exempt — it shows
    // in-progress, not completed (it filters !isComplete itself).
    //
    // Watched state lives in SwiftData (WatchProgress), separate from the SQLite
    // catalog, so the set of completed archiveIDs is fed in by an invisible
    // @Query-owning view (WatchedHomeSync) — keeping @Query out of HomeView to
    // avoid the macro cascade. Filtering happens app-side in HomeView.
    var hideWatchedOnHome: Bool = AppStore.loadHideWatchedDefault() {
        didSet { UserDefaults.standard.set(hideWatchedOnHome, forKey: Self.hideWatchedKey) }
    }
    /// archiveIDs the user has finished watching. Maintained by WatchedHomeSync.
    var completedArchiveIDs: Set<String> = []

    private static let hideWatchedKey = "hideWatchedOnHome"
    private static func loadHideWatchedDefault() -> Bool {
        guard UserDefaults.standard.object(forKey: hideWatchedKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: hideWatchedKey)
    }

    // #10: global autoplay-next default for the movie player (off by default —
    // the user opts in). A per-video override lives in the player's transport.
    var autoplayMode: AutoplayMode = AppStore.loadAutoplayMode() {
        didSet { UserDefaults.standard.set(autoplayMode.rawValue, forKey: Self.autoplayKey) }
    }
    private static let autoplayKey = "autoplayMode"
    private static func loadAutoplayMode() -> AutoplayMode {
        AutoplayMode(rawValue: UserDefaults.standard.string(forKey: autoplayKey) ?? "") ?? .off
    }

    // Channels: play vintage PD commercials between programs (the 1990s-TV feel).
    // On by default — it's the point of the commercials. Toggle in Settings.
    var channelCommercialBreaks: Bool = AppStore.loadCommercialBreaks() {
        didSet { UserDefaults.standard.set(channelCommercialBreaks, forKey: Self.commercialBreaksKey) }
    }
    private static let commercialBreaksKey = "channelCommercialBreaks"
    private static func loadCommercialBreaks() -> Bool {
        guard UserDefaults.standard.object(forKey: commercialBreaksKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: commercialBreaksKey)
    }

    /// Max length of a commercial break, in seconds. The player cuts a longer ad
    /// off at this point and moves to the next full title. 0 = play the ad in full
    /// (no cap). User-set from the Channels view + Settings; default 60s.
    var commercialBreakMaxSeconds: Int = {
        UserDefaults.standard.object(forKey: "commercialBreakMaxSeconds") != nil
            ? UserDefaults.standard.integer(forKey: "commercialBreakMaxSeconds") : 60
    }() {
        didSet { UserDefaults.standard.set(commercialBreakMaxSeconds, forKey: "commercialBreakMaxSeconds") }
    }

    // #83 idle screensaver. Transient flag set by the players so the idle
    // trigger can NEVER fire over a video. Opt-in (default off) so it can't
    // surprise anyone; RootView watches it.
    var isPlayingVideo = false
    var screensaverIdleEnabled: Bool = UserDefaults.standard.bool(forKey: "screensaverIdleEnabled") {
        didSet { UserDefaults.standard.set(screensaverIdleEnabled, forKey: "screensaverIdleEnabled") }
    }

    // Optional analog VHS/CRT veneer on channel playback (the retro-TV experience,
    // alongside commercial breaks). On by default — for archival film/TV the tape
    // look reads as more authentic, not less. Toggled from the Channels header and
    // Settings; applied as an overlay over the channel player.
    var channelVHS: Bool = AppStore.loadVHSDefault() {
        didSet { UserDefaults.standard.set(channelVHS, forKey: "channelVHS") }
    }
    private static func loadVHSDefault() -> Bool {
        // Off by default — it's an opt-in retro effect, not the default viewing
        // experience.
        UserDefaults.standard.bool(forKey: "channelVHS")
    }

    /// Drop completed titles from a Home list when the setting is on. No-op
    /// otherwise. Used by HomeView's hero + shelves.
    func filteringWatched(_ items: [Catalog.Item]) -> [Catalog.Item] {
        guard hideWatchedOnHome, !completedArchiveIDs.isEmpty else { return items }
        return items.filter { !completedArchiveIDs.contains($0.archiveID) }
    }

    func loadBundledData() async {
        // STEP 1 — synchronous bundle load. Unblocks the UI within a
        // second; the user never sees "Loading catalog…" hang waiting
        // on the actor hop or a network fetch. Before this refactor,
        // an empty disk cache + slow JSON decode in the actor could
        // leave the spinner up indefinitely.
        //
        // IMPORTANT: featured is loaded FIRST so CategoryTilesRow +
        // accent colors are populated by the time Home first renders.
        // The catalog assignment triggers rebuildDerived() which can
        // take 100ms+ on the full catalog; if featured isn't set yet,
        // Home flashes with no categories during that blocking
        // rebuild and the user experiences "categories don't show
        // until catalog loads".
        let bundleStart = Date()
        do {
            // featured.json is small (categories + shelf metadata) and stays
            // JSON. The catalog ITSELF is no longer decoded into memory — the
            // SQLite DB (seed → downloaded full) is the source now (Decision
            // 017). This is the memory win: we never hold ~26k full items in RAM.
            featured = try CatalogLoader.loadFeatured()
            print("[AppStore] featured loaded in \(String(format: "%.2fs", Date().timeIntervalSince(bundleStart)))")
            // Open the bundled seed DB for instant first paint.
            if let seed = Bundle.main.path(forResource: "seed", ofType: "sqlite"),
               let seedDB = CatalogDB(path: seed) {
                swapDB(seedDB)
                print("[AppStore] seed.sqlite: \(seedDB.itemCount) items")
            } else {
                loadError = "Missing bundled seed.sqlite"
                return
            }
        } catch CatalogLoader.LoadError.bundleMissing(let name) {
            loadError = "Missing bundled resource: \(name)"
            return
        } catch CatalogLoader.LoadError.decodeFailed(let name, let err) {
            loadError = "Failed to decode \(name): \(err.localizedDescription)"
            return
        } catch {
            loadError = error.localizedDescription
            return
        }

        // Full SQLite catalog (Decision 017). Open the cached DB if we
        // already downloaded one (upgrades from the bundled seed), then fetch a
        // fresh copy from the release in the background and swap it in.
        Task { [weak self] in
            if let cached = await CatalogRefreshService.shared.cachedDatabasePath(),
               let fullDB = CatalogDB(path: cached) {
                await MainActor.run {
                    guard let self else { return }
                    if fullDB.itemCount >= (self.db?.itemCount ?? 0) { self.swapDB(fullDB) }
                }
            }
            if let path = await CatalogRefreshService.shared.downloadDatabase(),
               let fullDB = CatalogDB(path: path) {
                await MainActor.run {
                    guard let self else { return }
                    if fullDB.itemCount >= (self.db?.itemCount ?? 0) {
                        self.swapDB(fullDB)
                        print("[AppStore] swapped to full DB: \(fullDB.itemCount) items")
                    }
                }
            }
        }
    }

    /// Items assigned to the given shelf id (SQLite, Decision 017).
    func items(forShelf shelfID: String) -> [Catalog.Item] {
        db?.shelf(shelfID) ?? []
    }

    // MARK: - SQLite-backed queries (Decision 017)
    // Thin wrappers so views call the store; the store owns the db + adult
    // state. Each returns [] when the db isn't open yet (first frames before
    // the seed loads), which views render as an empty state.

    func swapDB(_ newDB: CatalogDB) {
        newDB.hideAdult = hideAdultContent
        newDB.hiddenTypes = Self.contentTypes(for: hiddenCategories)
        db = newDB
        dbGeneration += 1
    }

    func dbBrowse(contentType: String? = nil, decade: Int? = nil, genre: String? = nil,
                  year: Int? = nil, sort: CatalogDB.Sort = .popular, limit: Int = 60,
                  offset: Int = 0, homeOnly: Bool = false) -> [Catalog.Item] {
        db?.browse(contentType: contentType, decade: decade, genre: genre, year: year,
                   sort: sort, limit: limit, offset: offset, homeOnly: homeOnly) ?? []
    }
    func dbSearch(_ q: String) -> [Catalog.Item] { db?.search(q) ?? [] }
    func dbSeriesCards() -> [Catalog.Item] { db?.seriesCards() ?? [] }
    func dbItem(_ id: String) -> Catalog.Item? { db?.item(id) }
    func dbRelated(to item: Catalog.Item) -> [Catalog.Item] { db?.related(to: item) ?? [] }
    func dbDecadeCounts() -> [Int: Int] { db?.decadeCounts() ?? [:] }
    /// Live count of searchable titles in the loaded DB (tracks seed→full + rebuilds).
    var dbSearchableCount: Int { db?.searchableCount ?? 0 }
    func dbTopGenres() -> [String] { db?.topGenres() ?? [] }
    func dbItemsByIDs(_ ids: [String]) -> [Catalog.Item] { db?.itemsByIDs(ids) ?? [] }
    func dbHiddenGems() -> [Catalog.Item] { db?.hiddenGems() ?? [] }
    func dbTopDirectors() -> [(name: String, count: Int)] { db?.topDirectors() ?? [] }
    func dbByDirector(_ name: String, homeOnly: Bool = false) -> [Catalog.Item] { db?.byDirector(name, homeOnly: homeOnly) ?? [] }
    func dbByPerson(_ name: String) -> [Catalog.Item] { db?.byPerson(name) ?? [] }   // #4
    /// Raw JSON for a browse page — fast SQLite read on main; decode off-main.
    func dbBrowsePageJSON(contentType: String? = nil, decade: Int? = nil, genre: String? = nil,
                          sort: CatalogDB.Sort = .popular, limit: Int = 300, offset: Int = 0) -> [String] {
        db?.browsePageJSON(contentType: contentType, decade: decade, genre: genre,
                           sort: sort, limit: limit, offset: offset) ?? []
    }
    func dbBrowseCount(contentType: String? = nil, decade: Int? = nil,
                       genre: String? = nil, year: Int? = nil) -> Int {
        db?.browseCount(contentType: contentType, decade: decade, genre: genre, year: year) ?? 0
    }
    func dbByCollection(_ id: String, limit: Int = 2000) -> [Catalog.Item] { db?.byCollection(id, limit: limit) ?? [] }
    func dbCollectionCount(_ id: String) -> Int { db?.collectionCount(id) ?? 0 }
    func dbRandomPlayable(contentType: String? = nil) -> Catalog.Item? { db?.randomPlayable(contentType: contentType) }
    func dbRandomCommercials(limit: Int = 12) -> [Catalog.Item] { db?.randomCommercials(limit: limit) ?? [] }

    // Immersive-mode lineups (#2 cartoon / #3 party), shared by Surprise + Home so
    // both launch identical sessions.

    /// #2 Cartoon/Kids: COLOR cartoons kids enjoy — animation, never silent (those
    /// are pre-1930 B&W for older viewers), color-era leaning (year-weighted), with
    /// real artwork. Scary subjects are filtered out for a kid-safe set.
    func cartoonLineup() -> [Catalog.Item] {
        kidsCartoonPool(limit: 250)
    }

    /// Shared kid-friendly color-cartoon pool (used by cartoonLineup + Kids Mode).
    func kidsCartoonPool(limit: Int) -> [Catalog.Item] {
        let scary = ["horror", "war", "nightmare", "death", "ghost story", "macabre"]
        var pool = dbBrowse(contentType: "animation", sort: .popular, limit: 600).filter { it in
            guard it.videoURLParsed != nil, it.hasDesignedArtwork else { return false }
            if it.isSilentFilm == true { return false }              // color-era, not silent B&W
            let blob = (it.genres + it.subjects).map { $0.lowercased() }
            if blob.contains(where: { g in scary.contains(where: g.contains) }) { return false }
            return true
        }
        // #7: prioritize COLOR cartoons over black-and-white. The authoritative
        // signal is `colorMode` (frame-classified by tools/classify_color.py):
        // known color floats to the top, known B&W sinks to the bottom. For items
        // not yet classified, fall back to metadata/year color-likelihood so the
        // ordering is still sensible before classification has fully run.
        func colorScore(_ it: Catalog.Item) -> Int {
            let pop = (it.popularityScore ?? 0) / 50
            if it.isColor == true { return 1000 + pop }
            if it.isBlackAndWhite { return -1000 + pop }
            var s = 0
            let blob = (it.genres + it.subjects + [it.title])
                .map { $0.lowercased() }.joined(separator: " ")
            if blob.contains("technicolor") || blob.contains("cinecolor")
                || blob.contains(" color") || blob.contains("colour") { s += 8 }
            if blob.contains("black and white") || blob.contains("b&w") { s -= 6 }
            if let y = it.year { s += y >= 1935 ? 5 : (y >= 1930 ? 0 : -4) }
            return s + pop
        }
        pool.sort { colorScore($0) > colorScore($1) }
        let head = Array(pool.prefix(max(limit, 120)))
        return head.shuffled()
    }

    /// #3 Party Play: muted background eye-candy — COLOR (never silent B&W), SHORT
    /// (≤ ~15 min so the wall keeps changing), and visually-engaging by subject
    /// (abstract / animation / nature / dance / light, etc.). Ranked so the most
    /// visual content leads.
    func partyLineup() -> [Catalog.Item] {
        let visual = Self.partyVisualKeywords
        var seen = Set<String>()
        var scored: [(Catalog.Item, Int)] = []
        let raw = dbBrowse(contentType: "animation", sort: .popular, limit: 250)
            + dbBrowse(contentType: "short-film", sort: .popular, limit: 250)
            + dbBrowse(genre: "Animation", sort: .popular, limit: 120)
        for it in raw {
            guard it.videoURLParsed != nil, it.hasDesignedArtwork else { continue }
            guard it.isSilentFilm != true else { continue }           // color only
            guard !it.isBlackAndWhite else { continue }               // drop frame-classified B&W
            if let r = it.runtimeSeconds, r > 0, r > 15 * 60 { continue }   // short only
            guard seen.insert(it.archiveID).inserted else { continue }
            let blob = (it.genres + it.subjects + [it.title]).map { $0.lowercased() }.joined(separator: " ")
            let hits = visual.reduce(0) { $0 + (blob.contains($1) ? 1 : 0) }
            let isAnim = it.contentType == "animation"
            scored.append((it, hits * 3 + (isAnim ? 2 : 0) + (it.popularityScore ?? 0) / 25))
        }
        // Keep the most-visual 220, then shuffle so a session isn't identical.
        let ranked = scored.sorted { $0.1 > $1.1 }.prefix(220).map { $0.0 }
        return Array(ranked).shuffled()
    }

    /// Subject/genre words that signal visually-engaging, sound-optional content for
    /// Party Play (researched from the kinds of PD shorts that read well muted).
    static let partyVisualKeywords: [String] = [
        "abstract", "experimental", "avant-garde", "avant garde", "psychedelic",
        "kaleidoscope", "surreal", "animation", "animated", "cartoon", "color",
        "colour", "technicolor", "dance", "ballet", "music", "musical", "light",
        "fireworks", "nature", "scenic", "travelogue", "landscape", "flowers",
        "garden", "ocean", "underwater", "aquarium", "space", "nasa", "aurora",
        "fractal", "mandala", "op art", "oil", "liquid", "paint", "art", "visual",
        "fantasia", "rhythm", "geometric", "neon", "carnival", "parade",
    ]

    // MARK: - Kids / Cartoon Mode (#1)

    /// Well-known cartoon characters/series kids recognize, each with the
    /// distinctive title/subject term(s) that identify it. Only the ones with
    /// actual catalog matches are surfaced (see kidsCharacters()). Most Looney
    /// Tunes headliners (Bugs, Tweety) aren't public domain, but Porky, Daffy,
    /// and "Looney Tunes"-tagged items are present, so they appear.
    static let kidsCharacterDefs: [(name: String, terms: [String])] = [
        ("Popeye",              ["popeye"]),
        ("Betty Boop",          ["betty boop"]),
        ("Porky Pig",           ["porky"]),
        ("Mr. Magoo",           ["magoo"]),
        ("Looney Tunes",        ["looney tunes", "looney"]),
        ("Felix the Cat",       ["felix"]),
        ("Daffy Duck",          ["daffy"]),
        ("Bosko",               ["bosko"]),
        ("Mighty Mouse",        ["mighty mouse"]),
        ("Casper",              ["casper"]),
        ("Mickey Mouse",        ["mickey mouse"]),
        ("Superman",            ["superman"]),
        ("Little Lulu",         ["little lulu"]),
        ("Gulliver",            ["gulliver"]),
        ("Gerald McBoing-Boing", ["mcboing"]),
        ("Bimbo",               ["bimbo"]),
    ]

    /// Characters that have at least a few cartoons, each with its items + a cover.
    /// Substring match over the kid-safe cartoon pool (the FTS search was too strict
    /// and only ever surfaced Popeye + Betty Boop).
    func kidsCharacters() -> [(name: String, items: [Catalog.Item])] {
        let scary = ["horror", "nightmare", "macabre"]
        let pool = dbBrowse(contentType: "animation", sort: .popular, limit: 1500).filter { it in
            guard it.isSilentFilm != true, it.hasDesignedArtwork, it.videoURLParsed != nil else { return false }
            let g = (it.genres + it.subjects).map { $0.lowercased() }
            return !g.contains { x in scary.contains(where: x.contains) }
        }
        return Self.kidsCharacterDefs.compactMap { name, terms in
            let lc = terms.map { $0.lowercased() }
            let items = pool.filter { it in
                let hay = it.title.lowercased() + " "
                    + it.subjects.map { $0.lowercased() }.joined(separator: " ")
                return lc.contains(where: hay.contains)
            }
            return items.count >= 3 ? (name, items) : nil
        }
    }

    /// Themed cartoon collections (era + type), each non-empty, for Kids Mode.
    func kidsCollections() -> [(title: String, items: [Catalog.Item])] {
        let pool = kidsCartoonPool(limit: 600)
        func byDecade(_ d: Int) -> [Catalog.Item] { pool.filter { $0.decade == d } }
        func byWords(_ words: [String]) -> [Catalog.Item] {
            pool.filter { it in
                let blob = (it.genres + it.subjects + [it.title]).map { $0.lowercased() }.joined(separator: " ")
                return words.contains { blob.contains($0) }
            }
        }
        let groups: [(String, [Catalog.Item])] = [
            ("Color Classics",   byWords(["color", "colour", "technicolor"])),
            ("Funny Animals",    byWords(["mouse", "cat", "dog", "rabbit", "bear", "duck", "pig", "fox", "squirrel"])),
            ("Sing-Along",       byWords(["song", "music", "sing", "musical", "jazz", "band", "melody"])),
            ("Fairy Tales",      byWords(["fairy", "tale", "prince", "princess", "king", "queen", "castle", "giant", "witch", "gnome", "elf"])),
            ("Under the Sea",    byWords(["sea", "ocean", "fish", "underwater", "mermaid", "whale", "pirate", "sailor", "boat", "ship"])),
            ("Space & Robots",   byWords(["space", "rocket", "planet", "moon", "robot", "mars", "martian", "future"])),
            ("Spooky Fun",       byWords(["ghost", "spooky", "haunted", "skeleton", "goblin"])),
            ("Holidays",         byWords(["christmas", "santa", "holiday", "new year", "easter", "halloween"])),
            ("Circus & Clowns",  byWords(["circus", "clown", "carnival", "ringmaster"])),
            ("Wild West",        byWords(["cowboy", "west", "western", "ranch", "rodeo"])),
            ("Birds of a Feather", byWords(["bird", "owl", "crow", "chicken", "rooster", "penguin", "stork"])),
            ("Bugs & Bees",      byWords(["bug", "bee", "ant", "insect", "spider", "grasshopper", "fly"])),
            ("Things That Go",   byWords(["car", "auto", "airplane", "plane", "train", "truck", "race"])),
            ("Super Heroes",     byWords(["superman", "hero", "super"])),
            ("Big Adventures",   byWords(["adventure", "jungle", "island", "treasure", "explorer", "safari"])),
            ("Dance Party",      byWords(["dance", "ballet", "party", "swing"])),
            ("Fables & Morals",  byWords(["fable", "aesop", "moral", "lesson"])),
            ("Laugh-Out-Loud",   byWords(["comedy", "slapstick", "gag", "funny", "laugh"])),
            ("1930s Toons",      byDecade(1930)),
            ("1940s Toons",      byDecade(1940)),
            ("1950s Toons",      byDecade(1950)),
        ]
        // Dedupe each group and require enough to fill a row; keep declared order.
        return groups.compactMap { name, items in
            var seen = Set<String>()
            let uniq = items.filter { seen.insert($0.archiveID).inserted }
            return uniq.count >= 6 ? (name, uniq) : nil
        }
    }
    func dbRandomSeries() -> Catalog.Item? { db?.randomSeries() }
    func dbRandomByGenre(_ genres: [String]) -> Catalog.Item? { db?.randomByGenre(genres) }
    func dbSeriesCard(slug: String) -> Catalog.Item? { db?.seriesCard(slug: slug) }

    /// Catalog readiness: true once any DB (seed or full) is open. Replaces the
    /// old `catalog != nil` gate now that the JSON load is gone.
    var isReady: Bool { db != nil }

    /// Accent color for a category, parsed from `featured.json`.
    func accentColor(forCategory id: String?) -> Color {
        guard let id, let hex = featured?.category(id: id)?.accent else { return .accentColor }
        return Color(hex: hex) ?? .accentColor
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >>  8) & 0xFF) / 255
        let b = Double( v        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
