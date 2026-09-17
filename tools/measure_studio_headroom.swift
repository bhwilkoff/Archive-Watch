// PHASE 0's ONLY REAL UNKNOWN: can one device decode a film, composite a
// program over it, and encode 1080p30 at the same time? (WATCH-TOGETHER §7,
// §9; docs/LIVE-RIFF-RESEARCH.md §8.)
//
// This measures the whole chain on whatever machine runs it — a real
// archive.org film through AVPlayer, its frames pulled with
// AVPlayerItemVideoOutput, composited by ProgramRenderer at the program size,
// encoded by VideoToolbox, and published as RTMP to a local mediamtx. No
// camera: a camera tile is a cheap composite next to a 1080p film decode, and
// on the Mac there may not be one. The camera's cost is measured on device.
//
// What it prints, once a second: program fps actually achieved, mean render
// ms, frames the clock overran, encoded frames, bytes published, thermal
// state. What matters is whether achieved fps holds at the target and whether
// render ms stays under the frame budget (33.3 ms at 30 fps).
//
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -O \
//     ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioEngine.swift \
//     tools/measure_studio_headroom.swift -o /tmp/awhead && /tmp/awhead
//
// Env: AW_FILM (an mp4 URL), AW_SECONDS (default 40), AW_W/AW_H/AW_FPS,
//      AW_LAYOUT (film|corner|theatre|side|host), AW_DEST (rtmp destination;
//      default is a local mediamtx this harness starts itself).

import AVFoundation
import CoreMedia
import Foundation

@main
struct Measure {
    static func env(_ k: String) -> String? {
        let v = ProcessInfo.processInfo.environment[k]
        return (v?.isEmpty ?? true) ? nil : v
    }

