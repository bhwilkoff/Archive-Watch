import SwiftUI
import Combine

// #14 cover-art screensaver (tvOS-DESIGN §9.4). An iTunes-style animated cover
// wall over the catalog's poster art — a grid of tiles that periodically flip to
// a new title. Adapted (lean) from BOBA-Playbook's Showcase
// (CollectionShowcaseView.swift / the lingkuma AlbumArtwork pattern): same idea —
// pick a few random tiles each cycle and animate them — without porting its 2.9k
// lines. Launchable ambient view; any remote press exits. A true idle-trigger
// (system screensaver) is harder on tvOS -> #14b.
struct ScreensaverView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var pool: [Catalog.Item] = []
    @State private var slots: [Catalog.Item] = []
    @State private var flips: [Bool] = []        // per-slot flip state for the 3D animation
    @FocusState private var exitFocused: Bool

    private let columns = 6
    private let rows = 4
    private var slotCount: Int { columns * rows }
    private let tick = Timer.publish(every: 1.1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 18
            let w = (geo.size.width - spacing * CGFloat(columns + 1)) / CGFloat(columns)
            let h = (geo.size.height - spacing * CGFloat(rows + 1)) / CGFloat(rows)
            let grid = Array(repeating: GridItem(.fixed(w), spacing: spacing), count: columns)

            LazyVGrid(columns: grid, spacing: spacing) {
                ForEach(slots.indices, id: \.self) { i in
                    SaverTile(item: slots[i], flipped: flips.indices.contains(i) ? flips[i] : false)
                        .frame(width: w, height: h)
                }
            }
            .padding(spacing)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black.ignoresSafeArea())
        // Invisible focusable backstop so a remote press has somewhere to land and
        // exits the saver (tvOS focus must have a target).
        .overlay {
            Button { dismiss() } label: { Color.clear }
                .buttonStyle(.borderless)       // exit-only backstop (never .plain on tvOS)
                .focused($exitFocused)
        }
        .onExitCommand { dismiss() }
        .onAppear { start() }
        .onReceive(tick) { _ in advance() }
    }

    private func start() {
        pool = store.dbBrowse(sort: .popular, limit: 500)
            .filter { $0.posterURLParsed != nil && $0.hasDesignedArtwork }
            .shuffled()
        guard pool.count >= slotCount else { return }
        slots = Array(pool.prefix(slotCount))
        flips = Array(repeating: false, count: slotCount)
        exitFocused = true
    }

    private func advance() {
        guard pool.count > slotCount else { return }
        // Flip 2-3 random tiles to a fresh poster each cycle.
        for _ in 0..<Int.random(in: 2...3) {
            let i = Int.random(in: 0..<slots.count)
            let next = pool.randomElement()!
            withAnimation(.easeInOut(duration: 0.6)) {
                slots[i] = next
                if flips.indices.contains(i) { flips[i].toggle() }
            }
        }
    }
}

private struct SaverTile: View {
    let item: Catalog.Item
    let flipped: Bool

    var body: some View {
        RemoteImage(url: item.posterURLParsed,
                    targetSize: CGSize(width: 360, height: 540),
                    blurredBackdrop: true)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .id(item.archiveID)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
            .rotation3DEffect(.degrees(flipped ? 360 : 0), axis: (x: 0, y: 1, z: 0))
            .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
    }
}
