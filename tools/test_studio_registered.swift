// The checks that could not exist until a client id was REGISTERED.
//
// `test_studio_signin.swift` proves the request shapes with credentials that
// are wrong on purpose, which is the right test to have while no account
// exists. It leaves one class of defect completely untouched: a shape the
// platform accepts in general and rejects for OUR registration — a
// `redirect_uri` the client does not declare, a client of the wrong TYPE, a
// project whose API is not enabled. Every one of those surfaces as an opaque
// error inside `ASWebAuthenticationSession`, on the owner's own account,
// mid-flow, which is the exact failure this harness family exists to prevent.
//
// So this file asks the registered client four questions, each paired with
// the control that should produce the OPPOSITE answer (Decision 130) — because
// "Google returned 200" proves nothing unless a deliberately wrong request
// returns something else.
//
//   swiftc -parse-as-library \
//     ArchiveWatch/ArchiveWatch/Studio/StudioPlatformAuth.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioPlatforms.swift \
//     tools/test_studio_registered.swift -o /tmp/aw_reg && /tmp/aw_reg
//
// Exit 2 (SKIP, never PASS) when `Secrets.xcconfig` carries no client id —
// the state every machine but the owner's is in.
//
// NOTHING here prints a client id. A client id is not a secret, but this
// output is pasted into commit messages and design docs, and one rule for
// credential-shaped strings is cheaper than an exception (§5).

import Foundation

@main
@MainActor
struct RegisteredClientHarness {
    static var failures: [String] = []

    static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print(ok ? "  PASS  \(name)" : "  FAIL  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures.append(name) }
    }

    /// The bundle id, which is the redirect scheme (Decision 128). Read from
    /// the project rather than typed, so it cannot drift: a command-line tool
    /// has no bundle identifier of its own, so `GoogleAuth.redirectScheme`
    /// would return its fallback and the harness would be asserting against
    /// its own constant.
    static let bundleID: String = {
        let plist = "ArchiveWatch/Info.plist"
        let text = (try? String(contentsOfFile: plist, encoding: .utf8)) ?? ""
        return text.contains("<string>app.archivewatch.tvos</string>")
            ? "app.archivewatch.tvos" : ""
    }()

