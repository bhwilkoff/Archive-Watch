import SwiftUI

@MainActor
@Observable
final class AppStore {

    var navigationPath = NavigationPath()
    var catalog: Catalog?
    var featured: Featured?
    var loadError: String?

    func loadBundledData() async {
        do {
            // Prefer cached/downloaded catalog over the bundled one if present.
            if let refreshed = await CatalogRefreshService.shared.loadLatest() {
                catalog = refreshed
            } else {
                catalog = try CatalogLoader.loadCatalog()
            }
            featured = try CatalogLoader.loadFeatured()
        } catch CatalogLoader.LoadError.bundleMissing(let name) {
            loadError = "Missing bundled resource: \(name)"
        } catch CatalogLoader.LoadError.decodeFailed(let name, let err) {
            loadError = "Failed to decode \(name): \(err.localizedDescription)"
        } catch {
            loadError = error.localizedDescription
        }

        // Kick off a background refresh from GitHub Pages. Doesn't block UI.
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
