// Signing in to YouTube and Twitch, for a PUBLIC client
// (docs/WATCH-TOGETHER.md §4).
//
// The app never sees a password. The platform's own page collects it, and what
// comes back is a token — which lives in the Keychain, is never logged, and is
// never shown. The app also holds no client SECRET: it cannot keep one, so it
// uses only flows designed for clients that cannot.
//
// THE TWO PLATFORMS NEED DIFFERENT FLOWS, and that is not a preference:
//
//   · GOOGLE / YOUTUBE — authorization code + **PKCE** (S256), the documented
//     flow for an installed app. Redirect is the reversed client id as a
//     custom scheme. `access_type=offline` + `prompt=consent` yields a refresh
//     token, so a host authorises once.
//
//   · TWITCH — **the Device Code Grant**, because Twitch's own documentation
//     for public clients offers only the implicit grant or the device flow,
//     and says nothing about PKCE (checked 2026-09-17). The implicit grant
//     returns no refresh token, so a host would re-authorise every few hours;
//     the device flow returns one and is the same code path on a television
//     and a phone. A short code the viewer confirms on another device is worth
//     more than a smoother screen they must repeat every show.
//
// `ASWebAuthenticationSession` is available on tvOS 16+ as well as iOS
// (checked in the tvOS 27 SDK), so the Google flow needs no separate TV path —
// on a television the system hands off to a nearby device rather than asking
// anyone to type on a remote.

import AuthenticationServices
#if canImport(AppKit)
import AppKit
#endif
import CryptoKit
import Foundation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Token storage

/// Tokens in the Keychain, never `UserDefaults`. A broadcast credential in a
/// plist is a credential in every backup and every crash report.
enum StudioTokenStore {
    private static let service = "org.archivewatch.studio.oauth"

    struct Token: Sendable, Codable {
        var access: String
        var refresh: String?
        var expires: Date?
        var isFresh: Bool {
            guard let expires else { return true }
            // A minute of slack: a token that expires mid-handshake is worse
            // than one refreshed slightly early.
            return expires.timeIntervalSinceNow > 60
        }
    }

    /// Returns the Keychain's own verdict.
    ///
    /// This used to return Void, which made a failed write indistinguishable
    /// from a successful one. The most dangerous caller is the REFRESH path:
    /// Twitch's refresh tokens are one-time-use, so by the time the store is
    /// asked to keep the renewed token the OLD one is already dead. A dropped
    /// status there signs the host out permanently, at the next call, with
    /// nothing to diagnose — and `SecItemAdd` really does fail in the field:
    /// an unentitled process gets `-34018` (a required entitlement is not
    /// present), measured 2026-09-18 (§9.rrr).
    /// EVERY query carries this. Without it, macOS routes a generic password to
    /// the FILE-BASED (legacy) keychain, which has no concept of
    /// `kSecAttrAccessible` — so §6.1's
    /// `…AfterFirstUnlockThisDeviceOnly` was accepted by the API and then meant
    /// nothing. Measured from inside the signed, sandboxed Mac app
    /// (`AW_KEYCHAIN_PROBE=1`, §9.aaaa):
    ///
    ///     readable from the file-based (legacy) keychain: true
    ///     readable from the data-protection keychain:     false
    ///     kSecAttrAccessible reported: <absent>
    ///
    /// iOS and tvOS already use the data-protection keychain, where this flag
    /// is a no-op, so it is set unconditionally rather than behind an `#if` —
    /// one query shape is easier to keep honest than two.
    private static let dataProtection = kSecUseDataProtectionKeychain as String