    static func run(_ launch: String, _ args: [String]) -> (Int32, String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: launch); p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        try? p.run(); p.waitUntilExit()
        return (p.terminationStatus, String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    static func which(_ t: String) -> String? {
        let (_, o) = run("/usr/bin/which", [t])
        let s = o.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    // A 1080p public-domain feature that the catalog keeps, with a direct mp4.
    static let defaultFilm = "https://archive.org/download/TheGeneral720p1926/TheGeneral720p.mp4"

    static func main() async {
        setvbuf(stdout, nil, _IOLBF, 0)
        let seconds = Int(env("AW_SECONDS") ?? "") ?? 40
        var cfg = StudioEngine.Configuration()
        cfg.width = Int(env("AW_W") ?? "") ?? 1920
        cfg.height = Int(env("AW_H") ?? "") ?? 1080
        cfg.frameRate = Int(env("AW_FPS") ?? "") ?? 30
        let layout = StudioLayout(rawValue: env("AW_LAYOUT") ?? "corner") ?? .corner
        let filmURL = URL(string: env("AW_FILM") ?? defaultFilm)!

        // A local sink unless a destination was named: the measurement is of
        // OUR chain, and a real platform's ingest would add its own variance.
        var server: Process?
        var destination = env("AW_DEST")
        if destination == nil {
            guard let mediamtx = which("mediamtx") else {
                print("SKIP: no mediamtx and no AW_DEST (brew install mediamtx)"); exit(2)
            }
            let cfgPath = NSTemporaryDirectory() + "/aw-head-mediamtx.yml"
            try? """
            rtmp: yes
            rtmpAddress: :19351
            api: no
            hls: no
            webrtc: no
            rtsp: no
            srt: no
            moq: no
            playback: no
            metrics: no
            pprof: no
            logLevel: error
            paths:
              all:
                source: publisher
            """.write(toFile: cfgPath, atomically: true, encoding: .utf8)
            let p = Process(); p.executableURL = URL(fileURLWithPath: mediamtx); p.arguments = [cfgPath]
            let devNull = FileHandle(forWritingAtPath: "/dev/null")!
            p.standardOutput = devNull; p.standardError = devNull
            try? p.run(); server = p
            try? await Task.sleep(nanoseconds: 700_000_000)
            destination = "rtmp://127.0.0.1:19351/live/headroom"
        }
        defer { server?.terminate() }

        print("Watch Together Studio — headroom, \(cfg.width)x\(cfg.height)@\(cfg.frameRate), layout \(layout.rawValue)")
        print("  host: \(hostDescription())")
        print("  film: \(filmURL.lastPathComponent)")

        // The film, played exactly as the app plays it (a plain remote mp4 here;
        // the app's resilient loader is a URL concern, not a decode concern).
        let item = AVPlayerItem(url: filmURL)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true          // the audio path is measured separately
        let engine = StudioEngine(configuration: cfg)
        await engine.setLayout(layout)
        await engine.attachFilm(player: player)

        // Wait for the film to be playable, or there is nothing to composite.
        var waited = 0.0
        while item.status != .readyToPlay && waited < 30 {
            if item.status == .failed {
                print("FAIL: the film failed to load — \(item.error?.localizedDescription ?? "no reason")"); exit(1)
            }
            try? await Task.sleep(nanoseconds: 250_000_000); waited += 0.25
        }
        guard item.status == .readyToPlay else { print("FAIL: film not ready after 30s"); exit(1) }
        print("  film ready in \(String(format: "%.1f", waited))s; starting")
        player.play()

        do {
            try await engine.start(destination: URL(string: destination!)! as URL?)
        } catch {
            print("FAIL: engine start — \(error)"); exit(1)
        }

        var last = StudioHealth()
        var samples: [Double] = []      // achieved fps per second
        var worstRender = 0.0
        for second in 1...seconds {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await engine.refreshHealth()
            let h = await engine.health
            let fps = Double(h.programFramesRendered - last.programFramesRendered)
            let encoded = h.programFramesEncoded - last.programFramesEncoded
            let bytes = h.publisher.bytesSent - last.publisher.bytesSent
            samples.append(fps)
            worstRender = max(worstRender, h.averageRenderMilliseconds)
            print(String(format: "  %3ds  %5.1f fps rendered · %3d encoded · render mean %5.2f ms · overruns %d · %6.0f kbps · %@",
                         second, fps, encoded, h.averageRenderMilliseconds, h.renderDroppedFrames,
                         Double(bytes) * 8 / 1000, h.thermalState))
            if let e = h.publisher.lastError {
                print("  publisher error: \(e)"); break
            }
            last = h
        }

        await engine.stop()
        player.pause()

        // The verdict. Ignore the first two seconds: the film is still filling
        // its buffer and the encoder is still ramping, and a number taken there
        // describes the warm-up rather than the show.
        let steady = samples.count > 2 ? Array(samples.dropFirst(2)) : samples
        let mean = steady.reduce(0, +) / Double(max(1, steady.count))
        let low = steady.min() ?? 0
        let h = await engine.health
        print("\nSteady state over \(steady.count)s: mean \(String(format: "%.1f", mean)) fps, worst second \(String(format: "%.1f", low)) fps")
        print("Render mean \(String(format: "%.2f", h.averageRenderMilliseconds)) ms of a \(String(format: "%.1f", 1000.0 / Double(cfg.frameRate))) ms budget; \(h.renderDroppedFrames) clock overruns")
        print("Published \(h.publisher.bytesSent) bytes, \(h.publisher.videoFramesSent) video frames, \(h.publisher.videoFramesDropped) dropped; thermal \(h.thermalState)")

        let target = Double(cfg.frameRate)
        let verdict = mean >= target * 0.95 && low >= target * 0.85
        print(verdict
              ? "\nPASS: the chain holds \(cfg.frameRate) fps at \(cfg.width)x\(cfg.height) on this host"
              : "\nBELOW TARGET: \(String(format: "%.1f", mean)) fps against \(cfg.frameRate) — composite-on-device is not free here")
        exit(verdict ? 0 : 1)
    }

    static func hostDescription() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let name = String(cString: model)
        let cores = ProcessInfo.processInfo.processorCount
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return "\(name), \(cores) cores, \(os)"
    }
}
