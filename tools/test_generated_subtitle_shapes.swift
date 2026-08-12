// WHICH ASSET SHAPE DOES THE SYSTEM ACTUALLY CAPTION?
//
// From 27 Apple generates subtitles on device for video that carries none, and
// says no app implementation is required (WWDC26 session 256). It is required
// for HLS and for "file-based content". archive.org serves a REMOTE PROGRESSIVE
// MP4, which is neither — and every playback path in this app wraps that MP4 in
// a custom `AVAssetResourceLoaderDelegate` (Decisions 021/031/034), which is the
// same property that disqualifies us from video AirPlay (Decision 051).
//
// So the question this settles is not "does the feature exist" but "which of the
// shapes we could ship does it actually caption". Four candidates:
//
//     A  plain direct MP4 URL              — no resilience, simplest
//     B  aw-stream:// resilient loader     — what ships today
//     C  HLS master wrapping the same MP4  — what we already publish for
//                                            captioned films, minus the subs
//     D  A, with an AVPlayerItemLegibleOutput attached — the check the app runs
//
// D matters because `emitsCaptions` attaches one to LISTEN for text. If
// attaching it suppresses the player's own rendering, the check destroys the
// thing it measures, and every negative result the app has ever recorded is
// worthless.
//
// A shape PASSES only if text is actually EMITTED. Offering a track and
// producing captions are different claims — treating them as one is what made
// Decision 061 wrong and cost three shipped builds (Decision 065).
//
// Build + run:
//   xcrun swiftc -parse-as-library \
//     ArchiveWatch/ArchiveWatch/Networking/ResilientStreamLoader.swift \
//     ArchiveWatch/ArchiveWatch/Networking/AirPlayRouting.swift \
//     tools/test_generated_subtitle_shapes.swift -o /tmp/awshapes && /tmp/awshapes

import AVFoundation
import Foundation

// A shape's verdict, kept explicit so "offered" can never be mistaken for
// "working" — the distinction this whole harness exists to preserve.
struct Verdict {
    let label: String
    let offered: Bool
    let optionNames: [String]
    let emitted: Bool
    let secondsToText: Double?
}

final class TextSink: NSObject, AVPlayerItemLegibleOutputPushDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _seen: String?
    var seen: String? { lock.lock(); defer { lock.unlock() }; return _seen }
    func legibleOutput(_ output: AVPlayerItemLegibleOutput,
                       didOutputAttributedStrings strings: [NSAttributedString],
                       nativeSampleBuffers: [Any], forItemTime itemTime: CMTime) {
        let text = strings.map(\.string)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        lock.lock(); if _seen == nil { _seen = text }; lock.unlock()
    }
}

@main
struct Harness {
    // A 1975 documentary with clear narration — the one film in the sample the
    // system was already proven to caption, so a failure here is about the
    // SHAPE and not about the soundtrack being too rough to transcribe.
    static let film = "https://archive.org/download/mantheincrediblemachine/"
        + "mantheincrediblemachine.mp4"

