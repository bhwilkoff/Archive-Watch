// The §8.3 soak, re-run against a real server after §6.4/§6.5/§6.6 landed.
//
// The last soak predates all four of this session's changes — the idle timer,
// the reconnect supervisor, the thermal dial, and the latency-based
// back-pressure budget. One of them carries an obvious regression risk: the
// send-queue cap went from a flat 2 MB to 1.5 s of the show's bitrate
// (474 kB at 2.5 Mbps). If that is too tight, a host on a perfectly healthy
// link loses frames for no reason, and the fix for a rule that never fired
// would have become a rule that fires when it should not.
//
// So this is a soak with a NEGATIVE framing: on a healthy link, over ten
// minutes, nothing should happen. No drops, no reconnects, no encoder faults,
// no pool failures, a flat memory footprint, and a queue that never comes
// near the cap.
//
// Memory is logged rather than assumed: the 291-second tvOS stall was
// diagnosed as a memory leak for hours before an instrument showed the
// footprint flat at 278 MB (§9).
//
//   DEVELOPER_DIR=... xcrun swiftc -parse-as-library -O \
//     ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioEngine.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioAudio.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioOverlayRenderer.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioChatTwitch.swift \
//     tools/test_studio_soak.swift -o /tmp/awsoak
//   AW_SOAK_SECONDS=600 AW_THERMAL_CLIP=... /tmp/awsoak

import AVFoundation
import CoreMedia
import Foundation

@main
struct SoakHarness {

    static let mtxPort = 19359

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

