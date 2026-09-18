// YouTube and Twitch, as the Studio uses them (docs/WATCH-TOGETHER.md §4).
//
// THE RULE THIS FILE EXISTS TO KEEP: a host never copies a stream key. Each
// platform hands one to an authorised app through its own API, and that is the
// only way the Studio gets one. A key is a credential — it is never logged,
// never written to disk, never put in a URL this app prints, and it does not
// outlive the session that fetched it.
//
// Shapes verified against the current documentation (2026-09-17), not memory:
//
//   YouTube — POST https://www.googleapis.com/youtube/v3/liveStreams?part=snippet,cdn
//     body { snippet.title, cdn: { ingestionType, resolution, frameRate } }
//     → cdn.ingestionInfo.{ingestionAddress, rtmpsIngestionAddress,
//                           backupIngestionAddress, rtmpsBackupIngestionAddress,
//                           streamName}
//     resolution ∈ 240p…2160p | variable   frameRate ∈ 30fps | 60fps | variable
//     streamStatus ∈ active | created | error | inactive | ready
//     scope https://www.googleapis.com/auth/youtube
//   Twitch — GET  https://api.twitch.tv/helix/users                (resolve me)
//            GET  https://api.twitch.tv/helix/streams/key?broadcaster_id=…
//                 scope channel:read:stream_key   → data[0].stream_key
//            PATCH https://api.twitch.tv/helix/channels?broadcaster_id=…
//                 scope channel:manage:broadcast  → 204, body { title, game_id }
//            headers: Authorization: Bearer …, Client-Id: …
//
// WHAT IS NOT HERE, DELIBERATELY: the token exchange. Signing in is the
// platform's own web flow in an `ASWebAuthenticationSession` — the app sees a
// token, never a password, and it cannot be built without a client id that
// only the owner can register. `StudioPlatformAuth` is that boundary, and it
// says so out loud rather than pretending.

import Foundation

// MARK: - What the publisher needs

/// An ingest address and the key for it. Constructed, used, discarded.
public struct StreamCredentials: Sendable {
    public let server: URL
    public let key: String
    /// The platform's own backup ingest, when it offers one.
    public let backupServer: URL?
    /// Platform-side identifiers the Studio needs afterwards (to take the
    /// broadcast live, to read chat, to end it). Never a credential.
    public let broadcastID: String?
    public let liveChatID: String?

    public init(server: URL, key: String, backupServer: URL? = nil,
                broadcastID: String? = nil, liveChatID: String? = nil) {
        self.server = server; self.key = key; self.backupServer = backupServer
        self.broadcastID = broadcastID; self.liveChatID = liveChatID
    }
}

public enum StudioPlatformError: Error, CustomStringConvertible {
    case notConfigured(String)
    case notSignedIn(String)
    case http(Int, String)
    case badResponse(String)
    case ineligible(String)

    public var description: String {
        switch self {
        case .notConfigured(let s): return s
        case .notSignedIn(let s): return s
        case .http(let code, let body):
            return "the platform answered \(code)" + (body.isEmpty ? "" : ": \(body)")
        case .badResponse(let s): return "unexpected answer from the platform: \(s)"
        case .ineligible(let s): return s
        }
    }
}

// MARK: - The auth boundary

/// Where signing in happens — and the one thing that cannot be written yet.
///
/// Each platform needs an application registered by the account's owner (a
/// Google Cloud project with YouTube Data API v3 enabled; a Twitch
/// application). Those produce a client id, which goes in `Secrets.xcconfig`
/// like the TMDb token and never into git. Until they exist this reports
/// `notConfigured`, and the go-live sheet says so — which is a better state
/// than a sign-in button that fails for reasons a host cannot see.
public enum StudioPlatformAuth {

    /// Client ids, read from the build's Info.plist (populated from the
    /// gitignored `Secrets.xcconfig`).
    static func clientID(for platform: Platform) -> String? {
        info(platform == .youtube ? youTubeClientIDKey : "TWITCH_CLIENT_ID")
    }

