// The data half of the tvOS functional audit, runnable WITHOUT the Apple TV.
//
// `FunctionalAudit` (AW_UI_AUDIT=1) runs on the device; its data-spine checks
// exercise the SHARED `CatalogDB` — the same queries, the same published
// `catalog.sqlite` every platform downloads. Those answers do not depend on
// which machine asks, so when the Bedroom Apple TV slept through six audit
// passes, this CLI took over the rows a Mac can settle: every Home shelf gate,
// every Browse facet and sort, the TV-leak guard, search, collections,
// surprise, and the settings-toggle consumption that lives on the DB handle.
// What it cannot answer stays on the device: rendering, focus, and the
// store-level plumbing (featured shelves via AppStore, watched filtering).
//
// Build + run:
//   gh release download catalog-db -p 'catalog.sqlite.zz' -O /tmp/catalog.sqlite.zz --clobber
//   python3 -c "import zlib;d=zlib.decompressobj(-15);o=open('/tmp/catalog-audit.sqlite','wb');\
//     f=open('/tmp/catalog.sqlite.zz','rb');\
//     [o.write(d.decompress(c)) for c in iter(lambda:f.read(1<<20),b'')];o.write(d.flush())"
//   xcrun swiftc -parse-as-library \
//     ArchiveWatch/ArchiveWatch/Store/CatalogDB.swift \
//     ArchiveWatch/ArchiveWatch/Models/Catalog.swift \
//     tools/test_catalog_audit.swift -o /tmp/awcatalog && /tmp/awcatalog

import Foundation

@main
struct Harness {
    nonisolated(unsafe) static var passed = 0
    nonisolated(unsafe) static var failed = 0

    static func check(_ name: String, _ ok: Bool, _ detail: String) {
        if ok { passed += 1 } else { failed += 1 }
        print("[AWAUDIT] \(ok ? "PASS" : "FAIL") \(name) — \(detail)")
    }

    static func main() {
        let path = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1] : "/tmp/catalog-audit.sqlite"
        guard let db = CatalogDB(path: path) else {
            print("[AWAUDIT] FAIL open — no DB at \(path)"); exit(2)
        }
        let total = db.itemCount
        check("catalog", total > 10_000, "\(total) items")

        // ── Home shelf gates ────────────────────────────────────────────────
        var populated = 0, playable = 0
        for id in Featured.homeShelfPriority {
            let items = db.shelf(id)
            if items.isEmpty { continue }
            populated += 1
            if items.prefix(12).allSatisfy({ ($0.downloadURL ?? "").isEmpty == false }) {
                playable += 1
            } else {
                check("home.shelf.\(id)", false, "unplayable tile in the first 12 (D056)")
            }
        }
        check("home.shelves", populated >= 6,
              "\(populated)/\(Featured.homeShelfPriority.count) populated, \(playable) fully playable")

        let gems = db.hiddenGems()
        check("home.hiddenGems", !gems.isEmpty, "\(gems.count) gems")

        let top = db.topRated()
        let topOrdered = zip(top, top.dropFirst()).allSatisfy { ($0.imdbRating ?? 0) >= ($1.imdbRating ?? 0) }
        let topFloored = top.allSatisfy { ($0.imdbVotes ?? 0) >= 1000 }
        check("home.topRated", !top.isEmpty && topOrdered && topFloored,
              "\(top.count), ordered=\(topOrdered), votes≥1000=\(topFloored)")

        for (name, items) in [("watchingNow", db.watchingNow()),
                              ("communityFavorites", db.communityFavorites()),
                              ("mostDiscussed", db.mostDiscussed())] {
            let floored = items.allSatisfy { ($0.imdbVotes ?? 0) >= 1000 }
            check("home.\(name)", !items.isEmpty && floored, "\(items.count), floored=\(floored)")
        }

        let directors = db.topDirectors()
        if let first = directors.first {
            check("home.directors", db.byDirector(first.name).count >= 3,
                  "\(directors.count) directors; \(first.name) leads")
        } else { check("home.directors", false, "none met the floor") }

        let decades = db.decadeCounts()
        check("home.decadeTiles", !decades.isEmpty
              && decades.keys.allSatisfy { (1890...2029).contains($0) },
              "\(decades.count) decades, all sane")

        // ── Browse: every facet, every sort ─────────────────────────────────
        let all = db.browseCount()
        check("browse.total", all > 5_000, "\(all) browsable")

