#if os(macOS)
import SwiftUI

// Detail: poster + metadata + play, synopsis, cast (tappable → person), More Like This,
// community reviews. The "Open in Creation Studio" affordance lands here in a later phase.

struct DetailView: View {
    let item: Catalog.Item
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let s = item.displaySynopsis {
                    Text(s).font(.body).textSelection(.enabled)
                }
                if !item.cast.isEmpty { castRow }
                let related = store.related(to: item)
                if !related.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("More Like This").font(.title3).fontWeight(.semibold)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 14) {
                                ForEach(related) { PosterCard(item: $0).frame(width: 140) }
                            }
                        }
                    }
                }
                if !item.displayReviews.isEmpty { reviews }
            }
            .padding(28)
        }
        .navigationTitle(item.title)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                if let url = item.posterURLParsed {
                    AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fit) }
                        placeholder: { Color.clear }
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(width: 240, height: 360)

            VStack(alignment: .leading, spacing: 12) {
                Text(item.title).font(.largeTitle).fontWeight(.bold)
                HStack(spacing: 10) {
                    if let y = item.year { Text(verbatim: String(y)) }
                    if let r = item.imdbRatingDisplay { Label(r, systemImage: "star.fill") }
                    if let rt = item.runtimeSeconds { Text("\(rt/60) min") }
                    if item.isBlackAndWhite { Text("B&W") }
                }
                .foregroundStyle(.secondary)
                if let by = item.byline { Text(by).foregroundStyle(.secondary) }
                if !item.genres.isEmpty {
                    Text(item.genres.prefix(4).joined(separator: " · "))
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    if item.videoURLParsed != nil {
                        Button { router.play(item) } label: {
                            Label("Play", systemImage: "play.fill")
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                    }
                    Link(destination: URL(string: item.sourceDetailsURL)!) {
                        Label("archive.org", systemImage: "link")
                    }
                }
                .padding(.top, 4)
                Spacer()
            }
            Spacer()
        }
    }

    private var castRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cast").font(.title3).fontWeight(.semibold)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(item.cast.prefix(20), id: \.name) { member in
                        VStack(spacing: 4) {
                            Circle().fill(.quaternary).frame(width: 56, height: 56)
                                .overlay {
                                    if let p = member.profilePath, let u = URL(string: p) {
                                        AsyncImage(url: u) { $0.resizable().scaledToFill() }
                                            placeholder: { Image(systemName: "person.fill") }
                                            .clipShape(Circle())
                                    } else { Image(systemName: "person.fill") }
                                }
                            Text(member.name).font(.caption).lineLimit(1).frame(width: 76)
                            if let c = member.character {
                                Text(c).font(.caption2).foregroundStyle(.secondary)
                                    .lineLimit(1).frame(width: 76)
                            }
                        }
                        .onTapGesture { router.openPerson(member.name) }
                    }
                }
            }
        }
    }

    private var reviews: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reviews").font(.title3).fontWeight(.semibold)
            ForEach(item.displayReviews.prefix(6)) { r in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(r.displayName).fontWeight(.medium)
                        if let s = r.stars {
                            Text(String(repeating: "★", count: s)).foregroundStyle(.orange)
                        }
                        Spacer()
                        if let d = r.date { Text(d).font(.caption).foregroundStyle(.secondary) }
                    }
                    if let t = r.title, !t.isEmpty { Text(t).fontWeight(.semibold) }
                    if let b = r.body { Text(b).font(.callout).foregroundStyle(.secondary) }
                }
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
#endif
