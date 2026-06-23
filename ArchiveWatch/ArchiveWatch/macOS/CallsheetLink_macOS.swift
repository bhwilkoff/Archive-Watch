#if os(macOS)
import AppKit

// "Open in Callsheet" — deep-link a title into Callsheet (callsheetapp.com), the
// cast/crew companion app, via its public URL scheme. The macOS twin of
// CallsheetLink_iOS (Decision 038, amended to cover all Apple platforms per owner):
// Callsheet ships a Mac app, so this lives in the macOS target too. We detect
// installation with NSWorkspace.urlForApplication(toOpen:) — the AppKit analog of
// UIApplication.canOpenURL, which needs NO Info.plist queries-schemes entry on macOS.
enum Callsheet {
    static let appStoreURL =
        URL(string: "https://apps.apple.com/us/app/callsheet-find-cast-crew/id1672356376")!

    /// Is a handler registered for callsheet://? Drives the menu label + routing.
    static var isInstalled: Bool {
        guard let probe = URL(string: "callsheet://") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
    }

    static var actionTitle: String { isInstalled ? "Open in Callsheet" : "Get Callsheet" }
    static var actionIcon: String { isInstalled ? "person.text.rectangle" : "arrow.down.app" }

    // Films + TV have cast/crew in Callsheet; newsreel/ephemeral/home-movie/
    // commercial don't, so the action is hidden for those.
    private static let supportedTypes: Set<String> = [
        "feature-film", "silent-film", "short-film", "animation", "documentary",
        "tv-series", "tv-special",
    ]

    static func supports(_ item: Catalog.Item) -> Bool { supportedTypes.contains(item.contentType) }

    private static func isTV(_ item: Catalog.Item) -> Bool {
        item.contentType == "tv-series" || item.contentType == "tv-special"
    }

    /// Deep link for a title: by TMDB id when we have one (callsheet://open/...),
    /// else a title search (Callsheet ignores the media type on search, so it
    /// resolves any title we can name).
    static func url(for item: Catalog.Item) -> URL? {
        let media = isTV(item) ? "tv" : "movie"
        if let tmdb = item.tmdbID { return URL(string: "callsheet://open/\(media)/\(tmdb)") }
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              let q = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "callsheet://search/\(media)?q=\(q)")
    }

    /// Episode deep link — Callsheet's search takes season/episode.
    static func episodeURL(seriesTitle: String, season: Int?, episode: Int?) -> URL? {
        let t = seriesTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty,
              let q = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        var s = "callsheet://search/tv?q=\(q)"
        if let season { s += "&season=\(season)" }
        if let episode { s += "&episode=\(episode)" }
        return URL(string: s)
    }

    /// Open the title in Callsheet when installed; otherwise the App Store page.
    static func open(_ url: URL?) {
        guard isInstalled, let url else { NSWorkspace.shared.open(appStoreURL); return }
        NSWorkspace.shared.open(url)
    }
}
#endif
