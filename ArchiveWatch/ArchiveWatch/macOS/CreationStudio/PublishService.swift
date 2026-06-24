#if os(macOS)
import Foundation
import Security
import Observation

// Publish a finished edit to the Internet Archive (Decision 042 Phase 5 / feature #7).
// archive.org-first because YouTube uploads from an unverified OAuth app are forced Private +
// 100-user-capped; the Archive is on-brand and accepts the user's own IAS3 ("S3-like") keys.
// Creates a NEW community item, uploads the exported file, and stamps provenance + a free
// license — the create→edit→SHARE loop that is the whole point of the Mac app.
//
// The actual upload needs the user's real keys (Settings ▸ Publishing) and creates a public
// item, so it can't run in CI — but every request (identifier, URL, headers, auth) is built by
// pure functions an env-gated self-test verifies offline (AW_CS_PUBTEST=1).

/// archive.org IAS3 credentials, kept in the login Keychain (never UserDefaults/iCloud).
enum IAS3Keychain {
    private static let service = "org.archive.s3.archivewatch"
    static func load() -> (access: String, secret: String)? {
        guard let a = read("access"), let s = read("secret"), !a.isEmpty, !s.isEmpty else { return nil }
        return (a, s)
    }
    static func save(access: String, secret: String) {
        write("access", access); write("secret", secret)
    }
    static func clear() { delete("access"); delete("secret") }

