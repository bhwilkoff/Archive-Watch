import Compression
import Foundation

/// A playlist you can hand to somebody, as a link.
///
/// THE PLAYLIST IS THE LINK. This project has no backend and no accounts
/// (Decisions 009 and 028), and `privacy.html` promises a playlist never
/// leaves the device except through the viewer's own cloud. A sharing service
/// would undo both, and measurement says one is unnecessary: archive ids are
/// short (median 23 characters), so deflated and base64url'd a 50-title
/// playlist is about 1,200 characters — inside what messages, mail and QR
/// codes carry without mangling.
///
/// THE FORMAT IS THE WEB'S. `js/watch.js`'s `ShareList` is the reference
/// implementation; this must produce blobs it can read and read blobs it
/// produces, because a link made on an Apple TV is opened in someone else's
/// browser. Raw DEFLATE is the codec precisely because every platform here
/// already has it: `COMPRESSION_ZLIB` is raw deflate (see
/// `CatalogRefreshService`, which inflates the catalogue with it) and Android
/// has `Deflater(level, nowrap: true)`.
///
/// A `0` PREFIX MEANS UNCOMPRESSED, and it exists for Roku. BrightScript has
/// no deflate — it has base64 on `roByteArray` and nothing else — so a
/// platform that cannot compress may emit the same JSON uncompressed behind
/// that marker rather than being locked out of sharing. Every decoder accepts
/// both; only encoders choose.
enum PlaylistShare {

    /// Titles past this make a link that messaging apps and QR codes start to
    /// mangle. Measured, not guessed: 50 real ids encode to ~1,223 characters.
    static let limit = 50

    static func blob(name: String, archiveIDs: [String]) -> String? {
        let payload: [String: Any] = ["n": String(name.prefix(80)), "i": archiveIDs]
        guard let json = try? JSONSerialization.data(withJSONObject: payload,
                                                     options: [.withoutEscapingSlashes])
        else { return nil }
        guard let deflated = deflate(json) else {
            // Uncompressed fallback: a shareable link beats no link at all.
            return "0" + base64url(json)
        }
        return base64url(deflated)
    }

    static func url(name: String, archiveIDs: [String]) -> URL? {
        guard !archiveIDs.isEmpty, archiveIDs.count <= limit,
              let b = blob(name: name, archiveIDs: archiveIDs) else { return nil }
        // The PATH is `/list/` and the playlist rides the FRAGMENT. A browser
        // never sends a fragment to a server, so the list stays off ours —
        // while the path is what a native app can match, because an Android
        // intent filter matches the path and cannot see a fragment at all.
        // `/list/` is also a real 200 page: several crawlers decline to
        // preview a 404, and this link is made to be posted.
        return URL(string: "https://archivewatch.org/list/#\(b)")
    }

    // MARK: - reading a link somebody sent

    /// What a shared link carries.
    struct Shared: Equatable {
        let name: String
        let archiveIDs: [String]
    }

    /// Pull the blob out of a share link, in either shape it has ever had.
    ///
    /// `/list/#<blob>` is what every platform emits now; `#/list/<blob>` is
    /// what shipped first and is already in the wild. Links are permanent, so
    /// both are read forever — only encoders ever choose (the same rule the
    /// `0` prefix follows).
    static func blob(from url: URL) -> String? {
        let s = url.absoluteString
        if let r = s.range(of: "/list/#") { return trimmed(String(s[r.upperBound...])) }
        if let r = s.range(of: "#/list/") { return trimmed(String(s[r.upperBound...])) }
        // A blob written into the path rather than the fragment. Nothing emits
        // this, and 404.html accepts it, so the app does too.
        let parts = url.pathComponents.filter { $0 != "/" }
        if let i = parts.firstIndex(of: "list"), i + 1 < parts.count { return trimmed(parts[i + 1]) }
        return nil
    }

    private static func trimmed(_ s: String) -> String? {
        let v = s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return v.isEmpty ? nil : v
    }

    /// Decode a blob into the playlist it carries. Accepts both variants: a
    /// leading `0` is the uncompressed one Roku emits, anything else is raw
    /// DEFLATE.
    static func decode(_ blob: String) -> Shared? {
        let bytes: Data?
        if blob.hasPrefix("0") {
            bytes = data(base64url: String(blob.dropFirst()))
        } else {
            guard let d = data(base64url: blob) else { return nil }
            bytes = inflate(d)
        }
        guard let json = bytes,
              let o = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let ids = o["i"] as? [String]
        else { return nil }
        // The name is optional on the wire; a playlist without one is still a
        // playlist, and the web's reference decoder says so too.
        let name = (o["n"] as? String) ?? "Shared playlist"
        return Shared(name: name, archiveIDs: ids)
    }

    static func shared(from url: URL) -> Shared? {
        guard let b = blob(from: url) else { return nil }
        return decode(b)
    }

    // MARK: - the two primitives

    /// Raw DEFLATE, the same shape `deflate-raw` produces in the browser.
    private static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        // Deflate can expand incompressible input; the margin is generous
        // because a wrong-sized buffer here is a silent truncation.
        let cap = data.count + 1_024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        defer { dst.deallocate() }
        let n = data.withUnsafeBytes { src -> Int in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(dst, cap, base, data.count, nil, COMPRESSION_ZLIB)
        }
        return n > 0 ? Data(bytes: dst, count: n) : nil
    }

    /// Raw INFLATE. `COMPRESSION_ZLIB` is raw deflate on Apple platforms, the
    /// same codec `CatalogRefreshService` uses for the catalogue.
    private static func inflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        // A playlist is small and bounded by `limit`, so one generous buffer
        // beats a streaming decode. 64 KB is far past a 50-title payload.
        let cap = 64 * 1_024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        defer { dst.deallocate() }
        let n = data.withUnsafeBytes { src -> Int in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(dst, cap, base, data.count, nil, COMPRESSION_ZLIB)
        }
        return n > 0 ? Data(bytes: dst, count: n) : nil
    }

    /// base64url -> bytes. The padding was stripped on the way out, so it has
    /// to be put back: Foundation refuses an unpadded string.
    private static func data(base64url s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - t.count % 4) % 4
        t += String(repeating: "=", count: pad)
        return Data(base64Encoded: t)
    }

    /// base64url with the padding stripped — what survives a URL fragment.
    private static func base64url(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
