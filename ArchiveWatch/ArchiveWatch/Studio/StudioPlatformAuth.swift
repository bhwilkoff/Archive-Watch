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

    static func save(_ token: Token, for platform: String) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: platform]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        // Not synchronised to iCloud, and readable only after first unlock:
        // this token belongs to this device's session, not to the account.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load(for platform: String) -> Token? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: platform,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Token.self, from: data)
    }

    static func clear(for platform: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service,
                       kSecAttrAccount as String: platform] as CFDictionary)
    }
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
            .init(name: "prompt", value: "consent"),
            .init(name: "state", value: state),
        ]
        return c.url!
    }

    func authorize(scopes: [String]) async throws -> StudioTokenStore.Token {
        let verifier = Self.randomVerifier()
        let state = Self.randomVerifier()
        let url = authorizeURL(scopes: scopes,
                               challenge: Self.challenge(for: verifier),
                               state: state)

        let callback = try await present(url: url, scheme: redirectScheme)
        guard let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
              let code = items.first(where: { $0.name == "code" })?.value else {
            let err = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error" })?.value
            throw StudioPlatformError.notSignedIn(err.map { "Google refused: \($0)" }
                                                  ?? "Google returned no authorisation code.")
        }
        // CSRF: a callback whose state is not the one we sent is not ours.
        guard items.first(where: { $0.name == "state" })?.value == state else {
            throw StudioPlatformError.notSignedIn("The sign-in response did not match this request.")
        }
        return try await exchange(code: code, verifier: verifier)
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
            throw StudioPlatformError.badResponse("Google would not exchange the code.")
        }
        let expiresIn = (o["expires_in"] as? Double) ?? 3600
        return .init(access: access, refresh: o["refresh_token"] as? String,
                     expires: Date().addingTimeInterval(expiresIn))
    }

    // MARK: Web session

    private func present(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { c in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback { c.resume(returning: callback) }
                else if let e = error as? ASWebAuthenticationSessionError,
                        e.code == .canceledLogin {
                    c.resume(throwing: StudioPlatformError.notSignedIn("Sign-in was cancelled."))
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
            // The television presents the flow itself, so there is no anchor
            // to hand it. This has NOT been exercised on the glass — it cannot
            // be until a client id exists — so if the TV's own screen turns
            // out to be unusable, the fallback is the same device-code flow
            // Twitch already forces (Google supports one for limited-input
            // devices), not a redesign of this file.
            session = s
            if !s.start() {
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
        let (data, _) = try await URLSession.shared.data(for: r)
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = o["access_token"] as? String else {
            // A refresh token can be revoked from the account page, and an
            // expired Google grant answers 400 — neither is recoverable here.
            throw StudioPlatformError.notSignedIn("Sign in to YouTube again.")
        }
        let expiresIn = (o["expires_in"] as? Double) ?? 3600
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

    /// Polls until the host confirms, at the interval Twitch asked for — a
    /// faster poll is refused, and ignoring the stated interval is how an app
    /// gets rate-limited rather than authorised.
    func poll(_ p: Pending) async throws -> StudioTokenStore.Token {
        while Date() < p.expires {
            try await Task.sleep(nanoseconds: UInt64(p.interval * 1_000_000_000))
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
            // "authorization_pending" is the normal case; anything else is over.
            let message = (o["message"] as? String ?? "").lowercased()
            if !message.contains("pending") && http.statusCode != 400 {
                throw StudioPlatformError.notSignedIn("Twitch refused: \(o["message"] as? String ?? "unknown")")
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
        let (data, _) = try await URLSession.shared.data(for: r)
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = o["access_token"] as? String else {
            throw StudioPlatformError.notSignedIn("Sign in to Twitch again.")
        }
        return .init(access: access,
                     refresh: o["refresh_token"] as? String ?? refresh,
                     expires: Date().addingTimeInterval((o["expires_in"] as? Double) ?? 14400))
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
