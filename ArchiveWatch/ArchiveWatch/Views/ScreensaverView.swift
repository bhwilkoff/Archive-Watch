import SwiftUI
import Combine

// #14 / #14b cover-art screensaver (tvOS-DESIGN §9.4). An iTunes-style cover wall:
// a full-bleed grid of the catalog's poster art that periodically cross-dissolves
// random tiles to fresh titles. Launchable from Surprise/Home and auto-triggered
// when idle (RootView). Any remote press exits.
//
// Design notes (this iteration):
//  - tiles are EXACT 2:3 cells so every poster shows in FULL — no cropping, no
//    overlap (the old fixed w/h cells didn't match poster aspect and the
//    rotation3D + scale transition let neighbors bleed into each other).
//  - the pool is deliberately DIVERSE + colorful: a mix of categories and eras,
//    designed artwork only, silent B&W de-emphasized — so the wall reads as a
//    vibrant mosaic rather than rows of the same popular films.
struct ScreensaverView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var pool: [Catalog.Item] = []
    @State private var slots: [Catalog.Item] = []
    @FocusState private var exitFocused: Bool

    private let spacing: CGFloat = 16
    private let targetWidth: CGFloat = 220   // ~2:3 poster width; grid fits to it
    private let tick = Timer.publish(every: 0.9, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let cols = max(5, Int((geo.size.width + spacing) / (targetWidth + spacing)))
            let w = (geo.size.width - spacing * CGFloat(cols + 1)) / CGFloat(cols)
            let h = w * 1.5                                   // exact 2:3 -> full poster, no crop
            let rows = max(3, Int((geo.size.height + spacing) / (h + spacing)))
            let count = cols * rows
            let grid = Array(repeating: GridItem(.fixed(w), spacing: spacing), count: cols)

            LazyVGrid(columns: grid, spacing: spacing) {
                ForEach(0..<count, id: \.self) { i in
                    if i < slots.count {
                        SaverTile(item: slots[i], width: w, height: h)
                    } else {
                        Color.white.opacity(0.04)
                            .frame(width: w, height: h)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(spacing)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .onAppear { start(count: count) }
            .onChange(of: count) { _, n in start(count: n) }
        }
        .background(Color.black.ignoresSafeArea())
        // Invisible focusable backstop so a remote press lands + exits (tvOS focus
        // needs a target). Never .plain on tvOS.
        .overlay {
            Button { dismiss() } label: { Color.clear }
                .buttonStyle(.borderless)
                .focused($exitFocused)
        }
        .onExitCommand { dismiss() }
        .onAppear { exitFocused = true }
        .onReceive(tick) { _ in advance() }
    }

    /// A wide, varied, colorful pool: several categories + eras, designed art only,
    /// silent B&W dropped so the wall stays vibrant. Deduped + shuffled.
    private func buildPool() -> [Catalog.Item] {
        let mixes: [[Catalog.Item]] = [
            store.dbBrowse(contentType: "feature-film", sort: .popular, limit: 250),
            store.dbBrowse(contentType: "animation",    sort: .popular, limit: 200),
            store.dbBrowse(contentType: "tv-special",   sort: .popular, limit: 120),
            store.dbBrowse(contentType: "documentary",  sort: .popular, limit: 80),
            store.dbBrowse(sort: .newest, limit: 200),     // a different slice for variety
            store.dbBrowse(sort: .popular, limit: 300),
        ]
        var seen = Set<String>()
        var out: [Catalog.Item] = []
        for mix in mixes {
            for it in mix where it.posterURLParsed != nil && it.hasDesignedArtwork {
                if it.isSilentFilm == true { continue }    // keep the wall colorful
                if seen.insert(it.archiveID).inserted { out.append(it) }
            }
        }
        return out.shuffled()
    }

    private func start(count: Int) {
        if pool.isEmpty { pool = buildPool() }
        guard pool.count >= count, count > 0 else { return }
        slots = Array(pool.shuffled().prefix(count))
        exitFocused = true
    }

    private func advance() {
        guard pool.count > slots.count, !slots.isEmpty else { return }
        // Cross-dissolve a few random tiles each tick to fresh, non-visible posters.
        let onScreen = Set(slots.map(\.archiveID))
        for _ in 0..<Int.random(in: 2...4) {
            guard let next = pool.first(where: { !onScreen.contains($0.archiveID) })
                    ?? pool.randomElement() else { continue }
            let i = Int.random(in: 0..<slots.count)
            withAnimation(.easeInOut(duration: 0.8)) { slots[i] = next }
        }
        // Re-shuffle the pool occasionally so "next unseen" stays varied.
        if Int.random(in: 0..<12) == 0 { pool.shuffle() }
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
            .id(item.archiveID)
            .transition(.opacity)                          // clean cross-dissolve, no overlap
    }
}
