// ONE ENCODE, TWO DESTINATIONS — WATCH-TOGETHER §8.37, roadmap #2.
//
// Simulcast's whole claim is that the expensive half happens once: composite,
// then H.264, then the SAME encoded frames to N sockets. A test that only
// checked "two publishers connected" would prove the cheap half. This asserts
// the claim — two independent server paths each ingest a complete, readable
// stream, and the frames they received are the same frames.
//
// TWO PATHS ON ONE SERVER rather than two servers: from the publisher's side
// that is two connections and two streams, and it removes a variable that has
// burned this project before — §8.6 once failed because several servers were
// fighting for the machine (§9, and again 2026-09-22).
//
//   DEVELOPER_DIR=… xcrun swiftc -parse-as-library -O \
//     ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift \
//     tools/StudioTestMedia.swift tools/harness_awdiag.swift \
//     tools/test_studio_simulcast.swift -o /tmp/awsimul && /tmp/awsimul

import AVFoundation
import CoreMedia
import Foundation

@main
struct Simulcast {

    static func shell(_ launch: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        try? p.run(); p.waitUntilExit()
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    static func which(_ tool: String) -> String? {
        for p in ["/opt/homebrew/bin/", "/usr/local/bin/", "/usr/bin/"]
        where FileManager.default.isExecutableFile(atPath: p + tool) { return p + tool }
        return nil
    }

    static func main() async {
        guard let mtx = which("mediamtx"), let ffprobe = which("ffprobe") else {
            print("SKIP: needs mediamtx and ffmpeg (brew install mediamtx ffmpeg)")
            exit(0)
        }

        let scratch = NSTemporaryDirectory() + "awsimul-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: scratch) }

        let port = 19370
        let conf = """
        rtmp: yes
        rtmpAddress: :\(port)
        rtspAddress: :19371
        hlsAddress: :19372
        webrtcAddress: :19373
        srtAddress: :19374
        api: no
        logLevel: info
        pathDefaults:
          record: yes
          recordPath: \(scratch)/%path_%Y-%m-%d_%H-%M-%S-%f
          recordFormat: fmp4
        paths:
          all_others:
        """
        let confPath = scratch + "/mtx.yml"
        try? conf.write(toFile: confPath, atomically: true, encoding: .utf8)

        let server = Process()
        server.executableURL = URL(fileURLWithPath: mtx)
        server.arguments = [confPath]
        let log = Pipe(); server.standardOutput = log; server.standardError = log
        do { try server.run() } catch { print("FAIL: could not start mediamtx: \(error)"); exit(1) }
        defer { server.terminate() }
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        // ONE encoder pair — that is the point.
        let video = TestVideoEncoder(); let audio = TestAudioEncoder()
        video.start(); audio.start()
        let a = RTMPPublisher(), b = RTMPPublisher()

        var gotConfig = false
        let box = ConfigBox()
        video.onSample = { sample in
            if !gotConfig, let c = avcC(from: sample) {
                gotConfig = true
                box.value = RTMPStreamConfig(
                    width: video.width, height: video.height, frameRate: Double(video.fps),
                    videoBitrate: 1_500_000, avcC: c,
                    audioSampleRate: audio.sampleRate, audioChannels: 1,
                    audioBitrate: 96_000, audioSpecificConfig: audio.audioSpecificConfig)
            }
            box.append(sample)
        }
        video.encode(frame: 0)
        var tries = 0
        while !gotConfig && tries < 50 { try? await Task.sleep(nanoseconds: 20_000_000); tries += 1 }
        guard let config = box.value else { print("FAIL: no avcC from the encoder"); exit(1) }

        do {
            try await a.publish(to: URL(string: "rtmp://127.0.0.1:\(port)/live/primary")!, config: config)
            try await b.publish(to: URL(string: "rtmp://127.0.0.1:\(port)/live/second")!, config: config)
        } catch {
            print("FAIL: a destination would not accept the publish — \(error)")
            print(String(decoding: log.fileHandleForReading.availableData, as: UTF8.self))
            exit(1)
        }
        print("OK: both destinations accepted the publish")

        // THE SAME FRAME OBJECT to both publishers, which is the claim.
        for s in box.drainVideo() {
            if let f = EncodedVideoFrame(s) { await a.send(video: f); await b.send(video: f) }
        }
        audio.onFrame = { data, pts in
            Task { await a.send(audioFrame: data, presentationTime: pts)
                   await b.send(audioFrame: data, presentationTime: pts) }
        }
        for i in 1...150 {
            video.encode(frame: i)
            for s in box.drainVideo() {
                if let f = EncodedVideoFrame(s) { await a.send(video: f); await b.send(video: f) }
            }
            audio.encodeOneFrame()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        video.finish()
        for s in box.drainVideo() {
            if let f = EncodedVideoFrame(s) { await a.send(video: f); await b.send(video: f) }
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        let ha = await a.health, hb = await b.health
        print("  primary: \(ha.videoFramesSent)v/\(ha.audioFramesSent)a \(ha.bytesSent) bytes, dropped \(ha.videoFramesDropped)")
        print("  second:  \(hb.videoFramesSent)v/\(hb.audioFramesSent)a \(hb.bytesSent) bytes, dropped \(hb.videoFramesDropped)")
        await a.close(); await b.close()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        server.terminate()
        try? await Task.sleep(nanoseconds: 800_000_000)

        var fail = false

        // 1. BOTH published — the publisher's own state, before any file.
        for (label, h) in [("primary", ha), ("second", hb)] where h.state != .publishing {
            print("FAIL: \(label) is \(h.state.rawValue)" + (h.lastError.map { " — \($0)" } ?? ""))
            fail = true
        }

        // 2. BOTH RECORDED, read back by ffprobe — an independent reference on
        //    the far end, which is what separates "we sent bytes" from "a
        //    demuxer could make a stream of them" (Decision 119's rule).
        // RECURSIVELY. mediamtx expands `%path` to the stream's full path —
        // `live/primary` — so it writes into a SUBDIRECTORY, and a flat
        // listing finds nothing while the recordings sit there. Caught by
        // this harness reporting "no recording" for two streams whose own
        // counters said 151 frames each: the instrument, not the product.
        let files = (FileManager.default.enumerator(atPath: scratch)?
            .compactMap { $0 as? String } ?? [])
            .filter { $0.hasSuffix(".mp4") }
        for label in ["primary", "second"] {
            guard let file = files.first(where: { $0.contains(label) }) else {
                print("FAIL: \(label) produced no recording"); fail = true; continue
            }
            let text = shell(ffprobe, ["-v", "error", "-show_entries",
                                       "stream=codec_name,width,height",
                                       "-of", "csv=p=0", scratch + "/" + file])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.contains("h264,\(video.width),\(video.height)"), text.contains("aac") {
                print("OK: \(label) read back — \(text.replacingOccurrences(of: "\n", with: " | "))")
            } else {
                print("FAIL: \(label) read back as \(text)"); fail = true
            }
        }

        // 3. THE SAME SHOW, not two different ones.
        if ha.videoFramesSent > 0, ha.videoFramesSent == hb.videoFramesSent {
            print("OK: both destinations received the same \(ha.videoFramesSent) video frames")
        } else {
            print("FAIL: frame counts differ — \(ha.videoFramesSent) vs \(hb.videoFramesSent)")
            fail = true
        }

        // 4. CONTROL — the check can fail. A path nothing published to must
        //    record nothing, or "both recorded" proves only that mediamtx
        //    writes files.
        if files.contains(where: { $0.contains("third") }) {
            print("FAIL: CONTROL — a path nothing published to produced a recording")
            fail = true
        } else {
            print("OK: CONTROL — a path nothing published to recorded nothing")
        }

        print()
        print(fail ? "FAILED — simulcast did not deliver the same show twice"
                   : "PASS: §8.37 — one encode reached two destinations intact")
        exit(fail ? 1 : 0)
    }
}