    /// Serve an HLS master + media playlist that wrap `mp4` as a single segment.
    /// This is byte-for-byte the shape `build_subtitle_assets.py` publishes for
    /// captioned films, minus the subtitle rendition — so a pass here is a
    /// statement about something we already know how to build and host.
    static func serveHLS(wrapping mp4: URL, durationSeconds: Int) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("awhls-\(UInt32.random(in: 0...UInt32.max))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let master = """
        #EXTM3U
        #EXT-X-VERSION:6
        #EXT-X-STREAM-INF:BANDWIDTH=2000000
        video.m3u8

        """
        let video = """
        #EXTM3U
        #EXT-X-VERSION:6
        #EXT-X-TARGETDURATION:\(durationSeconds)
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXTINF:\(durationSeconds).0,
        \(mp4.absoluteString)
        #EXT-X-ENDLIST

        """
        try master.write(to: dir.appendingPathComponent("master.m3u8"),
                         atomically: true, encoding: .utf8)
        try video.write(to: dir.appendingPathComponent("video.m3u8"),
                        atomically: true, encoding: .utf8)

        // A `file://` master that references a remote segment does NOT play —
        // AVFoundation never even attempts the load (Decision 054). So it has to
        // be served over HTTP, which is also what production does.
        let port = Int.random(in: 8100...8999)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", "-m", "http.server", "\(port)", "--bind", "127.0.0.1",
                       "--directory", dir.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        servers.append(p)
        Thread.sleep(forTimeInterval: 1.0)
        return URL(string: "http://127.0.0.1:\(port)/master.m3u8")!
    }
    nonisolated(unsafe) static var servers: [Process] = []

    static func probe(_ label: String, item: AVPlayerItem,
                      attachOutput: Bool = true,
                      offerWait: Double = 20, textWait: Double = 120) async -> Verdict {
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.play()

        // 1. Is a legible option OFFERED? Poll: a generated track appears a
        //    moment into playback, not at item creation.
        var offered = false
        var names: [String] = []
        var group: AVMediaSelectionGroup?
        let offerDeadline = Date().addingTimeInterval(offerWait)
        while Date() < offerDeadline {
            if let g = try? await item.asset.loadMediaSelectionGroup(for: .legible),
               !g.options.isEmpty {
                group = g; offered = true
                names = g.options.map { "\($0.displayName) [\($0.mediaType.rawValue)]" }
                break
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        // 2. SELECT it. A generated track is only OFFERED — the system leaves it
        //    switched off, and an unselected track emits nothing, so judging
        //    emission without selecting first measures the selection (065).
        if let group, let option = group.options.first {
            item.select(option, in: group)
        }

        // 3. Did text actually arrive?
        let sink = TextSink()
        var output: AVPlayerItemLegibleOutput?
        if attachOutput {
            let o = AVPlayerItemLegibleOutput(mediaSubtypesForNativeRepresentation: [])
            o.suppressesPlayerRendering = false   // observe only
            o.setDelegate(sink, queue: .main)
            item.add(o)
            output = o
        }
        let start = Date()
        var seconds: Double?
        let textDeadline = Date().addingTimeInterval(textWait)
        while Date() < textDeadline {
            if sink.seen != nil { seconds = Date().timeIntervalSince(start); break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        if let output { item.remove(output) }
        player.pause()

        let v = Verdict(label: label, offered: offered, optionNames: names,
                        emitted: sink.seen != nil, secondsToText: seconds)
        report(v, sample: sink.seen)
        return v
    }

    static func report(_ v: Verdict, sample: String?) {
        let t = v.secondsToText.map { String(format: "%.0fs", $0) } ?? "never"
        print("  \(v.emitted ? "PASS" : "FAIL")  \(v.label)")
        print("        offered=\(v.offered) options=\(v.optionNames.isEmpty ? "none" : v.optionNames.joined(separator: ", "))")
        print("        text=\(v.emitted ? "YES in \(t)" : "NONE")")
        if let sample { print("        first cue: \"\(sample.prefix(60))\"") }
    }

    /// ONE SHAPE PER PROCESS, deliberately.
    ///
    /// The first version of this harness probed all four shapes in a single
    /// process and reported that only the plain MP4 captioned. That result was
    /// an artifact: the shape which passed was simply the one that ran FIRST,
    /// and a shape identical to it failed later in the same process. Whether
    /// that is model contention, a one-at-a-time limit, or players never being
    /// torn down, it means a sequential harness cannot attribute a failure to a
    /// shape at all.
    ///
    /// So the runner invokes this once per shape, and the caller varies the
    /// order. A shape only counts as failing if it fails when it goes FIRST.
    static func main() async {
        guard #available(macOS 27, iOS 27, tvOS 27, *) else {
            print("SKIP: generated subtitles need 27; this OS is older.")
            exit(0)
        }
        let args = CommandLine.arguments
        let shape = args.count > 1 ? args[1] : "direct"
        let url = URL(string: args.count > 2 ? args[2] : film)!
        let dur = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 3600

        print("shape=\(shape) film=\(url.lastPathComponent) duration=\(Int(dur))s")

        let verdict: Verdict
        switch shape {
        case "direct":
            verdict = await probe("plain direct MP4", item: AVPlayerItem(url: url))
        case "loader":
            let (asset, loader) = ResilientStreamLoader.makeAsset(for: url)
            _ = loader                  // the delegate is held weakly
            verdict = await probe("aw-stream:// loader", item: AVPlayerItem(asset: asset))
        case "hls":
            let hls = try! serveHLS(wrapping: url, durationSeconds: Int(dur))
            verdict = await probe("HLS master -> MP4 segment", item: AVPlayerItem(url: hls))
        default:
            print("unknown shape \(shape); use direct|loader|hls"); exit(2)
        }
        servers.forEach { $0.terminate() }
        print("VERDICT shape=\(shape) offered=\(verdict.offered) emitted=\(verdict.emitted)")
        exit(verdict.emitted ? 0 : 1)
    }
}