    /// The client secret, which exists for exactly ONE credential in this app.
    ///
    /// Google's device flow — the television's YouTube sign-in, per the owner's
    /// 2026-09-18 direction — requires a client of type "TVs and Limited Input
    /// devices", and that client type carries a secret. Nothing else here has
    /// one: Twitch's device flow takes none, and the PKCE flow iOS and macOS
    /// use exists precisely so an installed app does not need one.
    static func clientSecret(for platform: Platform) -> String? {
        guard platform == .youtube, let key = youTubeSecretKey else { return nil }
        return info(key)
    }

    /// WHICH Google client this platform signs in with, and why there are two.
    ///
    /// A television cannot usefully present a password field, so tvOS uses the
    /// device flow, and Google refuses that flow to any client that is not of
    /// type "TVs and Limited Input devices". The iOS client cannot be reused —
    /// this is not a preference. iOS and macOS keep the iOS client and PKCE.
    static var youTubeClientIDKey: String {
        #if os(tvOS)
        "YOUTUBE_TV_CLIENT_ID"
        #else
        "YOUTUBE_CLIENT_ID"
        #endif
    }

    /// Nil on every platform whose flow needs no secret, which is the point.
    static var youTubeSecretKey: String? {
        #if os(tvOS)
        "YOUTUBE_TV_CLIENT_SECRET"
        #else
        nil
        #endif
    }

    private static func info(_ key: String) -> String? {
        let v = Bundle.main.object(forInfoDictionaryKey: key) as? String
        return (v?.isEmpty ?? true) ? nil : v
    }

    public enum Platform: String, Sendable, CaseIterable {
        case youtube, twitch

        /// The platform's OWN spelling. Capitalising the raw value rendered
        /// "Youtube" on the glass (iPhone 12, 2026-09-17) two lines above a
        /// hand-written "YouTube" — a brand name is not a word to capitalise.
        public var displayName: String {
            switch self {
            case .youtube: return "YouTube"
            case .twitch:  return "Twitch"
            }
        }
    }

    /// The scopes each half of the feature needs, so the consent screen asks
    /// for exactly what it uses and nothing more.
    static func scopes(for platform: Platform) -> [String] {
        switch platform {
        case .youtube:
            // `youtube` covers creating the broadcast and reading live chat.
            return ["https://www.googleapis.com/auth/youtube"]
        case .twitch:
            return ["channel:read:stream_key", "channel:manage:broadcast", "user:read:chat"]
        }
    }

    /// What is missing before a host can sign in at all, or nil when the
    /// build is configured. Separated from `token` because the go-live sheet
    /// asks a DIFFERENT question of each: "can this build sign in" decides
    /// whether to offer a button, "is there a token" decides what it says.
    public static func configurationProblem(for platform: Platform) -> String? {
        // A client id ALONE is not a configured platform where the flow needs
        // a secret. Checking only the id would have let a television offer a
        // sign-in that Google refuses at the first request — the same shape as
        // §9.ooo's gate, which went green on a credential that did not cover
        // the path it was guarding.
        let haveID = clientID(for: platform) != nil
        let needSecret = platform == .youtube && youTubeSecretKey != nil
        let haveSecret = !needSecret || clientSecret(for: platform) != nil
        guard !(haveID && haveSecret) else { return nil }

        if platform == .youtube && needSecret {
            return "Signing in to YouTube is not set up on Apple TV yet. A television "
                + "signs in from your phone, and that needs a SECOND Google OAuth client "
                + "of type \u{201C}TVs and Limited Input devices\u{201D} \u{2014} the iPhone one cannot do "
                + "it \u{2014} with its client id and client secret in Secrets.xcconfig. "
                + "Twitch needs nothing extra."
        }
        return "Signing in to \(platform.displayName) is not set up in this build yet. "
            + "It needs an application registered on "
            + (platform == .youtube ? "Google Cloud (YouTube Data API v3)" : "the Twitch developer console")
            + " and its client id in Secrets.xcconfig."
    }

