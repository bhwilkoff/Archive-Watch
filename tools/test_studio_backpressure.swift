// Under a narrow uplink, does the host's VOICE survive? (§6.4 / §8.6.)
//
// §6.4: "back-pressure drops VIDEO frames first and never audio (viewers
// forgive a frame, not a gap in the host's voice)." The publisher is built
// that way — `send(video:)` drops inter-frames past `maxQueuedBytes` and
// `send(audioFrame:)` has no drop path at all — but the rule had never been
// exercised, so three things were unproven:
//
//   1. that the back-pressure signal can FIRE at all. `queuedBytes` counts
//      bytes handed to NWConnection and not yet completed, and Apple's
//      documented behaviour is that `contentProcessed` is DEFERRED once the
//      connection's send buffer passes its high-water mark — so the counter
//      should climb under congestion. "Should" is not "does".
//   2. that video is what gets dropped.
//   3. that audio keeps flowing THROUGHOUT — the actual promise to the host.
//
// The congestion is real: a proxy rate-limits the client->server direction so
// the publisher discovers it through its own send buffer, the way it will on a
// domestic uplink. Throttling inside the publisher would only prove the
// arithmetic we already wrote.
//
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -O \
//     ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioEngine.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioAudio.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioOverlayRenderer.swift \
//     tools/test_studio_backpressure.swift -o /tmp/awbp && AW_THERMAL_CLIP=... /tmp/awbp

import AVFoundation
import CoreMedia
import Foundation

@main
struct BackPressureHarness {

    static let mtxPort = 19357
    static let proxyPort = 19358
    static let openPhase = 8.0
    static let throttlePhase = 11.0
    static let recoverPhase = 7.0
    /// Well under the video bitrate, comfortably over the audio bitrate: the
    /// whole question is which of the two survives.
    static let throttleBps = 400_000.0

    struct Sample {
        let t: Double
        let queued: Int
        let videoSent: Int
        let videoDropped: Int
        let audioSent: Int
        let state: String
    }

    static func which(_ tool: String) -> String? {
        for p in ["/opt/homebrew/bin/", "/usr/local/bin/", "/usr/bin/"] where FileManager.default.isExecutableFile(atPath: p + tool) {
            return p + tool
        }
        return nil
    }

