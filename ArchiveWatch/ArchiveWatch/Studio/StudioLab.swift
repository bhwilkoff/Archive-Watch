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

    /// Probes the REAL ingest hosts from this device with a deliberately
    /// invalid key. macOS proving the protocol does not prove it from a phone
    /// or a television: different TLS stack, different network path, different
    /// service-class handling. Needs no credential — a refusal after an
    /// acknowledged `connect` is the pass (WATCH-TOGETHER §8.1a).
    static func probeDestinations() async {
        log("probing real ingest hosts from this device (invalid key, no credential)")
        // A real Baseline 1080p30 avcC and AAC-LC ASC: servers inspect the
        // sequence headers, so nonsense could be refused for the wrong reason.
        let sps: [UInt8] = [0x67, 0x42, 0x00, 0x28, 0xE9, 0x00, 0x80, 0x0C, 0x8B, 0x01, 0x00, 0x00, 0x03, 0x00, 0x01]
        let pps: [UInt8] = [0x68, 0xCE, 0x3C, 0x80]
        var avcC: [UInt8] = [0x01, 0x42, 0x00, 0x28, 0xFF, 0xE1]
        avcC += [UInt8(sps.count >> 8), UInt8(sps.count & 0xFF)] + sps
        avcC += [0x01, UInt8(pps.count >> 8), UInt8(pps.count & 0xFF)] + pps
        let cfg = RTMPStreamConfig(
            width: 1920, height: 1080, frameRate: 30, videoBitrate: 6_000_000,
            avcC: Data(avcC), audioSampleRate: 44100, audioChannels: 2,
            audioBitrate: 128_000, audioSpecificConfig: Data([0x12, 0x10]))

        let targets: [(String, String, String)] = [
            ("YouTube RTMPS", "rtmps://a.rtmps.youtube.com/live2", "aw-invalid-key-probe"),
            ("YouTube RTMP", "rtmp://a.rtmp.youtube.com/live2", "aw-invalid-key-probe"),
            ("Twitch RTMPS", "rtmps://ingest.global-contribute.live-video.net/app", "live_invalid_probe"),
            ("Twitch RTMP", "rtmp://ingest.global-contribute.live-video.net/app", "live_invalid_probe"),
        ]
        var ok = 0
        for (name, server, key) in targets {
            guard let url = URL(string: server) else { continue }
            let pub = RTMPPublisher()
            let t0 = Date()
            do {
                try await pub.publish(to: url, streamKey: key, config: cfg, timeout: 20)
                log("PROBE ? \(name) — accepted an invalid key (unexpected); closing")
                ok += 1
            } catch {
                let acked = await pub.health.connectAcknowledged
                let dt = Date().timeIntervalSince(t0)
                if acked {
                    log(String(format: "PROBE ✓ %@ — connect acknowledged, refused in %.1fs", name, dt))
                    ok += 1
                } else {
                    log(String(format: "PROBE ✗ %@ — failed BEFORE connect in %.1fs: %@", name, dt, "\(error)"))
                }
            }
            await pub.close()
        }
        log("PROBE \(ok)/\(targets.count) reached and answered from \(hostDescription())")
    }

    static func run() async {
        if env("AW_STUDIO_PROBE") == "1" {
            setUpAudioSession()
            await probeDestinations()
            if env("AW_STUDIO_PROBE_ONLY") == "1" { return }
        }
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
        if env("AW_STUDIO_MUTE") == "1" { log("film MUTED locally (AW_STUDIO_MUTE=1)") }
        log("film \(filmURL.lastPathComponent)")

        // The audio session must allow playback while we are also (later)
        // recording — set it even for the film-only run, so the measurement
        // runs under the session the Studio will really use (§6.2).
        setUpAudioSession()
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = true
        #endif

        let item = AVPlayerItem(url: filmURL)
        let player = AVPlayer(playerItem: item)
        // NOT muted by default: the film's audio is what the tap carries, and
        // a muted player is the obvious way to measure silence and call it a
        // working audio path. `AW_STUDIO_MUTE=1` is available for a silent run.
        player.isMuted = env("AW_STUDIO_MUTE") == "1"

        let engine = StudioEngine(configuration: cfg)
        await engine.setLayout(layout)
        // The lower third is part of the program, so it is part of the
        // measurement. AW_STUDIO_NO_OVERLAY=1 isolates its cost.
        if env("AW_STUDIO_NO_OVERLAY") != "1" {
            var o = StudioOverlay()
            o.title = "The General"
            o.subtitle = "1926 · Buster Keaton, Clyde Bruckman"
            o.provenance = "Public domain since 1954"
            await engine.setOverlay(o)
        }

        var camera: AVCaptureSession?
        if wantCamera {
            if let s = await makeCameraSession() {
                let tap = CameraFrameTap()
                tap.attach(to: s)
                await engine.attachCamera(tap: tap)
                let micTap = MicAudioTap()
                let gotMic = micTap.attach(to: s)
                await engine.attachMicrophone(tap: micTap)
                s.startRunning()
                camera = s
                log("camera attached, microphone \(gotMic ? "attached" : "UNAVAILABLE")")
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
        // The audio tap needs the player's TRACKS, which exist only once the
        // item is ready — so the film is attached here, not before the wait.
        await engine.attachFilm(player: player)
        log("film audio track: \(await engine.filmHasAudio ? "tapped" : "none (silent film?)")")
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
            let a = h.audio
            let la = last.audio
            log(String(format: "%3ds fps=%.0f film=%d enc=%d render=%.2fms overruns=%d drops=%d kbps=%.0f thermal=%@ | aac=%d filmAud=%d micAud=%d pad=%d lvlF=%.2f lvlM=%.2f duck=%@",
                       second, fps, filmFps, encoded, h.averageRenderMilliseconds, h.renderDroppedFrames,
                       h.publisher.videoFramesDropped, kbps, h.thermalState,
                       a.aacFramesEncoded - la.aacFramesEncoded,
                       a.filmFramesWritten - la.filmFramesWritten,
                       a.micFramesWritten - la.micFramesWritten,
                       a.filmFramesPadded - la.filmFramesPadded,
                       a.filmLevel, a.micLevel, a.ducking ? "y" : "n"))
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
        let a = h.audio
        log("AUDIO aac=\(a.aacFramesEncoded) filmFrames=\(a.filmFramesWritten) micFrames=\(a.micFramesWritten) padded(film)=\(a.filmFramesPadded) padded(mic)=\(a.micFramesPadded)")
        if a.aacFramesEncoded == 0 {
            log("WARN no AAC was encoded — the program had NO audio at all")
        } else if await engine.filmHasAudio && a.filmFramesWritten == 0 {
            log("WARN the film's audio track was tapped but delivered NOTHING — the program is silent where the film should be")
        }
        if h.filmFramesPulled < h.programFramesRendered / 4 {
            log("WARN the film supplied only \(h.filmFramesPulled) frames for \(h.programFramesRendered) program frames — the program was mostly a frozen picture, so these fps are NOT a composite measurement")
        }
        log(pass
            ? "PASS \(cfg.width)x\(cfg.height)@\(cfg.frameRate) holds on \(hostDescription())"
            : "BELOW TARGET \(String(format: "%.1f", mean)) of \(cfg.frameRate) fps on \(hostDescription())")
    }

    /// The Studio's audio session, per platform. THREE device findings live
    /// here: `.moviePlayback` is a playback-only MODE and pairing it with
    /// `.playAndRecord` returns OSStatus -50 (iPhone 12); `.defaultToSpeaker`
    /// does not exist on tvOS; and `.playAndRecord` ITSELF fails on tvOS
    /// ("Session activation failed"), where a failed activation stops AVPlayer
    /// dead — the Apple TV showed rate=0.00 with status=readyToPlay and
    /// encoded a frozen frame while every counter looked healthy.
    static func setUpAudioSession() {
        #if os(iOS) || os(tvOS)
        do {
            let s = AVAudioSession.sharedInstance()
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
    }

    // MARK: Camera

    /// A camera session for whichever platform this is. On tvOS this is
    /// Continuity Camera, which requires the viewer to have paired an iPhone
    /// through the system picker first — so here it only picks up a device
    /// that is ALREADY available, and says so when there is none.
    private static func makeCameraSession() async -> AVCaptureSession? {
        #if os(tvOS)
        // tvOS goes through StudioContinuity, which knows that the MICROPHONE
        // is an audio-session PORT rather than a capture device, and that
        // `.playAndRecord` only becomes legitimate once such a port exists.
        let continuity = StudioContinuity()
        // Discovery is asynchronous; give it a moment before judging.
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        log("continuity: \(continuity.state) — \(continuity.note)")
        guard continuity.state.isConnected, let s = continuity.makeSession() else {
            log("SKIP camera — pair an iPhone once on this Apple TV (the system picker); a paired phone is found automatically afterwards")
            return nil
        }
        return s
        #elseif os(iOS)
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        #else
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera]
        #endif
        #if !os(tvOS)

        // PERMISSION IS A HUMAN ACTION, AND THIS HARNESS MUST NOT WAIT ON ONE.
        // `requestAccess` presents a system alert and suspends until it is
        // tapped, which hung a device run with no output past "film …" — and
        // the standing rule is that the owner is never the tester. So the
        // status is reported and an undecided permission is REFUSED rather
        // than requested, with the one-time grant named in the log.
        let video = AVCaptureDevice.authorizationStatus(for: .video)
        let audio = AVCaptureDevice.authorizationStatus(for: .audio)
        log("permissions: camera=\(name(video)) microphone=\(name(audio))")
        guard video == .authorized else {
            log("SKIP camera — grant it once on the device (Settings ▸ Archive Watch ▸ Camera + Microphone), then re-run; AW_STUDIO_ASK=1 will present the prompt instead")
            if env("AW_STUDIO_ASK") == "1" {
                log("AW_STUDIO_ASK=1 — presenting the system prompt; tap Allow on the device")
                _ = await AVCaptureDevice.requestAccess(for: .video)
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                log("permissions now: camera=\(name(AVCaptureDevice.authorizationStatus(for: .video))) microphone=\(name(AVCaptureDevice.authorizationStatus(for: .audio)))")
            }
            return nil
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified)
        guard let device = discovery.devices.first else {
            log("WARN no camera device of \(types.map(\.rawValue).joined(separator: ", "))")
            return nil
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else { return nil }
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720   // the camera tile is never full-frame in v1
        if session.canAddInput(input) { session.addInput(input) }
        // The microphone rides the SAME session, which is how tvOS gets the
        // Continuity microphone alongside the Continuity camera.
        if audio == .authorized,
           let micDevice = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: micDevice),
           session.canAddInput(micInput) {
            session.addInput(micInput)
        } else {
            log("WARN no microphone input on the session (audio=\(name(audio)))")
        }
        session.commitConfiguration()
        log("camera \(device.localizedName) via \(device.deviceType.rawValue)")
        return session
        #endif
    }

    private static func name(_ s: AVAuthorizationStatus) -> String {
        switch s {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not-determined"
        @unknown default: return "unknown"
        }
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
