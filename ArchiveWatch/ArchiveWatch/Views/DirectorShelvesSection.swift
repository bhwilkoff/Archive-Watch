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
    @State private var groups: [DirectorGroup] = []

    private struct DirectorGroup: Identifiable {
        let id: String           // director name = stable id
        let name: String
        let items: [Catalog.Item]
        let category: String     // dominant contentType, for accent colour
    }

    /// Top directors come from a grouped DB query; each shelf is a second
    /// query for that director's films (Decision 017).
    private func loadGroups() -> [DirectorGroup] {
        store.dbTopDirectors().compactMap { d in
            // #2: Home shows only professional posters, never generated covers.
            let films = store.dbByDirector(d.name, homeOnly: true).filter { $0.hasProfessionalArtwork }
            guard !films.isEmpty else { return nil }
            return DirectorGroup(id: d.name, name: d.name, items: films,
                         category: dominantCategory(for: films))
        }
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
        Group {
            if groups.isEmpty {
                EmptyView()
            } else {
                directorShelves
            }
        }
        .task(id: store.dbGeneration) { groups = loadGroups() }
    }

    @ViewBuilder
    private var directorShelves: some View {
        VStack(alignment: .leading, spacing: 48) {
                Text("Directors")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 80)
                ForEach(groups) { group in
                    let shelf = Featured.Shelf(
                        id: "director-\(group.id)",
                        title: group.name,
                        subtitle: "\(group.items.count) films to discover",
                        category: group.category,
                        type: "dynamic",
                        items: nil, query: nil, sort: nil, limit: nil
                    )
                    ShelfRow(shelf: shelf, items: group.items)
                }
        }
    }
}
