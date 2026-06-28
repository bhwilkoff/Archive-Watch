#if os(iOS)
import UIKit

// "Open in Callsheet" — deep-link a title into Callsheet (callsheetapp.com), the
// cast/crew companion app, via its public URL scheme. We detect whether Callsheet
// is installed with `canOpenURL` so the menu reads "Open in Callsheet" (installed)
// or "Get Callsheet" (not), and route accordingly — installed → the deep link,
// not installed → the App Store. canOpenURL("callsheet://") REQUIRES `callsheet`
// in the Info.plist `LSApplicationQueriesSchemes` array (added for this). Callsheet
// is iPhone/iPad only, so this lives in the iOS target.
enum Callsheet {
    static let appStoreURL =
        URL(string: "https://apps.apple.com/us/app/callsheet-find-cast-crew/id1672356376")!

    /// Is Callsheet installed? Drives the menu label + open routing.
    /// Needs `callsheet` in Info.plist LSApplicationQueriesSchemes.
    @MainActor static var isInstalled: Bool {
        guard let probe = URL(string: "callsheet://") else { return false }
        return UIApplication.shared.canOpenURL(probe)
    }

    @MainActor static var actionTitle: String {
        isInstalled ? "Open in Callsheet" : "Get Callsheet"
    }
    @MainActor static var actionIcon: String {
        isInstalled ? "person.text.rectangle" : "arrow.down.app"
    }

    // Films + TV have cast/crew in Callsheet; newsreel/ephemeral/home-movie/
    // commercial don't, so the action is hidden for those.
    private static let supportedTypes: Set<String> = [
        "feature-film", "silent-film", "short-film", "animation", "documentary",
        "tv-series", "tv-special",
    ]

    static func supports(_ item: Catalog.Item) -> Bool {
        supportedTypes.contains(item.contentType)
    }

    private static func isTV(_ item: Catalog.Item) -> Bool {
        item.contentType == "tv-series" || item.contentType == "tv-special"
    }

    /// Deep link for a title: by TMDB id when we have one (callsheet://open/...),
    /// else a title search (callsheet://search/... — Callsheet ignores the media
    /// type on search, so it resolves any title we can name).
    static func url(for item: Catalog.Item) -> URL? {
        let media = isTV(item) ? "tv" : "movie"
        if let tmdb = item.tmdbID {
            return URL(string: "callsheet://open/\(media)/\(tmdb)")
        }
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              let q = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "callsheet://search/\(media)?q=\(q)")
    }

    /// Person deep link (Decision 038, unblocked by Decision 046's cast
    /// tmdbPersonID): open a cast/crew member directly in Callsheet.
    static func personURL(tmdbPersonID: Int) -> URL? {
        URL(string: "callsheet://open/person/\(tmdbPersonID)")
    }

    /// Episode deep link — Callsheet's search takes season/episode, so a TV
    /// episode opens to the right entry by series title + S/E.
    static func episodeURL(seriesTitle: String, season: Int?, episode: Int?) -> URL? {
        let t = seriesTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty,
              let q = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        var s = "callsheet://search/tv?q=\(q)"
        if let season { s += "&season=\(season)" }
        if let episode { s += "&episode=\(episode)" }
        return URL(string: s)
    }

    /// Open the title in Callsheet when installed; otherwise go straight to the
    /// App Store. The completion-handler fallback covers the rare case where
    /// canOpenURL said yes but the specific deep link can't open.
    @MainActor static func open(_ url: URL?) {
        guard isInstalled, let url else { UIApplication.shared.open(appStoreURL); return }
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened { UIApplication.shared.open(appStoreURL) }
        }
    }
}
#endif
