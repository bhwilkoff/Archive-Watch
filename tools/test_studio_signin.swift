// Proving the sign-in flows BEFORE there is a client id to try them with.
//
// The owner's remaining work on Watch Together is pasting two strings into
// Secrets.xcconfig. The risk that creates is obvious: the moment those strings
// exist, any defect in the request shapes surfaces as an opaque platform
// error, on the owner's account, in a flow that cannot be stepped through.
// So everything that does NOT depend on the client id is checked now.
//
// It compiles the REAL source files rather than restating their logic — a
// harness that re-implements what it tests asserts nothing (Decision 119).
//
//   swiftc -parse-as-library \
//     ArchiveWatch/ArchiveWatch/Studio/StudioPlatformAuth.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioPlatforms.swift \
//     tools/test_studio_signin.swift -o /tmp/aw_signin && /tmp/aw_signin
//
// The live checks send DELIBERATELY invalid credentials to the real endpoints.
// That is the whole point: a platform that rejects our CREDENTIAL has accepted
// our REQUEST, and the two failures read completely differently. "missing
// required parameter" means the shape is wrong and would still be wrong with a
// real client id; "invalid client" means everything but the string is right.

import Foundation

@main
@MainActor
struct SignInHarness {
    static var failures: [String] = []

    static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print(ok ? "  PASS  \(name)" : "  FAIL  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures.append(name) }
    }

    static func main() async {
        print("Watch Together — sign-in request shapes\n")

        pkce()
        googleAuthorizeURL()
        redirectScheme()
        await twitchDeviceShape()
        await googleTokenShape()
        await negativeControl()

        print()
        if failures.isEmpty {
            print("ALL CHECKS PASSED — the flows are correct up to the client ids.")
            exit(0)
        }
        print("FAILED: \(failures.joined(separator: ", "))")
        exit(1)
    }

    // MARK: PKCE, against RFC 7636's own test vector

    /// This is the one check with a genuinely INDEPENDENT reference: RFC 7636
    /// Appendix B publishes a verifier and the challenge it must produce. A
    /// golden file generated from this code would prove nothing; the RFC was
    /// written before it.
    static func pkce() {
        print("PKCE (RFC 7636 Appendix B)")
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expected = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        let got = GoogleAuth.challenge(for: verifier)
        check("S256 challenge matches the RFC vector", got == expected, "got \(got)")

        // A verifier carrying +, / or = is rejected by the authorization
        // server, and base64 produces all three. 200 draws are enough that a
        // 64-byte encoding would have to be extraordinarily lucky to hide one.
        var clean = true, lengthsOK = true
        var seen = Set<String>()
        for _ in 0..<200 {
            let v = GoogleAuth.randomVerifier()
            if v.contains("+") || v.contains("/") || v.contains("=") { clean = false }
            // RFC 7636 §4.1: 43–128 characters.
            if v.count < 43 || v.count > 128 { lengthsOK = false }
            seen.insert(v)
        }
        check("200 verifiers are base64url-clean", clean)
        check("200 verifiers are 43–128 characters", lengthsOK)
        check("200 verifiers are all distinct", seen.count == 200, "\(seen.count) unique")
    }

    // MARK: The authorization request

    static func googleAuthorizeURL() {
        print("\nGoogle authorization URL")
        let auth = GoogleAuth(clientID: "123-abc.apps.googleusercontent.com")
        let url = auth.authorizeURL(scopes: ["https://www.googleapis.com/auth/youtube"],
                                    challenge: "CHALLENGE", state: "STATE")
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func v(_ n: String) -> String? { q.first { $0.name == n }?.value }

        check("host is accounts.google.com", url.host == "accounts.google.com", url.host ?? "nil")
        check("response_type=code", v("response_type") == "code")
        check("code_challenge_method=S256", v("code_challenge_method") == "S256")
        check("the challenge is carried", v("code_challenge") == "CHALLENGE")
        check("state is carried", v("state") == "STATE")
        // Without access_type=offline Google returns NO refresh token, and the
        // host re-authorises every hour — the failure would not appear until
        // an hour into a broadcast.
        check("access_type=offline (or there is no refresh token)", v("access_type") == "offline")
        // `prompt` MUST NAME select_account, and this case asserted the
        // opposite until 2026-09-20.
        //
        // It asserted `prompt == "consent"`, which is what the app sent until
        // 2026-09-18 and is the DEFECT: `consent` re-shows the consent screen
        // for the account Google has ALREADY chosen and never offers the Brand
        // Account chooser. The owner's first YouTube broadcast therefore went
        // to their personal channel, and "sign out and sign in again to pick
        // another" could not work — a sign-out/sign-in returned the same
        // channel in 42 seconds. `select_account consent` fixes it.
        //
        // So this case has been failing since the day the bug was fixed,
        // against the fix. Nobody saw it because nobody ran the suite.
        let prompt = v("prompt") ?? ""
        check("prompt asks for the account chooser (select_account)",
              prompt.contains("select_account"), prompt)
        check("and still forces consent, or there is no refresh token",
              prompt.contains("consent"), prompt)
        // CONTROL: the value this used to require must NOT satisfy the check
        // above, or the check cannot tell the fix from the bug.
        check("CONTROL: bare \"consent\" would fail the chooser assertion",
              !"consent".contains("select_account"))
        check("scope is the YouTube scope", v("scope") == "https://www.googleapis.com/auth/youtube")
        // No secret may ever appear in a URL the app builds.
        check("no client_secret anywhere in the URL",
              !url.absoluteString.lowercased().contains("secret"))
    }

