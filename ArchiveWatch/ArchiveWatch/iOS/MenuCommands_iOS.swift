#if os(iOS)
import SwiftUI
import UIKit

// The iPad's menu bar (docs/IPAD-DESIGN.md §8). On iPadOS 26 `.commands` builds
// a real menu bar, the same code path as the Mac's; the items and their words
// follow macOS/MenuCommands_macOS.swift. Everything a window can act on is
// published by that window (`focusedSceneValue`), so a command always acts on
// the window in front and is dimmed, never hidden, when nothing answers it.

/// The film whose page is in front, and what can be done with it.
struct FilmMenuActions {
    let title: String
    let isFavorite: Bool
    let isWatched: Bool
    let canPlay: Bool
    let play: () -> Void
    let toggleFavorite: () -> Void
    let addToPlaylist: () -> Void
    let toggleWatched: () -> Void
    let openInNewWindow: (() -> Void)?
    let pageURL: URL
    let archiveURL: URL
    let reportURL: URL?
}

struct FilmMenuActionsKey: FocusedValueKey { typealias Value = FilmMenuActions }
struct SceneRouterKey: FocusedValueKey { typealias Value = Router }

extension FocusedValues {
    var filmMenuActions: FilmMenuActions? {
        get { self[FilmMenuActionsKey.self] }
        set { self[FilmMenuActionsKey.self] = newValue }
    }
    /// The Router of the window in front (IPAD-DESIGN §9.2: one per window).
    var sceneRouter: Router? {
        get { self[SceneRouterKey.self] }
        set { self[SceneRouterKey.self] = newValue }
    }
}

/// Go: the sidebar's tabs on ⌘1–⌘5, Search ⌘F, Back ⌘[, Surprise Me.
struct GoCommands_iOS: Commands {
    @FocusedValue(\.sceneRouter) private var router

    var body: some Commands {
        CommandMenu("Go") {
            ForEach(Array(Router.Tab.allCases.enumerated()), id: \.element) { n, tab in
                Button(tab.title) { router?.tab = tab }
                    .keyboardShortcut(KeyEquivalent(Character(String(n + 1))), modifiers: .command)
                    .disabled(router == nil)
            }
            Divider()
            Button("Search") { router?.tab = .search }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(router == nil)
            Button("Back") { router?.popActiveTab() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(router == nil || router?.activeTabAtRoot == true)
            Divider()
            Button("Surprise Me") {
                guard let router else { return }
                router.tab = .home
                router.push(SurpriseRoute())
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(router == nil)
        }
    }
}

/// Film: every action on the page of the film in front.
struct FilmCommands_iOS: Commands {
    @FocusedValue(\.filmMenuActions) private var film
    @Environment(\.openURL) private var openURL

    var body: some Commands {
        CommandMenu("Film") {
            Button("Play") { film?.play() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(film?.canPlay != true)
            Divider()
            Button(film?.isFavorite == true ? "Remove from Favorites" : "Add to Favorites") {
                film?.toggleFavorite()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(film == nil)
            Button("Add to Playlist…") { film?.addToPlaylist() }
                .disabled(film == nil)
            Button(film?.isWatched == true ? "Mark as Not Watched" : "Mark as Watched") {
                film?.toggleWatched()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(film == nil)
            Divider()
            Button("Open in New Window") { film?.openInNewWindow?() }
                .disabled(film?.openInNewWindow == nil)
            Divider()
            Button("Copy Link") {
                if let url = film?.pageURL { UIPasteboard.general.url = url }
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

/// Help: the same links as the Mac's Help menu.
struct HelpCommands_iOS: Commands {
    @Environment(\.openURL) private var openURL
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Archive Watch Help") { open("https://archivewatch.org/support.html") }
                .keyboardShortcut("?", modifiers: .command)
            Divider()
            Button("How Titles Are Vetted") { open("https://archivewatch.org/vetting/") }
            Button("Privacy Policy") { open("https://archivewatch.org/privacy.html") }
            Button("Terms of Use") { open("https://archivewatch.org/terms.html") }
        }
    }
    private func open(_ s: String) { if let u = URL(string: s) { openURL(u) } }
}

#endif
