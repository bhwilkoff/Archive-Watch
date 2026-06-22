import SwiftUI

// Community surface for the Detail page: archive.org usage stats (views, favorites,
// rating) + genuine reviews of the title. The reviews are already filtered in the
// pipeline (tools/comment_fit.py) so we only ever show real reviews of the FILM —
// never file-quality talk or inappropriate comments — and the app just displays
// them. Shared by iOS and tvOS Detail. Renders nothing when there's no data.
struct CommunityDetailSection: View {
    let item: Catalog.Item

    private var hasStats: Bool {
        item.viewsDisplay != nil || item.favoritesDisplay != nil || item.avgRatingDisplay != nil
    }
    private var reviews: [Catalog.Review] { item.displayReviews }

    var body: some View {
        if hasStats || !reviews.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if hasStats { statsRow }
                if !reviews.isEmpty {
                    Text("From archive.org viewers")
                        .font(.title3).fontWeight(.semibold)
                    ForEach(reviews.prefix(6)) { ReviewCard(review: $0) }
                }
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 20) {
            if let r = item.avgRatingDisplay {
                stat(symbol: "star.fill", value: r, caption: "rating", tint: .yellow)
            }
            if let v = item.viewsDisplay {
                stat(symbol: "eye.fill", value: v, caption: "views")
            }
            if let f = item.favoritesDisplay {
                stat(symbol: "heart.fill", value: f, caption: "favorites", tint: .pink)
            }
        }
    }

    private func stat(symbol: String, value: String, caption: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.headline)
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ReviewCard: View {
    let review: Catalog.Review

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let s = review.stars, s > 0 {
                    HStack(spacing: 1) {
                        ForEach(0..<5, id: \.self) { i in
                            Image(systemName: i < s ? "star.fill" : "star")
                                .font(.caption2).foregroundStyle(.yellow)
                        }
                    }
                }
                if let t = review.title, !t.isEmpty {
                    Text(t).font(.subheadline).fontWeight(.semibold).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if let b = review.body, !b.isEmpty {
                Text(b).font(.callout).foregroundStyle(.secondary).lineLimit(6)
            }
            Text(review.displayName + (review.date.map { " · \($0)" } ?? ""))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
