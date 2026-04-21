import SwiftUI

// "Directors" — home section that surfaces the most-prolific directors
// in the catalog, each as a horizontally scrolling shelf. This is how
// browsing a 25k archive actually rewards the viewer: not as a uniform
// list, but clustered around the people who made many of the films.
//
// Heuristic: director must have ≥ 3 films with designed artwork in the
// catalog; we then show the top N directors by film count. Each shelf
// is sorted by popularity so the best-known film leads.

struct DirectorShelvesSection: View {
    @Environment(AppStore.self) private var store

    private static let maxDirectorsShown:   Int = 4
    private static let minFilmsPerDirector: Int = 3
    private static let perShelfLimit:       Int = 20

    private struct Group: Identifiable {
        let id: String           // director name = stable id
        let name: String
        let items: [Catalog.Item]
        let category: String     // dominant contentType, for accent colour
    }

    private var groups: [Group] {
        guard let catalog = store.catalog else { return [] }
        var byDirector: [String: [Catalog.Item]] = [:]
        for item in catalog.items {
            guard let director = item.director,
                  !director.isEmpty,
                  item.hasDesignedArtwork else { continue }
            byDirector[director, default: []].append(item)
        }
        return byDirector
            .filter { $0.value.count >= Self.minFilmsPerDirector }
            .map { (name, films) in
                let sorted = films.sorted {
                    ($0.popularityScore ?? 0) > ($1.popularityScore ?? 0)
                }
                return Group(
                    id: name,
                    name: name,
                    items: Array(sorted.prefix(Self.perShelfLimit)),
                    category: dominantCategory(for: films)
                )
            }
            .sorted { $0.items.count > $1.items.count }
            .prefix(Self.maxDirectorsShown)
            .map { $0 }
    }

    // Pick the category that appears most often across the director's
    // films — tints the ShelfRow's accent dot appropriately. Ties break
    // alphabetically so the choice is stable across launches.
    private func dominantCategory(for items: [Catalog.Item]) -> String {
        var counts: [String: Int] = [:]
        for it in items { counts[it.contentType, default: 0] += 1 }
        return counts
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .first?.key ?? "feature-film"
    }

    var body: some View {
        if groups.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 48) {
                Text("Directors")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 80)
                ForEach(groups) { group in
                    let shelf = Featured.Shelf(
                        id: "director-\(group.id)",
                        title: group.name,
                        subtitle: "\(group.items.count) films in the archive",
                        category: group.category,
                        type: "dynamic",
                        items: nil, query: nil, sort: nil, limit: nil
                    )
                    ShelfRow(shelf: shelf, items: group.items)
                }
            }
        }
    }
}
