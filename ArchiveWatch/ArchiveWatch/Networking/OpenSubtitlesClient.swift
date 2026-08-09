import Foundation

// OpenSubtitles, using the VIEWER'S OWN free account.
//
// WHY THIS SHAPE: the OpenSubtitles REST API is free — 5 downloads/day
// anonymous, 20/day with a free account — and their Pro packages exist
// specifically "for applications where users don't need to enter login
// credentials". That is the tell: WITHOUT Pro, the download quota follows the
// END USER. So each viewer connects their own free account, their own 20/day
// applies, and the project pays nothing and does not scale into a bill. It is
// the same arrangement Infuse and Jellyfin use.
//
// Sign-in is OPTIONAL and gates only this feature — browsing and playback are
// untouched, per the no-funnel ethos (Decisions 009/010). Note this is a
// third-party CONTENT credential, not an identity: Decision 022's "no non-Apple
// login" rule governs accounts and sync, which this deliberately does not touch.
//
// Credentials live in the Keychain, never in the catalog or UserDefaults.
enum OpenSubtitles {

    static let host = "https://api.opensubtitles.com/api/v1"

    struct Match: Sendable, Equatable {
        let fileID: Int
        let language: String
        let downloadCount: Int
        let fromTrusted: Bool
        let hearingImpaired: Bool
        let releaseName: String
    }

    // MARK: - Pure logic (unit-testable; see tools/test_opensubtitles.swift)

    /// Search URL for a title we hold an IMDb id for. Matching on the id — not
    /// the title — is what keeps a subtitle for a DIFFERENT film or cut from
    /// landing on this one (the failure Decision 026 exists to prevent, and the
    /// reason ~3% of shipped tracks were for the wrong cut).
    static func searchURL(imdbID: String, language: String = "en") -> URL? {
        let raw = imdbID.hasPrefix("tt") ? String(imdbID.dropFirst(2)) : imdbID
        // Strip the zero padding: "tt0070666" is the IMDb display form, but the
        // API wants the plain number, and a padded value is not guaranteed to match.
        guard !raw.isEmpty, raw.allSatisfy(\.isNumber), let n = Int(raw) else { return nil }
        let digits = String(n)
        var c = URLComponents(string: "\(host)/subtitles")
        c?.queryItems = [.init(name: "imdb_id", value: digits),
                         .init(name: "languages", value: language),
                         .init(name: "order_by", value: "download_count"),
                         .init(name: "order_direction", value: "desc")]
        return c?.url
    }

    /// Pick the best of several candidates.
    ///
    /// Prefer trusted uploads, then download count — the crowd's own verdict on
    /// which release actually syncs. Hearing-impaired tracks are ranked LAST
    /// rather than dropped: they carry sound descriptions some viewers do not
    /// expect, but they are far better than nothing, which is the whole point.
    static func best(of matches: [Match]) -> Match? {
        matches.max { a, b in
            (a.hearingImpaired ? 0 : 1, a.fromTrusted ? 1 : 0, a.downloadCount)
                < (b.hearingImpaired ? 0 : 1, b.fromTrusted ? 1 : 0, b.downloadCount)
        }
    }

