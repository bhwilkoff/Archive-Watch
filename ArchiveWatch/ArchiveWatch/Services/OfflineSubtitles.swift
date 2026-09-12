#if os(iOS) || os(macOS)
import Foundation

// A film's WebVTT cues, rendered through the caption overlay rather than
// carried as an HLS rendition — for a DOWNLOADED film (Decision 099) and, since
// the wrapper turned out to buffer whole films, for an online captioned one too.
//
// Everything else in this app puts a subtitle track in front of AVKit as an
// HLS rendition, because that is what gets the NATIVE CC menu (Decision 039).
// That shape cannot be reused here: the master's video rendition is an https
// URL to archive.org, and offline there is no archive.org — the whole asset
// fails, not just the captions. Rewriting the segment to the local `file://`
// path is an HLS shape nothing in this project has ever run, and an unverified
// player shape is exactly what Decisions 054 and 065 were spent on.
//
// So a downloaded film renders its cues through the SAME overlay label the live
// caption engine already draws into. The words are the published human ones;
// only the renderer differs from the online path, and it is a renderer that has
// been on screen since Decision 070.
struct OfflineSubtitles: Sendable {

    private let cues: [SubtitleAgreement.Cue]

    /// Load a downloaded WebVTT, or nil when this title has none.
    init?(archiveID: String) {
        guard let url = OfflineLibrary.subtitleURL(for: archiveID),
              let body = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        self.init(vtt: body)
    }

    /// Parse a WebVTT body from anywhere. ONLINE captioned films render through
    /// this renderer too now (Decision 070 ported to iOS/macOS): the HLS
    /// wrapper that used to carry the track declares the whole film as one
    /// segment, which is AVFoundation's atomic buffering unit, so it downloaded
    /// the entire MP4 into memory. Measured on The Grapes of Wrath (2.19 GB):
    /// 4,195 seconds buffered against a 300-second request and a 1.37 GB
    /// footprint still climbing at 90 seconds, against 193s and 55 MB flat
    /// through ResilientStreamLoader.
    init?(vtt body: String) {
        let parsed = SubtitleAgreement.parseVTT(body)
        guard !parsed.isEmpty else { return nil }
        // Sorted so the search below can stop early; a published file is
        // normally in order already, but nothing guarantees it.
        cues = parsed.sorted { $0.start < $1.start }
    }

    /// Fetch and parse a published WebVTT. Small (a feature's cues are tens of
    /// KB), so it is pulled whole rather than streamed.
    static func published(_ url: URL) async -> OfflineSubtitles? {
        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode ?? 200 < 400,
              let body = String(data: data, encoding: .utf8)
        else { return nil }
        return OfflineSubtitles(vtt: body)
    }

    var isEmpty: Bool { cues.isEmpty }

    /// The cue text to show at `seconds`, or "" between cues.
    ///
    /// Linear from the front is fine: a feature carries a few thousand cues and
    /// this is called a handful of times a second. Binary search would be
    /// faster and harder to read, and nothing here is measurably slow.
    func line(at seconds: Double) -> String {
        for cue in cues {
            if cue.start > seconds { break }
            if seconds >= cue.start, seconds <= cue.end { return cue.text }
        }
        return ""
    }
}
#endif