    @discardableResult
    static func save(_ token: Token, for platform: String) -> OSStatus {
        guard let data = try? JSONEncoder().encode(token) else { return errSecParam }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: platform,
                                    dataProtection: true]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        // Not synchronised to iCloud, and readable only after first unlock:
        // this token belongs to this device's session, not to the account.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil)
    }

    static func load(for platform: String) -> Token? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: platform,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne,
                                    dataProtection: true]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Token.self, from: data)
    }

    static func clear(for platform: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service,
                       kSecAttrAccount as String: platform,
                       dataProtection: true] as CFDictionary)
        // The LEGACY copy too, for one release: every macOS token written
        // before this change lives there, and a sign-out that leaves a token
        // behind is worse than the bug it is cleaning up after.
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service,
                       kSecAttrAccount as String: platform] as CFDictionary)
    }

    #if DEBUG
    /// WHERE THE TOKENS ACTUALLY LAND — asked from inside the signed app,
    /// which §9.rrr established is the only place the question can be answered.
    ///
    /// §6.1 promises tokens live in the Keychain under
    /// `…AfterFirstUnlockThisDeviceOnly` and are never synchronised. On macOS
    /// that promise is not obviously kept: a generic password goes to the
    /// FILE-BASED (legacy) keychain unless `kSecUseDataProtectionKeychain` is
    /// set, and the legacy keychain has no concept of `kSecAttrAccessible` at
    /// all — the API accepts the attribute and then means nothing by it.
    ///
    /// The §8.11 harness could only report and refuse to judge: an unentitled
    /// command-line binary is answered `-34018` by the data-protection
    /// keychain, so it would have measured its own lack of entitlement rather
    /// than the product's behaviour. A signed, sandboxed app has the access
    /// group the sandbox gives it, so here the answer is about the product.
    ///
    /// Writes only under a probe account and deletes it again.
    static func describeStorage() -> [String] {
        let probe = "keychain-probe-do-not-use"
        var out: [String] = []

        clear(for: probe)
        let status = save(Token(access: "probe", refresh: "probe",
                                expires: Date().addingTimeInterval(3600)),
                          for: probe)
        out.append("save() -> OSStatus \(status)")
        out.append("round-trips: \(load(for: probe)?.access == "probe")")

        func attributes(dataProtection: Bool) -> [String: Any]? {
            var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: probe,
                                    kSecReturnAttributes as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
            if dataProtection { q[kSecUseDataProtectionKeychain as String] = true }
            var r: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess else { return nil }
            return r as? [String: Any]
        }

        let legacy = attributes(dataProtection: false)
        let dp = attributes(dataProtection: true)
        out.append("readable from the file-based (legacy) keychain: \(legacy != nil)"
                   + "  accessible=\((legacy?[kSecAttrAccessible as String] as? String) ?? "<absent>")")
        out.append("readable from the data-protection keychain:     \(dp != nil)"
                   + "  accessible=\((dp?[kSecAttrAccessible as String] as? String) ?? "<absent>")")

        // IS IT TWO ITEMS OR ONE? A duplicate token in the weaker keychain
        // would be exactly the leak §6.1 exists to prevent, and "both queries
        // returned something" cannot tell the two apart. Delete from the
        // data-protection keychain only, then ask the legacy one again: if it
        // still answers, there are two copies.
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service,
                       kSecAttrAccount as String: probe,
                       kSecUseDataProtectionKeychain as String: true] as CFDictionary)
        let survivor = attributes(dataProtection: false)
        out.append("after deleting ONLY the data-protection item, a legacy copy survives: "
                   + "\(survivor != nil)")

        let chosen = dp ?? legacy   // captured BEFORE the isolation delete above
        let acc = chosen?[kSecAttrAccessible as String] as? String
        let syn = chosen?[kSecAttrSynchronizable as String]
        out.append("kSecAttrAccessible reported: \(acc ?? "<absent>")")
        out.append("kSecAttrSynchronizable reported: \(syn.map { "\($0)" } ?? "<absent>")")
        out.append("§6.1 promise kept: "
                   + ((dp != nil && acc == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))
                      ? "YES" : "NO"))

        clear(for: probe)
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service,
                       kSecAttrAccount as String: probe,
                       kSecUseDataProtectionKeychain as String: true] as CFDictionary)
        out.append("cleaned up: \(load(for: probe) == nil)")
        return out
    }
    #endif
}

// MARK: - The Google / YouTube flow

@MainActor
final class GoogleAuth: NSObject {
    private let clientID: String
    private var session: ASWebAuthenticationSession?

    init(clientID: String) { self.clientID = clientID }

