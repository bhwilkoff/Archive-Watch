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

        if let yt { await google(yt) } else {
            print("YouTube: no YOUTUBE_CLIENT_ID — not asserted")
        }
        if let tw { await twitch(tw) } else {
            print("\nTwitch: no TWITCH_CLIENT_ID — not asserted")
        }

        print()
        if failures.isEmpty {
            print("ALL CHECKS PASSED — the registrations accept our real requests.")
            // A partial run must not read as a full one.
            if yt == nil || tw == nil {
                print("(one platform was not configured and was NOT asserted)")
                exit(2)
            }
            exit(0)
        }
        print("FAILED: \(failures.joined(separator: ", "))")
        exit(1)
    }

    // MARK: Google

    static func google(_ clientID: String) async {
        print("YouTube — the registered Google client (live)")

        // 1. The authorization URL the app actually builds, with the real
        //    client id and the real redirect. This is the request
        //    `ASWebAuthenticationSession` opens, and the first thing a host
        //    would ever see.
        let auth = GoogleAuth(clientID: clientID)
        var url = auth.authorizeURL(scopes: StudioPlatformAuth.scopes(for: .youtube),
                                    challenge: GoogleAuth.challenge(for: GoogleAuth.randomVerifier()),
                                    state: "harness")
        // The harness has no bundle id, so the URL it built carries the
        // fallback. Assert they agree rather than silently testing a string
        // this file chose.
        check("the redirect scheme is the app's bundle id",
              url.absoluteString.contains("\(bundleID):/oauth2redirect"),
              "redirect not found in the authorize URL")

        var (code, body) = await get(url)
        print("        authorize: HTTP \(code), \(summary(body))")
        check("Google serves the consent flow for this client (not an error page)",
              code == 200 && !body.lowercased().contains("invalid_client")
              && !body.lowercased().contains("redirect_uri_mismatch"),
              "HTTP \(code) \(summary(body))")

        // 2. CONTROL: the same request with the client id mangled must be
        //    refused. Without this, check 1 is satisfied by any 200.
        let broken = GoogleAuth(clientID: "000000-notaclient.apps.googleusercontent.com")
        url = broken.authorizeURL(scopes: StudioPlatformAuth.scopes(for: .youtube),
                                  challenge: "CHALLENGE", state: "harness")
        (code, body) = await get(url)
        print("        control (bad client): HTTP \(code), \(summary(body))")
        check("CONTROL — an unregistered client id is refused",
              code != 200 || body.lowercased().contains("invalid_client")
              || body.lowercased().contains("error"),
              "HTTP \(code) \(summary(body))")

        // 3. CONTROL: the real client id with a redirect it does not declare
        //    must fail on the REDIRECT. This is the check that proves the
        //    registration carries our bundle id — the one thing that cannot
        //    be inferred from the client id string.
        var c = URLComponents(url: auth.authorizeURL(
            scopes: StudioPlatformAuth.scopes(for: .youtube),
            challenge: "CHALLENGE", state: "harness"),
            resolvingAgainstBaseURL: false)!
        c.queryItems = (c.queryItems ?? []).map {
            $0.name == "redirect_uri"
                ? URLQueryItem(name: "redirect_uri", value: "app.archivewatch.wrong:/oauth2redirect")
                : $0
        }
        (code, body) = await get(c.url!)
        print("        control (bad redirect): HTTP \(code), \(summary(body))")
        check("CONTROL — a redirect the client does not declare is refused",
              code != 200 || body.lowercased().contains("redirect_uri_mismatch")
              || body.lowercased().contains("error"),
              "HTTP \(code) \(summary(body))")

        // 4. The token exchange with the real client id and a junk code.
        //    `invalid_grant` means the CODE was the only thing wrong: the
        //    client, the redirect and every required field were accepted.
        //    `invalid_client` would mean the id itself is not usable here —
        //    which is what the same request returns with a fake id (8.2).
        let text = await token(clientID: clientID, redirect: "\(bundleID):/oauth2redirect")
        print("        token: \(summary(text))")
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
    }

    // MARK: Plumbing

    static func get(_ url: URL) async -> (Int, String) {
        var r = URLRequest(url: url)
        // Google serves a different (JS-only) page to an unknown agent; a
        // browser agent is what the app's web view sends.
        r.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                   + "(KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                   forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: r),
              let http = resp as? HTTPURLResponse else { return (0, "no response") }
        return (http.statusCode, String(decoding: data, as: UTF8.self))
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
