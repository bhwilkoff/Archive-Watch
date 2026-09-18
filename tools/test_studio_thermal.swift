// Does thermal pressure do what §6.5 says — and NOT what it used to say?
// (WATCH-TOGETHER §6.5 / §8.5.)
//
// §6.5 was written on the day the Studio was designed and implemented
// nowhere: `thermalState` was reported as a string and nothing acted on it.
// It also said the wrong thing — `.serious` was to "halve the encode
// resolution", but an RTMP stream's format is fixed for the life of the
// publish (Bitmovin's input requirements: "Codec and format parameters, such
// as resolution and frame rate, must not change during the stream"), so the
// documented response would have broken the broadcast it was meant to save.
//
// This drives the REAL `StudioEngine` — not a stand-in — against a real
// mediamtx, and asserts:
//
//   1. `.serious` lowers the bitrate.       (measured from the recording)
//   2. Resolution and frame rate DO NOT     (read back from the recording;
//      change across the step.               this is the corrected rule)
//   3. `.critical` ENDS the show.           (the engine stops, with a reason)
//
// A device cannot be made `.critical` on demand, which is precisely why this
// rule went four weeks unexercised — so the engine carries a harness seam,
// `overrideThermalState`, and this is the thing that uses it.
//
//   brew install mediamtx ffmpeg          # once
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -O \
//     ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioEngine.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioAudio.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioOverlayRenderer.swift \
//     tools/test_studio_thermal.swift -o /tmp/awthermal && /tmp/awthermal

import AVFoundation
import CoreMedia
import Foundation

@main
struct ThermalHarness {

    static let mtxPort = 19355
    static let phase = 9.0        // seconds per phase: nominal, then serious

    static func which(_ tool: String) -> String? {
        for p in ["/opt/homebrew/bin/", "/usr/local/bin/", "/usr/bin/"] where FileManager.default.isExecutableFile(atPath: p + tool) {
            return p + tool
        }
        return nil
    }

