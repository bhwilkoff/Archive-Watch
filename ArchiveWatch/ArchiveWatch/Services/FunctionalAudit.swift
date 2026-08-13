#if os(tvOS)
// tvOS-only: the harness drives tvOS surfaces (RootView is its only
// caller) and references tvOS-scoped types (IntentInbox). iOS/macOS get the
// same data checks via tools/test_catalog_audit.swift, which compiles the
// shared CatalogDB directly. The macOS ARCHIVE failed on this file's first
// shipping build because only tvOS had been rebuilt after adding it.
import Foundation

// FunctionalAudit — every tab's data spine, every Browse facet and sort, and
// every Settings toggle's CONSUMPTION, exercised on the device and reported on
// stdout. `AW_UI_AUDIT=1` (dev builds via `devicectl launch --console`).
//
// This is the audit tier between a compile and a human with a remote
// (docs/TVOS-AUDIT.md, tier T1): `LayoutCheck` proves tiles LOOK right, this
// proves the queries and state behind every button and filter DO something —
// each facet filters, each sort orders, each toggle changes what a query
// returns. What it deliberately does not test is the focus engine and the
// press itself; those rows stay T3 (owner-visual) in the ledger.
//
// Every check prints `[AWAUDIT] PASS/FAIL name — detail` and the run ends with
// a summary line, so a device run is judged by reading the console — the same
// discipline as the caption work: assert the OUTPUT, never the offer.
//
// Checks MUTATE nothing durable: toggles are flipped on the DB handle and
// restored; nothing touches SwiftData, sync, or UserDefaults.

@MainActor
enum FunctionalAudit {
    private static var passed = 0
    private static var failed = 0

    static var enabled: Bool {
        ProcessInfo.processInfo.environment["AW_UI_AUDIT"] == "1"
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String) {
        if ok { passed += 1 } else { failed += 1 }
        print("[AWAUDIT] \(ok ? "PASS" : "FAIL") \(name) — \(detail)")
    }

