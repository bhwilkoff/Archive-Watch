#if os(macOS)
import SwiftUI

// Discovery modes (parity with tvOS/iOS — docs/macOS-DESIGN.md §1): Cartoon Mode
// (character + theme shelves + marathon), Party Play (muted color eye-candy lineup),
// and Screensaver (a wall of professional poster art). Reached from Surprise, like
// the other platforms fold them away from the main nav. Pool logic mirrors the tvOS
// AppStore / shared KidsContent; the lineup players reuse the macOS ChannelPlayer.

struct CartoonRoute: Hashable {}
struct PartyRoute: Hashable {}
struct ScreensaverRoute: Hashable {}

// MARK: - Cartoon Mode (full: character + theme shelves + marathon)

struct CartoonView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var characters: [(name: String, items: [Catalog.Item])] = []
    @State private var collections: [(title: String, items: [Catalog.Item])] = []
    @State private var marathon: ChannelLineup?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Button { startMarathon() } label: {
                    Label("Play a Cartoon Marathon", systemImage: "play.fill")
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background((Color(hex: "#3FA796") ?? .teal).gradient, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain).padding(.horizontal, 24)

                ForEach(characters, id: \.name) { shelf(title: $0.name, items: $0.items) }
                ForEach(collections, id: \.title) { shelf(title: $0.title, items: $0.items) }
            }
            .padding(.vertical)
        }
        .navigationTitle("Cartoon Mode")
        .task(id: store.dbVersion) {
            characters = KidsContent.characters(store)
            collections = KidsContent.collections(store)
        }
        .sheet(item: $marathon) { box in
            ChannelPlayer(lineup: box.items, startOffset: 0)
                .frame(minWidth: 760, minHeight: 480)
        }
    }

    private func startMarathon() {
        let pool = KidsContent.cartoonPool(store)
        guard !pool.isEmpty else { return }
        marathon = ChannelLineup(items: pool, startOffset: 0)
    }

    private func shelf(title: String, items: [Catalog.Item]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3).fontWeight(.semibold).padding(.horizontal, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(items.prefix(20)) { PosterCard(item: $0).frame(width: 140) }
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

// MARK: - Party Play (muted color eye-candy lineup)

struct PartyPlayView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var preview: [Catalog.Item] = []
    @State private var playing: ChannelLineup?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Party Play").font(.largeTitle.bold())
                    Text("Nonstop, muted color visuals for the background of any gathering.")
                        .font(.title3).foregroundStyle(.secondary)
                    Button { start() } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 4)
                }
                if !preview.isEmpty {
                    Text("What's in the mix").font(.title3).fontWeight(.semibold)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 14) {
                            ForEach(preview) { PosterCard(item: $0).frame(width: 140) }
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Party Play")
        .task(id: store.dbVersion) { preview = Array(Modes.partyPool(store).prefix(18)) }
        .sheet(item: $playing) { box in
            ChannelPlayer(lineup: box.items, startOffset: 0, muted: true)
                .frame(minWidth: 760, minHeight: 480)
        }
    }

    private func start() {
        let pool = Modes.partyPool(store)
        guard !pool.isEmpty else { return }
        playing = ChannelLineup(items: pool, startOffset: 0)
    }
}

// MARK: - Screensaver (a wall of professional poster art)

struct ScreensaverView: View {
    var onExit: () -> Void = {}
    @Environment(AppStore.self) private var store
    @State private var pool: [Catalog.Item] = []
    @State private var slots: [Catalog.Item] = []
    private let spacing: CGFloat = 12
    private let target: CGFloat = 150

    var body: some View {
        GeometryReader { geo in
            let cols = max(4, Int((geo.size.width + spacing) / (target + spacing)))
            let w = (geo.size.width - spacing * CGFloat(cols + 1)) / CGFloat(cols)
            let h = w * 1.5
            let rows = max(3, Int((geo.size.height + spacing) / (h + spacing)))
            let n = cols * rows
            let grid = Array(repeating: GridItem(.fixed(w), spacing: spacing), count: cols)
            LazyVGrid(columns: grid, spacing: spacing) {
                ForEach(0..<max(n, slots.count), id: \.self) { i in
                    if i < slots.count { SaverTile(item: slots[i], width: w, height: h) }
                    else { RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)).frame(width: w, height: h) }
                }
            }
            .padding(spacing)
            .frame(width: geo.size.width, alignment: .center)
            .onAppear { if pool.isEmpty { pool = Modes.screensaverPool(store) }; fill(n) }
            .onChange(of: n) { _, newN in fill(newN) }
        }
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea()
        // Native structured-concurrency tick (replaces a Combine Timer.publish): auto-cancelled on
        // disappear, no stray fire into a torn-down view.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.2))
                if Task.isCancelled { break }
                advance()
            }
        }
        .onTapGesture { onExit() }             // any click exits (screensaver convention)
        .overlay(alignment: .topTrailing) {    // a subtle exit affordance (Esc also works, RootView)
            Button { onExit() } label: { Image(systemName: "xmark.circle.fill").font(.title) }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5)).padding(20)
                .help("Exit screensaver (Esc)")
        }
    }

    private func fill(_ n: Int) {
        guard !pool.isEmpty else { return }
        slots = (0..<n).compactMap { _ in pool.randomElement() }
    }
    private func advance() {
        guard !slots.isEmpty, pool.count > 4 else { return }
        var s = slots
        let k = Int.random(in: 0..<s.count)
        if let fresh = pool.randomElement() { s[k] = fresh; slots = s }
    }
}

