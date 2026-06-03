import SwiftUI

// The three random actions from Decision 014 — invite curiosity.
//
// Redesigned (#3): fits one screen with NO vertical scroll, so "Roll Again"
// is always visible and one focus-move from the result cards (the old design
// buried it in a scrolling header). Results use the app's standard PosterTile
// so they match Home/Browse exactly instead of a bespoke card. Roll Again is
// the default focus — land here, press to reroll, or move down to a pick.

struct SurpriseView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var rollSeed: Int = Int.random(in: 0..<1_000_000)
    @State private var film: Catalog.Item?
    @State private var categoryPick: (category: Featured.Category, item: Catalog.Item)?
    @State private var decadePick: (decade: Int, item: Catalog.Item)?
    @FocusState private var rollFocused: Bool

    private let orange = Color(hex: "#FF5C35") ?? .orange
    private let sepia  = Color(hex: "#C9A66B") ?? .brown

    var body: some View {
        VStack(spacing: 0) {
            header
                .focusSection()
            Spacer(minLength: 24)
            cards
                .focusSection()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .task(id: "\(rollSeed)-\(store.dbGeneration)") { roll() }
        .task {
            // Land on Roll Again so the primary action is immediately at hand.
            try? await Task.sleep(for: .milliseconds(80))
            rollFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Surprise Me")
                    .font(.system(size: 52, weight: .heavy, design: .serif))
                    .foregroundStyle(.white)
                Text("Three ways to wander the archive.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Button {
                rollSeed = Int.random(in: 0..<1_000_000)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "dice.fill").font(.title2)
                    Text("Roll Again").font(.title3.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 16)
            }
            .buttonStyle(PrimaryCTAStyle(accent: orange))
            .focusEffectDisabled()
            .focused($rollFocused)
        }
    }

    // MARK: - Result cards (standard PosterTile)

    private var cards: some View {
        HStack(alignment: .top, spacing: 64) {
            SurpriseColumn(label: "Random Film", accent: orange, item: film) { router.push($0) }
            SurpriseColumn(
                label: categoryPick.map { "Random \($0.category.shortName ?? $0.category.displayName)" } ?? "Random Category",
                accent: categoryPick.flatMap { Color(hex: $0.category.accent) } ?? .blue,
                item: categoryPick?.item) { router.push($0) }
            SurpriseColumn(
                label: decadePick.map { "Random \($0.decade)s" } ?? "Random Era",
                accent: sepia,
                item: decadePick?.item) { router.push($0) }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rolling

    private func roll() {
        film = store.dbRandomPlayable()
        categoryPick = rollCategory()
        decadePick = rollDecade()
    }

    private func rollCategory() -> (category: Featured.Category, item: Catalog.Item)? {
        guard let cats = store.featured?.categories else { return nil }
        var rng = SplitMix(seed: UInt64(bitPattern: Int64(rollSeed)) &+ 7)
        for c in cats.shuffled(using: &rng) where c.id != "tv-series" {
            if let item = store.dbRandomPlayable(contentType: c.id) { return (c, item) }
        }
        return nil
    }

    private func rollDecade() -> (decade: Int, item: Catalog.Item)? {
        var rng = SplitMix(seed: UInt64(bitPattern: Int64(rollSeed)) &+ 13)
        for d in store.dbDecadeCounts().keys.shuffled(using: &rng) {
            let pool = store.dbBrowse(decade: d, limit: 60)
            if let item = pool.randomElement(using: &rng) { return (d, item) }
        }
        return nil
    }
}

// MARK: - One labeled result column

private struct SurpriseColumn: View {
    let label: String
    let accent: Color
    let item: Catalog.Item?
    let onSelect: (Catalog.Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Circle().fill(accent).frame(width: 12, height: 12)
                Text(label.uppercased())
                    .font(.system(size: 17, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if let item {
                PosterTile(item: item, action: { onSelect(item) })
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.08))
                    .frame(width: 240, height: 360)
                    .overlay(ProgressView().tint(.white))
            }
        }
        .frame(width: 240, alignment: .leading)
    }
}
