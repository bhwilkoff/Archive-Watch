#if os(iOS)
import AVFoundation
import SwiftUI

// Watch Together Studio, hosted — iOS-DESIGN §8.8.
//
// This is the player, with the Studio's affordances over it. It is NOT a
// second player surface (§8.2) and NOT a new §3 shape: `PlayerView` builds and
// owns the transport exactly as it does for ordinary playback, and the engine
// only adds OUTPUTS to the item it already has — a video output for frames and
// an audio tap for sound.
//
// What this container owns is the part that is genuinely the Studio's: the
// engine's lifecycle, the host's controls, and the health the host is
// responsible for.
struct StudioPlayerContainer: View {
    let item: Catalog.Item
    let request: GoLiveRequest
    let onExit: () -> Void

    @Environment(AppStore.self) private var store

    @State private var engine: StudioEngine?
    @State private var health = StudioHealth()
    @State private var filmFPS = 0
    @State private var showControls = false
    @State private var startError: String?

    // Controls, bound into the sheet.
    @State private var layout: StudioLayout
    @State private var filmGain = 1.0
    @State private var micGain = 1.0
    @State private var filmMuted = false
    @State private var micMuted = false
    @State private var card: StudioOverlay.Card?
    @State private var showLowerThird = true

    init(item: Catalog.Item, request: GoLiveRequest, onExit: @escaping () -> Void) {
        self.item = item
        self.request = request
        self.onExit = onExit
        _layout = State(initialValue: request.layout)
    }

    // Split deliberately: one chain of this many modifiers defeated the
    // SwiftUI type-checker outright ("unable to type-check this expression in
    // reasonable time"). Sub-expressions are not a style choice here.
    var body: some View {
        player
            .overlay(alignment: .topLeading) {
                StudioHealthCapsule(health: health, filmFramesPerSecond: filmFPS) {
                    showControls = true
                }
            }
            .sheet(isPresented: $showControls) { controlsSheet }
            .alert("Could not go live", isPresented: .constant(startError != nil)) {
                Button("OK") { startError = nil; Task { await end() } }
            } message: {
                Text(startError ?? "")
            }
            .task { await pollHealth() }
            .modifier(StudioBindings(
                layout: $layout, filmGain: $filmGain, micGain: $micGain,
                filmMuted: $filmMuted, micMuted: $micMuted,
                card: $card, showLowerThird: $showLowerThird,
                apply: { await applyControls() }))
    }

    private var player: some View {
        PlayerView(item: item, autoplayIn: nil, onUnplayable: { msg in
            startError = msg
        }, captionChoice: nil, onPlayerReady: { p in
            Task { await attach(player: p) }
        })
        .ignoresSafeArea()
    }

    private var controlsSheet: some View {
        StudioControlsSheet(
            layout: $layout, filmGain: $filmGain, micGain: $micGain,
            filmMuted: $filmMuted, micMuted: $micMuted,
            card: $card, showLowerThird: $showLowerThird,
            audio: health.audio, health: health, filmFramesPerSecond: filmFPS,
            onEnd: { Task { await end() } })
    }

    /// One place that pushes every control into the engine, so the view has
    /// one `onChange` family instead of seven.
    private func applyControls() async {
        guard let e = engine else { return }
        await e.setLayout(layout)
        await e.setAudio(filmGain: Float(filmGain), micGain: Float(micGain),
                         filmMuted: filmMuted, micMuted: micMuted)
        await pushOverlay()
    }

    // MARK: Lifecycle

    private func attach(player: AVPlayer) async {
        // Re-entrant by design: a Decision-077 copy fallback rebuilds the
        // player, and the engine must follow it to the new item.
        let e = engine ?? StudioEngine()
        engine = e
        await e.attachFilm(player: player)
        await e.setLayout(layout)
        await pushOverlay()
        guard await !e.health.isRunning else { return }
        do {
            try await e.start(destination: destination)
        } catch {
            startError = "\(error)"
        }
    }

    /// The destination. Only the custom path is ever assembled from typed
    /// text; a platform key comes from that platform's API (§4) and is not
    /// yet wired, so those paths encode-and-discard rather than pretending.
    private var destination: URL? {
        guard request.platform == .custom,
              let server = request.customServer,
              let key = request.customKey, !key.isEmpty,
              var c = URLComponents(url: server, resolvingAgainstBaseURL: false)
        else { return nil }
        c.path = (c.path.hasSuffix("/") ? c.path : c.path + "/") + key
        return c.url
    }

    private func pushOverlay() async {
        var o = StudioOverlay()
        o.title = item.title
        o.subtitle = [item.year.map(String.init), item.director]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        if item.rightsBucket == "safe_pd_age", let y = item.year {
            o.provenance = "Public domain — published \(y), before 1930"
        }
        o.showLowerThird = showLowerThird
        o.card = card
        await engine?.setOverlay(o)
    }

    /// One second, the same cadence the capsule reads at. The film counter is
    /// a DELTA, because the absolute total says nothing about whether frames
    /// are arriving right now — which is the whole point of it (§9).
    private func pollHealth() async {
        var lastFilmFrames = 0
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let e = engine else { continue }
            await e.refreshHealth()
            let h = await e.health
            filmFPS = max(0, h.filmFramesPulled - lastFilmFrames)
            lastFilmFrames = h.filmFramesPulled
            health = h
        }
    }

    private func end() async {
        await engine?.stop()
        engine = nil
        onExit()
    }
}

/// The Studio's control bindings, as one modifier. Seven `onChange`s inline
/// is what broke the type-checker; it is also seven places to forget one.
private struct StudioBindings: ViewModifier {
    @Binding var layout: StudioLayout
    @Binding var filmGain: Double
    @Binding var micGain: Double
    @Binding var filmMuted: Bool
    @Binding var micMuted: Bool
    @Binding var card: StudioOverlay.Card?
    @Binding var showLowerThird: Bool
    let apply: () async -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: layout) { _, _ in Task { await apply() } }
            .onChange(of: filmGain) { _, _ in Task { await apply() } }
            .onChange(of: micGain) { _, _ in Task { await apply() } }
            .onChange(of: filmMuted) { _, _ in Task { await apply() } }
            .onChange(of: micMuted) { _, _ in Task { await apply() } }
            .onChange(of: card) { _, _ in Task { await apply() } }
            .onChange(of: showLowerThird) { _, _ in Task { await apply() } }
    }
}
#endif
