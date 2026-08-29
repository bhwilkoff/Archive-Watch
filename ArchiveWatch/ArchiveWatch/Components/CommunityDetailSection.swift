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

    /// Six lines of `.callout` is roughly this many characters at phone width.
    /// Only past that can the clamp actually be hiding something, and only
    /// then is a "More" affordance honest.
    private var maybeTruncated: Bool { (review.body?.count ?? 0) > 260 }

    /// The review text itself. Selection is iOS/macOS only — tvOS has no text
    /// selection at all, and reaches the same content by focusing the card.
    @ViewBuilder private func reviewBody(_ b: String) -> some View {
        let t = Text(b).font(.callout).foregroundStyle(.secondary)
            .lineLimit(expanded ? nil : 6)
        #if os(tvOS)
        t
        #else
        t.textSelection(.enabled)
        #endif
    }

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
                reviewBody(b)
                if maybeTruncated {
                    Button(expanded ? "Show less" : "Show more") {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                    }
                    .font(.caption)
                    // NEVER .plain on tvOS — it destroys focusability, and on
                    // this screen focusability is the whole point: a card the
                    // remote can reach is a card the viewer can scroll to and
                    // read (owner, 2026-08-28).
                    #if os(tvOS)
                    .buttonStyle(.borderless)
                    #else
                    .buttonStyle(.plain)
                    // `.tint` and NOT Brand.accent: this file is shared by
                    // every platform, and Brand is declared `#if os(iOS)` —
                    // so naming it here compiles on the phone and breaks the
                    // Mac archive, which is exactly how it reached the cloud
                    // build (2026-08-29). The environment tint is the same
                    // accent on iOS and resolves everywhere.
                    .foregroundStyle(.tint)
                    #endif
                }
            }
            Text(review.displayName + (review.date.map { " · \($0)" } ?? ""))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        // The whole card is the target as well as the button — on a phone the
        // text is what a thumb lands on.
        #if !os(tvOS)
        // The whole card is the target as well as the button — on a phone the
        // text is what a thumb lands on. tvOS has no tap; it uses the button,
        // which the remote can focus.
        .contentShape(.rect)
        .onTapGesture {
            guard maybeTruncated else { return }
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        }
        #endif
    }
}
