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

// MARK: - Random film action card

struct RandomMovieCard: View {
    @Environment(AppStore.self) private var store
    let seed: Int
    let shuffle: () -> Void

    private var pick: Catalog.Item? {
        guard let items = store.catalog?.items else { return nil }
        let playable = items.filter { $0.videoFile != nil && $0.hasDesignedArtwork }
        guard !playable.isEmpty else { return items.randomElement() }
        var rng = SplitMix(seed: UInt64(seed))
        return playable.randomElement(using: &rng)
    }

    var body: some View {
        if let p = pick {
            NavigationLink(value: p) {
                ActionCard(
                    title: "Random Film",
                    subtitle: p.title,
                    caption: p.year.map { String($0) } ?? "Pick something.",
                    icon: "sparkles",
                    accent: Color(hex: "#FF5C35") ?? .orange
                )
            }
            .buttonStyle(.card)
            .simultaneousGesture(TapGesture(count: 2).onEnded { shuffle() })
        } else {
            ActionCard(title: "Random Film", subtitle: "Shuffling...", caption: "",
                       icon: "sparkles", accent: .orange)
        }
    }
}

// MARK: - Random category action card

struct RandomCategoryCard: View {
    @Environment(AppStore.self) private var store
    let seed: Int

    private var pick: Featured.Category? {
        guard let cats = store.featured?.categories else { return nil }
        var rng = SplitMix(seed: UInt64(seed &+ 7))
        return cats.randomElement(using: &rng)
    }

    var body: some View {
        if let c = pick {
            NavigationLink(value: BrowseFilter(category: c.id)) {
                ActionCard(
                    title: "Random Category",
                    subtitle: c.displayName,
                    caption: "Wander a whole section.",
                    icon: "square.grid.2x2.fill",
                    accent: Color(hex: c.accent) ?? .blue
                )
            }
            .buttonStyle(.card)
        } else {
            ActionCard(title: "Random Category", subtitle: "—", caption: "",
                       icon: "square.grid.2x2.fill", accent: .blue)
        }
    }
}

// MARK: - Random decade action card

struct RandomDecadeCard: View {
    @Environment(AppStore.self) private var store
    let seed: Int

    private var decade: Int? {
        guard let items = store.catalog?.items else { return nil }
        let pool = Array(Set(items.compactMap { $0.decade })).sorted()
        guard !pool.isEmpty else { return nil }
        var rng = SplitMix(seed: UInt64(seed &+ 13))
        return pool.randomElement(using: &rng)
    }

    var body: some View {
        if let d = decade {
            NavigationLink(value: BrowseFilter(decade: d)) {
                ActionCard(
                    title: "Random Era",
                    subtitle: "\(d)s",
                    caption: "Time-travel.",
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
