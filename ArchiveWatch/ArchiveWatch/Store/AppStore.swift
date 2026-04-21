import SwiftUI

@MainActor
@Observable
final class AppStore {

    var catalog: Catalog? {
        didSet { rebuildDerived() }
    }
    var featured: Featured?
    var loadError: String?

    // Derived structures, rebuilt once per catalog assignment so
    // downstream views never re-filter 31k items on body recompute.
    // The old pattern — computed `items(forShelf:)` scanning catalog
    // items per call — cost 670k iterations per HomeView render (21
    // shelves × 31k items). Now it's an O(1) dict lookup.
    private(set) var shelfMembers: [String: [Catalog.Item]] = [:]
    private(set) var availableDecades: [Int] = []
    private(set) var decadeCounts: [Int: Int] = [:]
    private(set) var topGenres: [String] = []
    /// Everything except tv-series cards — what Browse's grid shows.
    private(set) var browseableItems: [Catalog.Item] = []
    /// Just the series cards — for future series-specific entry points.
    private(set) var seriesCards: [Catalog.Item] = []

    private func rebuildDerived() {
        guard let items = catalog?.items else {
            shelfMembers = [:]; availableDecades = []; decadeCounts = [:]
            topGenres = []; browseableItems = []; seriesCards = []
            return
        }

        // Split series cards from everything else — they have different
        // semantics (no direct playable URL, route to SeriesDetailView).
        var series: [Catalog.Item] = []
        var regular: [Catalog.Item] = []
        var decadeTally: [Int: Int] = [:]
        var genreCounts: [String: Int] = [:]
        var shelves: [String: [Catalog.Item]] = [:]

        for it in items {
            if it.contentType == "tv-series" {
                series.append(it)
            } else {
                regular.append(it)
            }
            if let d = it.decade { decadeTally[d, default: 0] += 1 }
            for g in it.genres where !g.isEmpty {
                genreCounts[g, default: 0] += 1
            }
            for s in it.shelves {
                shelves[s, default: []].append(it)
            }
        }

        self.seriesCards = series
        self.browseableItems = regular
        self.decadeCounts = decadeTally
        self.availableDecades = decadeTally.keys.sorted()
        self.topGenres = genreCounts
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(24)
            .map { $0.key }
        self.shelfMembers = shelves
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
            featured = try CatalogLoader.loadFeatured()
            catalog = try CatalogLoader.loadCatalog()
            print("[AppStore] bundle loaded in \(String(format: "%.2fs", Date().timeIntervalSince(bundleStart)))")
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

        // STEP 2 — disk cache (if any). Runs detached so a slow actor
        // hop doesn't matter. Only replace bundle if cache has at
        // least as many items (defensive against any regression).
        Task { [weak self] in
            guard let cached = await CatalogRefreshService.shared.loadDiskCache() else { return }
            await MainActor.run {
                guard let self else { return }
                if cached.items.count >= (self.catalog?.items.count ?? 0) {
                    self.catalog = cached
                }
            }
        }

        // STEP 3 — background refresh from GitHub Pages. Skipped when
        // the currently-loaded catalog was generated recently (default
        // 72h window) — no point downloading 77 MB to get the same
        // thing back. Users still get updates when they relaunch past
        // the freshness window, or when we publish a new catalog and
        // the cached copy ages out.
        let generatedAt = catalog?.generatedAt
        Task { [weak self] in
            let fresh = await CatalogRefreshService.shared.isFresh(generatedAt: generatedAt)
            guard !fresh else {
                print("[AppStore] catalog is fresh — skipping remote refresh")
                return
            }
            if let updated = await CatalogRefreshService.shared.refresh() {
                await MainActor.run { self?.catalog = updated }
            }
        }
    }

    /// Items assigned to the given shelf id. Preserves catalog order.
    /// Backed by the precomputed `shelfMembers` dict — O(1) lookup
    /// instead of the old per-call filter over all 31k items.
    func items(forShelf shelfID: String) -> [Catalog.Item] {
        shelfMembers[shelfID] ?? []
    }

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
