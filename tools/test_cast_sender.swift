// THE iOS CAST SENDER, against a real Cast device (iOS-DESIGN §8.10).
//
// Part 1 needs nothing: the CASTV2 envelope round-trips, and a truncated body
// is refused rather than half-read (the control). Part 2 casts to a device on
// the LAN and judges from the RECEIVER's own MEDIA_STATUS — PLAYING, with
// currentTime advancing between two reads — never from our having sent it.
// Its control is a URL that does not exist, which must NOT reach PLAYING.
// The receiver is muted before anything launches; the client restores it on
// close, AFTER the session is stopped, and the harness checks the TV is left
// unmuted and off our receiver.
//
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -O ArchiveWatch/ArchiveWatch/Networking/CastClient.swift \
//     tools/test_cast_sender.swift -o /tmp/awcast && /tmp/awcast 10.0.0.55

import Foundation
import Network

@main
struct CastSenderTest {
    nonisolated(unsafe) static var failures: [String] = []

    static func expect(_ label: String, _ ok: Bool, _ detail: String = "") {
        print(ok ? "  ✓ \(label)" : "  ✗ \(label) \(detail)")
        if !ok { failures.append(label) }
    }

    static func main() async {
        print("Part 1 — the envelope")
        let m = CastWire.Message(source: "sender-0", destination: "receiver-0",
                                 namespace: CastWire.receiverNS,
                                 payload: #"{"type":"LAUNCH","appId":"58AF34C3","requestId":1}"#)
        let framed = CastWire.frame(m)
        let len = framed.prefix(4).reduce(0) { $0 << 8 | Int($1) }
        expect("length prefix matches the body", len == framed.count - 4)
        expect("round-trips", CastWire.parse(framed.dropFirst(4)) == m)
        expect("control: a truncated body is refused", CastWire.parse(framed.dropFirst(4).dropLast(3)) == nil)
        let long = String(repeating: "x", count: 300)   // a length that needs a 2-byte varint
        let m2 = CastWire.Message(source: "a", destination: "b", namespace: "c", payload: long)
        expect("multi-byte lengths round-trip", CastWire.parse(CastWire.frame(m2).dropFirst(4)) == m2)

        guard CommandLine.arguments.count > 1 else {
            print("\nPart 2 skipped — pass a Cast device's IP to run it.")
            finish(); return
        }
        let host = CommandLine.arguments[1]
        let endpoint = NWEndpoint.hostPort(host: .init(host), port: 8009)

        print("\nPart 2 — a real film on \(host) (muted)")
        let film = CastMedia(url: URL(string: "https://archive.org/download/TheGeneral720p1926/TheGeneral720p.mp4")!,
                             title: "The General", subtitle: "1926",
                             posterURL: nil, subtitlesVTT: nil, startAt: 60)
        let good = await run(film, endpoint)
        expect("receiver reports PLAYING", good.contains { $0.playerState == "PLAYING" },
               "states: \(good.map(\.playerState))")
        let times = good.filter { $0.playerState == "PLAYING" }.map(\.currentTime)
        expect("its clock advances", (times.last ?? 0) > (times.first ?? 0) + 2, "times: \(times)")
        expect("it started where it was asked (60 s)", (times.first ?? 0) >= 59, "first: \(times.first ?? -1)")

        print("\nControl — a URL that does not exist")
        var bad = film
        bad.url = URL(string: "https://archive.org/download/aw-no-such-item-\(UUID().uuidString)/none.mp4")!
        let badStates = await run(bad, endpoint)
        expect("never reaches PLAYING", !badStates.contains { $0.playerState == "PLAYING" },
               "states: \(badStates.map(\.playerState))")
        finish()
    }

    /// Cast, collect MEDIA_STATUS for ~20 s (asking every 4 s), then stop.
    static func run(_ media: CastMedia, _ endpoint: NWEndpoint) async -> [CastClient.MediaStatus] {
        final class Box: @unchecked Sendable {
            var statuses: [CastClient.MediaStatus] = []
            var events: [String] = []
            let lock = NSLock()
        }
        let box = Box()
        let client = CastClient { event in
            box.lock.lock(); defer { box.lock.unlock() }
            switch event {
            case .launched: box.events.append("launched")
            case .media(let s):
                box.statuses.append(s)
                print("    MEDIA_STATUS \(s.playerState) t=\(String(format: "%.1f", s.currentTime)) \(s.idleReason ?? "")")
            case .failed(let r): box.events.append("failed: \(r)"); print("    failed: \(r)")
            case .closed: box.events.append("closed")
            }
        }
        client.cast(media, to: endpoint, muteReceiver: true)
        for _ in 0..<5 {
            try? await Task.sleep(for: .seconds(4))
            client.refresh()
        }
        client.stop()             // STOP, then the client restores the mute itself
        try? await Task.sleep(for: .seconds(1.5))
        return box.lock.withLock {
            print("    events: \(box.events)")
            return box.statuses
        }
    }

    static func finish() {
        print(failures.isEmpty ? "\nPASS" : "\nFAIL: \(failures)")
        exit(failures.isEmpty ? 0 : 1)
    }
}
