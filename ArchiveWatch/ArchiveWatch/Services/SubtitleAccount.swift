import Foundation

// The viewer's OpenSubtitles connection: credentials in the Keychain, session
// in memory, and the quota the API reports for THAT account.
//
// Only a username and password are asked for. The Api-Key identifies the APP and
// ships in the bundle (Secrets.xcconfig -> Info.plist, the same path
// TMDB_BEARER_TOKEN takes) — the viewer never sees it. That split is what makes
// this free: the shared key carries only per-second REQUEST throughput, while
// the DOWNLOAD quota follows the signed-in account, so every viewer spends their
// own allowance and nothing is pooled.
//
// The password is stored in the Keychain, never UserDefaults and never in the
// catalog. It is kept (rather than only the token) because OpenSubtitles tokens
// expire in about a day and silently re-authenticating beats asking again.
@MainActor
@Observable
final class SubtitleAccount {

    static let shared = SubtitleAccount()

    private(set) var username: String = ""
    private(set) var isConnected = false
    private(set) var quota: OpenSubtitles.Quota?
    private(set) var lastError: String?
    var isWorking = false

    private var session: OpenSubtitles.Session?
    private static let service = "org.archivewatch.opensubtitles"
    private static let userKey = "opensubtitlesUsername"

    private init() {
        username = UserDefaults.standard.string(forKey: Self.userKey) ?? ""
        isConnected = !username.isEmpty && Keychain.read(service: Self.service,
                                                         account: username) != nil
    }

    /// The app's Api-Key. Absent in a build made without Secrets.xcconfig, which
    /// is a normal state for a contributor — the feature simply stays off rather
    /// than failing at the viewer.
    static var apiKey: String? {
        guard let k = Bundle.main.object(forInfoDictionaryKey: "OPENSUBTITLES_API_KEY") as? String,
              !k.isEmpty, k != "$(OPENSUBTITLES_API_KEY)" else { return nil }
        return k
    }

    static var isAvailable: Bool { apiKey != nil }

    func connect(username rawUser: String, password p: String) async -> Bool {
        guard let key = Self.apiKey else {
            lastError = "This build has no OpenSubtitles API key."
            return false
        }
        // Autofill and keyboards routinely add a trailing space; the server
        // treats it as part of the name and just says the login is wrong.
        let u = rawUser.trimmingCharacters(in: .whitespacesAndNewlines)
        // Catch the commonest mistake before spending a request against a
        // 1-req/sec-per-IP login limit.
        if u.contains("@") {
            lastError = "OpenSubtitles wants your username, not your email address."
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let s = try await OpenSubtitles.login(.init(apiKey: key, username: u, password: p))
            Keychain.write(p, service: Self.service, account: u)
            UserDefaults.standard.set(u, forKey: Self.userKey)
            username = u
            session = s
            quota = s.quota
            isConnected = true
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            isConnected = false
            return false
        }
    }

    func disconnect() {
        Keychain.delete(service: Self.service, account: username)
        UserDefaults.standard.removeObject(forKey: Self.userKey)
        username = ""; isConnected = false; session = nil; quota = nil; lastError = nil
    }

    private func validSession() async throws -> (OpenSubtitles.Credentials, String) {
        guard let key = Self.apiKey, isConnected,
              let pw = Keychain.read(service: Self.service, account: username) else {
            throw OpenSubtitles.Failure.notConfigured
        }
        let creds = OpenSubtitles.Credentials(apiKey: key, username: username, password: pw)
        if let s = session, s.isFresh { return (creds, s.token) }
        let s = try await OpenSubtitles.login(creds)   // token expires ~daily
        session = s
        quota = s.quota
        return (creds, s.token)
    }

    /// Fetch subtitles for a title and store them for the player. Returns the
    /// local HLS master, or throws with something worth showing a person.
    func fetchSubtitles(imdbID: String, archiveID: String,
                        videoURL: URL, runtime: Int) async throws -> URL {
        let (creds, token) = try await validSession()
        let vtt = try await OpenSubtitles.fetchVTT(imdbID: imdbID, credentials: creds, token: token)
        guard let master = SubtitleStore.store(vtt: vtt, for: archiveID, videoURL: videoURL,
                                               runtime: runtime, label: "English") else {
            throw OpenSubtitles.Failure.network("Couldn't save the subtitles.")
        }
        if var q = quota { q.remaining = max(0, q.remaining - 1); quota = q }
        return master
    }
}

/// Minimal Keychain wrapper — a password has no business in UserDefaults.
enum Keychain {
    static func write(_ value: String, service: String, account: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(service: String, account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete(service: String, account: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
    }
}