private struct SaverTile: View {
    let item: Catalog.Item
    let width: CGFloat
    let height: CGFloat
    var body: some View {
        Color.black
            .frame(width: width, height: height)
            .overlay { RemotePoster(item: item) }   // poster → archive frame → title card (no empty tiles)
            .clipShape(.rect(cornerRadius: 8))
            .transition(.opacity)
            .id(item.archiveID)
    }
}

// MARK: - Pools (ported from the tvOS AppStore)

@MainActor
enum Modes {
    /// Party Play: muted background eye-candy — COLOR (never silent B&W), SHORT
    /// (≤ ~15 min), visually engaging by subject. Ranked so the most visual leads.
    static func partyPool(_ store: AppStore) -> [Catalog.Item] {
        let visual = ["abstract", "experimental", "avant-garde", "avant garde", "psychedelic",
                      "kaleidoscope", "surreal", "animation", "animated", "cartoon", "color",
                      "colour", "technicolor", "dance", "ballet", "music", "musical", "light",
                      "fireworks", "nature", "scenic", "travelogue", "landscape", "flowers",
                      "garden", "ocean", "underwater", "aquarium", "space", "nasa", "aurora",
                      "fractal", "mandala", "op art", "oil", "liquid", "paint", "art", "visual",
                      "fantasia", "rhythm", "geometric", "neon", "carnival", "parade"]
        var seen = Set<String>()
        var scored: [(Catalog.Item, Int)] = []
        let raw = store.dbBrowse(contentType: "animation", sort: .popular, limit: 250)
            + store.dbBrowse(contentType: "short-film", sort: .popular, limit: 250)
            + store.dbBrowse(genre: "Animation", sort: .popular, limit: 120)
        for it in raw {
            guard it.videoURLParsed != nil, it.hasDesignedArtwork else { continue }
            guard it.isSilentFilm != true, !it.isBlackAndWhite else { continue }
            if let r = it.runtimeSeconds, r > 0, r > 15 * 60 { continue }
            guard seen.insert(it.archiveID).inserted else { continue }
            let blob = (it.genres + it.subjects + [it.title]).map { $0.lowercased() }.joined(separator: " ")
            let hits = visual.reduce(0) { $0 + (blob.contains($1) ? 1 : 0) }
            let isAnim = it.contentType == "animation"
            scored.append((it, hits * 3 + (isAnim ? 2 : 0) + (it.popularityScore ?? 0) / 25))
        }
        return Array(scored.sorted { $0.1 > $1.1 }.prefix(220).map { $0.0 }).shuffled()
    }

    /// Screensaver: a dense wall of DESIGNED 2:3 poster art (hasDesignedArtwork — professional
    /// posters + generated frame covers), NOT the generic archive thumbnail. Broadened from the
    /// 3-source "pro only" filter so the wall stays full even after dead omdb posters are demoted
    /// to archive thumbnails (the poster-liveness gate) — otherwise the grid showed empty tiles.
    static func screensaverPool(_ store: AppStore) -> [Catalog.Item] {
        let mixes: [[Catalog.Item]] = [
            store.browse(contentType: "feature-film", sort: .popular, limit: 500),
            store.browse(contentType: "animation", sort: .popular, limit: 200),
            store.browse(contentType: "silent-film", sort: .popular, limit: 150),
            store.browse(contentType: "documentary", sort: .popular, limit: 120),
            store.seriesCards(),
        ]
        var seen = Set<String>()
        var out: [Catalog.Item] = []
        for mix in mixes {
            for it in mix where it.posterURLParsed != nil && it.hasDesignedArtwork {
                if seen.insert(it.archiveID).inserted { out.append(it) }
            }
        }
        return out.shuffled()
    }
}
#endif