    static func waitForListener(port: Int, seconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            let sock = socket(AF_INET, SOCK_STREAM, 0)
            if sock >= 0 {
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = UInt16(port).bigEndian
                addr.sin_addr.s_addr = inet_addr("127.0.0.1")
                let ok = withUnsafePointer(to: &addr) { p -> Bool in
                    p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        connect(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                    }
                }
                close(sock)
                if ok { return true }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    static func main() async {
        guard let mediamtx = which("mediamtx") else { print("SKIP: mediamtx not installed"); exit(2) }
        let clip = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AW_THERMAL_CLIP"]
                       ?? (NSTemporaryDirectory() + "/awnoise.mp4"))
        guard FileManager.default.fileExists(atPath: clip.path) else {
            print("SKIP: no saturating clip at \(clip.path) — see test_studio_thermal.swift for the recipe")
            exit(2)
        }

        let recDir = NSTemporaryDirectory() + "/aw-bp-rec"
        try? FileManager.default.removeItem(atPath: recDir)
        try? FileManager.default.createDirectory(atPath: recDir, withIntermediateDirectories: true)
        let cfg = """
        rtmp: yes
        rtmpAddress: :\(mtxPort)
        api: no
        hls: no
        webrtc: no
        rtsp: no
        srt: no
        moq: no
        playback: no
        metrics: no
        pprof: no
        logLevel: info
        record: yes
        recordPath: \(recDir)/%path_%Y-%m-%d_%H-%M-%S-%f
        recordFormat: fmp4
        recordPartDuration: 200ms
        recordSegmentDuration: 1h
        paths:
          all:
            source: publisher
        """
        let cfgURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aw-mtx-bp.yml")
        try? cfg.write(to: cfgURL, atomically: true, encoding: .utf8)
        let server = Process()
        server.executableURL = URL(fileURLWithPath: mediamtx)
        server.arguments = [cfgURL.path]
        let logURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aw-mtx-bp.log")
        try? Data().write(to: logURL)
        let h = FileHandle(forWritingAtPath: logURL.path)!
        server.standardOutput = h; server.standardError = h
        try? server.run()
        defer { server.terminate(); kill(server.processIdentifier, SIGKILL) }
        guard await waitForListener(port: mtxPort, seconds: 10) else { print("FAIL: mediamtx never listened"); exit(1) }

        let prox = Process()
        prox.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        prox.arguments = [FileManager.default.currentDirectoryPath + "/tools/rtmp_throttle_proxy.py",
                          "\(proxyPort)", "\(mtxPort)", "\(openPhase)", "\(Int(throttleBps))", "\(throttlePhase)"]
        let pp = Pipe(); prox.standardOutput = pp; prox.standardError = pp
        pp.fileHandleForReading.readabilityHandler = { fh in
            let d = fh.availableData
            if !d.isEmpty, let s = String(data: d, encoding: .utf8) {
                for line in s.split(separator: "\n") where !line.isEmpty { print("   [proxy] \(line)") }
            }
        }
        try? prox.run()
        defer { prox.terminate(); kill(prox.processIdentifier, SIGKILL) }
        guard await waitForListener(port: proxyPort, seconds: 10) else { print("FAIL: the proxy never listened"); exit(1) }

        var config = StudioEngine.Configuration()
        config.width = 1280; config.height = 720; config.frameRate = 30
        config.videoBitrate = 2_400_000
        config.audioBitrate = 128_000
        let publisher = RTMPPublisher()
        let engine = StudioEngine(configuration: config, publisher: publisher)
        print("WATCH-TOGETHER §8.6 — §6.4 back-pressure on the REAL engine")
        print("  program \(config.videoBitrate / 1000) kbps video + \(config.audioBitrate / 1000) kbps audio")
        print("  uplink throttled to \(Int(throttleBps / 1000)) kbps for \(Int(throttlePhase))s "
              + "after \(Int(openPhase))s")

        let player = AVPlayer(url: clip)
        player.isMuted = true
        await engine.attachFilm(player: player)
        player.play()

        do { try await engine.start(destination: URL(string: "rtmp://127.0.0.1:\(proxyPort)/live/awbp")!) }
        catch { print("FAIL: engine.start threw: \(error)"); exit(1) }

        // AFTER start, because §6.4's cap is a latency budget the engine
        // computes from this show's bitrates. Read before, it is the
        // pre-configuration default — which is how the first run of this
        // harness reported a 2000 kB cap, failed, and buried a correct result:
        // the drops were right there in the table.
        let cap = await publisher.maxQueuedBytes
        print("  back-pressure cap \(cap / 1000) kB "
              + "(\(RTMPPublisher.queueLatencyBudgetSeconds)s of the program's bitrate)")

        var samples: [Sample] = []
        let t0 = Date()
        let total = openPhase + throttlePhase + recoverPhase
        while Date().timeIntervalSince(t0) < total {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await engine.refreshHealth()
            let hh = await engine.health
            let p = hh.publisher
            samples.append(Sample(t: Date().timeIntervalSince(t0), queued: p.queuedBytes,
                                  videoSent: p.videoFramesSent, videoDropped: p.videoFramesDropped,
                                  audioSent: p.audioFramesSent, state: hh.showState.label))
        }
        await engine.stop()

        print("\n  t   state        queued   v-sent  v-drop  a-sent")
        for s in samples {
            print(String(format: "%4.0f  %-11@ %7d  %6d  %6d  %6d",
                         s.t, s.state as NSString, s.queued, s.videoSent, s.videoDropped, s.audioSent))
        }

        // Phase windows, judged a second inside each boundary so a sample
        // straddling a transition is not counted as either.
        func inWindow(_ a: Double, _ b: Double) -> [Sample] { samples.filter { $0.t > a + 1 && $0.t < b } }
        let open = inWindow(0, openPhase)
        let throttled = inWindow(openPhase, openPhase + throttlePhase)
        let recovered = inWindow(openPhase + throttlePhase, total)
        guard open.count >= 3, throttled.count >= 5, recovered.count >= 3 else {
            print("FAIL: not enough samples per phase (\(open.count)/\(throttled.count)/\(recovered.count))")
            exit(1)
        }

        // 1. The signal fires. Without this the rest is vacuous: a cap that is
        //    never reached drops nothing and the test would "pass" on a link
        //    that was never congested.
        let peak = throttled.map(\.queued).max() ?? 0
        print("\n  peak queued while throttled: \(peak / 1000) kB against a \(cap / 1000) kB cap")
        guard peak > cap else {
            print("FAIL: the send queue never passed the cap, so back-pressure never engaged.")
            print("      Either the throttle is not throttling or `queuedBytes` does not see congestion.")
            exit(1)
        }
        // Control: it must NOT have been over the cap before the throttle, or
        // the program was simply too big for the link all along.
        let openPeak = open.map(\.queued).max() ?? 0
        guard openPeak <= cap else {
            print("FAIL: the queue was already over the cap before the throttle (\(openPeak / 1000) kB) —")
            print("      this run proves nothing about congestion.")
            exit(1)
        }
        print("OK: the queue crossed the cap only while throttled (\(openPeak / 1000) kB before)")

        // 2. VIDEO is what gets dropped.
        let droppedDuring = (throttled.last!.videoDropped - throttled.first!.videoDropped)
        let droppedBefore = (open.last!.videoDropped - open.first!.videoDropped)
        print("  video frames dropped: \(droppedBefore) before, \(droppedDuring) while throttled")
        guard droppedDuring > 0 else { print("FAIL: no video frames were dropped under congestion"); exit(1) }
        guard droppedBefore == 0 else { print("FAIL: video was being dropped before the throttle"); exit(1) }
        print("OK: video is dropped, and only under congestion")

        // 3. THE PROMISE: the host's voice does not gap. Audio must advance in
        //    EVERY second of the congestion, not merely in total — a total can
        //    hide a four-second silence.
        var worstAudioSecond = Int.max
        for (a, b) in zip(throttled, throttled.dropFirst()) {
            worstAudioSecond = min(worstAudioSecond, b.audioSent - a.audioSent)
        }
        let expectedPerSecond = Int(Double(config.audioSampleRate) / 1024.0)   // AAC frames a second
        print("  audio frames in the worst throttled second: \(worstAudioSecond) (about \(expectedPerSecond) expected)")
        guard worstAudioSecond > 0 else {
            print("FAIL: there was a second of congestion with NO audio — that is a gap in the host's voice,")
            print("      which is the one thing §6.4 promises will not happen.")
            exit(1)
        }
        guard worstAudioSecond >= expectedPerSecond / 2 else {
            print("FAIL: audio thinned to \(worstAudioSecond) frames in a second (expected ~\(expectedPerSecond)) —")
            print("      audio is being starved even though nothing drops it.")
            exit(1)
        }
        print("OK: audio never gapped while the uplink was too narrow for the picture")

        // 4. Recovery: video comes back.
        //
        // RATES, not totals. The first version compared frames-sent across a
        // 9-second congested window and a 6-second recovered one and declared
        // "video did not recover" — 223 against 150 — while the table plainly
        // showed 30 fps after and barely 1 fps at the worst of the throttle.
        // Two windows of different lengths are not comparable by total.
        func framesPerSecond(_ w: [Sample]) -> Double {
            guard let a = w.first, let b = w.last, b.t > a.t else { return 0 }
            return Double(b.videoSent - a.videoSent) / (b.t - a.t)
        }
        // The worst SECOND of the congestion, which is what a viewer felt.
        var worstVideoSecond = Int.max
        for (a, b) in zip(throttled, throttled.dropFirst()) {
            worstVideoSecond = min(worstVideoSecond, b.videoSent - a.videoSent)
        }
        let afterFps = framesPerSecond(recovered)
        print(String(format: "  video: worst throttled second %d fps, recovered %.1f fps (configured %d)",
                     worstVideoSecond, afterFps, config.frameRate))
        guard afterFps > Double(config.frameRate) * 0.8 else {
            print("FAIL: video did not recover when the uplink re-opened "
                  + "(\(String(format: "%.1f", afterFps)) fps against a configured \(config.frameRate))")
            exit(1)
        }
        guard Double(worstVideoSecond) < afterFps * 0.5 else {
            print("FAIL: video never actually yielded — the worst throttled second still carried "
                  + "\(worstVideoSecond) frames, so this run did not test back-pressure")
            exit(1)
        }
        print("OK: video yielded under congestion and recovered when the uplink did")
        print("\nPASS: §6.4 — the picture yields, the voice does not")
        exit(0)
    }
}
