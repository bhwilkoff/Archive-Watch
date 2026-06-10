#if os(tvOS)
import SwiftUI

// Top-level landing pages for the two "press-start" immersive modes (Party Play,
// Screensaver), promoted from the old Home "Ways to Watch" shelf to their own
// sidebar tabs. Each is a page: a title, a description, a big Start, and a live
// preview of what it'll show.

private struct ModeLineupBox: Identifiable { let id = UUID(); let items: [Catalog.Item] }

// MARK: - Party Play

struct PartyView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var playing: ModeLineupBox?
    @State private var preview: [Catalog.Item] = []
    @FocusState private var startFocused: Bool

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 36) {
                ModeHeader(
                    title: "Party Play",
                    subtitle: "Nonstop, muted color visuals for the background of any gathering.",
                    accent: Color(hex: "#FF4D8D") ?? .pink)

                Button { playing = ModeLineupBox(items: store.partyLineup()) } label: {
                    Label("Start Party Play", systemImage: "sparkles.tv.fill")
                        .font(.title2.weight(.bold))
                        .padding(.horizontal, 44).padding(.vertical, 22)
                }
                .buttonStyle(.card)
                .focused($startFocused)
                .padding(.horizontal, 80)

                if !preview.isEmpty {
                    // Party Play: selecting a title opens its full Detail page.
                    ModePreviewRow(title: "What's in the mix", items: preview) { router.push($0) }
                }
            }
            .padding(.vertical, 56)
        }
        .background(Color.black.ignoresSafeArea())
        .task(id: store.dbGeneration) {
            loadPreview()
            try? await Task.sleep(for: .milliseconds(120))
            startFocused = true
        }
        // Reshuffle the preview every time the tab is shown, so it's not the same
        // titles each visit (partyLineup() is shuffled per call).
        .onAppear { if store.isReady { loadPreview() } }
        .fullScreenCover(item: $playing) { box in
            if let screen = PlayerScreen(lineup: box.items, startMuted: true) { screen }
        }
    }

    private func loadPreview() { preview = Array(store.partyLineup().prefix(18)) }
}

// MARK: - Screensaver

struct ScreensaverHomeView: View {
    @Environment(AppStore.self) private var store
    @State private var showSaver = false
    @State private var zoom: Catalog.Item?
    @State private var preview: [Catalog.Item] = []
    @FocusState private var startFocused: Bool

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 36) {
                ModeHeader(
                    title: "Screensaver",
                    subtitle: "A living wall of classic movie posters. Also appears on its own after a few idle minutes (Settings).",
                    accent: Color(hex: "#0047FF") ?? .blue)

                Button { showSaver = true } label: {
                    Label("Start Screensaver", systemImage: "photo.stack.fill")
                        .font(.title2.weight(.bold))
                        .padding(.horizontal, 44).padding(.vertical, 22)
                }
                .buttonStyle(.card)
                .focused($startFocused)
                .padding(.horizontal, 80)

                if !preview.isEmpty {
                    // Screensaver: selecting a poster zooms it in for a closer look.
                    ModePreviewRow(title: "A taste", items: preview) { zoom = $0 }
                }
            }
            .padding(.vertical, 56)
        }
        .background(Color.black.ignoresSafeArea())
        .fullScreenCover(item: $zoom) { PosterZoomView(item: $0) }
        .task(id: store.dbGeneration) {
            loadPreview()
            try? await Task.sleep(for: .milliseconds(120))
            startFocused = true
        }
        // Reshuffle the preview on each visit so it varies.
        .onAppear { if store.isReady { loadPreview() } }
        .fullScreenCover(isPresented: $showSaver) { ScreensaverView() }
    }

    /// A fresh random sample of professional 2:3 posters (same pool the wall uses).
    private func loadPreview() {
        preview = store.dbBrowse(sort: .popular, limit: 400)
            .filter { ["tmdb", "omdb", "fanart"].contains($0.artworkSource)
                      && $0.posterURLParsed != nil && $0.isSilentFilm != true }
            .shuffled().prefix(18).map { $0 }
    }
}

// MARK: - Shared bits

private struct ModeHeader: View {
    let title: String
    let subtitle: String
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 54, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: 1100, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 80)
        .overlay(alignment: .bottomLeading) {
            Capsule().fill(accent).frame(width: 90, height: 5).padding(.leading, 80)
                .offset(y: 12)
        }
    }
}

private struct ModePreviewRow: View {
    let title: String
    let items: [Catalog.Item]
    let onSelect: (Catalog.Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 80)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(items) { item in
                        Button { onSelect(item) } label: {
                            RemoteImage(url: item.posterURLParsed,
                                        targetSize: CGSize(width: 300, height: 450),
                                        contentMode: .fill,
                                        placeholder: Color(white: 0.1))
                                .frame(width: 160, height: 240)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.card)   // focusable + scales on focus = navigable
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 10)
            }
            .scrollClipDisabled()   // don't clip the focus scale
        }
    }
}

/// Full-screen, high-resolution view of a single poster (#zoom). Menu / select exits.
private struct PosterZoomView: View {
    let item: Catalog.Item
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 22) {
                RemoteImage(url: item.posterURLParsed,
                            targetSize: CGSize(width: 1000, height: 1500),
                            contentMode: .fit,
                            placeholder: Color(white: 0.1))
                    .frame(maxHeight: 820)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                VStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if let y = item.year {
                        Text(verbatim: String(y))
                            .font(.title3).foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .padding(60)
            // Focusable backstop so a remote press lands + exits (tvOS needs a target).
            Button { dismiss() } label: { Color.clear }
                .buttonStyle(.borderless)
                .focused($focused)
        }
        .onExitCommand { dismiss() }
        .onAppear { focused = true }
    }
}

#endif