    /// Google documents TWO custom schemes for an installed app: the reversed
    /// CLIENT ID (`com.googleusercontent.apps.123-abc`) or "the reverse DNS
    /// notation of a domain under your control" — i.e. the bundle identifier.
    ///
    /// We use the BUNDLE ID, and the reason is the owner's remaining work. A
    /// URL scheme has to be declared in Info.plist at BUILD time, and the
    /// reversed client id is not known until the client id is pasted in — so
    /// that choice would make the owner paste a second derived string, or make
    /// `ASWebAuthenticationSession` refuse to start with an error a host
    /// cannot read. The bundle id is fixed, is already in the project, and is
    /// declared in Info.plist beside the `archivewatch` deep-link scheme.
    ///
    /// Read from the bundle rather than written out, so it cannot drift from
    /// `PRODUCT_BUNDLE_IDENTIFIER`.
    nonisolated var redirectScheme: String {
        Bundle.main.bundleIdentifier ?? "app.archivewatch.tvos"
    }

    nonisolated var redirectURI: String { "\(redirectScheme):/oauth2redirect" }

    /// Built separately from the flow that presents it, so the request shape
    /// can be asserted without a window or a network
    /// (`tools/test_studio_signin.swift`).
    nonisolated func authorizeURL(scopes: [String], challenge: String, state: String) -> URL {
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            // A refresh token, so a host authorises once rather than per show.
            .init(name: "access_type", value: "offline"),
            // BOTH, and the second is what lets a host change channels.
            //
            // `consent` alone re-shows the CONSENT screen for the account
            // Google has already picked; it does not offer the account, and
            // therefore not the YouTube CHANNEL, chooser. Measured 2026-09-18:
            // signing out and straight back in returned a token for the same
            // channel (UCtPDkIGiSWSb5N8hNdaPizg) in 42 seconds — so the advice
            // "sign out and sign in again to choose another" was impossible to
            // follow, because nothing ever asked. Google offers the channel
            // chooser only at consent AFTER an account is chosen, and an app
            // cannot move a host's channel any other way.
            .init(name: "prompt", value: "select_account consent"),
            .init(name: "state", value: state),
        ]
        return c.url!
    }

    /// AWAUTH — the sign-in path had NO diagnostics of any kind.
    ///
    /// `grep -c awdiag StudioPlatformAuth.swift` returned 0, which is the same
    /// hole `AWPUB` was on 2026-09-19: when a sign-in stalls there is nothing
    /// to read, so "the spinner never stopped" and "the token exchange was
    /// refused" are the same observation. Found 2026-09-21 when a macOS
    /// sign-in hung after the host had already approved at Google and the
    /// app's own log had not one line about it.
    nonisolated static func adiag(_ line: String) {
        #if DEBUG
        let l = "[AWAUTH] " + line
        FileHandle.standardError.write(Data((l + "\n").utf8))
        DiagFile.log(l)
        #endif
    }

    func authorize(scopes: [String]) async throws -> StudioTokenStore.Token {
        let verifier = Self.randomVerifier()
        let state = Self.randomVerifier()
        let url = authorizeURL(scopes: scopes,
                               challenge: Self.challenge(for: verifier),
                               state: state)

        Self.adiag("google authorize scopes=\(scopes.joined(separator: ",")) "
                   + "redirect=\(redirectURI) clientID=\(clientID.isEmpty ? "MISSING" : "set")")
        let callback = try await present(url: url, scheme: redirectScheme)
        Self.adiag("google callback received host=\(callback.host ?? "-") "
                   + "query=\(callback.query.map { $0.count } ?? 0) bytes")
        guard let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
              let code = items.first(where: { $0.name == "code" })?.value else {
            let err = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error" })?.value
            Self.adiag("google callback carried NO CODE err=\(err ?? "-")")
            throw StudioPlatformError.notSignedIn(err.map { "Google refused: \($0)" }
                                                  ?? "Google returned no authorization code.")
        }
        // CSRF: a callback whose state is not the one we sent is not ours.
        guard items.first(where: { $0.name == "state" })?.value == state else {
            Self.adiag("google STATE MISMATCH — callback is not ours")
            throw StudioPlatformError.notSignedIn("The sign-in response did not match this request.")
        }
        Self.adiag("google code received, exchanging")
        let token = try await exchange(code: code, verifier: verifier)
        Self.adiag("google token stored refresh=\(token.refresh != nil)")
        return token
    }

    private func exchange(code: String, verifier: String) async throws -> StudioTokenStore.Token {
        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "code", value: code),
            .init(name: "code_verifier", value: verifier),
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "redirect_uri", value: redirectURI),
        ]
        r.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = o["access_token"] as? String else {
            // GOOGLE'S OWN WORDS, not ours. This threw a fixed sentence and
            // discarded the body, so `invalid_grant`, `redirect_uri_mismatch`
            // and `invalid_client` — three different problems with three
            // different fixes — were one indistinguishable message.
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let body = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
            let why = [body["error"] as? String,
                       body["error_description"] as? String]
                .compactMap { $0 }.joined(separator: " — ")
            Self.adiag("google exchange FAILED http=\(code) \(why.isEmpty ? "no error body" : why)")
            throw StudioPlatformError.badResponse(
                why.isEmpty ? "Google would not exchange the code (HTTP \(code))."
                            : "Google would not exchange the code: \(why)")
        }
        let expiresIn = (o["expires_in"] as? Double) ?? 3600
        return .init(access: access, refresh: o["refresh_token"] as? String,
                     expires: Date().addingTimeInterval(expiresIn))
    }

    // MARK: Web session

    private func present(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { c in
            // `@Sendable` IS LOAD-BEARING, and macOS is where that shows.
            //
            // `ASWebAuthenticationSession` is NOT `NS_SWIFT_UI_ACTOR` in the
            // SDK (only its presentation-context protocol is), so its
            // completion handler imports unisolated — and a closure literal
            // written inside this `@MainActor` type therefore INHERITS main
            // actor isolation, which makes Swift 6 emit a dynamic isolation
            // check at its entry. iOS and tvOS deliver the callback on the
            // main queue, so the check passed and nobody knew it was there.
            // macOS delivers it on an XPC reply queue, and the check TRAPS:
            // EXC_BREAKPOINT in `_dispatch_assert_queue_fail`, every sign-in,
            // AFTER the host has already approved at Google
            // (`Archive Watch-2026-09-21-090954.ips`).
            //
            // Marking the closure `@Sendable` makes it nonisolated, so no
            // check is emitted. Nothing in it needs the main actor: resuming
            // a continuation is not UI work.
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { @Sendable callback, error in
                Self.adiag("web session returned callback=\(callback != nil) "
                           + "error=\(error.map { String(describing: $0) } ?? "-")")
                if let callback { c.resume(returning: callback) }
                else if let e = error as? ASWebAuthenticationSessionError,
                        e.code == .canceledLogin {
                    c.resume(throwing: StudioPlatformError.notSignedIn("Sign-in was canceled."))
                } else {
                    c.resume(throwing: StudioPlatformError.notSignedIn(
                        error?.localizedDescription ?? "Sign-in did not complete."))
                }
            }
            #if !os(tvOS)
            s.presentationContextProvider = self
            // The host is signing in to THEIR account; a shared cookie jar is
            // what makes "it already knows me" work.
            s.prefersEphemeralWebBrowserSession = false
            #endif
            // On tvOS neither property EXISTS — read from the tvOS 27 header,
            // not assumed: `presentationContextProvider`,
            // `prefersEphemeralWebBrowserSession` and even `cancel` are
            // `API_UNAVAILABLE(tvos)`, while the class itself is tvos(16.0).
            //
            // AND NOW MEASURED ON THE GLASS (2026-09-18, Ben Bedroom): what
            // tvOS presents is not a web page at all. It is Apple's own sheet —
            // "Sign in to ArchiveWatch · Sign in with Apple Device · You will
            // get a notification on a nearby iPhone or iPad" — which HANDS THE
            // SESSION TO A PHONE. The owner signed in to Google and approved
            // the channel there, and the token arrived here: the go-live
            // surface went to "Signed in to YouTube" and `channels.list`
            // returned the host's own channel.
            //
            // THAT is why there is no context provider and no `cancel`: the
            // session is not ours to present or dismiss, because it is not on
            // this device. The absences really were the design, and they meant
            // something better than "the television presents it itself".
            //
            // So a television needs NO second Google client and no device flow
            // for this — the same client id the iPhone uses is enough.
            // `GoogleDeviceAuth` remains for a platform that has no equivalent
            // hand-off, and is selected only when a TV client is configured.
            session = s
            Self.adiag("web session start scheme=\(scheme)")
            if !s.start() {
                Self.adiag("web session REFUSED TO START — is \(scheme) in CFBundleURLTypes?")
                c.resume(throwing: StudioPlatformError.notConfigured(
                    "This build cannot open a sign-in window. The redirect scheme "
                    + "\(scheme) must be listed in the app's URL types."))
            }
        }
    }


    // MARK: PKCE

    nonisolated static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }

    nonisolated static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }
}

