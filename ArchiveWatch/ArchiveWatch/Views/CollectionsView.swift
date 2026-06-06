import SwiftUI

// Curator-led landing. Each collection is a card with a composite
// backdrop (3 overlapping posters from the collection) + count + blurb.
// Inspired by Channels' Library landing.

struct CollectionsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var collectionCards: [CollectionCardData] = []

    // Built from DB queries (Decision 017) — one count + a few poster rows per
    // registered collection. Computed in .task so we don't query per render.
    private func loadCards() -> [CollectionCardData] {
        CollectionMetadata.all.compactMap { entry in
            let count = store.dbCollectionCount(entry.id)
            guard count >= 10 else { return nil }   // needs enough to browse
            // #6: prefer designed art, but never render a blank card — fall back
            // to ANY available poster (generated covers, archive thumbs) so a
            // collection always shows images.
            let pool = store.dbByCollection(entry.id, limit: 40)
            var posters = pool.compactMap { $0.hasDesignedArtwork ? $0.posterURLParsed : nil }
                .prefix(3).map { $0 }
            if posters.isEmpty {
                posters = pool.compactMap { $0.posterURLParsed }.prefix(3).map { $0 }
            }
            return CollectionCardData(
                id: entry.id, title: entry.title, blurb: entry.blurb,
                accent: Color(hex: entry.accent) ?? .accentColor,
                itemCount: count, posterURLs: posters
            )
        }
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
                        Button { router.push(BrowseFilter(collection: data.id)) } label: {
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
        .task(id: store.dbGeneration) { collectionCards = loadCards() }
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.65), .black.opacity(0.95)],
                startPoint: .center, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Capsule()
                        .fill(data.accent)
                        .frame(width: 32, height: 4)
                    Text("\(data.itemCount) titles")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text(data.title)
                    .font(.system(size: 38, weight: .heavy, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(data.blurb)
                    .font(.system(size: 23, weight: .regular))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var posterStack: some View {
        GeometryReader { geo in
            ZStack {
                data.accent.opacity(0.3)
                HStack(spacing: 0) {
                    ForEach(Array(data.posterURLs.prefix(3).enumerated()), id: \.offset) { idx, url in
                        RemoteImage(
                            url: url,
                            targetSize: CGSize(width: geo.size.width / 3, height: geo.size.height),
                            contentMode: .fill,
                            placeholder: data.accent.opacity(0.4)
                        )
                        .frame(width: geo.size.width / 3, height: geo.size.height)
                        .clipped()
                        .opacity(idx == 1 ? 1.0 : 0.75)
                    }
                }
            }
        }
    }
}