    /// The problem when NEITHER platform is configured, or nil when at least
    /// one is.
    ///
    /// A surface with no platform picker — a television's transport menu —
    /// must not name one platform arbitrarily: a host told "signing in to
    /// YouTube is not set up" reasonably asks what about Twitch, and the true
    /// answer is that neither is.
    public static var anyConfigurationProblem: String? {
        let missing = Platform.allCases.filter { configurationProblem(for: $0) != nil }
        guard missing.count == Platform.allCases.count else { return nil }
        return "Signing in to \(Platform.youtube.displayName) or "
            + "\(Platform.twitch.displayName) is not set up in this build yet. "
            + "It needs an application registered on Google Cloud (YouTube Data API v3) "
            + "and on the Twitch developer console, and their client ids in Secrets.xcconfig."
    }

    public static func isSignedIn(_ platform: Platform) -> Bool {
        StudioTokenStore.load(for: platform.rawValue) != nil
    }

    public static func signOut(_ platform: Platform) {
        StudioTokenStore.clear(for: platform.rawValue)
    }

    /// A token for this platform, or an error naming what is missing.
    ///
    /// Never returns a placeholder: a fake token would make every caller
    /// appear to work and fail at the far end with a platform error nobody
    /// could read. Refreshes silently when the stored one has aged out, and
    /// SAVES the result — Twitch's refresh tokens are one-time-use, so
    /// dropping the new one signs the host out on the next call.
    static func token(for platform: Platform) async throws -> String {
        guard let clientID = clientID(for: platform) else {
            throw StudioPlatformError.notConfigured(configurationProblem(for: platform)!)
        }
        guard let stored = StudioTokenStore.load(for: platform.rawValue) else {
            throw StudioPlatformError.notSignedIn(
                "Sign in to \(platform.displayName) to stream. Archive Watch will fetch the stream key itself.")
        }
        if stored.isFresh { return stored.access }

        let renewed: StudioTokenStore.Token
        switch platform {
        case .youtube:
            // The token came from whichever client signed in, and only that
            // client can renew it: on a television that is the TV client, and
            // its refresh REQUIRES the secret. Renewing a device-flow token
            // through the PKCE path would 401 on every call.
            if let secret = clientSecret(for: .youtube) {
                renewed = try await GoogleDeviceAuth(clientID: clientID, clientSecret: secret).refresh(stored)
            } else {
                renewed = try await GoogleTokenRefresh(clientID: clientID).refresh(stored)
            }
        case .twitch:  renewed = try await TwitchDeviceAuth(clientID: clientID).refresh(stored)
        }
        // MUST be checked. Twitch has already invalidated `stored.refresh`
        // by answering this call, so a silent failure here loses the only
        // token that could have renewed the session.
        try requireStored(StudioTokenStore.save(renewed, for: platform.rawValue), platform)
        return renewed.access
    }


    /// A Keychain write that failed is a host who is NOT signed in, whatever
    /// the screen says. Named rather than swallowed (§9.rrr).
    private static func requireStored(_ status: OSStatus, _ platform: Platform) throws {
        guard status != errSecSuccess else { return }
        throw StudioPlatformError.notSignedIn(
            "Signed in to \(platform.displayName), but the token could not be stored "
            + "(Keychain error \(status)). Sign in again.")
    }

    // MARK: Signing in

    /// YouTube: the platform's own page in an `ASWebAuthenticationSession`,
    /// authorization code + PKCE. Returns when a token is stored.
    @MainActor
    public static func signInToYouTube() async throws {
        guard let clientID = clientID(for: .youtube) else {
            throw StudioPlatformError.notConfigured(configurationProblem(for: .youtube)!)
        }
        let token = try await GoogleAuth(clientID: clientID).authorize(scopes: scopes(for: .youtube))
        try requireStored(StudioTokenStore.save(token, for: Platform.youtube.rawValue), .youtube)
    }

