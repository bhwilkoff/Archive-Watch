import SwiftUI
import Combine

// #14 / #14b cover-art screensaver (tvOS-DESIGN §9.4). A full-bleed grid of the
// catalog's poster art that periodically cross-dissolves random tiles to fresh
// titles. Launchable from Surprise/Home and auto-triggered when idle (RootView).
// Any remote press exits.
//
// Why it used to show dark gaps: RemoteImage clears to its placeholder while a
// poster loads over the network, and every swap tore the tile down and re-loaded
// — so freshly-swapped (or broken-URL) posters sat dark for seconds. Fix: PREFETCH
// the pool's images and only ever place posters that have ALREADY loaded
// (`ready`), so a displayed cell is never empty. Broken URLs are filtered out by
// the prefetch.
struct ScreensaverView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var pool: [Catalog.Item] = []
    @State private var ready: [Catalog.Item] = []   // prefetched + decodable only
    @State private var slots: [Catalog.Item] = []
    @State private var count = 0
    @State private var warming = false
    @FocusState private var exitFocused: Bool

    private let spacing: CGFloat = 16
    private let targetWidth: CGFloat = 220
    private let tick = Timer.publish(every: 2.2, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let cols = max(5, Int((geo.size.width + spacing) / (targetWidth + spacing)))
            let w = (geo.size.width - spacing * CGFloat(cols + 1)) / CGFloat(cols)
            let h = w * 1.5
            let rows = max(3, Int((geo.size.height + spacing) / (h + spacing)))
            let n = cols * rows
            let grid = Array(repeating: GridItem(.fixed(w), spacing: spacing), count: cols)

            LazyVGrid(columns: grid, spacing: spacing) {
                ForEach(0..<max(n, slots.count), id: \.self) { i in
                    if i < slots.count {
                        SaverTile(item: slots[i], width: w, height: h)
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.04))
                            .frame(width: w, height: h)
                    }
                }
            }
            .padding(spacing)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .onAppear {
                count = n
                if !warming { warming = true; Task { await warm() } }
                fillIfReady()
            }
            .onChange(of: n) { _, newN in count = newN; fillIfReady() }
        }
        .vhsEffect(enabled: store.screensaverVHS)
        .background(Color.black.ignoresSafeArea())
        .overlay {
            Button { dismiss() } label: { Color.clear }
                .buttonStyle(.borderless)
                .focused($exitFocused)
        }
        .onExitCommand { dismiss() }
        .onAppear { exitFocused = true }
        .onReceive(tick) { _ in advance() }
    }

    // ONLY professional, 2:3-formatted movie posters belong on the wall — never
    // our frame-captured covers (artworkSource "generated") or archive thumbnails.
    // tmdb / omdb / fanart are the designed one-sheet posters; everything else
    // (generated, archive, tvmaze, commons scans of varying aspect) is excluded.
    private static let professionalPosterSources: Set<String> = ["tmdb", "omdb", "fanart"]

    /// A wide, varied pool of professional movie posters across categories + eras.
    private func buildPool() -> [Catalog.Item] {
        let mixes: [[Catalog.Item]] = [
            store.dbBrowse(contentType: "feature-film", sort: .popular, limit: 400),
            store.dbBrowse(contentType: "animation",    sort: .popular, limit: 200),
            store.dbBrowse(contentType: "tv-special",   sort: .popular, limit: 120),
            store.dbBrowse(sort: .newest, limit: 250),
            store.dbBrowse(sort: .popular, limit: 400),
        ]
        var seen = Set<String>()
        var out: [Catalog.Item] = []
        for mix in mixes {
            for it in mix where it.posterURLParsed != nil {
                guard Self.professionalPosterSources.contains(it.artworkSource) else { continue }
                if it.isSilentFilm == true { continue }
                if seen.insert(it.archiveID).inserted { out.append(it) }
            }
        }
        return out.shuffled()
    }

    /// Prefetch poster images with bounded concurrency; only successes join
    /// `ready` (so broken URLs never become dark cells). Keeps warming the whole
    /// pool in the background so `ready` grows for variety.
    private func warm() async {
        pool = buildPool()
        guard !pool.isEmpty else { return }
        let maxConcurrent = 8
        var idx = 0
        await withTaskGroup(of: Catalog.Item?.self) { group in
            while idx < min(maxConcurrent, pool.count) {
                let it = pool[idx]; idx += 1
                group.addTask { await Self.prefetch(it) }
            }
            for await result in group {
                if let result { ready.append(result); fillIfReady() }
                if idx < pool.count {
                    let it = pool[idx]; idx += 1
                    group.addTask { await Self.prefetch(it) }
                }
            }
        }
    }

    private static func prefetch(_ it: Catalog.Item) async -> Catalog.Item? {
        guard let url = it.posterURLParsed else { return nil }
        do {
            _ = try await ImageLoader.shared.image(
                for: url, targetSize: CGSize(width: 320, height: 480), scale: 2)
            return it
        } catch {
            return nil
        }
    }

    private func fillIfReady() {
        guard slots.isEmpty, count > 0, ready.count >= count else { return }
        slots = Array(ready.shuffled().prefix(count))
        exitFocused = true
    }

    private func advance() {
        guard !slots.isEmpty, ready.count > slots.count else { return }
        let onScreen = Set(slots.map(\.archiveID))
        let candidates = ready.filter { !onScreen.contains($0.archiveID) }
        guard !candidates.isEmpty else { return }
        for _ in 0..<Int.random(in: 1...2) {
            guard let next = candidates.randomElement() else { continue }
            let i = Int.random(in: 0..<slots.count)
            withAnimation(.easeInOut(duration: 1.0)) { slots[i] = next }
        }
    }
}

private struct SaverTile: View {
    let item: Catalog.Item
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RemoteImage(url: item.posterURLParsed,
                    targetSize: CGSize(width: width * 2, height: height * 2),
                    contentMode: .fill,
                    placeholder: Color(white: 0.08))
            .frame(width: width, height: height)          // exact 2:3 -> full poster
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.45), radius: 7, y: 3)
            .transition(.opacity)
            .id(item.archiveID)
    }
}
