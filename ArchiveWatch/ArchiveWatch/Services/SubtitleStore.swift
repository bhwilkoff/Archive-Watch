import Foundation

// On-device subtitle store — the single seam both new caption sources feed into.
//
// The players already show a native CC menu when an item carries `subtitleHLS`
// (Decision 039): AVPlayerViewController reads an HLS master whose video
// rendition is the remote MP4 and whose subtitle rendition is a WebVTT. So a
// subtitle obtained ON DEVICE — pulled from the viewer's own OpenSubtitles
// account, or transcribed locally — needs no player change at all: write the VTT
// to Caches, write a local master pointing at it, and hand the player that URL.
//
// The video segment stays the REMOTE https MP4. Only the playlists and the VTT
// are local, which is the same shape as the published assets and the same shape
// `CaptionedHLSLoader` already serves (see the hls-custom-scheme note: a
// custom-scheme SEGMENT is rejected by AVFoundation, a remote https one is not).
//
// Caches, not Application Support: tvOS only permits Caches and the App Group
// container, and a regenerable transcript belongs in Caches anyway.
enum SubtitleStore {

    static var root: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("subtitles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func dir(for archiveID: String) -> URL? {
        let safe = archiveID.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_",
                                                  options: .regularExpression)
        guard let d = root?.appendingPathComponent(safe, isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// A previously-stored local HLS master for this title, if any.
    static func cachedHLS(for archiveID: String) -> URL? {
        guard let m = dir(for: archiveID)?.appendingPathComponent("master.m3u8"),
              FileManager.default.fileExists(atPath: m.path) else { return nil }
        return m
    }

    static func hasCaptions(for archiveID: String) -> Bool { cachedHLS(for: archiveID) != nil }

    /// Store a WebVTT and return a local HLS master the player can use directly.
    ///
    /// `label` is what the CC menu shows — always say when a track is machine
    /// made ("English (auto-generated)"), so the viewer can weigh it.
    @discardableResult
    static func store(vtt: String, for archiveID: String, videoURL: URL,
                      runtime: Int, lang: String = "en",
                      label: String = "English") -> URL? {
        guard let d = dir(for: archiveID) else { return nil }
        let vttName = "\(lang).vtt"
        do {
            try vtt.write(to: d.appendingPathComponent(vttName), atomically: true, encoding: .utf8)
        } catch { return nil }

        let dur = max(runtime, 1)
        let seg = encodeSegment(videoURL)
        let subsName = "subs.\(lang).m3u8"
        let subs = """
        #EXTM3U
        #EXT-X-VERSION:6
        #EXT-X-TARGETDURATION:\(dur)
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXTINF:\(dur).0,
        \(vttName)
        #EXT-X-ENDLIST
        """
        let video = """
        #EXTM3U
        #EXT-X-VERSION:6
        #EXT-X-TARGETDURATION:\(dur)
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXTINF:\(dur).0,
        \(seg)
        #EXT-X-ENDLIST
        """
        let master = """
        #EXTM3U
        #EXT-X-VERSION:6
        #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="\(label)",\
        LANGUAGE="\(lang)",DEFAULT=NO,AUTOSELECT=YES,FORCED=NO,URI="\(subsName)"
        #EXT-X-STREAM-INF:BANDWIDTH=1400000,SUBTITLES="subs"
        video.m3u8
        """
        do {
            try subs.write(to: d.appendingPathComponent(subsName), atomically: true, encoding: .utf8)
            try video.write(to: d.appendingPathComponent("video.m3u8"), atomically: true, encoding: .utf8)
            let m = d.appendingPathComponent("master.m3u8")
            try master.write(to: m, atomically: true, encoding: .utf8)
            return m
        } catch { return nil }
    }

    /// Percent-encode the segment path. AVFoundation rejects a segment URI with
    /// raw spaces/()/# outright ("resource unavailable") while lenient parsers
    /// resolve it — the exact bug that made captioned films unplayable once
    /// before, so it is encoded here too rather than trusted.
    static func encodeSegment(_ url: URL) -> String {
        guard let s = url.absoluteString.range(of: "://") else { return url.absoluteString }
        let full = url.absoluteString
        let hostEnd = full[s.upperBound...].firstIndex(of: "/") ?? full.endIndex
        let head = String(full[..<hostEnd])
        let path = String(full[hostEnd...])
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/%")
        return head + (path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path)
    }

    static func clear(_ archiveID: String) {
        if let d = dir(for: archiveID) { try? FileManager.default.removeItem(at: d) }
    }
}
