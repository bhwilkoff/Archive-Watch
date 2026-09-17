// DOES OUR PUBLISHER REACH THE REAL PLATFORMS? (WATCH-TOGETHER §8.1's
// negative control, extended to the destinations that matter.)
//
// This proves everything about the transport EXCEPT a valid stream key, and it
// needs no credential at all — which is the point. A deliberately invalid key
// exercises the whole chain against the actual ingest hosts:
//
//   DNS → TCP → TLS (for rtmps) → C0/C1/C2 handshake → AMF0 connect →
//   createStream → publish → the server's REFUSAL, with its own reason.
//
// A stream key is a credential. It does not belong in a test, a log, a
// transcript or this repository, and nothing here needs one: if `connect`
// succeeds and `publish` is refused by name, the only untested step is whether
// a good key is accepted — and that is what the go-live sheet does, once, with
// a key fetched by OAuth'd API (§4).
//
// PASS means: every destination completed `connect` and then refused the bad
// key with a named reason. A TLS failure, a handshake failure, or a hang is a
// FAIL — those are ours. A refusal is the server working correctly.
//
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -O \
//     ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift \
//     tools/test_rtmp_destinations.swift -o /tmp/awdest && /tmp/awdest

import CoreMedia
import Foundation

@main
struct DestinationTest {

    struct Target {
        let name: String
        let server: String
        let key: String
    }

    /// The published ingest endpoints. Twitch's host comes from its own
    /// `ingest.twitch.tv/ingests` list; YouTube's are documented constants.
    static let probeKey = "aw-invalid-key-probe"
    static let targets: [Target] = [
        Target(name: "YouTube primary (RTMPS, 443)",
               server: "rtmps://a.rtmps.youtube.com/live2", key: probeKey),
        Target(name: "YouTube primary (RTMP, 1935)",
               server: "rtmp://a.rtmp.youtube.com/live2", key: probeKey),
        Target(name: "YouTube backup (RTMPS, 443)",
               server: "rtmps://b.rtmps.youtube.com/live2?backup=1", key: probeKey),
        Target(name: "Twitch global (RTMPS, 443)",
               server: "rtmps://ingest.global-contribute.live-video.net/app", key: "live_invalid_probe"),
        Target(name: "Twitch global (RTMP, 1935)",
               server: "rtmp://ingest.global-contribute.live-video.net/app", key: "live_invalid_probe"),
    ]

    /// A minimal but VALID stream configuration. The servers inspect the
    /// sequence headers, so a nonsense avcC can be refused for the wrong
    /// reason — this is a real Baseline 1080p30 avcC and a real AAC-LC ASC.
    static var config: RTMPStreamConfig {
        // avcC: version 1, profile 66 (Baseline), compat 0, level 40,
        // lengthSizeMinusOne 3, 1 SPS, 1 PPS (minimal valid NALs).
        let sps: [UInt8] = [0x67, 0x42, 0x00, 0x28, 0xE9, 0x00, 0x80, 0x0C, 0x8B, 0x01, 0x00, 0x00, 0x03, 0x00, 0x01]
        let pps: [UInt8] = [0x68, 0xCE, 0x3C, 0x80]
        var avcC: [UInt8] = [0x01, 0x42, 0x00, 0x28, 0xFF, 0xE1]
        avcC += [UInt8(sps.count >> 8), UInt8(sps.count & 0xFF)] + sps
        avcC += [0x01, UInt8(pps.count >> 8), UInt8(pps.count & 0xFF)] + pps
        return RTMPStreamConfig(
            width: 1920, height: 1080, frameRate: 30, videoBitrate: 6_000_000,
            avcC: Data(avcC),
            audioSampleRate: 44100, audioChannels: 2, audioBitrate: 128_000,
            audioSpecificConfig: Data([0x12, 0x10]))
    }

