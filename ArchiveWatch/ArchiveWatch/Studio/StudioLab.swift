// StudioLab — the Watch Together Studio measurement, ON THE DEVICE
// (docs/WATCH-TOGETHER.md §8.2).
//
// Phase 0's question cannot be answered by a command-line harness: the
// hardware that matters is an iPhone 12 and a 2nd-generation Apple TV, and
// neither runs one. So the engine is exercised from inside the app behind an
// environment gate, printing one line a second to stdout — the same discipline
// as FunctionalAudit and CreationStudioSelfTest, read from the dev Mac with
// `devicectl device process launch --console`.
//
// It streams to a destination YOU name. Point it at a mediamtx on the dev Mac
// for a measurement; point it at a platform's rtmps:// ingest to prove the
// real thing. No UI, nothing durable is touched, and it is a no-op unless
// AW_STUDIO_LAB=1.
//
//   AW_STUDIO_LAB=1
//   AW_STUDIO_DEST=rtmp://10.0.0.90:19351/live/lab   (required)
//   AW_STUDIO_FILM=<direct mp4 url>                  (default: The General)
//   AW_STUDIO_W / _H / _FPS / _BITRATE               (default 1920/1080/30/6M)
//   AW_STUDIO_LAYOUT=film|corner|theatre|side|host   (default corner)
//   AW_STUDIO_SECONDS=40
//   AW_STUDIO_CAMERA=1                               (attach the front camera)

import AVFoundation
import Foundation

