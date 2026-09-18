// §5's stream-key rule, as a regression guard.
//
// "A key is a credential — it is never logged, never written to disk, never
// put in a URL this app prints, and it does not outlive the session that
// fetched it." That rule has been broken once already: a stream key could
// reach a TELEVISION SCREEN through an error string (§9, 2026-09-17), found by
// audit rather than by anything that would have caught it again. `redactingKey`
// was the fix, and nothing has been guarding it since.
//
// The method here is a SENTINEL: every destination carries a key nobody would
// ever type by accident, and the test asserts that string appears in no
// user-visible text. That is stronger than reading the code, because it does
// not depend on knowing which paths print things — it only depends on the
// paths being exercised.
//
//   swiftc -parse-as-library \
//     ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift \
//     tools/test_studio_key_hygiene.swift -o /tmp/aw_keys && /tmp/aw_keys
//
// AND A CONTROL, because a "no leak" verdict is what a broken detector also
// returns (Decision 120): one string that MUST be caught. If the control ever
// passes silently, every other line in this file is worthless.

import Foundation

@main
struct KeyHygiene {
    /// Distinctive on purpose: a substring search for it cannot match anything
    /// a host name, an app path or an error template would legitimately carry.
    static let sentinel = "SENTINEL-live-2-xy7k9q-DO-NOT-LEAK"

    static var failures: [String] = []

    static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print(ok ? "  PASS  \(name)" : "  FAIL  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures.append(name) }
    }

    /// Never prints the offending text: a harness that leaks the key while
    /// reporting that the key leaked has not helped.
    static func refute(_ name: String, _ text: String) {
        check(name, !text.contains(sentinel), "the sentinel appears in the message")
    }

    static let config = RTMPStreamConfig(
        width: 1920, height: 1080, frameRate: 30, videoBitrate: 6_000_000,
        avcC: Data([1, 0x64, 0, 0x28]), audioSampleRate: 44_100, audioChannels: 2,
        audioBitrate: 128_000, audioSpecificConfig: Data([0x12, 0x10]))

    static func main() async {
        print("Watch Together — §5 stream-key hygiene\n")

        // THE CONTROL FIRST. If the detector cannot see a key it is looking
        // straight at, nothing below means anything.
        let raw = URL(string: "rtmps://a.rtmp.youtube.com/live2/\(sentinel)")!
        check("CONTROL — the detector CATCHES a raw destination",
              raw.absoluteString.contains(sentinel),
              "the sentinel search is broken; every other line here is void")

        print("\nredactingKey")
        refute("a key in the last path component is replaced", redactingKey(raw))
        refute("a key hiding in the QUERY is dropped",
               redactingKey(URL(string: "rtmps://a.rtmp.youtube.com/live2?key=\(sentinel)")!))
        refute("a key in a single-component path is replaced",
               redactingKey(URL(string: "rtmps://a.rtmp.youtube.com/\(sentinel)")!))
        // It must still be USEFUL. Redaction that removes the host helps
        // nobody diagnose a typo, which is why the rule says redact rather
        // than omit.
        check("...and the host survives, so the message can still be read",
              redactingKey(raw).contains("a.rtmp.youtube.com"), redactingKey(raw))

        print("\nThe publisher's own error paths, exercised (no network — each guard throws first)")

        // Entry point 1: the destination URL CARRIES the key.
        let p1 = RTMPPublisher()
        do {
            try await p1.publish(to: URL(string: "rtmps://a.rtmp.youtube.com/\(sentinel)")!,
                                 config: config, timeout: 1)
            check("publish(to:config:) refused a malformed destination", false, "it did not throw")
        } catch {
            refute("publish(to:config:) — the thrown error does not carry the key",
                   "\(error)")
        }

        // Entry point 2: the key is a SEPARATE parameter, so `redactingKey`
        // is not automatically involved — and a caller that passes a
        // key-bearing server URL is not a hypothetical, it is what entry
        // point 1 receives.
        let p2 = RTMPPublisher()
        do {
            try await p2.publish(to: URL(string: "http://a.rtmp.youtube.com/live2/\(sentinel)")!,
                                 streamKey: sentinel, config: config, timeout: 1)
            check("publish(to:streamKey:config:) refused a bad scheme", false, "it did not throw")
        } catch {
            refute("publish(to:streamKey:config:) — the thrown error does not carry the key",
                   "\(error)")
        }

        // The same entry point's OTHER guard: a destination with no app path.
        let p3 = RTMPPublisher()
        do {
            try await p3.publish(to: URL(string: "rtmps://a.rtmp.youtube.com")!,
                                 streamKey: sentinel, config: config, timeout: 1)
            check("publish(to:streamKey:config:) refused an empty app path", false, "it did not throw")
        } catch {
            refute("publish(to:streamKey:config:) — the no-app-path error does not carry the key",
                   "\(error)")
        }

        print("\nEvery RTMPPublishError case, rendered")
        for (label, e) in [
            ("badURL", RTMPPublishError.badURL(redactingKey(raw))),
            ("connectFailed", RTMPPublishError.connectFailed(redactingKey(raw))),
            ("handshakeFailed", RTMPPublishError.handshakeFailed(redactingKey(raw))),
            ("closed", RTMPPublishError.closed(redactingKey(raw))),
            ("timeout", RTMPPublishError.timeout(redactingKey(raw))),
        ] {
            refute("\(label).description is clean", e.description)
        }

        print()
        if failures.isEmpty {
            print("ALL CHECKS PASSED — no exercised path renders the stream key.")
            exit(0)
        }
        print("FAILED: \(failures.joined(separator: ", "))")
        exit(1)
    }
}
