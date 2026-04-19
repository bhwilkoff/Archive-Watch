import SwiftUI

// The three random actions from Decision 014 — invite curiosity.
// Each tile picks fresh on tap.

struct SurpriseView: View {
    @Environment(AppStore.self) private var store
    @State private var rollSeed = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                header
                HStack(spacing: 24) {
                    RandomMovieCard(seed: rollSeed, shuffle: { rollSeed &+= 1 })
                    RandomCategoryCard(seed: rollSeed)
                    RandomDecadeCard(seed: rollSeed)
                }
                .padding(.horizontal, 80)
                Spacer(minLength: 80)
            }
            .padding(.vertical, 48)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Surprise Me")
                .font(.system(size: 54, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
            Text("Three ways to wander the archive.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 80)
    }
}

// MARK: - Shared helpers

private func playablePool(_ items: [Catalog.Item]?) -> [Catalog.Item] {
    (items ?? []).filter { $0.videoFile != nil }
}

private func randomItem(from pool: [Catalog.Item], seed: UInt64) -> Catalog.Item? {
    guard !pool.isEmpty else { return nil }
    // Prefer items with real artwork — they read better as "the pick".
    let designed = pool.filter { $0.hasDesignedArtwork }
    var rng = SplitMix(seed: seed)
    if !designed.isEmpty { return designed.randomElement(using: &rng) }
    return pool.randomElement(using: &rng)
}

// MARK: - Random film action card (anything, no filter)

struct RandomMovieCard: View {
    @Environment(AppStore.self) private var store
    let seed: Int
    let shuffle: () -> Void

    private var pick: Catalog.Item? {
        randomItem(from: playablePool(store.catalog?.items), seed: UInt64(seed))
    }

    var body: some View {
        if let p = pick {
            NavigationLink(value: p) {
                ActionCard(
                    title: "Random Film",
                    subtitle: p.title,
                    caption: p.year.map(String.init) ?? "Roll the dice.",
                    icon: "sparkles",
                    accent: Color(hex: "#FF5C35") ?? .orange
                )
            }
            .buttonStyle(.card)
            .simultaneousGesture(TapGesture(count: 2).onEnded { shuffle() })
        } else {
            ActionCard(title: "Random Film", subtitle: "No catalog loaded",
                       caption: "", icon: "sparkles", accent: .orange)
        }
    }
}

// MARK: - Random film IN a random category

struct RandomCategoryCard: View {
    @Environment(AppStore.self) private var store
    let seed: Int

    private var pick: (category: Featured.Category, item: Catalog.Item)? {
        guard let cats = store.featured?.categories else { return nil }
        var rng = SplitMix(seed: UInt64(seed &+ 7))
        let shuffledCats = cats.shuffled(using: &rng)
        for c in shuffledCats {
            let pool = playablePool(store.catalog?.items).filter { $0.contentType == c.id }
            if let pick = randomItem(from: pool, seed: UInt64(seed &+ 7)) {
                return (c, pick)
            }
        }
        return nil
    }

    var body: some View {
        if let p = pick {
            NavigationLink(value: p.item) {
                ActionCard(
                    title: "Random \(p.category.shortName ?? p.category.displayName)",
                    subtitle: p.item.title,
                    caption: p.item.year.map { "\(p.category.displayName) · \($0)" } ?? p.category.displayName,
                    icon: "square.grid.2x2.fill",
                    accent: Color(hex: p.category.accent) ?? .blue
                )
            }
            .buttonStyle(.card)
        } else {
            ActionCard(title: "Random Category", subtitle: "—", caption: "",
                       icon: "square.grid.2x2.fill", accent: .blue)
        }
    }
}

// MARK: - Random film from a random era

struct RandomDecadeCard: View {
    @Environment(AppStore.self) private var store
    let seed: Int

    private var pick: (decade: Int, item: Catalog.Item)? {
        guard let items = store.catalog?.items else { return nil }
        var rng = SplitMix(seed: UInt64(seed &+ 13))
        let decades = Array(Set(items.compactMap { $0.decade })).shuffled(using: &rng)
        for d in decades {
            let pool = playablePool(items).filter { $0.decade == d }
            if let pick = randomItem(from: pool, seed: UInt64(seed &+ 13)) {
                return (d, pick)
            }
        }
        return nil
    }

    var body: some View {
        if let p = pick {
            NavigationLink(value: p.item) {
                ActionCard(
                    title: "Random \(p.decade)s",
                    subtitle: p.item.title,
                    caption: "Time-travel to the \(p.decade)s.",
                    icon: "clock.arrow.circlepath",
                    accent: Color(hex: "#C9A66B") ?? .brown
                )
            }
            .buttonStyle(.card)
        } else {
            ActionCard(title: "Random Era", subtitle: "—", caption: "",
                       icon: "clock.arrow.circlepath", accent: .brown)
        }
    }
}

// MARK: - Shared action card

struct ActionCard: View {
    let title: String
    let subtitle: String
    let caption: String
    let icon: String
    let accent: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [accent.opacity(0.9), accent.mix(with: .black, 0.5)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.85))
                Text(subtitle)
                    .font(.system(size: 32, weight: .heavy, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .padding(32)
        }
        .frame(width: 440, height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
