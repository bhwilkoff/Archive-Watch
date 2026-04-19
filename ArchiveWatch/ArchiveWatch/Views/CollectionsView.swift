import SwiftUI

// Curator-led landing. Each collection is a card with a composite
// backdrop (3 overlapping posters from the collection) + count + blurb.
// Inspired by Channels' Library landing.

struct CollectionsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    private var collectionCards: [CollectionCardData] {
        // (Archive collection id, display title, blurb, accent hex)
        // Ordered roughly by editorial priority within each category band.
        let featuredCollections: [(id: String, title: String, blurb: String, accent: String)] = [
            // Marquee features
            ("Film_Noir",               "Film Noir",                 "Shadows, second thoughts, venetian-blind lighting.",         "#FF5C35"),
            ("SciFi_Horror",            "Sci-Fi & Horror",           "B-movies, creature features, postwar paranoia.",             "#7C5BBA"),
            ("Comedy_Films",            "Comedy",                    "Pratfalls, quick wit, surreal cinema.",                      "#FF4D8D"),
            ("TheVideoCellarCollection","The Video Cellar",          "A curator's devoted private library.",                       "#E8A317"),
            ("feature_films",           "Feature Films",             "The main library — thousands of public-domain features.",    "#FF5C35"),
            ("feature_films_picfixer",  "Picfixer Restorations",     "A collector's multi-year film restoration project.",         "#FF5C35"),
            ("mid-century-german-film", "Mid-Century German Film",   "Postwar to New German Cinema.",                              "#8A8F98"),

            // Silent cinema
            ("silenthalloffame",        "Silent Hall of Fame",       "Curator-picked silents: Griffith, Chaplin, Keaton, Lang.",   "#C9A66B"),
            ("georgesmelies",           "Georges Méliès",            "The magician who invented cinema.",                          "#C9A66B"),
            ("silent_films",            "Silent Cinema",             "The first thirty years of moving pictures.",                 "#C9A66B"),
            ("segundodechomon",         "Segundo de Chomón",         "Spanish Méliès-era trick cinema pioneer.",                   "#C9A66B"),

            // Animation
            ("animationandcartoons",    "Animation",                 "From Fleischer to Terrytoons to beyond.",                    "#FF4D8D"),
            ("vintage_cartoons",        "Vintage Cartoons",          "Pre-1970 animation on 16mm and 35mm.",                       "#FF4D8D"),
            ("classic_cartoons",        "Classic Cartoons",          "Early Disney, Fleischer, Terrytoons.",                       "#FF4D8D"),

            // Classic TV (by decade)
            ("classic_tv_1950s",        "1950s Television",          "Live broadcasts, rabbit-ears era.",                          "#2D5BFF"),
            ("classic_tv_1960s",        "1960s Television",          "The golden age of network drama.",                           "#2D5BFF"),
            ("classic_tv_1970s",        "1970s Television",          "Color, variety, sitcom reinvention.",                        "#2D5BFF"),
            ("classic_tv_1980s",        "1980s Television",          "Cable arrives; the networks respond.",                       "#2D5BFF"),
            ("classic_tv_1940s",        "1940s Television",          "The earliest surviving broadcasts.",                         "#2D5BFF"),
            ("classic_tv",              "Classic Television",        "Vintage broadcasts across the 20th century.",                "#2D5BFF"),

            // Government + ephemeral + educational
            ("prelinger",               "The Prelinger Archive",     "Industrial, educational, and ephemeral 20th-century film.",  "#7C5BBA"),
            ("nasa",                    "NASA Films",                "Earthrise, moonwalks, the long engineering story.",          "#3FA796"),
            ("educationalfilms",        "Educational Shorts",        "Encyclopædia Britannica, Coronet, classroom filmstrips.",    "#7C5BBA"),
            ("ephemera",                "Ephemera",                  "Industrial, instructional, home, in-between.",               "#7C5BBA"),
            ("newsandpublicaffairs",    "Newsreels",                 "How the 20th century reported itself to itself.",            "#8A8F98")
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
        // A "collection" needs enough items to feel browseable. Under ten
        // and it's just a list, not a collection.
        .filter { $0.itemCount >= 10 }
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
                        Button { router.push(.filter(BrowseFilter(collection: data.id))) } label: {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

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
                    .font(.system(size: 28, weight: .heavy, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(data.blurb)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
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
