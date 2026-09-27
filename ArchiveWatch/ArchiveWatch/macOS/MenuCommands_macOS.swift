#if os(macOS)
import SwiftUI

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
}
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
            ForEach(Array(Self.numbered.enumerated()), id: \.element) { index, section in
                Button(section.title) { go(section) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .disabled(browseIsKey != true)
            }
            Button("Surprise") { go(.surprise) }
                .disabled(browseIsKey != true)
            Divider()
            Button("Search") {
                go(.search)
                router.searchFocusRequest += 1
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(browseIsKey != true)
            Button("Back") { router.path.removeLast() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(browseIsKey != true || router.path.isEmpty)
            Divider()
            Button("Surprise Me") { router.surprise(store) }
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
#endif
