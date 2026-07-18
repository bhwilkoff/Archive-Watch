import Foundation
import Compression

// Downloads the prebuilt SQLite catalog DB and caches it for the app to query
// on disk (Decision 017/019, docs/architecture/catalog-delivery.md). The DB is
// hosted as a GitHub Release asset (off the Pages bandwidth budget; release
// CDN). First paint uses the bundled seed.sqlite; this fetches the full DB in
// the background and AppStore swaps it in.
//
// The asset is shipped raw-DEFLATE compressed (`catalog.sqlite.zz`, ~24 MB vs
// ~100 MB). GitHub Release assets are served as application/octet-stream with
// no Content-Encoding, so URLSession can't auto-decompress — we inflate on
// device with Apple's native Compression framework (hardware-accelerated, no
// third-party zlib), STREAMING file→file so peak memory stays ~64 KB rather
// than holding the 100 MB DB in RAM (Decision 017's whole point on a 3 GB
// Apple TV shared with 4K AVPlayer). Raw DEFLATE is the framework's native
// COMPRESSION_ZLIB input, so there's no fragile gzip-header parsing.

actor CatalogRefreshService {

    static let shared = CatalogRefreshService()

    /// Raw-DEFLATE prebuilt DB hosted as a GitHub Release asset. URLSession
    /// follows the redirect to the asset CDN automatically.
    private let dbURL = URL(string: "https://github.com/bhwilkoff/Archive-Watch/releases/download/catalog-db/catalog.sqlite.zz")!
    private static let dbETagKey = "catalogDBETag"
    private static let lastCheckedKey = "catalogDBLastCheckedAt"
    /// A valid full DB is tens of MB; a far smaller inflate means corruption.
    private static let minValidBytes = 10_000_000
    /// How long a check stays fresh before a foreground resume re-checks.
    static let defaultStaleAfter: TimeInterval = 6 * 3600

    // tvOS only permits writes to Caches / tmp — never Application Support.
    private var dbCacheURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appendingPathComponent("catalog.sqlite")
    }

    /// Path to the already-downloaded DB, if present.
    func cachedDatabasePath() -> String? {
        FileManager.default.fileExists(atPath: dbCacheURL.path) ? dbCacheURL.path : nil
    }

    /// True when the release hasn't been checked for a newer DB within `ttl`.
    func isStale(ttl: TimeInterval = defaultStaleAfter) -> Bool {
        let last = UserDefaults.standard.double(forKey: Self.lastCheckedKey)
        guard last > 0 else { return true }
        return Date().timeIntervalSince1970 - last >= ttl
    }

    /// Foreground/resume path. The launch path (`downloadDatabase`) only ever
    /// runs once per process, so an app resumed after days served the catalog
    /// from its last cold launch forever. This is the re-check: throttled by
    /// `ttl`, and it reports a path ONLY when the bytes actually changed, so
    /// callers bump `dbGeneration` (re-querying every view) exactly once per
    /// real update rather than on every foreground.
    func refreshIfStale(ttl: TimeInterval = defaultStaleAfter) async -> String? {
        guard isStale(ttl: ttl) else { return nil }
        return await downloadDatabase(onlyIfChanged: true)
    }

    /// Download the compressed catalog DB to Caches and inflate it (ETag-
    /// conditional so an unchanged DB isn't re-fetched). Returns the local
    /// path, or the cached path on 304/failure. Validated by the caller
    /// opening it via CatalogDB.
    ///
    /// `onlyIfChanged` returns nil instead of the cached path when the release
    /// is unchanged or unreachable — the resume path uses it to distinguish
    /// "nothing new" from "here is a newer DB".
    func downloadDatabase(onlyIfChanged: Bool = false) async -> String? {
        func unchanged() -> String? { onlyIfChanged ? nil : cachedDatabasePath() }
        var request = URLRequest(url: dbURL)
        request.cachePolicy = .reloadRevalidatingCacheData
        if let etag = UserDefaults.standard.string(forKey: Self.dbETagKey),
           FileManager.default.fileExists(atPath: dbCacheURL.path) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        do {
            let (tmp, response) = try await URLSession.shared.download(for: request)
            defer { try? FileManager.default.removeItem(at: tmp) }
            guard let http = response as? HTTPURLResponse else { return unchanged() }
            // A completed round trip counts as a check even when unchanged, so
            // the TTL throttles re-checks rather than re-downloads.
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckedKey)
            if http.statusCode == 304 { return unchanged() }
            guard http.statusCode == 200 else { return unchanged() }

            // Inflate to a sibling temp file, validate, then atomically swap in.
            let staging = dbCacheURL.appendingPathExtension("inflating")
            try? FileManager.default.removeItem(at: staging)
            try Self.inflate(src: tmp, dst: staging)

            let attrs = try? FileManager.default.attributesOfItem(atPath: staging.path)
            let size = (attrs?[.size] as? Int) ?? 0
            guard size >= Self.minValidBytes else {
                try? FileManager.default.removeItem(at: staging)
                return unchanged()
            }
            try? FileManager.default.removeItem(at: dbCacheURL)
            try FileManager.default.moveItem(at: staging, to: dbCacheURL)
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                UserDefaults.standard.set(etag, forKey: Self.dbETagKey)
            }
            return dbCacheURL.path
        } catch {
            return unchanged()
        }
    }

    // MARK: - Streaming raw-DEFLATE inflate (Apple Compression framework)

    /// Inflate a raw-DEFLATE file to `dst`, streaming in ~64 KB chunks so peak
    /// memory stays small. The Compression framework advances `src_ptr`/
    /// `src_size` through a STABLE source buffer as it consumes input; we only
    /// refill once a chunk is fully consumed. (Re-binding the source every
    /// iteration silently corrupts well-compressing data — verified against the
    /// real 96 MB DB: byte-identical + PRAGMA integrity_check ok.)
    static func inflate(src: URL, dst: URL) throws {
        let input = try FileHandle(forReadingFrom: src)
        FileManager.default.createFile(atPath: dst.path, contents: nil)
        let output = try FileHandle(forWritingTo: dst)
        defer { try? input.close(); try? output.close() }

        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: -1)!, dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(bitPattern: -1)!, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
                == COMPRESSION_STATUS_OK else {
            throw CocoaError(.fileReadCorruptFile)
        }
        defer { compression_stream_destroy(&stream) }

        let cap = 65_536
        let srcBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        let dstBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        defer { srcBuf.deallocate(); dstBuf.deallocate() }

        stream.src_size = 0
        var atEOF = false
        var status = COMPRESSION_STATUS_OK
        repeat {
            if stream.src_size == 0 && !atEOF {
                let chunk = input.readData(ofLength: cap)
                if chunk.isEmpty {
                    atEOF = true
                } else {
                    chunk.copyBytes(to: srcBuf, count: chunk.count)
                    stream.src_ptr = UnsafePointer(srcBuf)
                    stream.src_size = chunk.count
                }
            }
            stream.dst_ptr = dstBuf
            stream.dst_size = cap
            status = compression_stream_process(&stream, atEOF ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
            let produced = cap - stream.dst_size
            if produced > 0 { output.write(Data(bytes: dstBuf, count: produced)) }
            if status == COMPRESSION_STATUS_END { break }
            guard status == COMPRESSION_STATUS_OK else { throw CocoaError(.fileReadCorruptFile) }
        } while true
    }
}
