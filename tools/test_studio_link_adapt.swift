// §8.79 — a link that cannot keep up lowers the BITRATE before it drops a
// frame (WATCH-TOGETHER §6.4b).
//
// Owner, 2026-10-02: "It said dropped 451 (it did stutter occasionally)."
// The same real engine, the same saturating clip, the same throttle — run
// twice in one process: first with the adaptation OFF (the control: §6.4a's
// drops alone), then ON. ON must step the encoder's bitrate down while the
// link is narrow, drop at most a few frames, keep the voice, and climb back
// once the link clears. A throttle the program fits under proves nothing, so
// the control must drop frames or the run is refused.
//
//   swiftc -parse-as-library -O <Studio sources> tools/harness_awdiag.swift \
//     tools/test_studio_link_adapt.swift && AW_THERMAL_CLIP=<noise clip> ./a.out
import AVFoundation
import CoreMedia
import Foundation

@main
struct LinkAdaptHarness {
    static let openPhase = 8.0
    static let throttlePhase = 20.0
    static let recoverPhase = 30.0
    static let throttleBps = 2_000_000.0

    static func which(_ tool: String) -> String? {
        ["/opt/homebrew/bin/", "/usr/local/bin/", "/usr/bin/"].map { $0 + tool }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
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

    struct Result { var droppedThrottled = 0; var minKbps = Int.max; var endKbps = 0; var worstAudio = Int.max }

    static func run(adapt: Bool, clip: URL, mediamtx: String, mtxPort: Int, proxyPort: Int) async -> Result? {
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
        paths:
          all:
            source: publisher
        """
        let cfgURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aw-mtx-adapt-\(mtxPort).yml")
        try? cfg.write(to: cfgURL, atomically: true, encoding: .utf8)
        let server = Process()
        server.executableURL = URL(fileURLWithPath: mediamtx)
        server.arguments = [cfgURL.path]
        server.standardOutput = FileHandle.nullDevice; server.standardError = FileHandle.nullDevice
        try? server.run()
        defer { server.terminate() }
        guard await waitForListener(port: mtxPort, seconds: 10) else { print("FAIL: mediamtx never listened"); return nil }
        let prox = Process()
        prox.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        prox.arguments = [FileManager.default.currentDirectoryPath + "/tools/rtmp_throttle_proxy.py",
                          "\(proxyPort)", "\(mtxPort)", "\(openPhase)", "\(Int(throttleBps))", "\(throttlePhase)"]
        prox.standardOutput = FileHandle.nullDevice; prox.standardError = FileHandle.nullDevice
        try? prox.run()
        defer { prox.terminate() }
        guard await waitForListener(port: proxyPort, seconds: 10) else { print("FAIL: the proxy never listened"); return nil }

        var config = StudioEngine.Configuration()
        config.width = 1280; config.height = 720; config.frameRate = 30
        config.videoBitrate = 6_000_000
        config.audioBitrate = 128_000
        let engine = StudioEngine(configuration: config, publisher: RTMPPublisher())
        await engine.setLinkAdaptation(adapt)
        let player = AVPlayer(url: clip)
        player.isMuted = true
        await engine.attachFilm(player: player)
        player.play()
        do { try await engine.start(destination: URL(string: "rtmp://127.0.0.1:\(proxyPort)/live/adapt")!) }
        catch { print("FAIL: engine.start threw: \(error)"); return nil }

        var r = Result()
        let t0 = Date()
        var lastDropped = 0, lastAudio = 0
        print("  \(adapt ? "ADAPT ON " : "ADAPT OFF")   t   kbps  queued  v-drop")
        while Date().timeIntervalSince(t0) < openPhase + throttlePhase + recoverPhase {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await engine.refreshHealth()
            let h = await engine.health
            let t = Date().timeIntervalSince(t0)
            let throttled = t > openPhase + 1 && t < openPhase + throttlePhase + 1
            if throttled {
                r.droppedThrottled += h.publisher.videoFramesDropped - lastDropped
                r.minKbps = min(r.minKbps, h.videoBitrateNow / 1000)
                r.worstAudio = min(r.worstAudio, h.publisher.audioFramesSent - lastAudio)
            }
            lastDropped = h.publisher.videoFramesDropped
            lastAudio = h.publisher.audioFramesSent
            r.endKbps = h.videoBitrateNow / 1000
            if Int(t) % 4 == 0 {
                print(String(format: "            %3.0f  %5d  %6d  %6d", t, h.videoBitrateNow / 1000,
                             h.publisher.queuedBytes, h.publisher.videoFramesDropped))
            }
        }
        await engine.stop()
        player.pause()
        return r
    }

    static func main() async {
        guard let mediamtx = which("mediamtx") else { print("SKIP: mediamtx not installed"); exit(2) }
        let clip = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AW_THERMAL_CLIP"]
                       ?? (NSTemporaryDirectory() + "/awnoise.mp4"))
        guard FileManager.default.fileExists(atPath: clip.path) else {
            print("SKIP: no saturating clip at \(clip.path)"); exit(2)
        }
        print("WATCH-TOGETHER §8.79 — §6.4b: 6 Mbps program, a 2 Mbps link for \(Int(throttlePhase)) s")
        guard let off = await run(adapt: false, clip: clip, mediamtx: mediamtx, mtxPort: 19371, proxyPort: 19372),
              let on = await run(adapt: true, clip: clip, mediamtx: mediamtx, mtxPort: 19373, proxyPort: 19374)
        else { exit(1) }
        print("  dropped while throttled: OFF \(off.droppedThrottled), ON \(on.droppedThrottled)")
        print("  ON: lowest \(on.minKbps) kbps while throttled, \(on.endKbps) kbps at the end")
        var failures = 0
        func check(_ ok: Bool, _ what: String) { print(ok ? "OK: \(what)" : "FAIL: \(what)"); if !ok { failures += 1 } }
        guard off.droppedThrottled > 30 else {
            print("FAIL: the control dropped only \(off.droppedThrottled) frames — the throttle did not bind, so this run proves nothing")
            exit(1)
        }
        check(on.minKbps < 6000, "the bitrate stepped down under congestion")
        check(on.droppedThrottled * 4 < off.droppedThrottled,
              "adapting dropped under a quarter of what dropping alone did")
        check(on.worstAudio > 0, "the voice never gapped")
        check(on.endKbps > on.minKbps, "the bitrate climbed back once the link cleared")
        print(failures == 0 ? "PASS" : "FAILED (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }
}