/// Google's refresh, deliberately OUTSIDE the @MainActor class: renewing a
/// token presents no UI, and `StudioPlatformAuth.token(for:)` is called from
/// the engine's context rather than the main one.
struct GoogleTokenRefresh: Sendable {
    let clientID: String

    func refresh(_ token: StudioTokenStore.Token) async throws -> StudioTokenStore.Token {
        guard let refresh = token.refresh else {
            throw StudioPlatformError.notSignedIn("Sign in to YouTube again.")
        }
        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [.init(name: "client_id", value: clientID),
                           .init(name: "refresh_token", value: refresh),
                           .init(name: "grant_type", value: "refresh_token")]
        r.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: r)
        let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let access = o?["access_token"] as? String else {
            // A refresh token can be revoked from the account page, and an
            // expired Google grant answers 400 — neither is recoverable here.
            if StudioValidationClock.refreshWasRevoked(status: (resp as? HTTPURLResponse)?.statusCode, json: o) {
                throw StudioPlatformError.grantRevoked("YouTube has ended this sign-in. Sign in again to use YouTube.")
            }
            throw StudioPlatformError.notSignedIn("Sign in to YouTube again.")
        }
        let expiresIn = (o?["expires_in"] as? Double) ?? 3600
        // Google does not resend the refresh token; keep the one we have.
        return .init(access: access, refresh: refresh,
                     expires: Date().addingTimeInterval(expiresIn))
    }
}

