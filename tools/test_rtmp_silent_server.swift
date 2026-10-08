// A server that ACCEPTS and then says nothing must not hang Go Live.
// (Cross-platform review, 2026-09-28: the publisher's withTimeout raced its
// step in a task group, which waits for a child that ignores cancellation —
// the Creation Studio's Export hung on exactly that shape, Mac loop v1.42.807.)
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -O ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift tools/harness_awdiag.swift \
//     tools/test_rtmp_silent_server.swift -o /tmp/awsilent && /tmp/awsilent
//
// Exit 0 = the publish failed within the timeout plus a margin. The listener
// accepts every connection and never writes, so the handshake waits forever
// unless the timeout ends it.

import Foundation
import Network

@main
struct SilentServerTest {
    static func main() async {
        let listener = try! NWListener(using: .tcp, on: .any)
        final class Held: @unchecked Sendable { var conns: [NWConnection] = [] }
        let held = Held()
        listener.newConnectionHandler = { c in held.conns.append(c); c.start(queue: .main) }   // accept, say nothing
        listener.start(queue: .main)
        // Wait for READY: before it, `port` reads 0, and a publish to port 0
        // fails at once and "passes" without ever meeting a silent server
        // (the first run of this test did exactly that).
        var waited = 0
        while (listener.state != .ready || (listener.port?.rawValue ?? 0) == 0) && waited < 100 {
            try? await Task.sleep(nanoseconds: 50_000_000); waited += 1
        }
        guard let port = listener.port?.rawValue, port != 0 else { print("SKIP: listener never ready"); exit(2) }
        print("silent server on port \(port)")
        let timeout: TimeInterval = 3
        // The watchdog is the verdict when the bug is present: nothing else returns.
        DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
            print("FAIL: publish to a silent server was still waiting after 20 s (timeout \(Int(timeout)) s)")
            exit(1)
        }
        let config = RTMPStreamConfig(width: 1280, height: 720, frameRate: 30, videoBitrate: 2_500_000,
            avcC: Data([1, 0x64, 0, 0x1f, 0xff, 0xe1, 0, 0]), audioSampleRate: 44_100, audioChannels: 2,
            audioBitrate: 128_000, audioSpecificConfig: Data([0x12, 0x10]))
        let started = Date()
        do {
            try await RTMPPublisher().publish(to: URL(string: "rtmp://127.0.0.1:\(port)/live/bench")!,
                                              config: config, timeout: timeout)
            print("FAIL: a silent server was treated as a publish"); exit(1)
        } catch {
            let took = Date().timeIntervalSince(started)
            print(String(format: "publish gave up after %.1f s — %@", took, "\(error)"))
            // Control: it must have actually connected (a connect failure is
            // not the case under test).
            guard !held.conns.isEmpty else { print("FAIL: never connected — not the case under test"); exit(1) }
            if took <= timeout + 3 { print("PASS"); exit(0) }
            print("FAIL: gave up, but only after \(Int(took)) s"); exit(1)
        }
    }
}
