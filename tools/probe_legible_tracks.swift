// What subtitle tracks does AVFoundation actually SEE for a URL?
//
// The catalog can say a film has no captions while the PLAYER still offers
// "English" — because the MP4 itself carries an embedded text or CEA-608 track.
// AVPlayerViewController lists whatever the asset advertises, so a track that is
// present-but-empty (or a caption format the file declares and does not carry)
// shows up in the CC menu and renders nothing. From the viewer's side that is
// indistinguishable from broken subtitles, which is exactly the report.
//
// Prints every legible option, plus the raw track list, so "the app says it has
// English subtitles" can be traced to something concrete.
//
// Run: DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
//      xcrun swift tools/probe_legible_tracks.swift <url>

import AVFoundation
import Foundation

let args = CommandLine.arguments
guard args.count > 1, let url = URL(string: args[1]) else {
    print("usage: probe_legible_tracks.swift <url>"); exit(2)
}

let asset = AVURLAsset(url: url)

do {
    let dur = try await asset.load(.duration)
    print("duration: \(String(format: "%.0fs", CMTimeGetSeconds(dur)))")

    for mt in [AVMediaType.video, .audio, .subtitle, .closedCaption, .text] {
        let tracks = try await asset.loadTracks(withMediaType: mt)
        guard !tracks.isEmpty else { continue }
        for t in tracks {
            let fmts = (try? await t.load(.formatDescriptions)) ?? []
            let codes = fmts.map { String(describing: CMFormatDescriptionGetMediaSubType($0)) }
            let enabled = (try? await t.load(.isEnabled)) ?? false
            let range = (try? await t.load(.timeRange))
            let span = range.map { String(format: "%.0fs", CMTimeGetSeconds($0.duration)) } ?? "?"
            print("track \(t.trackID) \(mt.rawValue): enabled=\(enabled) span=\(span) subtypes=\(codes)")
        }
    }

    if let group = try? await asset.loadMediaSelectionGroup(for: .legible) {
        print("\nlegible media selection group: \(group.options.count) option(s)")
        for o in group.options {
            let loc = o.locale?.identifier ?? "-"
            print("  • \(o.displayName)  [\(o.mediaType.rawValue)]  locale=\(loc)")
        }
        if group.options.isEmpty {
            print("  (none — the CC menu would offer nothing but Off)")
        }
    } else {
        print("\nno legible media selection group at all")
    }
} catch {
    print("FAILED: \(error)")
    exit(1)
}
