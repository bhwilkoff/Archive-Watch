import SwiftUI

// #15 Public Domain Day (tvOS-DESIGN §2.3): browse the films/TV that entered the
// US public domain in a given year. The 95-year rule: a work published in year Y
// enters the public domain on January 1 of Y+95 — so the "Class of Y" is shown by
// picking the entry year (Y+95). Learning-oriented: it teaches the PD calendar and
// celebrates each new class. Reached as a route (e.g. from Surprise).
struct PublicDomainRoute: Hashable {}

struct PublicDomainView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    private let thisYear = Calendar.current.component(.year, from: Date())
    @State private var entryYear = 0          // the Jan-1 the class entered PD
    @State private var items: [Catalog.Item] = []

    /// Most-recent entry years first; 95-year rule means pubYear = entryYear - 95.
    private var entryYears: [Int] { Array(stride(from: thisYear, through: thisYear - 20, by: -1)) }
    private var pubYear: Int { entryYear - 95 }

    private let cols = Array(repeating: GridItem(.fixed(210), spacing: 24), count: 6)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header
                yearChips
                grid
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            if entryYear == 0 { entryYear = thisYear }
            reload()
        }
        .onChange(of: entryYear) { _, _ in reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Public Domain Day")
                .font(.system(size: 57, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
            Text("The Class of \(verbatimYear(pubYear)) — works that entered the U.S. public domain on January 1, \(verbatimYear(entryYear)).")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var yearChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(entryYears, id: \.self) { ey in
                    let on = ey == entryYear
                    Button { entryYear = ey } label: {
                        Text(verbatimYear(ey))
                            .font(.system(size: 24, weight: .semibold))
                            .padding(.horizontal, 22).padding(.vertical, 12)
                    }
                    .buttonStyle(PDYearChipStyle(isOn: on))
                }
            }
            .padding(.vertical, 6)
        }
        .focusSection()
    }

    @ViewBuilder
    private var grid: some View {
        if items.isEmpty {
            Text("No titles from \(verbatimYear(pubYear)) in the catalog yet.")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 40)
        } else {
            LazyVGrid(columns: cols, spacing: 36) {
                ForEach(items) { item in
                    PosterTile(item: item) { router.push(item) }
                }
            }
            .padding(.top, 8)
        }
    }

    private func reload() {
        guard pubYear > 1870 else { items = []; return }
        items = store.dbBrowse(year: pubYear, sort: .popular, limit: 200)
    }

    // Year as a bare 4-digit string (no locale grouping comma — playbook §7.6).
    private func verbatimYear(_ y: Int) -> String { String(y) }
}

// #15b: a Home shelf spotlighting the current Public Domain class (works that
// entered the public domain this year). Surfaces #15 on Home; tiles open Detail,
// and the full year-explorer lives in PublicDomainView (Surprise -> Public Domain Day).
struct PublicDomainShelf: View {
    @Environment(AppStore.self) private var store
    @State private var items: [Catalog.Item] = []

    private let pubYear = Calendar.current.component(.year, from: Date()) - 95

    private var shelfDef: Featured.Shelf {
        Featured.Shelf(
            id: "public-domain-day",
            title: "Public Domain Day",
            subtitle: "Class of \(String(pubYear)) — newly free to share",
            category: "feature-film",
            type: "dynamic",
            items: nil, query: nil, sort: nil, limit: nil
        )
    }

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyView()
            } else {
                ShelfRow(shelf: shelfDef, items: items)
            }
        }
        .task(id: store.dbGeneration) {
            items = store.dbBrowse(year: pubYear, sort: .popular, limit: 24)
                .filter { $0.hasDesignedArtwork }
        }
    }
}

private struct PDYearChipStyle: ButtonStyle {
    let isOn: Bool
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isFocused ? .black : (isOn ? .black : .white))
            .background(
                Capsule().fill(
                    isFocused ? Color.white
                    : (isOn ? (Color(hex: "#FF5C35") ?? .orange) : Color.white.opacity(0.12))
                )
            )
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .animation(Motion.focus, value: isFocused)
    }
}
