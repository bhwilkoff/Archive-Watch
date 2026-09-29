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
    /// A review was clamped to six lines with no way to read the rest, so a
    /// long one simply ended mid-sentence (owner, 2026-08-28). Tapping the
    /// card expands it; the title stays clamped because it is an identifier,
    /// not the content.
    @State private var expanded = false
    @State private var bodyTruncated = false
    #if os(tvOS)
    @State private var reading = false
    #endif

    /// MEASURED on every platform (tvOS v1.42.840, iPad v1.42.868): the full
    /// text is laid out hidden behind the clamped one, and "More" is offered
    /// only when it is taller. A 260-character guess offered "Show more" on
    /// short reviews at iPad width and missed short multi-paragraph ones.
    /// Once expanded the two match, so "Show less" keeps its place.
    private var maybeTruncated: Bool { expanded || bodyTruncated }

    /// The review text itself. Selection is iOS/macOS only — tvOS has no text
    /// selection at all, and reaches the same content by focusing the card.
    @ViewBuilder private func reviewBody(_ b: String) -> some View {
        let t = Text(b).font(.callout).foregroundStyle(.secondary)
            .lineLimit(expanded ? nil : 6)
        let measured = t
            .readsTruncation(of: Text(b).font(.callout), into: $bodyTruncated)
        #if os(tvOS)
        measured
        #else
        measured.textSelection(.enabled)
        #endif
    }

    /// The card's content. Identical on every platform; only what WRAPS it
    /// differs, because tvOS reaches it with a remote and the others with a
    /// finger.
    @ViewBuilder private var cardContent: some View {
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
                    Text(t).font(.subheadline).fontWeight(.semibold).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            if let b = review.body, !b.isEmpty {
                reviewBody(b)
                if maybeTruncated {
                    #if os(tvOS)
                    Text("More")
                        .font(.caption).fontWeight(.bold)
                        .foregroundStyle(.white.opacity(0.7))
                    #else
                    Text(expanded ? "Show less" : "Show more")
                        .font(.caption)
                        #if os(tvOS)
                        .foregroundStyle(.white.opacity(0.6))
                        #else
                        .foregroundStyle(.tint)
                        #endif
                    #endif
                }
            }
            Text(review.displayName + (review.date.map { " · \($0)" } ?? ""))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        #if os(tvOS)
        // EVERY card is focusable, not only the long ones. Previously the only
        // focusable thing in a card was the "Show more" button, which exists
        // only when the body runs past 260 characters — so a short review had
        // nothing for the focus engine to stop on, the ScrollView never
        // scrolled to it, and it could not be highlighted or read (owner,
        // 2026-09-04: "each review from archive.org does not scroll as it
        // should"). Now Up/Down walks review to review.
        //
        // The style changes no geometry on focus, so walking the list does not
        // reflow the page; Select opens a long one whole on its own page.
        Button {
            if maybeTruncated { reading = true }
        } label: {
            cardContent
        }
        .buttonStyle(ReadingCardStyle())
        .focusEffectDisabled()
        .fullScreenCover(isPresented: $reading) {
            FullTextReader(title: review.title ?? review.displayName, text: review.body ?? "")
        }
        #else
        cardContent
            .padding(12)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            // The whole card is the target — on a phone the text is what a
            // thumb lands on.
            .contentShape(.rect)
            .onTapGesture {
                guard maybeTruncated else { return }
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            }
        #endif
    }
}
