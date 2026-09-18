// Going live: the request a host makes, and the address it resolves to.
//
// These lived inside `GoLiveSheet_iOS.swift`, behind `#if os(iOS)`, and so did
// the only code in the project that turns an OAuth token into a real stream
// key. That is why §9.ccc found tvOS and macOS unable to broadcast at all: not
// a missing capability, a capability declared somewhere no other platform could
// see it. Nothing here is iOS-specific — a request is a platform, a title and a
// privacy choice on any screen.
//
// The SURFACE that collects the request is still per-platform and still needs
// its own binding rule (macOS: §B13g; tvOS: nothing yet — its menu arms the
// Studio and offers no way to choose a platform or title). This file
// deliberately does not invent one.
//
// WHY IT IS ITS OWN FILE, and not the bottom of `StudioPlatforms.swift` where
// it first landed: it reaches `Catalog.Item` and `StudioLayout`, which are
// APP types, and `StudioPlatforms.swift` is compiled standalone by two
// harnesses (§8.2, §8.7) that have no app. Moving these types in broke both
// cases the moment they moved — the same defect class §6.2n named, where a
// harness's file list is a silent second copy of the module's dependency
// graph. A file that the harnesses compile may depend only on Foundation.

import Foundation

// MARK: - The request

struct GoLiveRequest: Sendable, Equatable, Identifiable {
    /// Distinct per request, so re-going-live on the same film presents again.
    let id = UUID()
    let archiveID: String
    let platform: GoLivePlatform
    let title: String
    let category: String
    let privacy: YouTubePrivacy
    let layout: StudioLayout
    let customServer: URL?
    let customKey: String?
}

enum GoLivePlatform: String, CaseIterable, Sendable {
    case youtube, twitch, custom
    var label: String {
        switch self {
        case .youtube: return "YouTube"
        case .twitch: return "Twitch"
        case .custom: return "Custom server"
        }
    }
}

enum YouTubePrivacy: String, CaseIterable, Sendable {
    case `public`, unlisted, `private`
    var label: String {
        switch self {
        case .public: return "Public"
        case .unlisted: return "Unlisted"
        case .private: return "Private"
        }
    }
}

/// Turns a host's request into the address the publisher sends to.
enum StudioGoLive {

    /// Where the program goes.
    ///
    /// A platform key is fetched from that platform's API and used once — it is
    /// never shown, stored or logged (§4). The custom path is the only one
    /// assembled from typed text, and it exists for diagnostics.
    // Internal, not public: `Catalog.Item` is internal, and every caller is
    // in this module. A `public` face here buys nothing and will not compile.
    static func destination(for request: GoLiveRequest,
                            film: Catalog.Item) async throws -> URL? {
        switch request.platform {
        case .custom:
            guard let server = request.customServer,
                  let key = request.customKey, !key.isEmpty,
                  var c = URLComponents(url: server, resolvingAgainstBaseURL: false)
            else { return nil }
            c.path = (c.path.hasSuffix("/") ? c.path : c.path + "/") + key
            return c.url

        case .youtube:
            let token = try await StudioPlatformAuth.token(for: .youtube)
            let creds = try await YouTubeLive(token: token).prepare(
                title: request.title,
                description: description(for: film),
                privacy: request.privacy.rawValue)
            return combine(creds)

        case .twitch:
            let token = try await StudioPlatformAuth.token(for: .twitch)
            guard let clientID = StudioPlatformAuth.clientID(for: .twitch) else {
                throw StudioPlatformError.notConfigured("No Twitch client id in this build.")
            }
            let creds = try await TwitchLive(token: token, clientID: clientID).prepare(
                title: request.title,
                categoryName: request.category.isEmpty ? nil : request.category)
            return combine(creds)
        }
    }

    /// The publisher takes an address and a key separately; this is the one
    /// place they are joined, and the result never leaves this function.
    private static func combine(_ c: StreamCredentials) -> URL? {
        guard var comp = URLComponents(url: c.server, resolvingAgainstBaseURL: false) else { return nil }
        comp.path = (comp.path.hasSuffix("/") ? comp.path : comp.path + "/") + c.key
        return comp.url
    }

    /// What the platform's description field says — the catalog's own record,
    /// plus where the film came from. The audience should be able to find the
    /// film themselves afterwards, which is §2's agency test.
    private static func description(for item: Catalog.Item) -> String {
        var lines = [item.title]
        if let y = item.year { lines.append("Published \(y). In the public domain.") }
        if let d = item.director, !d.isEmpty { lines.append("Directed by \(d).") }
        lines.append("")
        lines.append("Streamed from the Internet Archive with Archive Watch — a free, "
                     + "ad-free cinematheque for public-domain film. archivewatch.org")
        lines.append("https://archive.org/details/\(item.archiveID)")
        return lines.joined(separator: "\n")
    }
}