    static func secret(_ key: String) -> String? {
        guard let text = try? String(contentsOfFile: "Secrets.xcconfig", encoding: .utf8)
        else { return nil }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == key
            else { continue }
            let v = parts[1].trimmingCharacters(in: .whitespaces)
            return v.isEmpty ? nil : v
        }
        return nil
    }

    static func main() async {
        print("Watch Together — the REGISTERED clients\n")

        guard !bundleID.isEmpty else {
            print("  the bundle id could not be read from ArchiveWatch/Info.plist")
            exit(1)
        }

        let yt = secret("YOUTUBE_CLIENT_ID")
        let tw = secret("TWITCH_CLIENT_ID")

        if yt == nil && tw == nil {
            print("SKIP — Secrets.xcconfig carries neither client id.")
            print("A skip is not a pass (§8). Once the ids exist this case must run.")
            exit(2)
        }

        let ytTV = secret("YOUTUBE_TV_CLIENT_ID")

        if let yt {
            await google(yt)
            await googleDevice(iosClientID: yt, tvClientID: ytTV)
        } else {
            print("YouTube: no YOUTUBE_CLIENT_ID — not asserted")
        }
        if let tw { await twitch(tw) } else {
            print("\nTwitch: no TWITCH_CLIENT_ID — not asserted")
        }

        print()
        if failures.isEmpty {
            print("ALL CHECKS PASSED — the registrations accept our real requests.")
            // A partial run must not read as a full one.
            if yt == nil || tw == nil || ytTV == nil {
                print("(something was not configured and was NOT asserted:"
                      + (yt == nil ? " YOUTUBE_CLIENT_ID" : "")
                      + (tw == nil ? " TWITCH_CLIENT_ID" : "")
                      + (ytTV == nil ? " YOUTUBE_TV_CLIENT_ID" : "") + ")")
                exit(2)
            }
            exit(0)
        }
        print("FAILED: \(failures.joined(separator: ", "))")
        exit(1)
    }

    // MARK: Google

    /// RFC 7636 Appendix B's published challenge. The controls MUST send a
    /// valid one: Google validates `code_challenge` BEFORE it looks at the
    /// client id or the redirect, so a literal like "CHALLENGE" makes every
    /// case fail identically with "Code Challenge must be base64 encoded" —
    /// which is what the first version of this file did, and why its two
    /// controls passed while proving nothing about the registration.
    static let rfcChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

    /// Google states the refusal in a base64url `authError` parameter on the
    /// FINAL url, never in the HTML. Both the success and failure pages are
    /// ~1 MB of script and both contain the substring "error", so a body
    /// search cannot tell them apart.
    static func authErrorText(_ finalURL: String) -> String? {
        guard let c = URLComponents(string: finalURL),
              let raw = c.queryItems?.first(where: { $0.name == "authError" })?.value
        else { return nil }
        var b64 = raw.replacingOccurrences(of: "-", with: "+")
                     .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let d = Data(base64Encoded: b64) else { return nil }
        return String(d.map { $0 >= 32 && $0 < 127 ? Character(UnicodeScalar($0)) : " " })
    }

    static func google(_ clientID: String) async {
        print("YouTube — the registered Google client (live)")

        let auth = GoogleAuth(clientID: clientID)
        let scopes = StudioPlatformAuth.scopes(for: .youtube)
        let real = auth.authorizeURL(scopes: scopes,
                                     challenge: GoogleAuth.challenge(for: GoogleAuth.randomVerifier()),
                                     state: "harness")
        check("the redirect scheme is the app's bundle id",
              real.absoluteString.contains("\(bundleID):/oauth2redirect"),
              "redirect not found in the authorize URL")

        // 1. The request the app actually opens.
        var (code, finalURL) = await get(real)
        print("        authorize:      HTTP \(code) \(landing(finalURL))")
        check("Google accepts this client AND this redirect — it serves the sign-in page",
              code == 200 && !finalURL.contains("/signin/oauth/error"),
              "HTTP \(code) \(landing(finalURL))")

        // 2. CONTROL: the same request with an unregistered client id. Same
        //    valid challenge, same redirect — the id is the ONLY difference.
        let broken = GoogleAuth(clientID: "000000-notaclient.apps.googleusercontent.com")
        (code, finalURL) = await get(broken.authorizeURL(scopes: scopes,
                                                         challenge: rfcChallenge,
                                                         state: "harness"))
        print("        bad client:     HTTP \(code) \(landing(finalURL))")
        check("CONTROL — an unregistered client id is refused as invalid_client",
              (authErrorText(finalURL) ?? "").contains("invalid_client"),
              landing(finalURL))

        // 3. CONTROL: our real client with a redirect it does not declare.
        //    This is the one that proves the registration carries our bundle
        //    id — the single thing no client id string can tell you.
        var c = URLComponents(url: auth.authorizeURL(scopes: scopes,
                                                     challenge: rfcChallenge,
                                                     state: "harness"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = (c.queryItems ?? []).map {
            $0.name == "redirect_uri"
                ? URLQueryItem(name: "redirect_uri", value: "app.archivewatch.wrong:/oauth2redirect")
                : $0
        }
        (code, finalURL) = await get(c.url!)
        print("        bad redirect:   HTTP \(code) \(landing(finalURL))")
        check("CONTROL — a redirect the client does not declare is refused as redirect_uri_mismatch",
              (authErrorText(finalURL) ?? "").contains("redirect_uri_mismatch"),
              landing(finalURL))

        // 4. The token exchange with the real client id and a junk code.
        //    `invalid_grant` means the CODE was the only thing wrong: the
        //    client, the redirect and every required field were accepted.
        //    The same request with a fake id returns `invalid_client` (§8.2).
        let text = await token(clientID: clientID, redirect: "\(bundleID):/oauth2redirect")
        print("        token:          \(summary(text))")
        let lower = text.lowercased()
        check("the token endpoint rejects the CODE, not the client",
              lower.contains("invalid_grant") && !lower.contains("invalid_client"),
              summary(text))
        check("and it does not complain about the redirect",
              !lower.contains("redirect_uri_mismatch"), summary(text))
    }

    // MARK: Twitch

    static func twitch(_ clientID: String) async {
        print("\nTwitch — the registered application (live)")

        // The device flow's first call. With a registered public client this
        // RETURNS A DEVICE CODE — a real one, which expires unused. With an
        // unregistered id it is refused, which is 8.2's case.
        var r = URLRequest(url: URL(string: "https://id.twitch.tv/oauth2/device")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "scopes", value: StudioPlatformAuth.scopes(for: .twitch)
                    .joined(separator: " ")),
        ]
        r.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        guard let (data, resp) = try? await URLSession.shared.data(for: r),
              let http = resp as? HTTPURLResponse else {
            check("the device endpoint answered", false, "no response"); return
        }
        let text = String(decoding: data, as: UTF8.self)
        print("        device: HTTP \(http.statusCode), \(summary(text))")
        check("the registered client is issued a device code",
              http.statusCode == 200 && text.contains("device_code")
              && text.contains("user_code"),
              "HTTP \(http.statusCode) \(summary(text))")
        // The scopes are the other half: a scope the application is not
        // allowed to ask for fails HERE, not at the point the stream key is
        // fetched an hour into building a show.
        check("the stream-key scope is accepted",
              !text.lowercased().contains("invalid scope")
              && !text.lowercased().contains("invalid_scope"),
              summary(text))

        // The POLL, which is what actually runs while a host is typing the
        // code into twitch.tv/activate. Twitch answers every poll with HTTP
        // 400 until they confirm, so the status cannot discriminate and the
        // message is the only signal. Both cases are exercised live, and the
        // product's own classifier judges them — not a copy of it.
        guard let device = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceCode = device["device_code"] as? String else {
            check("a device code came back to poll with", false); return
        }

        let pending = await pollMessage(clientID: clientID, deviceCode: deviceCode)
        print("        poll (real, unconfirmed): \(pending)")
        check("an unconfirmed code answers authorization_pending",
              pending.contains("authorization_pending"), pending)
        check("...and the product reads that as KEEP WAITING",
              TwitchDeviceAuth.pollOutcome(message: pending) == .keepWaiting)

        // CONTROL: a code that can never work. It answers 400 too — which is
        // why the old rule ("keep polling on any 400") could not tell the two
        // apart and polled a dead code 360 times over 30 minutes.
        let dead = await pollMessage(clientID: clientID, deviceCode: "not-a-real-device-code")
        print("        poll (dead code):        \(dead)")
        check("CONTROL — a dead device code answers something else",
              !dead.contains("authorization_pending"), dead)
        check("...and the product REFUSES rather than polling on",
              TwitchDeviceAuth.pollOutcome(message: dead) != .keepWaiting,
              "classified as keepWaiting")
    }

    /// One poll, returning Twitch's `message` verbatim.
    static func pollMessage(clientID: String, deviceCode: String) async -> String {
        var r = URLRequest(url: URL(string: "https://id.twitch.tv/oauth2/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "device_code", value: deviceCode),
            .init(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:device_code"),
        ]
        r.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        guard let (d, _) = try? await URLSession.shared.data(for: r),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else { return "<no response>" }
        return (o["message"] as? String) ?? "<no message>"
    }

    // MARK: Google's DEVICE flow — the TELEVISION's sign-in

    /// Owner direction, 2026-09-18: *"The sign in can make use of QR codes and
    /// signing in with a phone, but you are logging in on the TV using that
    /// other device."* That is Google's device flow, and this asserts the one
    /// claim the whole tvOS design now rests on — that the client we ALREADY
    /// hold cannot do it, so a second registration is required rather than
    /// merely tidier. Asserted BEFORE that client exists, which is the point
    /// of Decision 128's "prove the request shapes before the credentials".
    static func googleDevice(iosClientID: String, tvClientID: String?) async {
        print("\nGoogle — the device flow (the television's sign-in)")

        let iosDesc = await deviceCodeRefusal(clientID: iosClientID)
        check("the iOS client is refused by TYPE — which is WHY tvOS needs a second client",
              iosDesc == "Invalid client type.", iosDesc)

        // THE CONTROL, and it is load-bearing. Google answers `invalid_client`
        // for both a wrong-typed client and a nonexistent one, so the error
        // CODE cannot tell them apart — the same trap Twitch's blanket HTTP 400
        // sets. If the descriptions did not differ, the assertion above would
        // pass just as happily for an id that was simply mistyped, and would
        // prove nothing about client TYPES (Decision 120).
        let bogusDesc = await deviceCodeRefusal(
            clientID: "not-a-real-client.apps.googleusercontent.com")
        check("CONTROL — an UNKNOWN client id reads differently from a WRONG-TYPED one",
              bogusDesc == "The OAuth client was not found." && bogusDesc != iosDesc,
              bogusDesc)

        guard let tvClientID else {
            print("  YOUTUBE_TV_CLIENT_ID is absent — the television's own sign-in is NOT asserted.")
            print("  Owner step (SCRATCHPAD 7a3): a Google OAuth client of type")
            print("  \u{201C}TVs and Limited Input devices\u{201D}, which also issues a client secret.")
            return
        }

        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/device/code")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            .init(name: "client_id", value: tvClientID),
            .init(name: "scope", value: "https://www.googleapis.com/auth/youtube"),
        ]
        r.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        guard let (d, _) = try? await URLSession.shared.data(for: r),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            check("the device endpoint answered", false, "no response"); return
        }
        check("the registered TV client is issued a device code",
              o["device_code"] is String,
              summary(String(decoding: d, as: UTF8.self)))
        check("...and a user code for the host to enter on their phone",
              (o["user_code"] as? String).map { !$0.isEmpty } ?? false)
        // The product reads these two in RFC order and the second is Google's
        // own spelling; if neither is present there is nothing to put in a QR.
        let uri = (o["verification_uri"] as? String) ?? (o["verification_url"] as? String)
        check("...and a verification address, which is what the QR encodes",
              (uri?.hasPrefix("https://")) ?? false, uri ?? "<absent>")
        // Google publishes no code-bearing URI, unlike Twitch. Recorded as a
        // fact the SCREEN depends on: the code beside the QR is load-bearing
        // here, not a courtesy.
        print("  verification_uri_complete present: \(o["verification_uri_complete"] != nil)")
    }

    /// The `error_description` from a refused device-code request, which is the
    /// only field that discriminates. Never returns the client id: Google does
    /// not echo it in these two messages, and the raw body is not printed.
    static func deviceCodeRefusal(clientID: String) async -> String {
        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/device/code")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "scope", value: "https://www.googleapis.com/auth/youtube"),
        ]
        r.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        guard let (d, _) = try? await URLSession.shared.data(for: r),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else { return "<no response>" }
        if o["device_code"] is String { return "<accepted — this client CAN do the device flow>" }
        return (o["error_description"] as? String) ?? (o["error"] as? String) ?? "<no error>"
    }

    // MARK: Plumbing

    /// Returns the status and the FINAL url after redirects — which is where
    /// Google puts its answer. The body is deliberately not returned: it is a
    /// megabyte of script that reads the same either way.
    static func get(_ url: URL) async -> (Int, String) {
        var r = URLRequest(url: url)
        // Google serves a different (JS-only) page to an unknown agent; a
        // browser agent is what the app's web view sends.
        r.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                   + "(KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                   forHTTPHeaderField: "User-Agent")
        guard let (_, resp) = try? await URLSession.shared.data(for: r),
              let http = resp as? HTTPURLResponse else { return (0, "") }
        return (http.statusCode, http.url?.absoluteString ?? "")
    }

    /// Where a request LANDED, named rather than quoted — the raw url carries
    /// session identifiers and, on the error path, an encoded blob.
    static func landing(_ finalURL: String) -> String {
        if finalURL.isEmpty { return "<no response>" }
        if let e = authErrorText(finalURL) {
            for marker in ["invalid_client", "redirect_uri_mismatch", "invalid_request",
                           "access_denied", "deleted_client", "admin_policy_enforced"]
            where e.contains(marker) { return "<error: \(marker)>" }
            return "<error: unrecognised>"
        }
        if finalURL.contains("/signin/identifier") || finalURL.contains("/signin/v2/identifier") {
            return "<the sign-in page>"
        }
        if finalURL.contains("/signin/oauth/consent") { return "<the consent page>" }
        return "<no error parameter>"
    }

    static func token(clientID: String, redirect: String) async -> String {
        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "code", value: "not-a-real-code"),
            .init(name: "code_verifier", value: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "redirect_uri", value: redirect),
        ]
        r.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        guard let (data, _) = try? await URLSession.shared.data(for: r) else { return "no response" }
        return String(decoding: data, as: UTF8.self)
    }

    /// A page summary that cannot leak a client id: the id appears in Google's
    /// own error text, so the raw body is never printed.
    static func summary(_ body: String) -> String {
        let flat = body.replacingOccurrences(of: "\n", with: " ")
        for needle in ["redirect_uri_mismatch", "invalid_client", "invalid_grant",
                       "invalid_request", "unauthorized_client", "access_denied",
                       "deleted_client", "admin_policy_enforced", "device_code",
                       "invalid_scope", "Error 400", "Error 401", "Error 403"] {
            if flat.lowercased().contains(needle.lowercased()) { return "<\(needle)>" }
        }
        if flat.lowercased().contains("<html") { return "<an html page, \(flat.count) bytes>" }
        return "<\(flat.count) bytes>"
    }
}