    /// YouTube on a TELEVISION: the device flow, two steps, because the host
    /// has to be SHOWN a code and a QR between them. Same shape as Twitch's
    /// below — deliberately, so the sign-in row draws one thing.
    public static func beginYouTubeDeviceSignIn() async throws -> GoogleDeviceAuth.Pending {
        let (id, secret) = try youTubeDeviceCredentials()
        return try await GoogleDeviceAuth(clientID: id, clientSecret: secret)
            .begin(scopes: scopes(for: .youtube))
    }

    public static func completeYouTubeDeviceSignIn(_ pending: GoogleDeviceAuth.Pending) async throws {
        let (id, secret) = try youTubeDeviceCredentials()
        let token = try await GoogleDeviceAuth(clientID: id, clientSecret: secret).poll(pending)
        try requireStored(StudioTokenStore.save(token, for: Platform.youtube.rawValue), .youtube)
    }

    private static func youTubeDeviceCredentials() throws -> (String, String) {
        guard let id = clientID(for: .youtube), let secret = clientSecret(for: .youtube) else {
            throw StudioPlatformError.notConfigured(configurationProblem(for: .youtube)
                ?? "YouTube sign-in is not set up in this build.")
        }
        return (id, secret)
    }

    /// Whether THIS platform signs in to YouTube by device code rather than by
    /// web sheet. The surfaces ask rather than testing `#if os(tvOS)`
    /// themselves, so the answer lives in one place.
    public static var youTubeUsesDeviceFlow: Bool { youTubeSecretKey != nil }

    /// Twitch: the device flow, because Twitch offers a public client no
    /// PKCE — see StudioPlatformAuth.swift. Two steps, because the host has
    /// to be SHOWN a code between them.
    public static func beginTwitchSignIn() async throws -> TwitchDeviceAuth.Pending {
        guard let clientID = clientID(for: .twitch) else {
            throw StudioPlatformError.notConfigured(configurationProblem(for: .twitch)!)
        }
        return try await TwitchDeviceAuth(clientID: clientID).begin(scopes: scopes(for: .twitch))
    }

    public static func completeTwitchSignIn(_ pending: TwitchDeviceAuth.Pending) async throws {
        guard let clientID = clientID(for: .twitch) else {
            throw StudioPlatformError.notConfigured(configurationProblem(for: .twitch)!)
        }
        let token = try await TwitchDeviceAuth(clientID: clientID).poll(pending)
        try requireStored(StudioTokenStore.save(token, for: Platform.twitch.rawValue), .twitch)
    }
}

// MARK: - HTTP

private struct HTTP {
    static func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw StudioPlatformError.badResponse("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            // The body often names the real problem ("liveStreamingNotEnabled",
            // "insufficientPermissions"), and a host can act on that. It is
            // trimmed because a platform can return a page.
            let body = String(decoding: data.prefix(400), as: UTF8.self)
            throw StudioPlatformError.http(http.statusCode, body)
        }
        return (data, http)
    }

    static func json(_ data: Data) throws -> [String: Any] {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StudioPlatformError.badResponse("not JSON")
        }
        return o
    }
}

// MARK: - YouTube

public struct YouTubeLive: Sendable {
    let token: String

    private static let base = "https://www.googleapis.com/youtube/v3"

    public init(token: String) { self.token = token }

