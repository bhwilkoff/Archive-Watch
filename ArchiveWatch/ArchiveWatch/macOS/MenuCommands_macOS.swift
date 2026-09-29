#if os(macOS)
import SwiftUI
import AVFoundation

// The menu bar for the browsing window (docs/macOS-DESIGN.md Rule B14).
//
// Owner, 2026-09-27: "make sure that all features that should have menu items
// (macOS specific need), that they are well represented in the menu
// structure." HIG, the menu bar: "Even when commands are available elsewhere
// in your app, it's important to list them in the menu bar." Before this, the
// only custom items were New Project, Surprise Me and the Broadcast menu, so
// the sidebar, Search, Back and every action on a film's page had no menu item
// and no key.
//
// Custom menus sit between View and Window (HIG). A command that belongs to
// one kind of window is enabled only while that window is key, published with
// `focusedSceneValue`, so ⌘1–⌘8 here and the Studio's scene keys (⌘1–⌘9, only
// while the Studio is key) are never both live.

/// True while the browsing window (not a player) is the key window.
struct BrowseWindowIsKeyKey: FocusedValueKey { typealias Value = Bool }

/// The film whose page is in front, and what can be done with it.
struct FilmActions {
    let title: String
    let isFavorite: Bool
    let play: () -> Void
    let toggleFavorite: () -> Void
    let addToPlaylist: () -> Void
    let subtitles: (() -> Void)?
    let openInCreationStudio: (() -> Void)?
    let watchWithFriends: () -> Void
    let watchWithTheWorld: () -> Void
    let pageURL: URL
    let archiveURL: URL
    let reportURL: URL?
    let isWatched: Bool
    let toggleWatched: () -> Void
}

/// The player in front.
struct PlaybackControls { let player: AVPlayer }
struct PlaybackControlsKey: FocusedValueKey { typealias Value = PlaybackControls }

/// An episode player's chevrons (nil ends of the season are nil).
struct EpisodeNavigation {
    let previous: (() -> Void)?
    let next: (() -> Void)?
}
struct EpisodeNavigationKey: FocusedValueKey { typealias Value = EpisodeNavigation }
/// A channel player's surfing (macOS-DESIGN §B8b).
struct ChannelSurfing {
    let previous: () -> Void
    let next: () -> Void
}
struct ChannelSurfingKey: FocusedValueKey { typealias Value = ChannelSurfing }
struct FilmActionsKey: FocusedValueKey { typealias Value = FilmActions }

extension FocusedValues {
    var browseWindowIsKey: Bool? {
        get { self[BrowseWindowIsKeyKey.self] }
        set { self[BrowseWindowIsKeyKey.self] = newValue }
    }
    var filmActions: FilmActions? {
        get { self[FilmActionsKey.self] }
        set { self[FilmActionsKey.self] = newValue }
    }
    var playbackControls: PlaybackControls? {
        get { self[PlaybackControlsKey.self] }
        set { self[PlaybackControlsKey.self] = newValue }
    }
    var episodeNavigation: EpisodeNavigation? {
        get { self[EpisodeNavigationKey.self] }
        set { self[EpisodeNavigationKey.self] = newValue }
    }
    var channelSurfing: ChannelSurfing? {
        get { self[ChannelSurfingKey.self] }
        set { self[ChannelSurfingKey.self] = newValue }
    }
}

/// Go: the sidebar's sections with ⌘1–⌘8, Search ⌘F, Back ⌘[, Surprise Me.
struct GoCommands: Commands {
    let router: AppRouter
    let store: AppStore
    @FocusedValue(\.browseWindowIsKey) private var browseIsKey

    /// The sections that get a number key, in sidebar order. Surprise is a
    /// command below (it plays), and Search has ⌘F.
    private static let numbered: [AppRouter.Section] =
        [.home, .movies, .tv, .channels, .collections, .library, .watchTogether, .create]

