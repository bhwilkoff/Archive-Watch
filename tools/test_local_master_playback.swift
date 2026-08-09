// Does a LOCAL HLS master with a REMOTE segment actually play, and does it
// expose a CC menu?
//
// The whole "Get subtitles" feature rests on this: SubtitleStore writes the VTT
// and three playlists to Caches and hands AVPlayer the local master, while the
// video segment stays the remote archive.org MP4. That shape is asserted all
// over the code but has never been executed — and this project has been bitten
// twice by exactly that gap (a custom-scheme segment AVFoundation silently
// rejects; a segment URI with raw spaces that curl accepted and AVFoundation
// did not). A lenient probe is not evidence; AVFoundation is the only authority.
//
// Passing means: the item reaches .readyToPlay AND reports a legible media
// selection group containing our subtitle track.
//
// Run:  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
//       xcrun swift tools/test_local_master_playback.swift <mp4-url>

import AVFoundation
import Foundation

// Passing a .m3u8 runs the same assertions against an ALREADY-PUBLISHED remote
// master — the control that separates "the local-file shape is broken" from
// "this harness cannot observe playback at all".
let args = CommandLine.arguments
guard args.count > 1, let video = URL(string: args[1]) else {
    print("usage: test_local_master_playback.swift <mp4-url | published-master.m3u8>"); exit(2)
}
let controlMaster: URL? = video.pathExtension == "m3u8" ? video : nil

let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent("aw-master-test-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: dir) }

// Mirror SubtitleStore.encodeSegment: a segment URI with raw spaces or ()
// is rejected by AVFoundation even though every HTTP client accepts it.
func encodeSegment(_ url: URL) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.formUnion(CharacterSet(charactersIn: "#[]@!$&'*+,;=:/?"))
    allowed.remove(charactersIn: " \"<>\\^`{|}()")
    return url.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) ?? url.absoluteString
}

let dur = 600
let vtt = """
WEBVTT
X-TIMESTAMP-MAP=MPEGTS:0,LOCAL:00:00:00.000

1
00:00:01.000 --> 00:00:05.000
Archive Watch subtitle probe.

2
00:00:06.000 --> 00:00:10.000
Second cue.

"""
try vtt.write(to: dir.appendingPathComponent("en.vtt"), atomically: true, encoding: .utf8)
try """
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:\(dur)
#EXT-X-PLAYLIST-TYPE:VOD
#EXTINF:\(dur).0,
en.vtt
#EXT-X-ENDLIST
""".write(to: dir.appendingPathComponent("subs.en.m3u8"), atomically: true, encoding: .utf8)
try """
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:\(dur)
#EXT-X-PLAYLIST-TYPE:VOD
#EXTINF:\(dur).0,
\(encodeSegment(video))
#EXT-X-ENDLIST
""".write(to: dir.appendingPathComponent("video.m3u8"), atomically: true, encoding: .utf8)
let master = dir.appendingPathComponent("master.m3u8")
try """
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",LANGUAGE="en",AUTOSELECT=YES,DEFAULT=NO,URI="subs.en.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=2000000,SUBTITLES="subs"
video.m3u8
""".write(to: master, atomically: true, encoding: .utf8)

let use = controlMaster ?? master
print("probing \(controlMaster == nil ? "LOCAL master + remote segment" : "PUBLISHED remote master (control)")")
let item = AVPlayerItem(url: use)
let player = AVPlayer(playerItem: item)

let deadline = Date().addingTimeInterval(45)
while item.status == .unknown && Date() < deadline {
    try? await Task.sleep(nanoseconds: 250_000_000)
}

switch item.status {
case .readyToPlay:
    print("RESULT: OK — local master + remote segment reached .readyToPlay")
    let asset = item.asset
    if let group = try? await asset.loadMediaSelectionGroup(for: .legible) {
        let names = group.options.map { $0.displayName }
        print("  legible options: \(names.isEmpty ? "NONE" : names.joined(separator: ", "))")
        if names.isEmpty {
            print("RESULT: FAILED — playable but NO subtitle track; the CC menu would be empty")
            exit(1)
        }
    } else {
        print("RESULT: FAILED — no legible media selection group")
        exit(1)
    }
    let d = try? await asset.load(.duration)
    print("  duration: \(d.map { String(format: "%.0fs", CMTimeGetSeconds($0)) } ?? "?")")
    player.play()
    try? await Task.sleep(nanoseconds: 3_000_000_000)
    let t = CMTimeGetSeconds(player.currentTime())
    print("  played to \(String(format: "%.1fs", t)) after 3s of wall clock")
    if t <= 0 { print("RESULT: FAILED — never advanced"); exit(1) }
case .failed:
    print("RESULT: FAILED — \(item.error.map(String.init(describing:)) ?? "unknown")")
    exit(1)
default:
    print("RESULT: FAILED — still .unknown after 45s")
    if let log = item.errorLog() {
        for e in log.events {
            print("  errorLog: \(e.errorStatusCode) \(e.errorComment ?? "") uri=\(e.uri ?? "-")")
        }
    } else {
        print("  errorLog: empty — AVFoundation never even attempted a load")
    }
    if let log = item.accessLog() {
        print("  accessLog events: \(log.events.count)")
    }
    exit(1)
}
