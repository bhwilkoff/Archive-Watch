// Does a SEVERED link come back? (WATCH-TOGETHER §8.4 / §6.6.)
//
// §6.4 already governed a congested link. Nothing governed a link that is
// simply gone — the common case on domestic Wi-Fi — and the engine's answer
// was to keep encoding at full rate into a dead socket forever while the
// readout said OFFLINE. A host's broadcast of a two-hour film would end,
// silently, at minute twelve.
//
// The instrument: a TCP proxy in front of a real mediamtx that SEVERS the
// first connection with an RST after a few seconds (tools/rtmp_sever_proxy.py).
// Killing mediamtx would also destroy the recording the answer has to be read
// out of, and a harness cannot unplug real Wi-Fi.
//
// The assertion is the server's OWN recording, never our counters: media must
// exist that mediamtx accepted AFTER the sever. And the negative control is
// the same run with reconnection never attempted — it must NOT resume.
// Without that control this test passes on a server that never noticed the
// cut (Decision 120: negative-control the discriminator).
//
//   brew install mediamtx ffmpeg          # once
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -O \
//     ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift \
//     tools/StudioTestMedia.swift tools/test_rtmp_reconnect.swift -o /tmp/awrecon && /tmp/awrecon
//
// Exit 0 = the stream resumed after the cut AND the control did not.

import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

@main
struct ReconnectHarness {

    static let severAfter = 6.0
    static let runSeconds = 22.0

    /// A port PAIR per arm. Both arms used to share one pair, so a server the
    /// previous arm had not finished releasing could still hold the port while
    /// the next arm's mediamtx failed to bind and exited — leaving two
    /// recorders and an unexplained third segment. Distinct ports make the
    /// arms independent; the listening check below makes the failure loud.
    static func ports(forControl control: Bool) -> (mtx: Int, proxy: Int) {
        control ? (19351, 19352) : (19353, 19354)
    }

    /// mediamtx is SLOW to bind under load and `Process.run()` returning
    /// proves only that a process started. Poll the port instead of sleeping
    /// and hoping — a publish into a port nobody holds reads as
    /// "Connection refused", which looks like our own bug.
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

    /// Every mp4 mediamtx wrote, with the duration ffprobe reads from each.
    /// A republish makes a NEW segment, so "resumed" is provable two ways:
    /// a second segment carrying media, or one segment longer than the cut.
    struct Segment {
        let name: String
        let duration: Double
        /// Per-TRACK start times, which is where the forced keyframe shows up:
        /// without one, video begins a whole keyframe interval after audio.
        let videoStart: Double
        let audioStart: Double
        var avOffset: Double { abs(videoStart - audioStart) }
    }