#if !os(tvOS)
extension GoogleAuth: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        #elseif canImport(AppKit)
        // On macOS `ASPresentationAnchor` IS an `NSWindow`, so the old
        // `ASPresentationAnchor()` fallback handed the session a bare,
        // unattached window that is never on screen — nothing for the auth
        // sheet to hang from. It had never misbehaved because it had never
        // run: macOS had no sign-in surface at all until §9.ttt, so this
        // branch existed for a platform that could not reach it.
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first
            ?? ASPresentationAnchor()
        #else
        ASPresentationAnchor()
        #endif
    }
}
#endif

// MARK: - The Twitch device flow

/// Twitch's Device Code Grant. Chosen over the implicit grant because it
/// returns a REFRESH token — the implicit grant does not, and a host who must
/// re-authorise every few hours will stop using the feature.
public struct TwitchDeviceAuth: Sendable {
    let clientID: String

    public struct Pending: Sendable {
        /// Shown to the host: "go here and enter this".
        public let verificationURI: String
        public let userCode: String
        let deviceCode: String
        let interval: TimeInterval
        public let expires: Date
    }

    public func begin(scopes: [String]) async throws -> Pending {
        var r = URLRequest(url: URL(string: "https://id.twitch.tv/oauth2/device")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [.init(name: "client_id", value: clientID),
                           .init(name: "scopes", value: scopes.joined(separator: " "))]
        r.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: r)
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let device = o["device_code"] as? String,
              let user = o["user_code"] as? String,
              let uri = o["verification_uri"] as? String else {
            throw StudioPlatformError.badResponse("Twitch would not start a device sign-in.")
        }
        return .init(verificationURI: uri, userCode: user, deviceCode: device,
                     interval: (o["interval"] as? Double) ?? 5,
                     expires: Date().addingTimeInterval((o["expires_in"] as? Double) ?? 1800))
    }

