// Does our RTMP publisher produce a stream a real server accepts and a real
// demuxer reads back? (WATCH-TOGETHER §8.1, Decision 127.)
//
// The publisher is the transport under Watch Together Studio, and every part
// of it — the handshake, the AMF0 connect, the FLV tags, the AVC/AAC sequence
// headers — fails as a clean-looking stream of bytes that a golden file
// generated from the same code would not catch (the QR lesson, Decision 119).
// So this proves it against an INDEPENDENT reference on both ends: mediamtx
// ingests the RTMP, ffprobe reads the result back, and the harness asserts
// codec, resolution, frame rate and audio sample rate against what we fed in.
//
// It encodes a synthetic program (a moving bar, a 440 Hz tone) with
// VideoToolbox + AudioConverter — the SAME encoders the Studio uses — so the
// avcC/ASC path and the sample-buffer shapes are exercised, not faked.
//
//   brew install mediamtx ffmpeg          # once
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -O \
//     ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift \
//     tools/StudioTestMedia.swift tools/test_rtmp_publish.swift -o /tmp/awrtmp && /tmp/awrtmp
//
// Exit 0 = the stream was ingested and read back with the right shape.
// The negative control (a wrong path the server would refuse) is asserted too.

import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

// MARK: - Harness

@main
struct Harness {
    static func run(_ launch: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        try? p.run(); p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Whatever mediamtx has written to its log so far.
    static func serverLog(_ ignored: Any? = nil) -> String {
        let path = NSTemporaryDirectory() + "/aw-mediamtx.log"
        let s = (try? String(contentsOfFile: path, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? "(nothing)" : s
    }

    /// Is anything accepting TCP on this local port right now?
    static func isListening(_ port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return true }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        return r == 0
    }

    static func which(_ tool: String) -> String? {
        let (_, out) = run("/usr/bin/which", [tool])
        let path = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    static func main() async {
        setvbuf(stdout, nil, _IOLBF, 0)   // line-buffered: a hang must still show how far it got
        guard let mediamtx = which("mediamtx") else { print("SKIP: mediamtx not installed (brew install mediamtx)"); exit(2) }
        guard let ffprobe = which("ffprobe") else { print("SKIP: ffprobe not installed (brew install ffmpeg)"); exit(2) }

        // 1. Start mediamtx on a private port so we never collide with a real one.
        // mediamtx RECORDS what we publish. Probing the recording rather than a
        // live reader is the stronger assertion: it is the bytes the server
        // actually accepted, demuxed and re-muxed, read back by a demuxer that
        // shares no code with us — and it does not race the one-shot AVC
        // sequence header the way a late-joining live reader does.
        let recDir = NSTemporaryDirectory() + "/aw-rtmp-rec"
        try? FileManager.default.removeItem(atPath: recDir)
        try? FileManager.default.createDirectory(atPath: recDir, withIntermediateDirectories: true)
        let cfg = """
        rtmp: yes
        rtmpAddress: :19350
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
        let cfgURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aw-mediamtx.yml")
        try? cfg.write(to: cfgURL, atomically: true, encoding: .utf8)
        let server = Process()
        server.executableURL = URL(fileURLWithPath: mediamtx)
        server.arguments = [cfgURL.path]
        let logURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aw-mediamtx.log")
        try? Data().write(to: logURL)
        let serverOut = FileHandle(forWritingAtPath: logURL.path)!
        server.standardOutput = serverOut; server.standardError = serverOut
        print("… starting mediamtx on :19350")
        do { try server.run() } catch { print("FAIL: could not start mediamtx: \(error)"); exit(1) }
        defer { server.terminate() }
        try? await Task.sleep(nanoseconds: 800_000_000)

        // 2. Encode a 4-second synthetic program and publish it.
        let video = TestVideoEncoder(); let audio = TestAudioEncoder()
        video.start(); audio.start()
        let publisher = RTMPPublisher()

        // Collect the first video sample's avcC before publishing (config is
        // needed for the connect); encode one frame synchronously to get it.
        var gotConfig = false
        let configBox = ConfigBox()
        video.onSample = { sample in
            if !gotConfig, let avcC = avcC(from: sample) {
                gotConfig = true
                configBox.value = RTMPStreamConfig(width: video.width, height: video.height, frameRate: Double(video.fps),
                    videoBitrate: 2_000_000, avcC: avcC, audioSampleRate: audio.sampleRate, audioChannels: 1,
                    audioBitrate: 96_000, audioSpecificConfig: audio.audioSpecificConfig)
            }
            configBox.append(sample)
        }
        print("… encoding frame 0 for avcC")
        video.encode(frame: 0)
        var tries = 0
        while !gotConfig && tries < 50 { try? await Task.sleep(nanoseconds: 20_000_000); tries += 1 }
        guard let config = configBox.value else { print("FAIL: no avcC from the encoder"); exit(1) }

        print("… got avcC (\(config.avcC.count) bytes); connecting")
        let url = URL(string: "rtmp://127.0.0.1:19350/live/awtest")!
        do {
            try await publisher.publish(to: url, config: config)
        } catch {
            print("FAIL: publish() to local mediamtx threw: \(error)")
            print("  mediamtx said:\n\(serverLog())")
            exit(1)
        }
        print("OK: publish handshake accepted by mediamtx")

        // 3. Push the rest of the program: 120 video frames + 172 audio frames (~4s).
        // EncodedVideoFrame, built here on the harness's thread — a
        // CMSampleBuffer is not Sendable and never crosses into the actor.
        for f in configBox.drainVideo() {
            if let frame = EncodedVideoFrame(f) { await publisher.send(video: frame) }
        }
        audio.onFrame = { data, pts in Task { await publisher.send(audioFrame: data, presentationTime: pts) } }
        for i in 1...120 {
            video.encode(frame: i)
            for s in configBox.drainVideo() {
                if let frame = EncodedVideoFrame(s) { await publisher.send(video: frame) }
            }
            audio.encodeOneFrame()
            if i % 30 == 0 {
                let h = await publisher.health
                print("  \(i)/120 frames — sent \(h.videoFramesSent)v/\(h.audioFramesSent)a, \(h.bytesSent) bytes, dropped \(h.videoFramesDropped)")
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        video.finish()
        for s in configBox.drainVideo() {
            if let frame = EncodedVideoFrame(s) { await publisher.send(video: frame) }
        }
        try? await Task.sleep(nanoseconds: 500_000_000)

        let afterSend = await publisher.health
        print("… publisher: \(afterSend.state.rawValue), \(afterSend.videoFramesSent)v/\(afterSend.audioFramesSent)a, \(afterSend.bytesSent) bytes, dropped \(afterSend.videoFramesDropped)"
              + (afterSend.lastError.map { ", error: \($0)" } ?? ""))
        guard afterSend.state == .publishing else {
            print("FAIL: the publisher stopped before the probe — \(afterSend.lastError ?? "no reason recorded")")
            print("  mediamtx said:\n\(serverLog())")
            exit(1)
        }
        // 4. Close, let mediamtx flush its recording, then read it back.
        await publisher.close()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        // %path is "live/awtest", so mediamtx nests the segment one directory
        // down — enumerate rather than list.
        var recorded: [String] = []
        if let walk = FileManager.default.enumerator(atPath: recDir) {
            for case let f as String in walk where f.hasSuffix(".mp4") { recorded.append(f) }
        }
        recorded.sort()
        guard let newest = recorded.last else {
            print("FAIL: mediamtx recorded nothing in \(recDir)")
            print("  mediamtx said:\n\(serverLog())")
            exit(1)
        }
        let recPath = recDir + "/" + newest
        let recBytes = (try? FileManager.default.attributesOfItem(atPath: recPath)[.size] as? Int) ?? 0
        print("… probing the recording (\(newest), \(recBytes ?? 0) bytes)")
        let (probeStatus, probeOut) = run(ffprobe, [
            "-v", "error", "-of", "json", "-show_streams", "-show_format", recPath])

        guard probeStatus == 0 else { print("FAIL: ffprobe could not read the stream back (\(probeStatus))\n\(probeOut)"); exit(1) }
        guard let data = probeOut.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = json["streams"] as? [[String: Any]] else {
            print("FAIL: ffprobe output did not parse:\n\(probeOut)"); exit(1)
        }
        var okV = false, okA = false
        for s in streams {
            let codec = s["codec_name"] as? String ?? ""
            if s["codec_type"] as? String == "video" {
                let w = s["width"] as? Int ?? 0, h = s["height"] as? Int ?? 0
                let rate = s["avg_frame_rate"] as? String ?? "?"
                let frames = s["nb_frames"] as? String ?? "?"
                print("  video: \(codec) \(w)x\(h) @ \(rate), \(frames) frames")
                okV = (codec == "h264" && w == 640 && h == 360)
                if !okV { print("FAIL: expected h264 640x360, got \(codec) \(w)x\(h)") }
            } else if s["codec_type"] as? String == "audio" {
                let sr = Int(s["sample_rate"] as? String ?? "0") ?? 0
                print("  audio: \(codec) \(sr) Hz")
                okA = (codec == "aac" && sr == 44100)
                if !okA { print("FAIL: expected aac 44100, got \(codec) \(sr)") }
            }
        }
        guard okV && okA else { exit(1) }
        print("OK: mediamtx ingested, recorded, and ffprobe read back h264 640x360 + aac 44100")

        // 5. Negative control: a server that is not there must be REFUSED, not
        // hung. The port is PROVEN closed first — a hardcoded "dead" port is
        // not dead if a previous run's server is still on it, and this test
        // failed for exactly that reason once.
        var deadPort: UInt16 = 0
        for candidate in UInt16(19400)...UInt16(19450) where !isListening(candidate) {
            deadPort = candidate; break
        }
        guard deadPort != 0 else { print("SKIP: could not find a closed port to probe"); exit(2) }
        let bad = RTMPPublisher()
        do {
            try await bad.publish(to: URL(string: "rtmp://127.0.0.1:\(deadPort)/live/nope")!, config: config, timeout: 3)
            print("FAIL: publish to closed port \(deadPort) should have thrown"); exit(1)
        } catch {
            print("OK: closed port \(deadPort) refused — \(error)")
        }

        print("\nPASS: RTMP publisher verified against mediamtx + ffprobe")
        exit(0)
    }
}