#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum StudioLab {

    static var enabled: Bool {
        ProcessInfo.processInfo.environment["AW_STUDIO_LAB"] == "1"
    }

    private static func env(_ k: String) -> String? {
        let v = ProcessInfo.processInfo.environment[k]
        return (v?.isEmpty ?? true) ? nil : v
    }

    private static func log(_ s: String) { print("[AWSTUDIO] \(s)") }

    /// A 1080p-class public-domain feature the catalog keeps (rights: pre-1930
    /// by age), with a direct mp4 — the same film the Roku deep-link demo uses,
    /// so a failure here is never "which copy?".
    private static let defaultFilm =
        "https://archive.org/download/TheGeneral720p1926/TheGeneral720p.mp4"

    static func run() async {
        // `none` encodes and discards: the headroom question is decode +
        // composite + encode, and on iOS a LAN destination needs the
        // local-network permission prompt a human would have to tap.
        let destRaw = env("AW_STUDIO_DEST") ?? "none"
        let destURL: URL? = destRaw == "none" ? nil : URL(string: destRaw)
        if destRaw != "none" && destURL == nil {
            log("FAIL AW_STUDIO_DEST is not a URL: \(destRaw)")
            return
        }
        var cfg = StudioEngine.Configuration()
        cfg.width = Int(env("AW_STUDIO_W") ?? "") ?? 1920
        cfg.height = Int(env("AW_STUDIO_H") ?? "") ?? 1080
        cfg.frameRate = Int(env("AW_STUDIO_FPS") ?? "") ?? 30
        cfg.videoBitrate = Int(env("AW_STUDIO_BITRATE") ?? "") ?? 6_000_000
        let layout = StudioLayout(rawValue: env("AW_STUDIO_LAYOUT") ?? "corner") ?? .corner
        let seconds = Int(env("AW_STUDIO_SECONDS") ?? "") ?? 40
        let filmURL = URL(string: env("AW_STUDIO_FILM") ?? defaultFilm)!
        let wantCamera = env("AW_STUDIO_CAMERA") == "1"

        log("host \(hostDescription())")
        log("program \(cfg.width)x\(cfg.height)@\(cfg.frameRate) \(cfg.videoBitrate / 1000) kbps, layout \(layout.rawValue), camera \(wantCamera)")
        log(destURL.map { "dest \($0.host ?? "?"):\($0.port ?? 1935)\($0.path)" } ?? "dest none (encode and discard)")
        log("film \(filmURL.lastPathComponent)")

        // The audio session must allow playback while we are also (later)
        // recording — set it even for the film-only run, so the measurement
        // runs under the session the Studio will really use (§6.2).
        #if os(iOS) || os(tvOS)
        do {
            let s = AVAudioSession.sharedInstance()
            // THREE device findings live in these four lines.
            //
            // 1. `.moviePlayback` is a playback-only MODE; pairing it with
            //    `.playAndRecord` returns OSStatus -50 (iPhone 12).
            // 2. `.defaultToSpeaker` does not exist on tvOS — no earpiece to
            //    route away from.
            // 3. `.playAndRecord` ITSELF fails on tvOS ("Session activation
            //    failed"), and a failed activation stops AVPlayer dead: the
            //    Apple TV run showed rate=0.00 with status=readyToPlay, so the
            //    program encoded a frozen frame while every counter looked
            //    healthy. tvOS gets `.playback` until a Continuity microphone
            //    is actually attached, which is when recording becomes real.
            #if os(tvOS)
            try s.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            #else
            try s.setCategory(.playAndRecord, mode: .default,
                              options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
            #endif
            try s.setActive(true)
        } catch {
            log("WARN audio session — \(error.localizedDescription)")
        }
        #endif
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = true
        #endif

        let item = AVPlayerItem(url: filmURL)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true          // the audio path is a later measurement

        let engine = StudioEngine(configuration: cfg)
        await engine.setLayout(layout)
        await engine.attachFilm(player: player)

        var camera: AVCaptureSession?
        if wantCamera {
            if let s = await makeCameraSession() {
                let tap = CameraFrameTap()
                tap.attach(to: s)
                await engine.attachCamera(tap: tap)
                s.startRunning()
                camera = s
                log("camera attached")
            } else {
                log("WARN no camera available — continuing film-only")
            }
        }

        // Wait for the film, or there is nothing to composite. A slow archive
        // fetch is not a Studio fault, so it is timed and reported separately.
        var waited = 0.0
        while item.status != .readyToPlay && waited < 40 {
            if item.status == .failed {
                log("FAIL film did not load — \(item.error?.localizedDescription ?? "no reason")")
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000); waited += 0.25
        }
        guard item.status == .readyToPlay else { log("FAIL film not ready after 40s"); return }
        log(String(format: "film ready in %.1fs", waited))
        player.play()

        do {
            try await engine.start(destination: destURL)
        } catch {
            log("FAIL engine start — \(error)")
            return
        }
        log("live — one line a second for \(seconds)s")

        var last = StudioHealth()
        var samples: [Double] = []
        for second in 1...seconds {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await engine.refreshHealth()
            let h = await engine.health
            let fps = Double(h.programFramesRendered - last.programFramesRendered)
            let encoded = h.programFramesEncoded - last.programFramesEncoded
            // Encoded bytes, not published bytes: the same number on a null
            // sink as on a real destination.
            let kbps = Double(h.encodedBytes - last.encodedBytes) * 8 / 1000
            samples.append(fps)
            let filmFps = h.filmFramesPulled - last.filmFramesPulled
            log(String(format: "%3ds fps=%.0f film=%d enc=%d render=%.2fms overruns=%d drops=%d kbps=%.0f queue=%d thermal=%@",
                       second, fps, filmFps, encoded, h.averageRenderMilliseconds, h.renderDroppedFrames,
                       h.publisher.videoFramesDropped, kbps, h.publisher.queuedBytes, h.thermalState))
            if let e = h.publisher.lastError { log("FAIL publisher — \(e)"); break }
            // When the film is not arriving, say WHY rather than reporting a
            // healthy-looking frozen picture.
            if filmFps == 0 && second <= 5 {
                log("     film stalled: \(await engine.filmDiagnostics())")
            }
            last = h
        }

        await engine.stop()
        player.pause()
        camera?.stopRunning()
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif

        // The first two seconds are warm-up (the film is still buffering, the
        // encoder still ramping); a number taken there describes the warm-up.
        let steady = samples.count > 2 ? Array(samples.dropFirst(2)) : samples
        let mean = steady.reduce(0, +) / Double(max(1, steady.count))
        let low = steady.min() ?? 0
        let h = await engine.health
        let target = Double(cfg.frameRate)
        let pass = mean >= target * 0.95 && low >= target * 0.85
        log(String(format: "SUMMARY mean=%.1ffps worst=%.1ffps filmFrames=%d render=%.2fms budget=%.1fms overruns=%d dropped=%d thermal=%@",
                   mean, low, h.filmFramesPulled, h.averageRenderMilliseconds, 1000 / target,
                   h.renderDroppedFrames, h.publisher.videoFramesDropped, h.thermalState))
        if h.filmFramesPulled < h.programFramesRendered / 4 {
            log("WARN the film supplied only \(h.filmFramesPulled) frames for \(h.programFramesRendered) program frames — the program was mostly a frozen picture, so these fps are NOT a composite measurement")
        }
        log(pass
            ? "PASS \(cfg.width)x\(cfg.height)@\(cfg.frameRate) holds on \(hostDescription())"
            : "BELOW TARGET \(String(format: "%.1f", mean)) of \(cfg.frameRate) fps on \(hostDescription())")
    }

    // MARK: Camera

    /// A camera session for whichever platform this is. On tvOS this is
    /// Continuity Camera, which requires the viewer to have paired an iPhone
    /// through the system picker first — so here it only picks up a device
    /// that is ALREADY available, and says so when there is none.
    private static func makeCameraSession() async -> AVCaptureSession? {
        #if os(tvOS)
        let types: [AVCaptureDevice.DeviceType] = [.continuityCamera]
        #elseif os(iOS)
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        #else
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera]
        #endif
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified)
        guard let device = discovery.devices.first else { return nil }
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            log("WARN camera permission refused")
            return nil
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else { return nil }
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720   // the camera tile is never full-frame in v1
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        return session
    }

    // MARK: Host

    static func hostDescription() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let model = String(cString: machine)
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let cores = ProcessInfo.processInfo.processorCount
        let mem = ProcessInfo.processInfo.physicalMemory / 1_048_576
        return "\(model) \(cores)c \(mem)MB \(os)"
    }
}