    private static func q(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: key]
    }
    private static func read(_ key: String) -> String? {
        var item: CFTypeRef?
        var query = q(key); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let d = item as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    private static func write(_ key: String, _ value: String) {
        delete(key)
        var query = q(key); query[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }
    private static func delete(_ key: String) { SecItemDelete(q(key) as CFDictionary) }
}

enum PublishError: LocalizedError {
    case noCredentials, http(Int, String), badResponse
    var errorDescription: String? {
        switch self {
        case .noCredentials: return "Add your archive.org S3 keys in Settings ▸ Publishing first."
        case .http(let c, let m): return "Internet Archive returned \(c). \(m)"
        case .badResponse: return "Unexpected response from the Internet Archive."
        }
    }
}

@MainActor @Observable
final class PublishService {
    enum Phase: Equatable { case idle, creating, uploading(Double), done(URL), failed(String) }
    var phase: Phase = .idle
    var hasCredentials: Bool { IAS3Keychain.load() != nil }

    static let s3 = "https://s3.us.archive.org"

    /// A valid, unique archive.org identifier from a title: ascii-slug + an "archivewatch" tag
    /// + a short disambiguator. (Pure — verified by the self-test.)
    static func identifier(for title: String, salt: String) -> String {
        let base = title.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        var slug = String(base)
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.count > 50 { slug = String(slug.prefix(50)) }
        if slug.isEmpty { slug = "edit" }
        return "archivewatch-\(slug)-\(salt)"
    }

    /// The metadata headers for the create-item PUT (pure — verified by the self-test).
    static func metaHeaders(title: String, description: String, sources: [String]) -> [String: String] {
        var desc = description.isEmpty ? "A fan edit assembled in Archive Watch." : description
        if !sources.isEmpty {
            desc += "\n\nSources (public domain, via the Internet Archive):\n" + sources.joined(separator: "\n")
        }
        return [
            "x-amz-auto-make-bucket": "1",
            "x-archive-meta-mediatype": "movies",
            "x-archive-meta-collection": "opensource_movies",
            "x-archive-meta-title": title.isEmpty ? "Archive Watch edit" : title,
            "x-archive-meta-creator": "Archive Watch",
            "x-archive-meta-subject": "Archive Watch; fan edit; public domain; remix",
            "x-archive-meta-licenseurl": "https://creativecommons.org/publicdomain/zero/1.0/",
            "x-archive-meta-description": desc,
            "x-archive-meta-originalurl": "https://archivewatch.org",
        ]
    }

    static func auth(_ c: (access: String, secret: String)) -> String { "LOW \(c.access):\(c.secret)" }

    /// Upload `fileURL` to a new archive.org item. Returns its details URL.
    func publish(fileURL: URL, title: String, description: String, sources: [String], salt: String) async throws -> URL {
        guard let creds = IAS3Keychain.load() else { phase = .failed(PublishError.noCredentials.errorDescription!); throw PublishError.noCredentials }
        let id = Self.identifier(for: title, salt: salt)
        let authHeader = Self.auth(creds)

        // 1) Create the item (empty PUT to the bucket with metadata headers).
        phase = .creating
        var create = URLRequest(url: URL(string: "\(Self.s3)/\(id)")!)
        create.httpMethod = "PUT"
        create.setValue(authHeader, forHTTPHeaderField: "Authorization")
        for (k, v) in Self.metaHeaders(title: title, description: description, sources: sources) {
            create.setValue(v, forHTTPHeaderField: k)
        }
        create.setValue("0", forHTTPHeaderField: "x-archive-queue-derive")
        let (_, cResp) = try await URLSession.shared.data(for: create)
        try Self.check(cResp)

        // 2) Upload the file (streamed from disk).
        phase = .uploading(0)
        let remote = fileURL.lastPathComponent.replacingOccurrences(of: " ", with: "_")
        var put = URLRequest(url: URL(string: "\(Self.s3)/\(id)/\(remote)")!)
        put.httpMethod = "PUT"
        put.setValue(authHeader, forHTTPHeaderField: "Authorization")
        put.setValue("0", forHTTPHeaderField: "x-archive-queue-derive")
        put.setValue("0", forHTTPHeaderField: "x-archive-keep-old-version")
        let delegate = UploadProgress { [weak self] f in Task { @MainActor in self?.phase = .uploading(f) } }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (_, uResp) = try await session.upload(for: put, fromFile: fileURL)
        try Self.check(uResp)

        let url = URL(string: "https://archive.org/details/\(id)")!
        phase = .done(url)
        return url
    }

    /// Offline verification of the pure request-construction (AW_CS_PUBTEST=1) — the upload
    /// itself needs real keys + creates a public item, so it can't run in CI.
    static func selfTest() {
        func log(_ s: String) { FileHandle.standardError.write(Data("AWCS PUBTEST: \(s)\n".utf8)) }
        let id = identifier(for: "Méliès & Friends: A Trip! (1902) [test]", salt: "a1b2c3")
        log("identifier = \(id)")
        log("  valid charset = \(id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })")
        log("create URL = \(s3)/\(id)")
        log("upload URL = \(s3)/\(id)/My_Edit.mp4")
        log("auth = \(auth((access: "ACCESS", secret: "SECRET")))")
        for (k, v) in metaHeaders(title: "My Edit", description: "A test.",
                                  sources: ["https://archive.org/details/foo", "https://archive.org/details/bar"]).sorted(by: { $0.key < $1.key }) {
            log("  \(k): \(v.replacingOccurrences(of: "\n", with: " ⏎ "))")
        }
        log("hasCredentials (Keychain) = \(IAS3Keychain.load() != nil)")
    }

    private static func check(_ resp: URLResponse) throws {
        guard let h = resp as? HTTPURLResponse else { throw PublishError.badResponse }
        guard (200...299).contains(h.statusCode) else {
            throw PublishError.http(h.statusCode, HTTPURLResponse.localizedString(forStatusCode: h.statusCode))
        }
    }
}

/// Streams upload progress (archive.org items can be large).
private final class UploadProgress: NSObject, URLSessionTaskDelegate {
    let onProgress: (Double) -> Void
    init(_ onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }
    func urlSession(_ s: URLSession, task: URLSessionTask, didSendBodyData sent: Int64,
                    totalBytesSent total: Int64, totalBytesExpectedToSend expected: Int64) {
        guard expected > 0 else { return }
        onProgress(Double(total) / Double(expected))
    }
}
#endif
