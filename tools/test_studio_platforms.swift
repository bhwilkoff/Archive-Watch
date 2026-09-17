// What can be proven about the platform clients WITHOUT a credential
// (docs/WATCH-TOGETHER.md §4, §8).
//
// Three things, and they are the three that break silently:
//
//  1. Twitch's ingest list is PUBLIC. Fetch it for real and assert the URL the
//     client derives is one the publisher can actually use — this is the only
//     part of either platform's API that needs no token, and it is also the
//     part most likely to change under us.
//  2. An unauthenticated call must fail with the PLATFORM's reason, not a
//     crash and not a silent empty result.
//  3. The auth boundary must say what is missing. A stub that returns a fake
//     token would make every caller look like it works and fail far away.
//
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -O \
//     ArchiveWatch/ArchiveWatch/Studio/StudioPlatforms.swift \
//     tools/test_studio_platforms.swift -o /tmp/awplat && /tmp/awplat

import Foundation

@main
struct PlatformTest {
    static var failures: [String] = []

    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { print("  ✓ \(label)\(detail.isEmpty ? "" : " — \(detail)")") }
        else { print("  ✗ \(label)\(detail.isEmpty ? "" : " — \(detail)")"); failures.append(label) }
    }

    static func main() async {
        setvbuf(stdout, nil, _IOLBF, 0)
        print("Watch Together Studio — platform clients, no credential used\n")

        // 1. Twitch's public ingest list, for real.
        do {
            let (primary, backup) = try await TwitchLive.ingest()
            let scheme = primary.scheme ?? ""
            check("Twitch ingest resolves", true, primary.absoluteString)
            check("ingest is RTMPS", scheme == "rtmps", scheme)
            check("ingest carries an app path, not a key placeholder",
                  !primary.absoluteString.contains("{") && (primary.path.split(separator: "/").count == 1),
                  primary.path)
            check("a backup PoP is offered", backup != nil, backup?.host ?? "none")
        } catch {
            check("Twitch ingest resolves", false, "\(error)")
        }

        // 2. An unauthenticated Helix call must carry the platform's reason.
        let twitch = TwitchLive(token: "not-a-real-token", clientID: "not-a-real-client")
        do {
            _ = try await twitch.broadcasterID()
            check("unauthenticated Twitch call is refused", false, "it succeeded")
        } catch let e as StudioPlatformError {
            if case .http(let code, let body) = e {
                check("unauthenticated Twitch call is refused", code == 401,
                      "HTTP \(code): \(body.prefix(90))")
            } else {
                check("unauthenticated Twitch call is refused", false, "\(e)")
            }
        } catch {
            check("unauthenticated Twitch call is refused", false, "\(error)")
        }

        // The same for YouTube: a bad bearer must come back as the platform's
        // 401, not as a parse failure we would mistake for our own bug.
        let yt = YouTubeLive(token: "not-a-real-token")
        do {
            _ = try await yt.prepare(title: "probe", description: "", privacy: "private")
            check("unauthenticated YouTube call is refused", false, "it succeeded")
        } catch let e as StudioPlatformError {
            if case .http(let code, let body) = e {
                check("unauthenticated YouTube call is refused", code == 401,
                      "HTTP \(code): \(body.prefix(90))")
            } else {
                check("unauthenticated YouTube call is refused", false, "\(e)")
            }
        } catch {
            check("unauthenticated YouTube call is refused", false, "\(error)")
        }

        print("")
        if failures.isEmpty {
            print("PASS: the public half is real and the authenticated half fails honestly.")
            print("      The token exchange needs client ids only the owner can register.")
            exit(0)
        }
        print("FAIL: \(failures.count)"); for f in failures { print("  • \(f)") }
        exit(1)
    }
}