        for type in ["feature-film", "animation", "newsreel"] {
            let n = db.browseCount(contentType: type)
            let page = db.browse(contentType: type, limit: 30)
            check("browse.type.\(type)", n > 0 && n < all
                  && page.allSatisfy { $0.contentType == type }, "\(n) items")
        }
        for decade in [1930, 1950, 1970] {
            let page = db.browse(decade: decade, limit: 30)
            check("browse.decade.\(decade)s", !page.isEmpty
                  && page.allSatisfy { (decade...decade+9).contains($0.year ?? -1) },
                  "\(page.count) on page")
        }
        if let genre = db.topGenres().first {
            check("browse.genre", !db.browse(genre: genre, limit: 20).isEmpty, "'\(genre)'")
        } else { check("browse.genre", false, "no genres") }

        let alpha = db.browse(sort: .alphabetical, limit: 50)
        check("browse.sort.alphabetical", !alpha.isEmpty && zip(alpha, alpha.dropFirst()).allSatisfy {
            $0.title.localizedCaseInsensitiveCompare($1.title) != .orderedDescending }, "ok")
        let newest = db.browse(sort: .newest, limit: 50)
        check("browse.sort.newest", !newest.isEmpty && zip(newest, newest.dropFirst()).allSatisfy {
            ($0.year ?? 0) >= ($1.year ?? 0) }, "ok")
        let oldest = db.browse(sort: .oldest, limit: 50)
        check("browse.sort.oldest", !oldest.isEmpty && zip(oldest, oldest.dropFirst()).allSatisfy {
            ($0.year ?? 9999) <= ($1.year ?? 9999) }, "ok")
        let rated = db.browse(sort: .rating, limit: 50)
        check("browse.sort.rating", !rated.isEmpty && zip(rated, rated.dropFirst()).allSatisfy {
            ($0.imdbRating ?? -1) >= ($1.imdbRating ?? -1) }, "ok")
        check("browse.sort.popular", !db.browse(sort: .popular, limit: 50).isEmpty, "ok")

        let p1 = db.browse(limit: 50), p2 = db.browse(limit: 50, offset: 50)
        let overlap = Set(p1.map(\.archiveID)).intersection(p2.map(\.archiveID))
        check("browse.paging", !p2.isEmpty && overlap.isEmpty, "overlap=\(overlap.count)")
        check("browse.noTVLeak", p1.allSatisfy {
            !["tv-series", "tv-special", "tv-episode"].contains($0.contentType) }, "film surface clean")

        // ── TV ──────────────────────────────────────────────────────────────
        let cards = db.seriesCards()
        check("tv.seriesCards", !cards.isEmpty
              && cards.prefix(30).allSatisfy { $0.hasRealArtwork == true },
              "\(cards.count) series, first 30 postered")
        let specials = db.tvSpecials(limit: 30)
        check("tv.specials", db.tvSpecialsCount() > 0
              && specials.allSatisfy { $0.contentType == "tv-special" },
              "\(db.tvSpecialsCount()) specials")
        let episode = db.search("episode", limit: 200).first { $0.seriesID != nil }
        check("tv.episodesAsItems", episode != nil,
              episode.map { "'\($0.title)'" } ?? "none in FTS")

        // ── Search ──────────────────────────────────────────────────────────
        check("search.knownTitle",
              db.search("incredible machine").contains { $0.archiveID == "mantheincrediblemachine" },
              "found the reference film")
        let broad = db.search("the", limit: 200)
        check("search.noSpecialLeak", !broad.isEmpty
              && !broad.contains { $0.contentType == "tv-special" }, "\(broad.count) hits")

        // ── Surprise ────────────────────────────────────────────────────────
        var surpriseOK = true, why = ""
        for _ in 0..<5 {
            guard let pick = db.randomPlayable() else { surpriseOK = false; why = "nil"; break }
            if (pick.downloadURL ?? "").isEmpty { surpriseOK = false; why = "unplayable"; break }
            if ["tv-series", "tv-special", "tv-episode"].contains(pick.contentType) {
                surpriseOK = false; why = "TV leak \(pick.archiveID)"; break
            }
        }
        check("surprise.randomFilm", surpriseOK, surpriseOK ? "5 playable picks" : why)
        check("surprise.randomCommercial",
              db.randomPlayable(contentType: "commercial")?.contentType == "commercial", "ok")

        // ── Settings consumption (DB-level) ─────────────────────────────────
        let before = db.browseCount()
        db.hideAdult.toggle()
        let after = db.browseCount()
        db.hideAdult.toggle()
        check("settings.matureToggle", after != before, "\(before) → \(after)")

        let originalHidden = db.hiddenTypes
        db.hiddenTypes = originalHidden.union(["newsreel"])
        let leaked = db.browse(limit: 200).contains { $0.contentType == "newsreel" }
        db.hiddenTypes = originalHidden
        check("settings.hideCategory", !leaked, "newsreel hidden holds")

        print("[AWAUDIT] SUMMARY passed=\(passed) failed=\(failed)")
        exit(failed == 0 ? 0 : 1)
    }
}