    static func run(_ launch: String, _ args: [String]) -> (Int32, String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: launch); p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        try? p.run()
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: d, encoding: .utf8) ?? "")
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

    /// Video packets as (timestamp, bytes), from the SERVER's recording.
    /// The bitrate claim is measured here rather than read off our own
    /// counters — a readout can be correct and still lie (§9).
    static func videoPackets(_ ffprobe: String, _ path: String) -> [(Double, Int)] {
        let (_, out) = run(ffprobe, ["-v", "error", "-select_streams", "v:0", "-of", "csv=p=0",
                                     "-show_entries", "packet=pts_time,size", path])
        return out.split(separator: "\n").compactMap { line in
            let p = line.split(separator: ",").map(String.init)
            guard p.count >= 2, let t = Double(p[0]), let b = Int(p[1]) else { return nil }
            return (t, b)
        }
    }

    static func mean(_ xs: [Int]) -> Double { xs.isEmpty ? 0 : Double(xs.reduce(0, +)) / Double(xs.count) }

    static func main() async {
        guard let mediamtx = which("mediamtx") else { print("SKIP: mediamtx not installed"); exit(2) }
        guard let ffprobe = which("ffprobe") else { print("SKIP: ffprobe not installed"); exit(2) }

        let recDir = NSTemporaryDirectory() + "/aw-thermal-rec"
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
        let cfgURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aw-mtx-thermal.yml")
        try? cfg.write(to: cfgURL, atomically: true, encoding: .utf8)
        let server = Process()
        server.executableURL = URL(fileURLWithPath: mediamtx)
        server.arguments = [cfgURL.path]
        let logURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aw-mtx-thermal.log")
        try? Data().write(to: logURL)
        let h = FileHandle(forWritingAtPath: logURL.path)!
        server.standardOutput = h; server.standardError = h
        try? server.run()
        defer { server.terminate(); kill(server.processIdentifier, SIGKILL) }
        guard await waitForListener(port: mtxPort, seconds: 10) else { print("FAIL: mediamtx never listened"); exit(1) }

        // A modest program: this harness is about the bitrate dial, not about
        // how much the Mac can encode.
        var config = StudioEngine.Configuration()
        config.width = 1280; config.height = 720; config.frameRate = 30
        config.videoBitrate = 4_000_000
        let engine = StudioEngine(configuration: config)

        print("WATCH-TOGETHER §8.5 — §6.5 on the REAL engine")
        print("  configured \(config.width)x\(config.height)@\(config.frameRate), \(config.videoBitrate / 1000) kbps")
        print("  \u{00A7}6.5 step at .serious = \(Int(StudioEngine.seriousBitrateFraction * 100))% = "
              + "\(Int(Double(config.videoBitrate) * StudioEngine.seriousBitrateFraction) / 1000) kbps")

        // A film with enough ENTROPY to saturate the configured bitrate.
        //
        // The first version of this harness ran the engine with no film at
        // all, and passed while proving nothing: a static black program
        // compresses to ~58-byte frames, so it never approaches 4 Mbps and
        // lowering the CEILING to 2.4 Mbps changes not one byte on the wire.
        // A bitrate is a ceiling, not a floor — to see a ceiling move, the
        // program has to be pressed against it.
        let clip = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AW_THERMAL_CLIP"]
                       ?? (NSTemporaryDirectory() + "/awnoise.mp4"))
        guard FileManager.default.fileExists(atPath: clip.path) else {
            print("SKIP: no saturating clip at \(clip.path).")
            print("  Make one:  ffmpeg -f lavfi -i testsrc2=s=1280x720:r=30:d=30 \\")
            print("               -f lavfi -i 'nullsrc=s=1280x720:r=30:d=30,geq=random(1)*255:128:128' \\")
            print("               -filter_complex '[0:v][1:v]blend=all_mode=average' \\")
            print("               -c:v libx264 -preset veryfast -b:v 20M -pix_fmt yuv420p \(clip.path)")
            print("  then pass it as AW_THERMAL_CLIP.")
            exit(2)
        }
        let player = AVPlayer(url: clip)
        player.isMuted = true
        let engineForFilm = engine
        await engineForFilm.attachFilm(player: player)
        player.play()

        let dest = URL(string: "rtmp://127.0.0.1:\(mtxPort)/live/awthermal")!
        do { try await engine.start(destination: dest) }
        catch { print("FAIL: engine.start threw: \(error)"); exit(1) }

        // Phase 1 — nominal. Refreshed once a SECOND, because
        // `encodedFramesPerSecond` is a delta since the last refresh: calling
        // it once after nine seconds made the first run report "270 fps".
        for _ in 0..<Int(phase) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await engine.refreshHealth()
        }
        var health = await engine.health
        print("\n[nominal] \(health.showState.label) — \(health.encodedFramesPerSecond) fps encoded, "
              + "bitrate now \(health.videoBitrateNow / 1000) kbps, thermal \(health.thermalState)")
        guard health.showState == .live else {
            print("FAIL: not live in the nominal phase — \(health.showState.label)")
            print(String(data: (try? Data(contentsOf: logURL)) ?? Data(), encoding: .utf8) ?? "")
            exit(1)
        }
        let nominalEnd = Date()

        // Phase 2 — .serious. The seam exists because a bench device cannot
        // be made hot on cue.
        print("\n[.serious] injecting thermal pressure")
        await engine.overrideThermalState(.serious)
        for _ in 0..<Int(phase) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await engine.refreshHealth()
        }
        health = await engine.health
        print("  \(health.showState.label) — bitrate now \(health.videoBitrateNow / 1000) kbps, "
              + "thermal \(health.thermalState)")
        print("  note: \(health.qualityNote ?? "(none)")")
        let expected = Int(Double(config.videoBitrate) * StudioEngine.seriousBitrateFraction)
        guard health.videoBitrateNow == expected else {
            print("FAIL: the encoder is at \(health.videoBitrateNow) bps, expected \(expected)")
            exit(1)
        }
        guard let note = health.qualityNote, !note.isEmpty else {
            print("FAIL: the step is not SHOWN — §5 requires an adaptive step be visible")
            exit(1)
        }
        guard health.showState == .live else { print("FAIL: the show stopped at .serious — it should only slow down"); exit(1) }
        print("OK: .serious lowered the bitrate and said so, and the show is still live")

        // Phase 3 — .critical must END the show.
        print("\n[.critical] injecting")
        await engine.overrideThermalState(.critical)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        health = await engine.health
        print("  isRunning=\(health.isRunning), reason: \(health.endedReason ?? "(none)")")
        guard !health.isRunning else { print("FAIL: .critical did not end the show"); exit(1) }
        guard let reason = health.endedReason, reason.contains("hot") else {
            print("FAIL: the show ended without saying why — an end card needs a reason")
            exit(1)
        }
        print("OK: .critical ended the show with a reason")

        await engine.stop()
        try? await Task.sleep(nanoseconds: 2_500_000_000)

        // ---- The server's own recording has the last word.
        var recorded: [String] = []
        if let walk = FileManager.default.enumerator(atPath: recDir) {
            for case let f as String in walk where f.hasSuffix(".mp4") { recorded.append(f) }
        }
        guard let seg = recorded.sorted().last else { print("FAIL: mediamtx recorded nothing"); exit(1) }
        let path = recDir + "/" + seg
        let (_, shape) = run(ffprobe, ["-v", "error", "-select_streams", "v:0", "-of", "csv=p=0",
                                       "-show_entries", "stream=width,height,r_frame_rate,nb_frames", path])
        print("\n[recording] \(seg): \(shape.trimmingCharacters(in: .whitespacesAndNewlines))")

        // 2. THE CORRECTED RULE: one resolution and one frame rate for the
        // whole publish. ffprobe reports a single value per stream, so a
        // mid-stream change would show up as a broken/renegotiated stream
        // rather than two numbers — assert what we configured, exactly.
        let fields = shape.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",").map(String.init)
        guard fields.count >= 3, Int(fields[0]) == config.width, Int(fields[1]) == config.height else {
            print("FAIL: the recording is \(fields.first ?? "?")x\(fields.count > 1 ? fields[1] : "?"), "
                  + "not the configured \(config.width)x\(config.height) — the format moved mid-stream")
            exit(1)
        }
        print("OK: resolution held at \(config.width)x\(config.height) across the thermal step")

        // 1. The bitrate claim, measured from the server's packets.
        let packets = videoPackets(ffprobe, path)
        guard packets.count > 60 else { print("FAIL: only \(packets.count) video packets recorded"); exit(1) }
        let cut = packets[0].0 + phase
        // Skip the second either side of the step: the encoder's rate control
        // does not turn on a sixpence, and a window straddling the change
        // would average the two.
        let before = packets.filter { $0.0 < cut - 1 }.map { $0.1 }
        let after = packets.filter { $0.0 > cut + 1 }.map { $0.1 }
        guard before.count > 20, after.count > 20 else {
            print("FAIL: not enough packets either side of the step (\(before.count)/\(after.count))")
            exit(1)
        }
        let mb = mean(before), ma = mean(after)
        print("  mean video packet: \(String(format: "%.0f", mb))B before, \(String(format: "%.0f", ma))B after")
        let drop = (1 - ma / mb) * 100
        // A MARGIN, not `ma < mb`. The first version asserted only "smaller"
        // and passed on 58.4 B vs 58.3 B while printing "0% smaller" — a
        // float comparison standing in for a measurement.
        guard ma < mb * 0.85 else {
            print("FAIL: frames shrank by only \(String(format: "%.1f", drop))% after the step "
                  + "(\(String(format: "%.0f", mb))B → \(String(format: "%.0f", ma))B).")
            print("      Either the bitrate change never reached the wire, or the program is not")
            print("      pressed against the ceiling — check the clip saturates \(config.videoBitrate / 1000) kbps.")
            exit(1)
        }
        print("OK: the wire shows \(String(format: "%.0f", drop))% smaller frames after the step")
        print("\nPASS: §6.5 — thermal pressure moves the BITRATE, the format holds, and .critical ends the show")
        exit(0)
    }
}