    static func recordedSegments(_ ffprobe: String, _ dir: String) -> [Segment] {
        var found: [String] = []
        if let walk = FileManager.default.enumerator(atPath: dir) {
            for case let f as String in walk where f.hasSuffix(".mp4") { found.append(f) }
        }
        found.sort()
        return found.map { rel in
            let path = dir + "/" + rel
            let (_, dur) = run(ffprobe, ["-v", "error", "-of", "default=nw=1:nk=1",
                                         "-show_entries", "format=duration", path])
            let (_, streams) = run(ffprobe, ["-v", "error", "-of", "csv=p=0",
                                             "-show_entries", "stream=codec_name,start_time", path])
            var v = 0.0, a = 0.0
            for line in streams.split(separator: "\n") {
                let parts = line.split(separator: ",").map(String.init)
                guard parts.count >= 2, let t = Double(parts[1]) else { continue }
                if parts[0] == "h264" { v = t } else if parts[0] == "aac" { a = t }
            }
            return Segment(name: rel, duration: Double(dur.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
                           videoStart: v, audioStart: a)
        }
    }

    /// One episode: publish through the severing proxy for `runSeconds`,
    /// recovering or not according to `recover`.
    /// Returns (segments, publisherHealth, severObserved).
    static func episode(recover: Bool, forceKeyframe: Bool, ffprobe: String, mediamtx: String, proxy: String) async -> ([Segment], RTMPHealth, Bool) {
        let (mtxPort, proxyPort) = ports(forControl: !recover)
        let recDir = NSTemporaryDirectory() + "/aw-rtmp-recon-\(recover ? "on" : "off")\(forceKeyframe ? "-kf" : "")"
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
        logLevel: debug
        record: yes
        recordPath: \(recDir)/%path_%Y-%m-%d_%H-%M-%S-%f
        recordFormat: fmp4
        recordPartDuration: 200ms
        recordSegmentDuration: 1h
        paths:
          all:
            source: publisher
        """
        let cfgURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aw-mtx-recon-\(mtxPort).yml")
        try? cfg.write(to: cfgURL, atomically: true, encoding: .utf8)
        let server = Process()
        server.executableURL = URL(fileURLWithPath: mediamtx)
        server.arguments = [cfgURL.path]
        let logURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aw-mtx-recon-\(mtxPort).log")
        try? Data().write(to: logURL)
        let serverOut = FileHandle(forWritingAtPath: logURL.path)!
        server.standardOutput = serverOut; server.standardError = serverOut
        try? server.run()
        defer { server.terminate(); kill(server.processIdentifier, SIGKILL) }
        guard await waitForListener(port: mtxPort, seconds: 10) else {
            print("   mediamtx never listened on :\(mtxPort)")
            return ([], RTMPHealth(), false)
        }

        // The severing proxy, and its stdout is the evidence the cut happened.
        let prox = Process()
        prox.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        prox.arguments = [proxy, "\(proxyPort)", "\(mtxPort)", "\(severAfter)"]
        let proxPipe = Pipe(); prox.standardOutput = proxPipe; prox.standardError = proxPipe
        let proxLog = ProxyLog()
        proxPipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if !d.isEmpty, let s = String(data: d, encoding: .utf8) { proxLog.append(s) }
        }
        try? prox.run()
        defer { prox.terminate(); kill(prox.processIdentifier, SIGKILL) }
        guard await waitForListener(port: proxyPort, seconds: 10) else {
            print("   the sever proxy never listened on :\(proxyPort)")
            return ([], RTMPHealth(), false)
        }

        let video = TestVideoEncoder(); let audio = TestAudioEncoder()
        video.start(); audio.start()
        let publisher = RTMPPublisher()
        var gotConfig = false
        let box = ConfigBox()
        video.onSample = { sample in
            if !gotConfig, let a = avcC(from: sample) {
                gotConfig = true
                box.value = RTMPStreamConfig(width: video.width, height: video.height, frameRate: Double(video.fps),
                    videoBitrate: 2_000_000, avcC: a, audioSampleRate: audio.sampleRate, audioChannels: 1,
                    audioBitrate: 96_000, audioSpecificConfig: audio.audioSpecificConfig)
            }
            box.append(sample)
        }
        video.encode(frame: 0)
        var tries = 0
        while !gotConfig && tries < 50 { try? await Task.sleep(nanoseconds: 20_000_000); tries += 1 }
        guard let config = box.value else { return ([], RTMPHealth(), false) }

        let url = URL(string: "rtmp://127.0.0.1:\(proxyPort)/live/awrecon")!
        do { try await publisher.publish(to: url, config: config) }
        catch { print("   publish threw: \(error)"); return ([], await publisher.health, proxLog.severed) }

        audio.onFrame = { data, pts in Task { await publisher.send(audioFrame: data, presentationTime: pts) } }
        for s in box.drainVideo() {
            if let f = EncodedVideoFrame(s) { await publisher.send(video: f) }
        }

        let started = Date()
        var frame = 1
        var nextAttemptAt: Date? = nil
        var attempt = 0
        // Frame-level keyframe tracing, off by default. KEPT rather than
        // deleted because it is what corrected a wrong diagnosis: the A/V
        // assertion fired, "the reconnect did not open on a keyframe" looked
        // obvious, and this showed the forced keyframe landing one frame after
        // the reconnect — so the fault was the harness's own audio clock.
        //   AW_STUDIO_DIAG=1 /tmp/awrecon
        let diagnose = ProcessInfo.processInfo.environment["AW_STUDIO_DIAG"] == "1"
        var framesToWatch = 0
        var reconnectedAt: Date? = nil
        while Date().timeIntervalSince(started) < runSeconds {
            video.encode(frame: frame)
            for s in box.drainVideo() {
                if let f = EncodedVideoFrame(s) {
                    if framesToWatch > 0 {
                        print("   [diag] frame \(frame) isKeyframe=\(f.isKeyframe) \(f.avccData.count)B")
                        framesToWatch -= 1
                    }
                    await publisher.send(video: f)
                }
            }
            // Pace the tone to the VIDEO clock. One AAC frame per video frame
            // drifts ~10 ms a frame, and a republish makes a server re-base to
            // the earliest track — so the drift arrives looking exactly like
            // "the reconnect broke A/V sync". It cost a wrong diagnosis here
            // before the frame-level diagnostic showed the forced keyframe
            // landing correctly one frame after the reconnect.
            let videoClock = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(video.fps))
            while audio.elapsed < videoClock { audio.encodeOneFrame() }
            frame += 1

            // §6.6's recovery, driven through the PRODUCT's own predicate and
            // its own `reconnect()`, on the shared RTMPReconnectPolicy
            // schedule. The engine's supervisor wraps the same two calls in
            // the same schedule; what this harness does NOT prove is that
            // supervisor's wiring, which is verified on a device.
            if recover, await publisher.needsReconnect {
                let now = Date()
                if nextAttemptAt == nil || now >= nextAttemptAt! {
                    attempt += 1
                    do {
                        try await publisher.reconnect()
                        // §6.6: the new session must OPEN on a keyframe. The
                        // publisher drops inter-frames until one arrives, so
                        // without this the stream is AUDIO-ONLY until the
                        // encoder's next natural keyframe — measured at 2.26 s
                        // on a 60-frame interval (§9).
                        if forceKeyframe { video.requestKeyframe(); framesToWatch = diagnose ? 12 : 0 }
                        reconnectedAt = Date()
                        print("   reconnected on attempt \(attempt) after \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
                        nextAttemptAt = nil
                        attempt = 0
                    } catch {
                        let back = RTMPReconnectPolicy.backoffSeconds[min(attempt - 1, RTMPReconnectPolicy.backoffSeconds.count - 1)]
                        nextAttemptAt = Date().addingTimeInterval(back)
                        print("   attempt \(attempt) failed (\(error)); next in \(back)s")
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 33_000_000)
        }
        video.finish()
        _ = reconnectedAt
        try? await Task.sleep(nanoseconds: 500_000_000)
        let health = await publisher.health
        await publisher.close()
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        return (recordedSegments(ffprobe, recDir), health, proxLog.severed)
    }

    static func main() async {
        guard let mediamtx = which("mediamtx") else { print("SKIP: mediamtx not installed (brew install mediamtx)"); exit(2) }
        guard let ffprobe = which("ffprobe") else { print("SKIP: ffprobe not installed (brew install ffmpeg)"); exit(2) }
        let proxy = FileManager.default.currentDirectoryPath + "/tools/rtmp_sever_proxy.py"
        guard FileManager.default.fileExists(atPath: proxy) else { print("FAIL: run from the repo root (no \(proxy))"); exit(1) }

        print("WATCH-TOGETHER §8.4 — a severed link, cut at \(severAfter)s of a \(Int(runSeconds))s program")
        print("  policy: backoff \(RTMPReconnectPolicy.backoffSeconds)s, deadline \(RTMPReconnectPolicy.deadlineSeconds)s")

        // ---- The control FIRST, so a harness bug cannot be hidden by a pass.
        print("\n[control] reconnection NOT attempted — the stream must NOT resume")
        let (ctlSegs, ctlHealth, ctlSevered) = await episode(recover: false, forceKeyframe: false, ffprobe: ffprobe, mediamtx: mediamtx, proxy: proxy)
        guard ctlSevered else {
            print("FAIL: the proxy never reported severing the connection — the instrument did not do its job")
            exit(1)
        }
        let ctlTotal = ctlSegs.reduce(0.0) { $0 + $1.duration }
        print("  control: \(ctlSegs.count) segment(s), \(String(format: "%.1f", ctlTotal))s recorded, publisher \(ctlHealth.state.rawValue)")
        guard ctlTotal < severAfter + 4 else {
            print("FAIL: the control recorded \(String(format: "%.1f", ctlTotal))s — more than the \(severAfter)s before the cut.")
            print("      The sever is not severing, so a pass in the live case would prove nothing.")
            exit(1)
        }
        print("OK: without reconnection the stream stays dead (\(String(format: "%.1f", ctlTotal))s ≈ the \(severAfter)s before the cut)")

        // ---- §6.6 itself.
        print("\n[§6.6] reconnection attempted — the stream must resume")
        let (segs, health, severed) = await episode(recover: true, forceKeyframe: true, ffprobe: ffprobe, mediamtx: mediamtx, proxy: proxy)
        guard severed else { print("FAIL: the proxy never severed the live run"); exit(1) }
        let total = segs.reduce(0.0) { $0 + $1.duration }
        for seg in segs {
            print("  recorded \(seg.name) — \(String(format: "%.1f", seg.duration))s, "
                  + "video starts \(String(format: "%.2f", seg.videoStart))s, audio \(String(format: "%.2f", seg.audioStart))s")
        }
        print("  publisher: \(health.state.rawValue), \(health.reconnects) reconnect(s), "
              + "\(health.videoFramesSent)v/\(health.audioFramesSent)a, \(health.bytesSent) bytes")

        guard health.reconnects >= 1 else { print("FAIL: the publisher never reconnected"); exit(1) }
        guard health.state == .publishing else {
            print("FAIL: the publisher is \(health.state.rawValue), not publishing, at the end of the run")
            exit(1)
        }
        // The load-bearing assertion, and it is the SERVER's: media accepted
        // after the cut. Recorded seconds must exceed what existed before it
        // by a real margin, not by rounding.
        guard total > severAfter + 5 else {
            print("FAIL: mediamtx recorded \(String(format: "%.1f", total))s — no media arrived after the cut.")
            print("      The publisher believing it reconnected is not evidence that anything was ingested.")
            exit(1)
        }
        // And it must beat the control by more than noise, or "resumed" is
        // just a longer first segment.
        guard total > ctlTotal + 4 else {
            print("FAIL: \(String(format: "%.1f", total))s recorded vs the control's \(String(format: "%.1f", ctlTotal))s — not a resumption")
            exit(1)
        }
        print("OK: \(String(format: "%.1f", total))s recorded across \(segs.count) segment(s) after a cut at \(severAfter)s")

        // The forced keyframe, asserted where it is VISIBLE: in the resumed
        // segment's own track start times. Without it the publisher correctly
        // drops inter-frames until the next natural keyframe and the segment
        // opens audio-only — 2.26 s of it, measured on this harness before
        // the request was wired in (§9). A viewer rejoining into that hears
        // the host over a blank screen.
        // EVERY segment after the first, not `segs.last`. The first version of
        // this check read the last segment and PASSED while the resumed one
        // carried a 1.62 s offset: mediamtx had written a short third segment
        // at close, and the assertion looked at that. An instrument that picks
        // which sample to judge will eventually pick the wrong one.
        guard segs.count > 1 else { print("FAIL: only one segment — nothing resumed"); exit(1) }
        for seg in segs.dropFirst() {
            print("  post-cut segment \(seg.name) A/V offset: \(String(format: "%.2f", seg.avOffset))s")
            guard seg.avOffset < 0.5 else {
                print("FAIL: video starts \(String(format: "%.2f", seg.avOffset))s after audio in \(seg.name) —")
                print("      the reconnected session did not open on a keyframe, so a rejoining")
                print("      viewer hears the host over a blank screen for that long.")
                exit(1)
            }
        }
        print("OK: every post-cut segment opens on a keyframe (A/V within 0.5s)")
        print("\nPASS: §6.6 — a severed link is rebuilt and the server ingests the rest of the show")
        exit(0)
    }
}

/// The proxy's stdout, read on its own handler thread.
final class ProxyLog: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func append(_ s: String) { lock.lock(); text += s; lock.unlock(); FileHandle.standardError.write(Data()) }
    var severed: Bool { lock.lock(); defer { lock.unlock() }; return text.contains("SEVERED") }
}
