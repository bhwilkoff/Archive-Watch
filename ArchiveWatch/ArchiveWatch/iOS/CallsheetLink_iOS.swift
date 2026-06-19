#if os(iOS)
import UIKit

// "Open in Callsheet" — deep-link a title into Callsheet (callsheetapp.com), the
// cast/crew companion app, via its public URL scheme. If Callsheet isn't
// installed, UIApplication.open's completion fires `false` and we send the user
// to the App Store instead (the native "get the app" fallback). Opening a scheme
// needs no Info.plist entry (only canOpenURL would). Callsheet is iPhone/iPad
// only, so this lives in the iOS target.
enum Callsheet {
    static let appStoreURL =
        URL(string: "https://apps.apple.com/us/app/callsheet-find-cast-crew/id1672356376")!

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

    /// Open the URL in Callsheet, falling back to the App Store if it's not
    /// installed. Always lands somewhere useful.
    @MainActor static func open(_ url: URL?) {
        guard let url else { UIApplication.shared.open(appStoreURL); return }
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened { UIApplication.shared.open(appStoreURL) }
        }
    }
}
#endif
