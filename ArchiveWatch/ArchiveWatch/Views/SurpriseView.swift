import SwiftUI

// The three random actions from Decision 014 — invite curiosity.
// Each tile picks fresh on tap.

struct SurpriseView: View {
    @Environment(AppStore.self) private var store
    @State private var rollSeed: Int = Int.random(in: 0..<1_000_000)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                header
                HStack(spacing: 24) {
                    RandomMovieCard(seed: rollSeed)
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
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Surprise Me")
                    .font(.system(size: 54, weight: .heavy, design: .serif))
                    .foregroundStyle(.white)
                Text("Three ways to wander the archive. Roll again for fresh picks.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            RollAgainButton { rollSeed = Int.random(in: 0..<1_000_000) }
        }
        .padding(.horizontal, 80)
    }
}

struct RollAgainButton: View {
    let action: () -> Void
    @FocusState private var isFocused: Bool
    @State private var spin: Double = 0

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.4)) { spin += 360 }
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "dice.fill")
                    .font(.title2)
                    .rotationEffect(.degrees(spin))
                Text("Roll Again")
                    .font(.title3.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [Color(hex: "#FF5C35") ?? .orange,
                                 (Color(hex: "#FF5C35") ?? .orange).mix(with: .black, 0.2)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    isFocused ? Color.white : Color.white.opacity(0.15),
                    lineWidth: isFocused ? 3 : 1
                )
            )
            .shadow(color: (Color(hex: "#FF5C35") ?? .orange).opacity(isFocused ? 0.7 : 0.35),
                    radius: isFocused ? 20 : 12, y: 4)
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

// MARK: - Shared helpers

private func playablePool(_ items: [Catalog.Item]?) -> [Catalog.Item] {
    // Strict: only items with playable video AND real designed artwork.
    // Surprise is the "look at this thing" feature — procedural cards
    // in this context look like the roll failed.
    (items ?? []).filter { $0.videoFile != nil && $0.hasDesignedArtwork }
}

private func randomItem(from pool: [Catalog.Item], seed: UInt64) -> Catalog.Item? {
    guard !pool.isEmpty else { return nil }
    var rng = SplitMix(seed: seed)
    return pool.randomElement(using: &rng)
}

// MARK: - Random film action card (anything, no filter)

struct RandomMovieCard: View {
    @Environment(AppStore.self) private var store
    let seed: Int

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
                    accent: Color(hex: "#FF5C35") ?? .orange,
                    posterURL: p.backdropURLParsed ?? p.posterURLParsed
                )
            }
            .buttonStyle(.card)
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
                    accent: Color(hex: p.category.accent) ?? .blue,
                    posterURL: p.item.backdropURLParsed ?? p.item.posterURLParsed
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
                    accent: Color(hex: "#C9A66B") ?? .brown,
                    posterURL: p.item.backdropURLParsed ?? p.item.posterURLParsed
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
    /// Optional poster URL — when set, replaces the accent gradient
    /// backdrop with the actual movie art.
    var posterURL: URL? = nil

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let posterURL {
                AsyncImage(url: posterURL, transaction: Transaction(animation: .easeIn(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        LinearGradient(
                            colors: [accent.opacity(0.9), accent.mix(with: .black, 0.5)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    }
                }
                // Dark wash so title remains readable on bright art.
                LinearGradient(
                    colors: [.black.opacity(0.1), .black.opacity(0.4), .black.opacity(0.95)],
                    startPoint: .top, endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [accent.opacity(0.9), accent.mix(with: .black, 0.5)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                Spacer()
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.85))
                Text(subtitle)
                    .font(.system(size: 30, weight: .heavy, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            .padding(28)
        }
        .frame(width: 440, height: 580)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
