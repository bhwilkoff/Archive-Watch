import SwiftUI

@MainActor
@Observable
final class AppStore {

    var catalog: Catalog?
    var featured: Featured?
    var loadError: String?

    func loadBundledData() async {
        // STEP 1 — synchronous bundle load. Unblocks the UI within a
        // second; the user never sees "Loading catalog…" hang waiting
        // on the actor hop or a network fetch. Before this refactor,
        // an empty disk cache + slow JSON decode in the actor could
        // leave the spinner up indefinitely.
        let bundleStart = Date()
        do {
            catalog = try CatalogLoader.loadCatalog()
            featured = try CatalogLoader.loadFeatured()
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

        // STEP 3 — background refresh from GitHub Pages.
        Task { [weak self] in
            if let fresh = await CatalogRefreshService.shared.refresh() {
                await MainActor.run { self?.catalog = fresh }
            }
        }
    }

    /// Items assigned to the given shelf id. Preserves catalog order,
    /// which reflects the order the builder emitted them (Archive popularity
    /// + curator sequence within Editor's Picks).
    func items(forShelf shelfID: String) -> [Catalog.Item] {
        catalog?.items.filter { $0.shelves.contains(shelfID) } ?? []
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