    private func request(_ path: String, method: String,
                         query: [String: String] = [:],
                         body: [String: Any]? = nil) throws -> URLRequest {
        var c = URLComponents(string: Self.base + path)!
        if !query.isEmpty {
            c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var r = URLRequest(url: c.url!)
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return r
    }

    /// Creates a reusable stream and a bound broadcast, and returns the ingest
    /// address + key. Three calls, in the order YouTube documents: the STREAM
    /// carries the ingest, the BROADCAST carries the title and privacy, and
    /// `bind` joins them. A broadcast with no bound stream can never go live.
    public func prepare(title: String, description: String, privacy: String,
                        resolution: String = "1080p", frameRate: String = "30fps",
                        preferRTMPS: Bool = true) async throws -> StreamCredentials {
        // 1. The stream — where bytes go.
        let (streamData, _) = try await HTTP.send(try request(
            "/liveStreams", method: "POST",
            query: ["part": "snippet,cdn,status"],
            body: ["snippet": ["title": title],
                   "cdn": ["ingestionType": "rtmp",
                           "resolution": resolution,
                           "frameRate": frameRate],
                   "contentDetails": ["isReusable": true]]))
        let stream = try HTTP.json(streamData)
        guard let streamID = stream["id"] as? String,
              let cdn = stream["cdn"] as? [String: Any],
              let info = cdn["ingestionInfo"] as? [String: Any],
              let key = info["streamName"] as? String else {
            throw StudioPlatformError.badResponse("liveStreams.insert returned no ingestionInfo")
        }
        let primaryString = (preferRTMPS ? info["rtmpsIngestionAddress"] as? String : nil)
            ?? info["ingestionAddress"] as? String
        let backupString = (preferRTMPS ? info["rtmpsBackupIngestionAddress"] as? String : nil)
            ?? info["backupIngestionAddress"] as? String
        guard let primaryString, let server = URL(string: primaryString) else {
            throw StudioPlatformError.badResponse("liveStreams.insert returned no ingest address")
        }

        // 2. The broadcast — what the audience finds.
        let (bcData, _) = try await HTTP.send(try request(
            "/liveBroadcasts", method: "POST",
            query: ["part": "snippet,status,contentDetails"],
            body: ["snippet": ["title": title,
                               "description": description,
                               "scheduledStartTime": ISO8601DateFormatter().string(from: Date())],
                   "status": ["privacyStatus": privacy,
                              "selfDeclaredMadeForKids": false],
                   // autoStartStream so the broadcast goes live when bytes
                   // arrive, rather than needing a second transition the host
                   // would have to know about.
                   "contentDetails": ["enableAutoStart": true,
                                      "enableAutoStop": true]]))
        let broadcast = try HTTP.json(bcData)
        guard let broadcastID = broadcast["id"] as? String else {
            throw StudioPlatformError.badResponse("liveBroadcasts.insert returned no id")
        }
        let chatID = (broadcast["snippet"] as? [String: Any])?["liveChatId"] as? String

        // 3. Bind them.
        _ = try await HTTP.send(try request(
            "/liveBroadcasts/bind", method: "POST",
            query: ["part": "id,contentDetails", "id": broadcastID, "streamId": streamID]))

        return StreamCredentials(server: server, key: key,
                                 backupServer: backupString.flatMap(URL.init(string:)),
                                 broadcastID: broadcastID, liveChatID: chatID)
    }

    /// Ends the broadcast. `enableAutoStop` handles the normal case; this is
    /// the explicit end, for a host who stops deliberately.
    public func complete(broadcastID: String) async throws {
        _ = try await HTTP.send(try request(
            "/liveBroadcasts/transition", method: "POST",
            query: ["part": "id,status", "id": broadcastID, "broadcastStatus": "complete"]))
    }

    /// One page of live chat. Polling interval comes from the response —
    /// YouTube says how often to ask and an app that ignores it gets throttled.
    public func chat(liveChatID: String, pageToken: String?)
        async throws -> (messages: [(author: String, text: String)], next: String?, pollAfterMS: Int) {
        var q = ["liveChatId": liveChatID, "part": "snippet,authorDetails"]
        if let pageToken { q["pageToken"] = pageToken }
        let (data, _) = try await HTTP.send(try request("/liveChat/messages", method: "GET", query: q))
        let o = try HTTP.json(data)
        let items = o["items"] as? [[String: Any]] ?? []
        let msgs: [(String, String)] = items.compactMap { item in
            guard let snip = item["snippet"] as? [String: Any],
                  let text = snip["displayMessage"] as? String,
                  let author = (item["authorDetails"] as? [String: Any])?["displayName"] as? String
            else { return nil }
            return (author, text)
        }
        return (msgs, o["nextPageToken"] as? String,
                (o["pollingIntervalMillis"] as? Int) ?? 5000)
    }
}

// MARK: - Twitch

public struct TwitchLive: Sendable {
    let token: String
    let clientID: String

