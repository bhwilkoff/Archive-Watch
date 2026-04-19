import SwiftUI

// Curator-led landing. Each collection is a card with a composite
// backdrop (3 overlapping posters from the collection) + count + blurb.
// Inspired by Channels' Library landing.

struct CollectionsView: View {
    @Environment(AppStore.self) private var store

    private var collectionCards: [CollectionCardData] {
        let featuredCollections: [(id: String, title: String, blurb: String, accent: String)] = [
            ("feature_films",  "Feature Films",             "The main library — thousands of public-domain features.",     "#FF5C35"),
            ("silent_films",   "Silent Cinema",             "Before sound: 1894–1929. Melies, Griffith, Keaton.",          "#C9A66B"),
            ("prelinger",      "The Prelinger Archive",     "Industrial, educational, and ephemeral 20th-century film.",   "#7C5BBA"),
            ("classic_tv",     "Classic Television",        "Vintage broadcasts, episodic serials, public-domain TV.",     "#2D5BFF"),
            ("classic_cartoons","Classic Cartoons",         "Pre-1970 animation — Fleischer, Terrytoons, early Disney.",   "#FF4D8D"),
            ("fedflix",        "US Government Films",       "FedFlix, NASA, wartime information, PSAs.",                   "#3FA796"),
            ("newsandpublicaffairs", "Newsreels",           "How the 20th century reported itself to itself.",             "#8A8F98"),
            ("short_films",    "Short Films",               "Bizarre, beautiful, and under thirty minutes.",               "#E8A317")
        ]
        return featuredCollections.map { c in
            let matching = store.catalog?.items.filter { $0.collections.contains(c.id) } ?? []
            return CollectionCardData(
                id: c.id,
                title: c.title,
                blurb: c.blurb,
                accent: Color(hex: c.accent) ?? .accentColor,
                itemCount: matching.count,
                posterURLs: matching.compactMap { $0.hasDesignedArtwork ? $0.posterURLParsed : nil }.prefix(3).map { $0 }
            )
        }
        .filter { $0.itemCount > 0 }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Collections")
                        .font(.system(size: 54, weight: .heavy, design: .serif))
                        .foregroundStyle(.white)
                    Text("Curator-led paths through the archive.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 80)
                .padding(.top, 48)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 32), GridItem(.flexible(), spacing: 32)], spacing: 32) {
                    ForEach(collectionCards) { data in
                        NavigationLink(value: BrowseFilter(collection: data.id)) {
                            CollectionCard(data: data)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 80)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
}

struct CollectionCardData: Identifiable {
    let id: String
    let title: String
    let blurb: String
    let accent: Color
    let itemCount: Int
    let posterURLs: [URL]
}

struct CollectionCard: View {
    let data: CollectionCardData

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            posterStack
            LinearGradient(
                colors: [.clear, .black.opacity(0.65), .black.opacity(0.95)],
                startPoint: .center, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Capsule()
                        .fill(data.accent)
                        .frame(width: 28, height: 3)
                    Text("\(data.itemCount) titles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text(data.title)
                    .font(.system(size: 32, weight: .heavy, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(data.blurb)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
                    .frame(maxWidth: 600, alignment: .leading)
            }
            .padding(28)
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var posterStack: some View {
        ZStack {
            data.accent.opacity(0.3)
            HStack(spacing: 0) {
                ForEach(Array(data.posterURLs.prefix(3).enumerated()), id: \.offset) { idx, url in
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            data.accent.opacity(0.4)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .opacity(idx == 1 ? 1.0 : 0.75)
                }
            }
        }
    }
}