    /// Entry point — call from RootView once the store is ready.
    static func run(store: AppStore) async {
        passed = 0; failed = 0
        // The FULL catalog, not the seed: shelf gates and counts are claims
        // about the real DB (the seed is a 2.6k-item cold-start fallback).
        for _ in 0..<120 {
            if (store.db?.itemCount ?? 0) > 10_000 { break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        guard let db = store.db else {
            print("[AWAUDIT] FAIL no catalog DB — nothing else can run")
            return
        }
        let total = db.itemCount
        check("catalog", total > 10_000, "\(total) items open")

        auditHome(store: store, db: db)
        auditBrowse(db: db)
        auditTV(db: db)
        auditSearch(db: db)
        auditCollections(db: db)
        auditSurprise(db: db)
        auditSettingsConsumption(store: store, db: db)
        auditDeepLinks()

        print("[AWAUDIT] SUMMARY passed=\(passed) failed=\(failed)")
    }

    // MARK: Home

    private static func auditHome(store: AppStore, db: CatalogDB) {
        // Shelves in the canonical Home order — each populated and playable.
        var populated = 0, gated = 0
        for id in Featured.homeShelfPriority {
            let items = store.items(forShelf: id)
            if items.isEmpty { continue }
            populated += 1
            if items.prefix(12).allSatisfy({ ($0.downloadURL ?? "").isEmpty == false }) {
                gated += 1
            } else {
                check("home.shelf.\(id)", false, "carries an unplayable tile (D056 gate)")
            }
        }
        check("home.shelves", populated >= 6,
              "\(populated) of \(Featured.homeShelfPriority.count) priority shelves populated, "
              + "\(gated) fully playable")

        let gems = db.hiddenGems()
        check("home.hiddenGems", !gems.isEmpty, "\(gems.count) gems (D050 computed column)")

        let top = db.topRated()
        let ratingsOrdered = zip(top, top.dropFirst()).allSatisfy {
            ($0.imdbRating ?? 0) >= ($1.imdbRating ?? 0)
        }
        let floored = top.allSatisfy { ($0.imdbVotes ?? 0) >= 1000 }
        check("home.topRated", !top.isEmpty && ratingsOrdered && floored,
              "\(top.count) items, ordered=\(ratingsOrdered), votes≥1000=\(floored)")

        for (name, items) in [("watchingNow", db.watchingNow()),
                              ("communityFavorites", db.communityFavorites()),
                              ("mostDiscussed", db.mostDiscussed())] {
            let floored = items.allSatisfy { ($0.imdbVotes ?? 0) >= 1000 }
            check("home.\(name)", !items.isEmpty && floored,
                  "\(items.count) items, votes≥1000=\(floored)")
        }

        let directors = db.topDirectors()
        if let first = directors.first {
            let films = db.byDirector(first.name)
            check("home.directors", films.count >= 3,
                  "\(directors.count) directors; \(first.name) → \(films.count) films")
        } else {
            check("home.directors", false, "no directors met the 3-film floor")
        }

        let decades = db.decadeCounts()
        let sane = decades.keys.allSatisfy { (1890...2029).contains($0) }
        check("home.decadeTiles", !decades.isEmpty && sane,
              "\(decades.count) decades, all in 1890–2029=\(sane)")

        // Category tiles are count-gated at 30 — flag any canonical type whose
        // tile would render against a near-empty grid.
        var tiles = 0
        for type in ["feature-film", "silent-film", "animation", "newsreel",
                     "ephemeral", "short-film", "commercial", "tv-series"] {
            let n = db.browseCount(contentType: type)
            if n >= 30 { tiles += 1 }
        }
        check("home.categoryTiles", tiles >= 4, "\(tiles) types clear the ≥30 gate")
    }

    // MARK: Browse (Movies) — every facet, every sort

    private static func auditBrowse(db: CatalogDB) {
        let all = db.browseCount()
        check("browse.total", all > 5_000, "\(all) browsable titles")

        // Type facet: a filtered count is smaller and its page honors the type.
        for type in ["feature-film", "animation", "newsreel"] {
            let n = db.browseCount(contentType: type)
            let page = db.browse(contentType: type, limit: 30)
            let honored = page.allSatisfy { $0.contentType == type }
            check("browse.type.\(type)", n > 0 && n < all && !page.isEmpty && honored,
                  "\(n) items, page honors type=\(honored)")
        }

        // Decade facet.
        for decade in [1930, 1950, 1970] {
            let page = db.browse(decade: decade, limit: 30)
            let honored = page.allSatisfy { (decade...decade + 9).contains($0.year ?? -1) }
            check("browse.decade.\(decade)s", !page.isEmpty && honored,
                  "\(page.count) on page, all in-decade=\(honored)")
        }

        // Genre facet (top genre must filter).
        if let genre = db.topGenres().first {
            let page = db.browse(genre: genre, limit: 20)
            check("browse.genre", !page.isEmpty, "'\(genre)' → \(page.count) items")
        } else {
            check("browse.genre", false, "no genres in DB")
        }

        // Every sort: non-empty and honoring its own order.
        let alpha = db.browse(sort: .alphabetical, limit: 50)
        let alphaOK = zip(alpha, alpha.dropFirst()).allSatisfy {
            $0.title.localizedCaseInsensitiveCompare($1.title) != .orderedDescending
        }
        check("browse.sort.alphabetical", !alpha.isEmpty && alphaOK, "ordered=\(alphaOK)")

        let newest = db.browse(sort: .newest, limit: 50)
        let newestOK = zip(newest, newest.dropFirst()).allSatisfy {
            ($0.year ?? 0) >= ($1.year ?? 0)
        }
        check("browse.sort.newest", !newest.isEmpty && newestOK, "ordered=\(newestOK)")

        let oldest = db.browse(sort: .oldest, limit: 50)
        let oldestOK = zip(oldest, oldest.dropFirst()).allSatisfy {
            ($0.year ?? 9999) <= ($1.year ?? 9999)
        }
        check("browse.sort.oldest", !oldest.isEmpty && oldestOK, "ordered=\(oldestOK)")

        let rated = db.browse(sort: .rating, limit: 50)
        let ratedOK = zip(rated, rated.dropFirst()).allSatisfy {
            ($0.imdbRating ?? -1) >= ($1.imdbRating ?? -1)
        }
        check("browse.sort.rating", !rated.isEmpty && ratedOK, "ordered=\(ratedOK)")

        let popular = db.browse(sort: .popular, limit: 50)
        check("browse.sort.popular", !popular.isEmpty, "\(popular.count) items")

        // Paging: page 2 exists and does not repeat page 1.
        let p1 = db.browse(limit: 50)
        let p2 = db.browse(limit: 50, offset: 50)
        let overlap = Set(p1.map(\.archiveID)).intersection(p2.map(\.archiveID))
        check("browse.paging", !p2.isEmpty && overlap.isEmpty,
              "page2=\(p2.count), overlap=\(overlap.count)")

        // Film surfaces never leak TV (D036/D045).
        let leaks = p1.filter { ["tv-series", "tv-special", "tv-episode"].contains($0.contentType) }
        check("browse.noTVLeak", leaks.isEmpty, "\(leaks.count) TV items on the film surface")
    }

    // MARK: TV

    private static func auditTV(db: CatalogDB) {
        let cards = db.seriesCards()
        let postered = cards.prefix(30).allSatisfy { $0.hasRealArtwork == true }
        check("tv.seriesCards", !cards.isEmpty && postered,
              "\(cards.count) series, first 30 poster-gated=\(postered)")

        if !db.demotedIDs.isEmpty {
            let leaders = cards.prefix(20).map(\.archiveID)
            let demotedUpFront = leaders.contains { db.demotedIDs.contains($0) }
            check("tv.editorialDemotion", !demotedUpFront,
                  "no demoted series in the first 20 (deprioritizedSeries)")
        }

        let specials = db.tvSpecials(limit: 30)
        let honored = specials.allSatisfy { $0.contentType == "tv-special" }
        check("tv.specials", db.tvSpecialsCount() > 0 && honored,
              "\(db.tvSpecialsCount()) specials, page honors type=\(honored)")

        // Episodes are first-class items (D045) and searchable.
        let hits = db.search("episode", limit: 200)
        let episode = hits.first { $0.seriesID != nil }
        check("tv.episodesAsItems", episode != nil,
              episode.map { "episode item '\($0.title)' resolves" } ?? "no episode in FTS")
    }

    // MARK: Search

    private static func auditSearch(db: CatalogDB) {
        let hits = db.search("incredible machine")
        check("search.knownTitle", hits.contains { $0.archiveID == "mantheincrediblemachine" },
              "\(hits.count) hits for 'incredible machine'")

        let broad = db.search("the", limit: 200)
        let specialLeak = broad.contains { $0.contentType == "tv-special" }
        check("search.noSpecialLeak", !broad.isEmpty && !specialLeak,
              "\(broad.count) hits, tv-special excluded=\(!specialLeak)")
    }

    // MARK: Collections

    private static func auditCollections(db: CatalogDB) {
        let curated = CollectionMetadata.all
        let noFav = curated.allSatisfy { !$0.id.hasPrefix("fav-") }
        check("collections.curatedOnly", !curated.isEmpty && noFav,
              "\(curated.count) curated, no fav-* pseudo-collections=\(noFav)")

        if let first = curated.first {
            let n = db.collectionCount(first.id)
            check("collections.populated", n > 0, "'\(first.id)' → \(n) items")
        }
    }

    // MARK: Surprise

    private static func auditSurprise(db: CatalogDB) {
        var ok = true
        var why = ""
        for _ in 0..<5 {
            guard let pick = db.randomPlayable() else { ok = false; why = "nil pick"; break }
            if (pick.downloadURL ?? "").isEmpty { ok = false; why = "unplayable \(pick.archiveID)"; break }
            if ["tv-series", "tv-special", "tv-episode"].contains(pick.contentType) {
                ok = false; why = "TV leaked: \(pick.archiveID)"; break
            }
        }
        check("surprise.randomFilm", ok, ok ? "5 picks, all playable films" : why)

        let ad = db.randomPlayable(contentType: "commercial")
        check("surprise.randomCommercial", ad?.contentType == "commercial",
              ad.map { "'\($0.title)'" } ?? "nil")
    }

    // MARK: Settings consumption — a toggle must change what a query returns

    private static func auditSettingsConsumption(store: AppStore, db: CatalogDB) {
        // Mature filter (D012): flipping the DB gate changes the visible count.
        let before = db.browseCount()
        let original = db.hideAdult
        db.hideAdult = !original
        let after = db.browseCount()
        db.hideAdult = original
        check("settings.matureToggle", after != before,
              "hideAdult=\(original): \(before) → flipped: \(after)")

        // Per-category visibility: hiding a type removes it from Browse.
        let originalHidden = db.hiddenTypes
        db.hiddenTypes = originalHidden.union(["newsreel"])
        let hiddenPage = db.browse(limit: 200)
        let leaked = hiddenPage.contains { $0.contentType == "newsreel" }
        db.hiddenTypes = originalHidden
        check("settings.hideCategory", !leaked, "newsreel hidden → leaked=\(leaked)")

        // Hide-watched: the Home filter excludes a completed id.
        if let sample = db.browse(limit: 1).first {
            let originalCompleted = store.completedArchiveIDs
            let originalToggle = store.hideWatchedOnHome
            store.completedArchiveIDs.insert(sample.archiveID)
            store.hideWatchedOnHome = true
            let filtered = store.filteringWatched([sample])
            store.completedArchiveIDs = originalCompleted
            store.hideWatchedOnHome = originalToggle
            check("settings.hideWatched", filtered.isEmpty,
                  "completed item filtered from Home=\(filtered.isEmpty)")
        }
    }

    // MARK: Deep links

    private static func auditDeepLinks() {
        let cases: [(String, Bool)] = [
            ("archivewatch://item/mantheincrediblemachine", true),
            ("archivewatch://play/mantheincrediblemachine", true),   // D049: the Top Shelf resume route
            ("archivewatch://surprise", true),
            ("archivewatch://random/film", true),
            ("archivewatch://item/", false),                          // id-less must NOT parse
            ("https://example.com/item/x", false),                    // wrong scheme
        ]
        for (raw, expected) in cases {
            guard let url = URL(string: raw) else { continue }
            let parsed = IntentInbox.request(for: url) != nil
            check("deeplink.\(url.path.isEmpty ? url.host ?? "?" : url.lastPathComponent)",
                  parsed == expected, "\(raw) → parsed=\(parsed), expected=\(expected)")
        }
    }
}

#endif
