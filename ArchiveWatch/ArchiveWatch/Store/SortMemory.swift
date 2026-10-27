import Foundation

/// The sort a viewer chose for a grid, remembered per grid.
///
/// A viewer, 2026-10-25: "Sorting Menu resets to first menu item, not keeping
/// what we previously chose." Every grid held its sort in `@State`, so each
/// visit started over. The owner's answer, 2026-10-27: A–Z by default for
/// television, "with the ability to change and have it remember."
///
/// One UserDefaults key per KIND of grid, the same name on every Apple
/// platform (iOS-DESIGN §9.5): `browseSort.<surface>`. Per kind, not per
/// genre or decade, so a choice made once holds wherever it would be expected.
/// The value is the case's raw value, so a case is never renamed once shipped.
enum SortMemory {
    /// Television grids: series cards and TV Specials.
    static let tv = "tv"
    /// Browse's Films grid (the chips).
    static let browse = "browse"
    /// A category, genre, decade or facet grid of films.
    static let category = "category"
    /// A collection's own grid.
    static let collection = "collection"
    /// What a grid starts on before the viewer chooses: A–Z for television
    /// (series and specials are found by name), Popular for everything else
    /// (designed artwork first, Decision 097).
    static func defaultSort(for surface: String) -> CatalogDB.Sort {
        isTelevision(surface) ? .alphabetical : .popular
    }

    static func sort(for surface: String) -> CatalogDB.Sort {
        UserDefaults.standard.string(forKey: key(surface)).flatMap(CatalogDB.Sort.init(rawValue:))
            ?? defaultSort(for: surface)
    }

    static func remember(_ sort: CatalogDB.Sort, for surface: String) {
        UserDefaults.standard.set(sort.rawValue, forKey: key(surface))
    }

    /// The surface a category grid belongs to.
    static func surface(contentType: String?) -> String {
        contentType == "tv-series" || contentType == "tv-special" ? tv : category
    }

    static func key(_ surface: String) -> String { "browseSort.\(surface)" }

    private static func isTelevision(_ surface: String) -> Bool { surface == tv }
}

extension CatalogDB.Sort {
    /// The menu's words, one place for every Apple platform.
    var label: String {
        switch self {
        case .popular:             "Popular"
        case .rating:              "Top Rated"
        case .alphabetical:        "A–Z"
        case .reverseAlphabetical: "Z–A"
        case .newest:              "Newest"
        case .oldest:              "Oldest"
        }
    }
}