    private static let base = "https://api.twitch.tv/helix"

    public init(token: String, clientID: String) {
        self.token = token; self.clientID = clientID
    }

    private func request(_ path: String, method: String,
                         query: [String: String] = [:],
                         body: [String: Any]? = nil) throws -> URLRequest {
        var c = URLComponents(string: Self.base + path)!
        if !query.isEmpty {
            c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var r = URLRequest(url: c.url!)
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue(clientID, forHTTPHeaderField: "Client-Id")
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return r
    }

    /// The signed-in user's id. Twitch keys every channel call on it and the
    /// token does not carry it in a form we should parse ourselves.
    public func broadcasterID() async throws -> String {
        let (data, _) = try await HTTP.send(try request("/users", method: "GET"))
        guard let first = (try HTTP.json(data)["data"] as? [[String: Any]])?.first,
              let id = first["id"] as? String else {
            throw StudioPlatformError.badResponse("/users returned no user")
        }
        return id
    }

    /// Title and category. Category is a game_id, so a name has to be resolved
    /// first — a title change must not fail because the category did.
    public func setChannel(broadcasterID: String, title: String, categoryName: String?) async throws {
        var body: [String: Any] = ["title": title]
        if let categoryName, !categoryName.isEmpty,
           let gameID = try? await gameID(named: categoryName) {
            body["game_id"] = gameID
        }
        _ = try await HTTP.send(try request("/channels", method: "PATCH",
                                            query: ["broadcaster_id": broadcasterID],
                                            body: body))
    }

    private func gameID(named name: String) async throws -> String? {
        let (data, _) = try await HTTP.send(try request("/games", method: "GET",
                                                        query: ["name": name]))
        return ((try HTTP.json(data)["data"] as? [[String: Any]])?.first)?["id"] as? String
    }

    /// The ingest endpoint and the key. The ingest list is PUBLIC (no auth) and
    /// its first entry is Twitch's own "Default" recommendation, so it is what
    /// an encoder should use unless a host picks a region.
    public func prepare(title: String, categoryName: String?) async throws -> StreamCredentials {
        let id = try await broadcasterID()
        // The title is set BEFORE the key is fetched: a stream that goes live
        // under the previous show's title is worse than one that fails to set
        // a category.
        try await setChannel(broadcasterID: id, title: title, categoryName: categoryName)

        let (keyData, _) = try await HTTP.send(try request("/streams/key", method: "GET",
                                                           query: ["broadcaster_id": id]))
        guard let first = (try HTTP.json(keyData)["data"] as? [[String: Any]])?.first,
              let key = first["stream_key"] as? String else {
            throw StudioPlatformError.badResponse("/streams/key returned no key")
        }
        let (server, backup) = try await Self.ingest()
        return StreamCredentials(server: server, key: key, backupServer: backup,
                                 broadcastID: id, liveChatID: id)
    }

    /// `ingest.twitch.tv/ingests` — the current PoP list. Templates arrive as
    /// `rtmp://host/app/{stream_key}`, and the key is supplied separately, so
    /// the placeholder is stripped rather than substituted.
    static func ingest() async throws -> (URL, URL?) {
        let url = URL(string: "https://ingest.twitch.tv/ingests")!
        let (data, _) = try await HTTP.send(URLRequest(url: url))
        let list = (try HTTP.json(data)["ingests"] as? [[String: Any]]) ?? []
        func server(_ entry: [String: Any]) -> URL? {
            guard var t = entry["url_template"] as? String else { return nil }
            t = t.replacingOccurrences(of: "/{stream_key}", with: "")
            // RTMPS on 443 travels through more networks than RTMP on 1935.
            if t.hasPrefix("rtmp://") {
                t = "rtmps://" + t.dropFirst("rtmp://".count)
            }
            return URL(string: t)
        }
        guard let primary = list.first.flatMap(server) else {
            throw StudioPlatformError.badResponse("no Twitch ingest servers listed")
        }
        return (primary, list.dropFirst().first.flatMap(server))
    }
}