    /// Resident footprint, the same number `phys_footprint` reports.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1024 / 1024
    }

    static func main() async {
        guard let mediamtx = which("mediamtx") else { print("SKIP: mediamtx not installed"); exit(2) }
        let seconds = Double(ProcessInfo.processInfo.environment["AW_SOAK_SECONDS"] ?? "") ?? 600
        let clip = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AW_THERMAL_CLIP"]
                       ?? (NSTemporaryDirectory() + "/awnoise.mp4"))
        guard FileManager.default.fileExists(atPath: clip.path) else {
            print("SKIP: no clip at \(clip.path) — see test_studio_thermal.swift for the recipe")
            exit(2)
        }

        let recDir = NSTemporaryDirectory() + "/aw-soak-rec"
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
        recordPartDuration: 500ms
        recordSegmentDuration: 2h
        paths:
          all:
            source: publisher
        """
        let cfgURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aw-mtx-soak.yml")
        try? cfg.write(to: cfgURL, atomically: true, encoding: .utf8)
        let server = Process()
        server.executableURL = URL(fileURLWithPath: mediamtx)
        server.arguments = [cfgURL.path]
        let logURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aw-mtx-soak.log")
        try? Data().write(to: logURL)
        let h = FileHandle(forWritingAtPath: logURL.path)!
        server.standardOutput = h; server.standardError = h
        try? server.run()
        defer { server.terminate(); kill(server.processIdentifier, SIGKILL) }
        guard await waitForListener(port: mtxPort, seconds: 10) else { print("FAIL: mediamtx never listened"); exit(1) }

        var config = StudioEngine.Configuration()
        config.width = 1920; config.height = 1080; config.frameRate = 30
        config.videoBitrate = 6_000_000
        let publisher = RTMPPublisher()
        let engine = StudioEngine(configuration: config, publisher: publisher)

        print("WATCH-TOGETHER §8.3 — \(Int(seconds / 60))-minute soak, \(config.width)x\(config.height)@\(config.frameRate), "
              + "\(config.videoBitrate / 1000) kbps")
        print("  the question is whether NOTHING happens: no drops, no reconnects, no faults,")
        print("  flat memory, and a send queue that never approaches §6.4a's cap.")

        // The film LOOPS: a ten-minute soak on a thirty-second clip otherwise
        // measures nine and a half minutes of a finished player.
        let item = AVPlayerItem(url: clip)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        let looper = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { _ in
            player.seek(to: .zero)
            player.play()
        }
        defer { NotificationCenter.default.removeObserver(looper) }
        await engine.attachFilm(player: player)
        player.play()

        do { try await engine.start(destination: URL(string: "rtmp://127.0.0.1:\(mtxPort)/live/awsoak")!) }
        catch { print("FAIL: engine.start threw: \(error)"); exit(1) }
        let cap = await publisher.maxQueuedBytes
        print("  back-pressure cap: \(cap / 1000) kB\n")

        let t0 = Date()
        let baselineFootprint = footprintMB()
        var peakQueue = 0
        var peakFootprint = baselineFootprint
        var minFps = Int.max
        var firstMinuteDrops = 0
        var lastDrops = 0
        var offAirSeconds = 0
        var faults: [String] = []

        print("  mins  state   fps   drops  reconn  queue kB  RSS MB")
        var lastPrint = 0.0
        while Date().timeIntervalSince(t0) < seconds {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await engine.refreshHealth()
            let hh = await engine.health
            let el = Date().timeIntervalSince(t0)
            peakQueue = max(peakQueue, hh.publisher.queuedBytes)
            let rss = footprintMB()
            peakFootprint = max(peakFootprint, rss)
            if el > 60 { minFps = min(minFps, hh.encodedFramesPerSecond) }
            if el <= 60 { firstMinuteDrops = hh.publisher.videoFramesDropped }
            lastDrops = hh.publisher.videoFramesDropped
            if hh.showState != .live { offAirSeconds += 1 }
            if let f = hh.encoderFault, !faults.contains(f) { faults.append(f) }
            if el - lastPrint >= 30 {
                lastPrint = el
                print(String(format: "  %4.1f  %-6@  %3d  %6d  %6d  %8d  %6.1f",
                             el / 60, hh.showState.label as NSString, hh.encodedFramesPerSecond,
                             hh.publisher.videoFramesDropped, hh.publisher.reconnects,
                             hh.publisher.queuedBytes / 1000, rss))
            }
        }
        await engine.refreshHealth()
        let final = await engine.health
        await engine.stop()

        print("\n  ran \(String(format: "%.1f", Date().timeIntervalSince(t0) / 60)) minutes")
        print("  encoded \(final.programFramesEncoded) frames, sent \(final.publisher.videoFramesSent)v/"
              + "\(final.publisher.audioFramesSent)a, \(final.publisher.bytesSent / 1_000_000) MB")
        print("  memory \(String(format: "%.1f", baselineFootprint)) → "
              + "\(String(format: "%.1f", footprintMB())) MB (peak \(String(format: "%.1f", peakFootprint)))")
        print("  peak send queue \(peakQueue / 1000) kB of a \(cap / 1000) kB cap "
              + "(\(Int(Double(peakQueue) / Double(cap) * 100))%)")
        print("  thermal \(final.thermalState); pool failures \(final.pixelBufferPoolFailures)")

        var failed = false
        func check(_ ok: Bool, _ pass: String, _ fail: String) {
            print(ok ? "OK: \(pass)" : "FAIL: \(fail)")
            if !ok { failed = true }
        }
        print("")
        check(offAirSeconds == 0, "the show stayed LIVE for the whole soak",
              "the show was not LIVE for \(offAirSeconds) of \(Int(seconds)) seconds")
        // §8.3's own wording: no dropped-frame GROWTH after the first minute.
        check(lastDrops == firstMinuteDrops,
              "no dropped frames after the first minute (\(lastDrops) total)",
              "dropped frames grew from \(firstMinuteDrops) to \(lastDrops) after the first minute")
        // The regression this soak exists for.
        check(peakQueue < cap,
              "the send queue never reached §6.4a's cap on a healthy link",
              "the queue hit \(peakQueue / 1000) kB against a \(cap / 1000) kB cap — the budget is too tight")
        check(final.publisher.reconnects == 0, "§6.6 never fired on a healthy link",
              "§6.6 reconnected \(final.publisher.reconnects) time(s) on a healthy link")
        check(faults.isEmpty, "no encoder faults", "encoder faults: \(faults.joined(separator: "; "))")
        check(final.pixelBufferPoolFailures == 0, "no pixel-buffer pool failures",
              "\(final.pixelBufferPoolFailures) pool failures")
        check(final.thermalState != "serious" && final.thermalState != "critical",
              "thermal state stayed under .serious (\(final.thermalState))",
              "thermal reached \(final.thermalState)")
        check(minFps >= config.frameRate - 3,
              "encoding held \(minFps) fps at worst after the first minute",
              "encoding fell to \(minFps) fps (configured \(config.frameRate))")
        // Memory: a real leak at 6 Mbps for ten minutes would be hundreds of MB.
        check(footprintMB() < baselineFootprint + 150,
              String(format: "memory grew %.1f MB over the soak", footprintMB() - baselineFootprint),
              String(format: "memory grew %.1f MB — investigate before shipping", footprintMB() - baselineFootprint))

        print(failed ? "\nFAIL: §8.3 soak" : "\nPASS: §8.3 — ten minutes of nothing happening, which is the point")
        exit(failed ? 1 : 0)
    }
}