    /// What a poll answer MEANS.
    ///
    /// Extracted from `poll` so the harness can assert the rule the product
    /// actually runs, against responses measured from the live endpoint,
    /// rather than re-implementing it (Decision 119).
    public enum PollOutcome: Sendable, Equatable {
        case keepWaiting, backOff, refused(String)
    }

    /// Twitch answers EVERY poll with HTTP 400 until the host confirms.
    /// Measured 2026-09-18 against the real registration:
    ///
    ///     not yet confirmed    400  {"message":"authorization_pending"}
    ///     a dead device code   400  {"message":"invalid device code"}
    ///
    /// So the STATUS carries no information and the message is the only
    /// discriminator. This used to read `!message.contains("pending") &&
    /// http.statusCode != 400`, which kept polling on any 400 — so a denied,
    /// expired or invalid code polled every 5 s for the whole 30-minute
    /// window (360 requests at a code that could never work, the exact
    /// behaviour `poll`'s own comment says gets an app rate-limited) and then
    /// reported "the code expired", which was not what had happened.
    public static func pollOutcome(message: String) -> PollOutcome {
        let lower = message.lowercased()
        if lower.contains("authorization_pending") { return .keepWaiting }
        // RFC 8628 §3.5's back-off. NOT observed in testing — honoured
        // defensively, because a client that ignores slow_down is precisely
        // the one that gets throttled.
        if lower.contains("slow_down") { return .backOff }
        return .refused(message.isEmpty ? "Twitch refused the sign-in." : message)
    }