    static func parseMatches(_ data: Data) -> [Match] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["data"] as? [[String: Any]] else { return [] }
        var out: [Match] = []
        for it in items {
            guard let attrs = it["attributes"] as? [String: Any],
                  let files = attrs["files"] as? [[String: Any]],
                  let fid = files.first?["file_id"] as? Int else { continue }
            out.append(Match(
                fileID: fid,
                language: (attrs["language"] as? String) ?? "en",
                downloadCount: (attrs["download_count"] as? Int) ?? 0,
                fromTrusted: (attrs["from_trusted"] as? Bool) ?? false,
                hearingImpaired: (attrs["hearing_impaired"] as? Bool) ?? false,
                releaseName: (attrs["release"] as? String) ?? ""))
        }
        return out
    }

    /// SRT → WebVTT. Comma decimal separators are invalid in WebVTT and are the
    /// single most common reason a downloaded track renders nothing.
    static func srtToVTT(_ srt: String) -> String {
        var body = srt.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        body = body.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}\n "))
        // 00:01:02,345 -> 00:01:02.345
        body = body.replacingOccurrences(
            of: #"(\d{1,2}:\d{2}:\d{2}),(\d{1,3})"#, with: "$1.$2",
            options: .regularExpression)
        return "WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:0,LOCAL:00:00:00.000\n\n" + body + "\n"
    }

    // MARK: - Networked

    struct Credentials: Sendable {
        var apiKey: String
        var username: String
        var password: String
    }

    enum Failure: Error, LocalizedError {
        case notConfigured, auth(String), quota, none, network(String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Connect your OpenSubtitles account in Settings."
            case .auth(let m):   return "OpenSubtitles sign-in failed: \(m)"
            case .quota:         return "You've used today's OpenSubtitles downloads (20/day on a free account)."
            case .none:          return "No subtitles found for this title."
            case .network(let m): return m
            }
        }
    }

    private static func request(_ url: URL, key: String, token: String?,
                                method: String = "GET", body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.timeoutInterval = 25
        r.setValue(key, forHTTPHeaderField: "Api-Key")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // OpenSubtitles requires an identifying User-Agent and rejects generic ones.
        r.setValue("ArchiveWatch v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")",
                   forHTTPHeaderField: "User-Agent")
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        r.httpBody = body
        return r
    }

    static func login(_ c: Credentials) async throws -> String {
        guard let url = URL(string: "\(host)/login") else { throw Failure.notConfigured }
        let body = try JSONSerialization.data(withJSONObject: ["username": c.username,
                                                              "password": c.password])
        let (data, resp) = try await URLSession.shared.data(
            for: request(url, key: c.apiKey, token: nil, method: "POST", body: body))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = j["token"] as? String else {
            throw Failure.auth("HTTP \(code)")
        }
        return token
    }

    /// Fetch the best English subtitle for an IMDb id, as WebVTT.
    static func fetchVTT(imdbID: String, credentials c: Credentials,
                         token: String) async throws -> String {
        guard let url = searchURL(imdbID: imdbID) else { throw Failure.none }
        let (data, _) = try await URLSession.shared.data(for: request(url, key: c.apiKey, token: token))
        guard let pick = best(of: parseMatches(data)) else { throw Failure.none }

        guard let dl = URL(string: "\(host)/download") else { throw Failure.none }
        let body = try JSONSerialization.data(withJSONObject: ["file_id": pick.fileID])
        let (dData, dResp) = try await URLSession.shared.data(
            for: request(dl, key: c.apiKey, token: token, method: "POST", body: body))
        let code = (dResp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 406 || code == 429 { throw Failure.quota }
        guard code == 200,
              let j = try? JSONSerialization.jsonObject(with: dData) as? [String: Any],
              let link = j["link"] as? String, let fileURL = URL(string: link) else {
            throw Failure.network("Download failed (HTTP \(code))")
        }
        let (subData, _) = try await URLSession.shared.data(from: fileURL)
        // BYTES, decoded deliberately: subtitle sites serve UTF-16 and cp1252
        // constantly, and guessing wrong yields a file that renders nothing.
        let text = decode(subData)
        guard !text.isEmpty else { throw Failure.none }
        return srtToVTT(text)
    }

    /// Decode subtitle bytes: BOM first, then a NUL-heavy body as UTF-16, then
    /// UTF-8, then cp1252. Mirrors tools/build_subtitle_assets.decode_subtitle.
    static func decode(_ data: Data) -> String {
        let b = [UInt8](data.prefix(4))
        if b.count >= 2 {
            if b[0] == 0xFF && b[1] == 0xFE { return String(data: data, encoding: .utf16LittleEndian) ?? "" }
            if b[0] == 0xFE && b[1] == 0xFF { return String(data: data, encoding: .utf16BigEndian) ?? "" }
            if b.count >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF {
                return String(data: data.dropFirst(3), encoding: .utf8) ?? ""
            }
        }
        if data.prefix(400).filter({ $0 == 0 }).count > 40,
           let s = String(data: data, encoding: .utf16LittleEndian) { return s }
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .windowsCP1252) ?? ""
    }
}