    /// The scheme is the bundle identifier, and it MUST be declared in
    /// Info.plist or `ASWebAuthenticationSession` refuses to start. So the
    /// check that matters is not the string this harness computes (its own
    /// bundle id is not the app's) — it is that the app's Info.plist declares
    /// whatever the app's bundle id is. Both are asserted.
    static func redirectScheme() {
        print("\nThe redirect scheme")
        let auth = GoogleAuth(clientID: "123456-abcdef.apps.googleusercontent.com")
        // Independent of the client id — which is the whole point of the
        // choice, since Info.plist is written before any client id exists.
        let other = GoogleAuth(clientID: "999-zzz.apps.googleusercontent.com")
        check("the scheme does not depend on the client id",
              auth.redirectScheme == other.redirectScheme, auth.redirectScheme)
        check("the redirect URI appends the path",
              auth.redirectURI == "\(auth.redirectScheme):/oauth2redirect", auth.redirectURI)

        // Info.plist, read from the source of truth for the shipped app.
        let plist = "ArchiveWatch/Info.plist"
        let text = (try? String(contentsOfFile: plist, encoding: .utf8)) ?? ""
        check("Info.plist was readable", !text.isEmpty, plist)
        check("Info.plist declares the app's bundle id as a URL scheme",
              text.contains("<string>app.archivewatch.tvos</string>"))
        check("Info.plist still declares the archivewatch deep-link scheme",
              text.contains("<string>archivewatch</string>"))
        check("Info.plist carries YOUTUBE_CLIENT_ID", text.contains("YOUTUBE_CLIENT_ID"))
        check("Info.plist carries TWITCH_CLIENT_ID", text.contains("TWITCH_CLIENT_ID"))
    }

    /// The live checks above assert that the platforms complain about the
    /// CREDENTIAL rather than the SHAPE. That discriminator is worthless
    /// unless a genuinely wrong shape trips it — a guard on a rule's
    /// consequence is not a guard on the rule (Decision 120). So: send
    /// Google the same request with `grant_type` removed, and require the
    /// answer to look DIFFERENT.
    static func negativeControl() async {
        print("\nNegative control (a deliberately malformed request)")
        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            .init(name: "client_id", value: "000000-aaaa.apps.googleusercontent.com"),
            .init(name: "code", value: "not-a-real-code"),
            // grant_type omitted on purpose.
        ]
        r.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        guard let (data, _) = try? await URLSession.shared.data(for: r) else {
            check("the endpoint answered", false, "no response"); return
        }
        let lower = String(decoding: data, as: UTF8.self).lowercased()
        print("        \(lower.prefix(160))")
        check("a missing grant_type is reported as a REQUEST fault",
              lower.contains("invalid_request") || lower.contains("unsupported_grant_type")
              || lower.contains("missing"),
              lower.prefix(160).description)
        check("and it does NOT read as invalid_client, so the discriminator discriminates",
              !lower.contains("invalid_client"))
    }

    // MARK: Live shape checks against the real endpoints

    /// Twitch's device endpoint with a deliberately invalid client id.
    static func twitchDeviceShape() async {
        print("\nTwitch device flow (live, invalid client id on purpose)")
        var r = URLRequest(url: URL(string: "https://id.twitch.tv/oauth2/device")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [.init(name: "client_id", value: "0000000000000000000000000000000"),
                           .init(name: "scopes", value: "channel:read:stream_key channel:manage:broadcast")]
        r.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        guard let (data, resp) = try? await URLSession.shared.data(for: r),
              let http = resp as? HTTPURLResponse else {
            check("the endpoint answered", false, "no response")
            return
        }
        let text = String(decoding: data, as: UTF8.self)
        print("        \(http.statusCode): \(text.prefix(200))")
        let lower = text.lowercased()
        // The discriminator. A missing-parameter complaint means our request
        // would be wrong with a real client id too.
        check("the endpoint exists (not 404)", http.statusCode != 404)
        check("Twitch rejects the CREDENTIAL, not the request shape",
              !lower.contains("missing") && !lower.contains("must be provided")
              && !lower.contains("invalid scope") && !lower.contains("unsupported"),
              text.prefix(160).description)
    }

    /// Google's token endpoint with an invalid client id and a junk code.
    static func googleTokenShape() async {
        print("\nGoogle token exchange (live, invalid client id on purpose)")
        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            .init(name: "client_id", value: "000000-aaaa.apps.googleusercontent.com"),
            .init(name: "code", value: "not-a-real-code"),
            .init(name: "code_verifier", value: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "redirect_uri", value: "com.googleusercontent.apps.000000-aaaa:/oauth2redirect"),
        ]
        r.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        guard let (data, resp) = try? await URLSession.shared.data(for: r),
              let http = resp as? HTTPURLResponse else {
            check("the endpoint answered", false, "no response")
            return
        }
        let text = String(decoding: data, as: UTF8.self)
        print("        \(http.statusCode): \(text.prefix(200))")
        let lower = text.lowercased()
        check("the endpoint exists (not 404)", http.statusCode != 404)
        // `invalid_client` / `invalid_grant` = the form was parsed and every
        // required field was present. `invalid_request` names a MISSING one.
        check("Google rejects the credential, not the request shape",
              lower.contains("invalid_client") || lower.contains("invalid_grant")
              || lower.contains("unauthorized_client"),
              text.prefix(160).description)
    }
}