    /// Polls until the host confirms, at the interval Twitch asked for — a
    /// faster poll is refused, and ignoring the stated interval is how an app
    /// gets rate-limited rather than authorised.
    func poll(_ p: Pending) async throws -> StudioTokenStore.Token {
        var interval = p.interval
        while Date() < p.expires {
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            var r = URLRequest(url: URL(string: "https://id.twitch.tv/oauth2/token")!)
            r.httpMethod = "POST"
            r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var body = URLComponents()
            body.queryItems = [
                .init(name: "client_id", value: clientID),
                .init(name: "device_code", value: p.deviceCode),
                .init(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:device_code"),
            ]
            r.httpBody = body.percentEncodedQuery?.data(using: .utf8)
            let (data, resp) = try await URLSession.shared.data(for: r)
            guard let http = resp as? HTTPURLResponse,
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if (200..<300).contains(http.statusCode), let access = o["access_token"] as? String {
                let expiresIn = (o["expires_in"] as? Double) ?? 14400
                return .init(access: access, refresh: o["refresh_token"] as? String,
                             expires: Date().addingTimeInterval(expiresIn))
            }
            switch Self.pollOutcome(message: o["message"] as? String ?? "") {
            case .keepWaiting: continue
            case .backOff:     interval += 5
            case .refused(let why):
                throw StudioPlatformError.notSignedIn("Twitch refused the sign-in: \(why).")
            }
        }
        throw StudioPlatformError.notSignedIn("The Twitch code expired before it was confirmed.")
    }

    /// Twitch device-flow refresh tokens are **one time use**: each refresh
    /// returns a new one, and the old one dies. Storing the new token is not
    /// housekeeping — skip it and the host is signed out.
    func refresh(_ token: StudioTokenStore.Token) async throws -> StudioTokenStore.Token {
        guard let refresh = token.refresh else {
            throw StudioPlatformError.notSignedIn("Sign in to Twitch again.")
        }
        var r = URLRequest(url: URL(string: "https://id.twitch.tv/oauth2/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [.init(name: "client_id", value: clientID),
                           .init(name: "refresh_token", value: refresh),
                           .init(name: "grant_type", value: "refresh_token")]
        r.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: r)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let o = json, let access = o["access_token"] as? String else {
            if StudioValidationClock.refreshWasRevoked(status: (resp as? HTTPURLResponse)?.statusCode, json: json) {
                throw StudioPlatformError.grantRevoked("Twitch has ended this sign-in. Sign in again to use Twitch.")
            }
            throw StudioPlatformError.notSignedIn("Sign in to Twitch again.")
        }
        return .init(access: access,
                     refresh: o["refresh_token"] as? String ?? refresh,
                     expires: Date().addingTimeInterval((o["expires_in"] as? Double) ?? 14400))
    }
}

// MARK: - Google's device flow (the TELEVISION's YouTube sign-in)

/// YouTube on a television, signed in from a phone.
///
/// The owner, 2026-09-18: *"The sign in can make use of QR codes and signing in
/// with a phone, but you are logging in on the TV using that other device."*
/// That is this flow exactly — the phone authorises and the TOKEN lands on the
/// television — and it replaces `GoogleAuth`'s `ASWebAuthenticationSession` on
/// tvOS only. iOS and macOS keep PKCE: on a device with a keyboard a web sheet
/// is the better experience, and it needs no client secret.
///
/// **This needs a SECOND Google client**, type "TVs and Limited Input devices",
/// and Google refuses the flow for any other type — the iOS client we already
/// hold cannot do it. That client carries a **client secret**, which is the
/// cost Decision 128 named when it put this flow second and which is now paid
/// deliberately rather than by surprise. Google's own documentation for
/// installed apps is explicit that this secret is not treated as confidential;
/// it is still kept out of git, in `Secrets.xcconfig` like every other key.
///
/// Read from Google's limited-input-device documentation, 2026-09-18:
///
///     device code   POST https://oauth2.googleapis.com/device/code
///                   client_id, scope
///     poll          POST https://oauth2.googleapis.com/token
///                   client_id, client_secret, device_code,
///                   grant_type=urn:ietf:params:oauth:grant-type:device_code
///     scopes        https://www.googleapis.com/auth/youtube IS permitted
///
/// Two differences from Twitch that are easy to get wrong:
///
///  1. **Google answers with an `error` FIELD and meaningful status codes**
///     (428 `authorization_pending`, 403 `slow_down`/`access_denied`), where
///     Twitch answers 400 for everything and only its `message` discriminates.
///     So this reads `error`, and does not inherit Twitch's rule.
///  2. **Google publishes no `verification_uri_complete`** and spells the field
///     `verification_url` in its own docs while RFC 8628 says
///     `verification_uri`. Both are read, in RFC order, because a response that
///     carries neither is a response we cannot show anybody.
public struct GoogleDeviceAuth: Sendable {
    let clientID: String
    let clientSecret: String

    public struct Pending: Sendable {
        /// Shown to the host, and encoded in the QR. Unlike Twitch's, this one
        /// does NOT carry the user code — Google has no such URI — so the code
        /// beside it is load-bearing rather than a courtesy.
        public let verificationURI: String
        public let userCode: String
        let deviceCode: String
        let interval: TimeInterval
        public let expires: Date
    }

