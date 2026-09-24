// §8.62 — a reconnect is not killed by news from the connection it replaced
// (launch audit B). Publish to a local server, then reconnect five times back
// to back: each reconnect cancels the old connection, whose ".cancelled"
// arrives while the new one is mid-handshake. Before the fix that stale news
// marked the NEW connection failed and threw its publish away.
import Foundation
import CoreVideo

@main struct ReconnectStaleTest {
    static func main() async {
        let url = URL(string: CommandLine.arguments[1])!
        let enc = H264Encoder(width: 640, height: 360, frameRate: 30, bitrate: 1_000_000)
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 640, 360, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &pb)
        guard (try? enc.start()) != nil,
              let avcC = try? await enc.encodeAndAwaitFormat(pb!) else { print("FAIL no avcC"); exit(1) }
        let cfg = RTMPStreamConfig(width: 640, height: 360, frameRate: 30, videoBitrate: 1_000_000,
                                   avcC: avcC, audioSampleRate: 44_100, audioChannels: 1, audioBitrate: 96_000,
                                   audioSpecificConfig: StudioEngine.audioSpecificConfig(sampleRate: 44_100, channels: 1))
        let pub = RTMPPublisher()
        do { try await pub.publish(to: url, config: cfg, timeout: 5) } catch { print("FAIL first publish: \(error)"); exit(1) }
        var ok = 0, failed = 0
        for i in 1...5 {
            do { try await pub.reconnect(timeout: 5); ok += 1 }
            catch { failed += 1; print("  reconnect \(i) failed: \(error)") }
            try? await Task.sleep(nanoseconds: 300_000_000)   // let the old connection's news arrive
            let st = await pub.health.state
            if st != .publishing { print("  after reconnect \(i) the state is \(st)") }
        }
        let final = await pub.health.state
        print("  reconnects ok=\(ok) failed=\(failed), final state \(final)")
        await pub.close()
        let pass = ok == 5 && final == .publishing
        print(pass ? "PASS" : "FAIL"); exit(pass ? 0 : 1)
    }
}