    var body: some Commands {
        CommandMenu("Go") {
            // The sidebar's order, so the menu reads as the same list. Surprise
            // takes no number (it is a page of dice), Search has ⌘F.
            ForEach(AppRouter.Section.allCases) { section in
                if section == .search {
                    Button("Search") {
                        go(.search)
                        router.searchFocusRequest += 1
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(browseIsKey != true)
                } else if let n = Self.numbered.firstIndex(of: section) {
                    Button(section.title) { go(section) }
                        .keyboardShortcut(KeyEquivalent(Character(String(n + 1))), modifiers: .command)
                        .disabled(browseIsKey != true)
                } else {
                    Button(section.title) { go(section) }
                        .disabled(browseIsKey != true)
                }
            }
            Divider()
            Button("Back") { router.path.removeLast() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(browseIsKey != true || router.path.isEmpty)
            Divider()
            // Beside the sidebar's "Surprise" (a page), "Surprise Me" read as the
            // same item twice; this one PLAYS, so it says so.
            Button("Play a Surprise Film") { router.surprise(store) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }

    private func go(_ section: AppRouter.Section) {
        router.path = NavigationPath()
        router.section = section
    }
}

/// Film: every action on the page of the film in front.
struct FilmCommands: Commands {
    @FocusedValue(\.filmActions) private var film
    @Environment(\.openURL) private var openURL

    var body: some Commands {
        CommandMenu("Film") {
            Button("Play") { film?.play() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(film == nil)
            Divider()
            Button(film?.isFavorite == true ? "Remove from Favorites" : "Add to Favorites") {
                film?.toggleFavorite()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(film == nil)
            Button("Add to Playlist…") { film?.addToPlaylist() }
                .disabled(film == nil)
            Button("Subtitles…") { film?.subtitles?() }
                .disabled(film?.subtitles == nil)
            Button("Open in Creation Studio") { film?.openInCreationStudio?() }
                .disabled(film?.openInCreationStudio == nil)
            // The Mac had no way to mark a film watched at all (loop, 2026-09-27).
            Button(film?.isWatched == true ? "Mark as Not Watched" : "Mark as Watched") {
                film?.toggleWatched()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(film == nil)
            Divider()
            Menu("Watch Together") {
                Button("With Friends…") { film?.watchWithFriends() }
                Button("With the World…") { film?.watchWithTheWorld() }
            }
            .disabled(film == nil)
            Divider()
            Button("Copy Link") {
                guard let url = film?.pageURL else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(film == nil)
            Button("View on archive.org") { if let u = film?.archiveURL { openURL(u) } }
                .disabled(film == nil)
            Button("Something Wrong with This Film?") { if let u = film?.reportURL { openURL(u) } }
                .disabled(film?.reportURL == nil)
        }
    }
}
/// Controls: the player in front (Rule B14). The HUD does all of this with a
/// pointer; the menu is where a keyboard finds it and where its keys are shown.
struct ControlsCommands: Commands {
    let router: AppRouter
    @FocusedValue(\.playbackControls) private var playback
    @FocusedValue(\.episodeNavigation) private var episodes
    @FocusedValue(\.channelSurfing) private var channels

    private static let speeds: [Double] = [0.5, 1.0, 1.25, 1.5, 2.0]

    var body: some Commands {
        CommandMenu("Controls") {
            Button("Play/Pause") {
                guard let p = playback?.player else { return }
                if p.rate == 0 { p.play() } else { p.pause() }
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(playback == nil)
            Button("Skip Forward 10 Seconds") { skip(10) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(playback == nil)
            Button("Skip Back 10 Seconds") { skip(-10) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(playback == nil)
            Divider()
            Button("Next Episode") { episodes?.next?() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
                .disabled(episodes?.next == nil)
            Button("Previous Episode") { episodes?.previous?() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
                .disabled(episodes?.previous == nil)
            // A modified key here (Rule B14: no bare keys in the menu bar); the
            // channel player itself also takes bare up/down (§B8b).
            Button("Previous Channel") { channels?.previous() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                .disabled(channels == nil)
            Button("Next Channel") { channels?.next() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .shift])
                .disabled(channels == nil)
            Divider()
            Menu("Speed") {
                ForEach(Self.speeds, id: \.self) { s in
                    Button(s == 1 ? "Normal" : (s == s.rounded() ? "\(Int(s))×" : "\(s)×")) {
                        guard let p = playback?.player else { return }
                        p.defaultRate = Float(s)
                        if p.rate != 0 { p.rate = Float(s) }
                    }
                }
            }
            .disabled(playback == nil)
            Button("Volume Up") { volume(+0.1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(playback == nil)
            Button("Volume Down") { volume(-0.1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(playback == nil)
            Button("Mute") { playback?.player.isMuted.toggle() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(playback == nil)
            Divider()
            Button("Close Player") {
                router.nowPlaying = nil
                router.nowPlayingEpisode = nil
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(playback == nil)
        }
    }

    private func skip(_ seconds: Double) {
        guard let p = playback?.player else { return }
        let t = CMTimeAdd(p.currentTime(), CMTime(seconds: seconds, preferredTimescale: 600))
        p.seek(to: CMTimeMaximum(t, .zero), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func volume(_ delta: Float) {
        guard let p = playback?.player else { return }
        p.isMuted = false
        p.volume = min(1, max(0, p.volume + delta))
    }
}
/// Help: where the answers are. "Archive Watch Help" was the system's
/// placeholder with no Help Book behind it (Mac loop, 2026-09-27).
struct HelpCommands: Commands {
    @Environment(\.openURL) private var openURL
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Archive Watch Help") { open("https://archivewatch.org/support.html") }
                .keyboardShortcut("?", modifiers: .command)
            Divider()
            Button("Feeds & Integrations") { open("https://archivewatch.org/#/feeds") }
            Button("How Titles Are Vetted") { open("https://archivewatch.org/vetting/") }
            Button("Privacy Policy") { open("https://archivewatch.org/privacy.html") }
            Button("Terms of Use") { open("https://archivewatch.org/terms.html") }
        }
    }
    private func open(_ s: String) { if let u = URL(string: s) { openURL(u) } }
}
#endif