    public func begin(scopes: [String]) async throws -> Pending {
        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/device/code")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [.init(name: "client_id", value: clientID),
                           .init(name: "scope", value: scopes.joined(separator: " "))]
        r.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: r)
        // Parsed BEFORE the guard so the failure path can still read the
        // reason out of it — a `guard let` binding is not in scope in its own
        // else, and the reason is the whole point of the message below.
        let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let o,
              let device = o["device_code"] as? String,
              let user = o["user_code"] as? String,
              let uri = (o["verification_uri"] as? String) ?? (o["verification_url"] as? String)
        else {
            // SAY WHAT GOOGLE SAID. Measured against the live endpoint
            // 2026-09-18, and the reason this is not a generic sentence:
            //
            //   our real iOS client  -> invalid_client "Invalid client type."
            //   a nonexistent id     -> invalid_client "The OAuth client was not found."
            //
            // The `error` field is IDENTICAL for both, so it alone cannot tell
            // "you registered the wrong KIND of client" from "you pasted the id
            // wrong" — and those need opposite responses from whoever set it
            // up. `error_description` is the only discriminator, the same trap
            // Twitch's blanket HTTP 400 sets one endpoint over (§9.ppp).
            let why = (o?["error_description"] as? String)
                ?? (o?["error"] as? String)
                ?? "no reason given"
            throw StudioPlatformError.badResponse(
                "Google would not start a device sign-in: \(why)")
        }
        return .init(verificationURI: uri, userCode: user, deviceCode: device,
                     interval: (o["interval"] as? Double) ?? 5,
                     expires: Date().addingTimeInterval((o["expires_in"] as? Double) ?? 1800))
    }

    /// What a poll answer MEANS. Extracted so a harness can assert the rule the
    /// product runs rather than re-implementing it (Decision 119), and kept
    /// separate from Twitch's because the two platforms genuinely differ.
    public enum PollOutcome: Sendable, Equatable {
        case keepWaiting, backOff, refused(String)
    }

    public static func pollOutcome(error: String) -> PollOutcome {
        switch error {
        case "authorization_pending": return .keepWaiting
        case "slow_down":             return .backOff
        case "":                      return .keepWaiting   // unreadable body: wait, do not give up
        default:                      return .refused(error)
        }
    }

    func poll(_ p: Pending) async throws -> StudioTokenStore.Token {
        var interval = p.interval
        while Date() < p.expires {
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
            r.httpMethod = "POST"
            r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var body = URLComponents()
            body.queryItems = [
                .init(name: "client_id", value: clientID),
                .init(name: "client_secret", value: clientSecret),
                .init(name: "device_code", value: p.deviceCode),
                .init(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:device_code"),
            ]
            r.httpBody = body.percentEncodedQuery?.data(using: .utf8)
            let (data, resp) = try await URLSession.shared.data(for: r)
            guard let http = resp as? HTTPURLResponse,
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if (200..<300).contains(http.statusCode), let access = o["access_token"] as? String {
                let expiresIn = (o["expires_in"] as? Double) ?? 3600
                return .init(access: access, refresh: o["refresh_token"] as? String,
                             expires: Date().addingTimeInterval(expiresIn))
            }
            switch Self.pollOutcome(error: o["error"] as? String ?? "") {
            case .keepWaiting: continue
            case .backOff:     interval += 5
            case .refused(let code):
                // Prefer the DESCRIPTION for the same reason `begin` does: the
                // code is a category and the description is the sentence a
                // person can act on.
                let why = (o["error_description"] as? String) ?? code
                throw StudioPlatformError.notSignedIn("Google refused the sign-in: \(why)")
            }
        }
        throw StudioPlatformError.notSignedIn("The Google code expired before it was confirmed.")
    }

    /// Google's refresh tokens are NOT one-time-use the way Twitch's are, and
    /// the refresh response usually omits `refresh_token` entirely — so the
    /// stored one is carried forward rather than dropped. The secret is
    /// required here too: this token came from the TV client, and only the TV
    /// client can renew it.
    func refresh(_ token: StudioTokenStore.Token) async throws -> StudioTokenStore.Token {
        guard let refresh = token.refresh else {
            throw StudioPlatformError.notSignedIn("Sign in to YouTube again.")
        }
        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [.init(name: "client_id", value: clientID),
                           .init(name: "client_secret", value: clientSecret),
                           .init(name: "refresh_token", value: refresh),
                           .init(name: "grant_type", value: "refresh_token")]
        r.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: r)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let o = json, let access = o["access_token"] as? String else {
            if StudioValidationClock.refreshWasRevoked(status: (resp as? HTTPURLResponse)?.statusCode, json: json) {
                throw StudioPlatformError.grantRevoked("YouTube has ended this sign-in. Sign in again to use YouTube.")
            }
            throw StudioPlatformError.notSignedIn("Sign in to YouTube again.")
        }
        return .init(access: access,
                     refresh: o["refresh_token"] as? String ?? refresh,
                     expires: Date().addingTimeInterval((o["expires_in"] as? Double) ?? 3600))
    }
}

extension Data {
    /// base64url, per RFC 7636 — `+/=` are not allowed in a PKCE verifier.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
