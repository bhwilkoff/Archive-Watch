// Proving the CREDENTIAL path's request shapes before there is a credential.
//
// Decision 128 proved the sign-in flows this way and stopped there: the auth
// half is checked, and `YouTubeLive.prepare` / `TwitchLive.prepare` — the code
// that runs the INSTANT the owner pastes two strings — has never had its
// requests looked at by anything. That is the same risk D128 was written
// about, left standing on the other half of the feature
// (docs/WATCH-TOGETHER.md §9.ddd).
//
// It compiles the REAL source rather than restating it (Decision 119):
//
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -O \
//     ArchiveWatch/ArchiveWatch/Studio/StudioPlatformAuth.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioPlatforms.swift \
//     tools/test_studio_live_shapes.swift -o /tmp/awshapes && /tmp/awshapes
//
// THE DISCRIMINATOR: a platform that rejects our CREDENTIAL (401/403) has
// accepted our REQUEST. A platform that rejects the request itself answers
// differently — 400 for a malformed body, 404 for a wrong path — so the status
// code separates "the shape is right, the token is fake" from "the shape is
// wrong". Anything else is reported rather than judged.
//
// AND THE CONTROLS, because a check that cannot fail proves nothing
// (Decision 120, and §9.oo which ran a "control" that could not reach its own
// dial): one request that must SUCCEED, so a 401 elsewhere is not merely "no
// network", and one that must FAIL, so the harness is known to notice.

import Foundation

@main
struct LiveShapes {
    nonisolated(unsafe) static var pass = 0
    nonisolated(unsafe) static var fail = 0

    static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if ok { pass += 1; print("  PASS  \(name)") }
        else  { fail += 1; print("  FAIL  \(name)\(detail.isEmpty ? "" : " — \(detail)")") }
    }

    static func main() async {
        print("=== Watch Together: live-platform request shapes ===\n")
        await controls()
        await twitchIngest()
        await youTubeShape()
        await twitchShape()
        print("\npass=\(pass) fail=\(fail)")
        exit(fail == 0 ? 0 : 1)
    }

    // MARK: controls — the harness must be able to say both things

    static func controls() async {
        print("-- controls")
        // URLSession directly, not our own `HTTP`: these controls are about
        // the ENVIRONMENT — is the network up, and can this harness tell a
        // success from a failure at all — so they must not depend on the code
        // under test to answer.
        func status(_ u: String) async -> Int? {
            guard let url = URL(string: u) else { return nil }
            return try? await (URLSession.shared.data(from: url).1 as? HTTPURLResponse)?.statusCode
        }
        let ok = await status("https://ingest.twitch.tv/ingests")
        check("a request that must SUCCEED does", ok == 200, "\(ok.map(String.init) ?? "no response")")
        let bad = await status("https://ingest.twitch.tv/aw-no-such-path")
        check("a request that must FAIL does", (bad ?? 0) >= 400, "\(bad.map(String.init) ?? "no response")")
        check("and the two answers DIFFER", ok != bad, "both \(ok.map(String.init) ?? "nil")")
    }

    // MARK: Twitch's ingest list — no credential needed, so fully checkable

    static func twitchIngest() async {
        print("\n-- Twitch ingest list (no credential required)")
        do {
            let (primary, backup) = try await TwitchLive.ingest()
            check("an ingest server is returned", true, primary.absoluteString)
            check("it is RTMPS, not RTMP", primary.scheme == "rtmps", primary.scheme ?? "nil")
            check("the {stream_key} placeholder is stripped",
                  !primary.absoluteString.contains("{stream_key}"), primary.absoluteString)
            // NOT `twitch.tv`. Twitch's ingest PoPs answer on
            // **live-video.net** (e.g. ingest.global-contribute.live-video.net)
            // and the API host is the only twitch.tv name in this flow. The
            // first version of this check asserted twitch.tv and failed
            // against correct code — an expectation invented by the test, not
            // a defect. Anyone "fixing" the host to twitch.tv would break the
            // broadcast (§9.ddd).
            let host = primary.host ?? ""
            check("the host is one Twitch actually serves ingest from",
                  host.hasSuffix("live-video.net") || host.hasSuffix("twitch.tv"), host)
            if let backup {
                check("the backup is also RTMPS", backup.scheme == "rtmps", backup.scheme ?? "nil")
                check("the backup is a DIFFERENT server", backup != primary)
            } else {
                print("  note  Twitch listed only one ingest; backup is nil, which is allowed")
            }
        } catch {
            check("an ingest server is returned", false, "\(error)")
        }
    }

    // MARK: the two prepare() paths, with deliberately invalid credentials

    static func youTubeShape() async {
        print("\n-- YouTube liveStreams/liveBroadcasts request shape")
        do {
            _ = try await YouTubeLive(token: "aw-deliberately-invalid").prepare(
                title: "Archive Watch shape check",
                description: "not a real broadcast",
                privacy: "private")
            check("YouTube rejected the fake token", false, "it ACCEPTED it — investigate")
        } catch let StudioPlatformError.http(status, body) {
            check("YouTube answered the request (credential rejected, not shape)",
                  status == 401 || status == 403, "HTTP \(status): \(oneLine(body))")
            check("the body names an auth problem, not a field problem",
                  looksLikeAuth(body), oneLine(body))
        } catch {
            check("YouTube answered the request (credential rejected, not shape)",
                  false, "\(error)")
        }
    }

    static func twitchShape() async {
        print("\n-- Twitch helix request shape")
        do {
            _ = try await TwitchLive(token: "aw-deliberately-invalid",
                                     clientID: "aw-deliberately-invalid").broadcasterID()
            check("Twitch rejected the fake token", false, "it ACCEPTED it — investigate")
        } catch let StudioPlatformError.http(status, body) {
            check("Twitch answered the request (credential rejected, not shape)",
                  status == 401 || status == 403, "HTTP \(status): \(oneLine(body))")
            check("the body names an auth problem, not a field problem",
                  looksLikeAuth(body), oneLine(body))
        } catch {
            check("Twitch answered the request (credential rejected, not shape)",
                  false, "\(error)")
        }
    }

    // MARK: helpers

    static func oneLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ").prefix(150).description
    }

    /// An auth refusal names the CREDENTIAL. A shape refusal names a FIELD
    /// ("required parameter", "invalid value for"), which is the answer this
    /// harness exists to catch.
    static func looksLikeAuth(_ body: String) -> Bool {
        let b = body.lowercased()
        let auth = ["unauthenticated", "unauthorized", "invalid oauth", "invalid access token",
                    "authentication", "credential", "login required", "invalid token",
                    "client id", "forbidden", "insufficient"]
        let shape = ["required parameter", "missing required", "invalid value",
                     "unknown part", "parse error", "badrequest"]
        return auth.contains(where: b.contains) && !shape.contains(where: b.contains)
    }
}