    static func main() async {
        setvbuf(stdout, nil, _IOLBF, 0)
        print("Watch Together Studio — real destinations, with a DELIBERATELY INVALID key.")
        print("No credential is used or needed. A refusal is a PASS; a TLS or handshake")
        print("failure is ours.\n")

        var reached = 0
        var ourFaults: [String] = []

        for t in targets {
            guard let url = URL(string: t.server) else { print("  ✗ \(t.name): unparseable URL"); continue }
            let publisher = RTMPPublisher()
            let started = Date()
            do {
                try await publisher.publish(to: url, streamKey: t.key, config: config, timeout: 20)
                // A bad key ACCEPTED would be the surprise. Report it loudly
                // and close immediately — we are not going to stream to it.
                let elapsed = Date().timeIntervalSince(started)
                print(String(format: "  ? %@ — ACCEPTED an invalid key in %.1fs (unexpected; nothing was streamed)", t.name, elapsed))
                await publisher.close()
                reached += 1
            } catch let e as RTMPPublishError {
                let elapsed = Date().timeIntervalSince(started)
                switch e {
                case .rejected(let code, let description):
                    // Reached, spoke RTMP, and was refused by name. This is
                    // the whole chain working.
                    print(String(format: "  ✓ %@ — reached and refused in %.1fs: %@%@",
                                 t.name, elapsed, code,
                                 description.isEmpty ? "" : " (\(description))"))
                    reached += 1
                case .closed(let why):
                    // Several servers hang up on a bad key rather than sending
                    // onStatus. That proves TLS + handshake + connect ONLY if
                    // connect was actually acknowledged — a close during the
                    // handshake looks identical from here, and counting it as
                    // success is how this test passed against a publisher whose
                    // chunking was wrong (2026-09-17).
                    let acked = await publisher.health.connectAcknowledged
                    if acked {
                        print(String(format: "  ✓ %@ — connect acknowledged; server closed on the bad key in %.1fs (%@)",
                                     t.name, elapsed, why))
                        reached += 1
                    } else {
                        print("  ✗ \(t.name) — closed BEFORE connect was acknowledged: \(why)")
                        ourFaults.append("\(t.name): closed pre-connect — \(why)")
                    }
                case .timeout(let phase):
                    // A timeout AFTER connect is the server ignoring a bad
                    // key; a timeout at connect or handshake is ours.
                    if phase == "publish" {
                        print(String(format: "  ✓ %@ — reached; no answer to the bad publish in %.1fs (connect succeeded)",
                                     t.name, elapsed))
                        reached += 1
                    } else {
                        let h = await publisher.health
                        print("  ✗ \(t.name) — TIMED OUT at \(phase); \(h.bytesReceived) bytes received from the server")
                        if !h.wireHead.isEmpty { print("      wire: \(h.wireHead.prefix(400))") }
                        ourFaults.append("\(t.name): timeout at \(phase)")
                    }
                case .connectFailed(let why):
                    print("  ✗ \(t.name) — could not connect: \(why)")
                    ourFaults.append("\(t.name): connect — \(why)")
                case .handshakeFailed(let why):
                    print("  ✗ \(t.name) — HANDSHAKE FAILED: \(why)")
                    ourFaults.append("\(t.name): handshake — \(why)")
                case .badURL(let why):
                    print("  ✗ \(t.name) — bad URL: \(why)")
                    ourFaults.append("\(t.name): url — \(why)")
                }
                await publisher.close()
            } catch {
                print("  ✗ \(t.name) — \(error)")
                ourFaults.append("\(t.name): \(error)")
                await publisher.close()
            }
        }

        print("\nReached and answered: \(reached) of \(targets.count)")
        if ourFaults.isEmpty {
            print("PASS: TLS, the RTMP handshake and AMF0 connect work against every real")
            print("      ingest host. The only untested step is a VALID key, which the")
            print("      go-live sheet supplies from the platform's own API.")
            exit(0)
        }
        print("FAIL — these are ours, not the servers':")
        for f in ourFaults { print("  • \(f)") }
        exit(1)
    }
}
