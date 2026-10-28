#if os(macOS)
import SwiftUI
import AppKit

// Mac-native navigation model (docs/macOS-DESIGN.md §7): a sidebar SECTION selection +
// one NavigationPath for drill-in. NOT the iOS per-tab-stack Router — the Mac uses a
// single split-view detail column. A PersonRoute mirrors the iOS person-filter routing.

struct PersonRoute: Hashable { let name: String }
struct CollectionRoute: Hashable { let id: String; let title: String }

@MainActor
@Observable
final class AppRouter {
    /// Rule B13g: the menu command cannot present a sheet itself, so it flips
    /// this and the window root presents. Nothing else reads it.
    var showGoLive = false

    enum Section: String, CaseIterable, Identifiable, Hashable {
        case home, movies, tv, channels, collections, surprise, search, library, watchTogether, create
        var id: String { rawValue }
        var title: String {
            switch self {
            case .home: "Home"; case .movies: "Movies"; case .tv: "TV"
            case .channels: "Channels"
            case .collections: "Collections"; case .surprise: "Surprise"
            case .search: "Search"; case .library: "Library"
            case .watchTogether: "Watch Together"
            case .create: "Creation Studio"
            }
        }
        var systemImage: String {
            switch self {
            case .home: "house"; case .movies: "film"; case .tv: "tv"
            case .channels: "dot.radiowaves.left.and.right"
            case .collections: "square.stack"; case .surprise: "sparkles"
            case .search: "magnifyingglass"; case .library: "books.vertical"
            case .watchTogether: "person.2.wave.2"
            case .create: "movieclapper"
            }
        }
    }

    var section: Section = .home
    /// Go ▸ Search (⌘F) bumps this; Search focuses its field on each change.
    var searchFocusRequest = 0
    var path = NavigationPath()
    var nowPlaying: Catalog.Item?          // drives the item player sheet
    var playStart: TimeInterval?           // Scenes (§B7c): start here instead of resuming
    var nowPlayingEpisode: EpisodeContext? // drives the episode player sheet
    var nowPlayingChannel: ChannelTuneIn?  // a tuned channel, the window root (§B8b)
    var screensaverActive = false          // a full-window, full-screen poster-wall overlay

    // A tv-series card drills into the season/episode list, not the movie Detail.
    func openDetail(_ item: Catalog.Item) {
        if item.contentType == "tv-series" { path.append(SeriesRef(card: item)) }
        else { path.append(item) }
    }
    func openPerson(_ name: String) { path.append(PersonRoute(name: name)) }
    func openCollection(_ id: String, _ title: String) { path.append(CollectionRoute(id: id, title: title)) }
    func play(_ item: Catalog.Item, at start: TimeInterval? = nil) {
        // ONE FILM, ONE PLAYER (§D7). While the Studio window holds a film, a
        // film played here would tear its surface down as a "projection" —
        // during a show, the audience's picture.
        let show = StudioMacShow.shared
        if let held = show.film,
           Self.studioWindow != nil || nowPlaying?.archiveID == held.archiveID {
            if held.archiveID == item.archiveID {
                // The Studio's own film, asked for in a window of its own (the
                // Studio's "Open in a separate window"); never mid-show.
                guard !StudioSession.shared.isLive else { Self.refuseDuringShow(); return }
            } else {
                guard !StudioSession.shared.isLive else { Self.refuseDuringShow(); return }
                show.take(item, from: self)
                Self.bringStudioForward()
                return
            }
        }
        playStart = start
        nowPlaying = item
    }

    private static var studioWindow: NSWindow? {
        NSApp.windows.first {
            $0.isVisible && ($0.identifier?.rawValue.hasPrefix(StudioWindowID.studio) ?? false)
        }
    }

    private static func bringStudioForward() { studioWindow?.makeKeyAndOrderFront(nil) }

    private static func refuseDuringShow() {
        let alert = NSAlert()
        alert.messageText = "A show is running in the Studio"
        alert.informativeText = "End the broadcast before playing another film."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    func playEpisode(_ episode: Episode, in series: Series?) {
        guard let series else { return }
        nowPlayingEpisode = EpisodeContext(series: series, episode: episode)
    }

    func surprise(_ store: AppStore) {
        if let item = store.db?.randomFeatureFilm() { play(item) }
    }
}
#endif
