// PlaybackVerifierCLI — STRICT playability verifier for Archive Watch.
//
// WHY: tools/check_liveness.py's byte-probe reads the first 1 KB of a video and
// checks an HTTP status + container magic. That is LENIENT — ffprobe/curl/requests
// all auto-encode URLs and never decode a frame, so a URL can pass the byte-probe
// yet still fail in the shipping app with "resource unavailable": a raw space/()/#
// in the URL makes Swift `URL(string:)` return nil, a truncated/corrupt stream
// reaches readyToPlay but can't decode, an unsupported codec sits inside a valid
// MP4 container, or an HLS master with a raw-URL segment is rejected by AVFoundation.
//
// This CLI verifies each URL through AVFoundation EXACTLY as the app does:
//   * MP4 (non-captioned): construct the URL with the same encoding the app uses
//     (Catalog.playableURL — space -> %20, # -> %23), load via AVURLAsset.
//   * HLS (captioned, item has subtitleHLS): construct via RAW `URL(string:)` (the
//     app's `subtitleHLSURL`, NO re-encoding) and verify the master through
//     AVPlayerItem — the strict path that actually ships for captioned films.
// Then: wait for AVPlayerItem.status == .readyToPlay (bounded). The deterministic
// hard signals are url_invalid, isPlayable=false, no video track, and the player
// reaching .failed with a media-domain error. For MP4 we ALSO decode a real frame
// at t~=0 and t~=duration/2 via AVAssetImageGenerator, but that check is ADVISORY
// ONLY — remote image-generator decode failures proved flaky (a slow storage node
// mid-seek surfaces as `decodeFailed` yet retries fine), so it never excludes; it
// only annotates the reason. Bias against false-excluding a playable film.
//
// NODE FAILOVER (2026-07, mirrors ResilientStreamLoader / Decision 034): a direct
// load of an archive.org `/download/{id}/{file}` URL 302-redirects to ONE storage
// node, and a single node can be degraded (-1008 resource-unavailable / 5xx / reset)
// while its siblings serve fine — exactly the "resource unavailable" the app RECOVERS
// from by switching to a healthy node. So when the direct load fails with a
// NETWORK/AVAILABILITY error (never a deterministic media error), this harness does
// what the app does: fetch `archive.org/metadata/{id}` for the node list
// (`server` + `alternate_locations.workable`), rewrite the URL onto each node host,
// skip nodes that can't even serve a byte, and retry the AVFoundation load against
// the healthy ones (bounded by a global per-item deadline so it never hangs). Only
// after failover is EXHAUSTED do we emit `unavailable_all_nodes` — and that is a SOFT
// signal (the Python tool requires it to recur across ≥3 runs / ≥2 days before it
// excludes), never an immediate exclude. A deterministic media error on a node that
// DID serve bytes stays HARD (bad file, not a bad node).
//
// CARDINAL RULE: bias every ambiguous verdict toward TRANSIENT/PASS. A wrongly
// hidden playable film is the costly error; a missed bad one is retried next run.
// Only DETERMINISTIC hard signals (nil URL, isPlayable=false, no video track, a
// clear decode/format AVError) exclude; all network/unknown errors are transient,
// and an all-node availability failure is soft (confirm-across-runs in Python).
//
// I/O: reads one input per line from stdin as JSON `{"id","url","hls"}` (or a
// bare URL string), plus any bare URLs passed as argv. `id` is the archive.org
// identifier (the harness fetches its /metadata for node failover). Emits one JSON
// result per input to stdout: {"id","url","verdict","reason","detail","ms"}.
//
// Verdicts:
//   PASS      : ok, ok_failover
//   HARD      : url_invalid, not_playable, no_video_track   (-> app should exclude)
//   APPLE     : apple_container_error, decode_failed, unsupported_codec,
//               failed_permanent  (-> AVFoundation-specific failure; NOT proof the
//               file is universally broken. The Python tool ffprobe-disambiguates
//               these into faststart-quirk (keep) / truncated (exclude) /
//               exotic-codec (Apple-advisory, keep) — never a blind global exclude.)
//   SOFT      : unavailable_all_nodes  (-> Python confirms across runs before excluding)
//   TRANSIENT : transient   (-> leave unverified, retry later, NEVER exclude)
//
// NOTE (2026-07 false-exclude fix): AVFoundation's -11829/-11828/-11833 are
// container/parse "media damaged" errors, NOT "unsupported codec". A valid
// H.264/AAC film with a non-faststart moov-at-EOF layout is REJECTED by
// AVFoundation-over-HTTP yet plays fine after a local faststart remux, and on
// ExoPlayer/browsers. So those codes now map to `apple_container_error` (distinct
// from a genuine codec problem) and the Python side runs ffprobe to tell a
// faststart quirk apart from a truly truncated/no-moov file.

import Foundation
import AVFoundation

// A broken-pipe write (consumer closed stdout) must not crash the process.
signal(SIGPIPE, SIG_IGN)

// MARK: - Verdicts

enum Verdict: String {
    case ok
    case ok_failover
    case url_invalid
    case not_playable
    case no_video_track
    case decode_failed
    case unsupported_codec
    case apple_container_error   // AVFoundation container/parse "damaged" (-11829/-11828/-11833)
    case failed_permanent
    case unavailable_all_nodes
    case transient
}

/// Deterministic media problems (a bad FILE, not a bad node). If the ORIGIN — or a
/// node that served bytes — returns one of these, do NOT fail over: it means the
/// file itself is unplayable, which is a HARD exclude. Availability/network errors
/// are NOT in this set and are what trigger node failover.
func isHardMedia(_ v: Verdict) -> Bool {
    switch v {
    case .url_invalid, .not_playable, .no_video_track,
         .decode_failed, .unsupported_codec, .apple_container_error, .failed_permanent:
        // apple_container_error is a property of the FILE (moov layout / damaged
        // container) — identical on every storage node, so a node switch won't
        // help. Treat it as hard-media for failover purposes (do NOT rotate nodes);
        // the Python side then ffprobe-disambiguates it (it is NOT a blind exclude).
        return true
    default:
        return false
    }
}

struct Input {
    let id: String
    let url: String?
    let hls: String?
}

struct VResult {
    let id: String
    let url: String
    let verdict: Verdict
    let reason: String
    let detail: String
    let ms: Int
}

// MARK: - URL construction (mirrors the app EXACTLY)

/// Mirrors `Catalog.playableURL` in Catalog.swift: only space and # are encoded,
/// everything else is passed to `URL(string:)` verbatim. Returns nil the same way
/// the app would (so a URL the app can't build is reported as url_invalid).
func playableURL(_ raw: String?) -> URL? {
    guard let raw, !raw.isEmpty else { return nil }
    if !raw.contains(" ") && !raw.contains("#") { return URL(string: raw) }
    let fixed = raw.replacingOccurrences(of: " ", with: "%20")
                   .replacingOccurrences(of: "#", with: "%23")
    return URL(string: fixed)
}

/// Mirrors `Catalog.Item.subtitleHLSURL`: RAW `URL(string:)`, no re-encoding. A
/// master URL with a raw space therefore yields nil here — exactly the app's
/// behavior, where a nil HLS URL would drop the captioned path entirely.
func hlsURL(_ raw: String?) -> URL? {
    guard let raw, !raw.isEmpty else { return nil }
    return URL(string: raw)
}

// MARK: - Error classification (bias: unknown -> transient)

/// AVFoundationErrorDomain codes we treat as HARD (deterministic media problems).
/// Everything else in that domain is left transient — many AVFoundation errors are
/// network/HTTP wrappers and must not false-exclude a playable film.
let hardAVCodes: [Int: (Verdict, String)] = [
    // Container/parse "media damaged" family -> apple_container_error (NOT a codec
    // problem). These are exactly what a valid H.264 film with a non-faststart
    // moov-at-EOF returns over HTTP; ffprobe reads it fine and it plays after a
    // local remux. The Python side disambiguates before ever excluding.
    -11828: (.apple_container_error, "format_not_recognized"),  // AVErrorFileFormatNotRecognized
    -11829: (.apple_container_error, "failed_to_parse"),        // AVErrorFailedToParse (media damaged)
    -11833: (.apple_container_error, "file_failed_to_parse"),   // AVErrorFileFailedToParse
    -11821: (.decode_failed, "decode_failed"),                 // AVErrorDecodeFailed
    -11850: (.unsupported_codec, "operation_not_supported"),   // genuine "op not supported"
]

func classify(_ error: Error?, hard: Bool) -> (Verdict, String) {
    // `hard == true` means we arrived here from AVPlayerItem.status == .failed
    // (the player gave up). Even so, only a clear media error excludes; a
    // network/HTTP failure is transient (retry).
    guard let error else {
        return hard ? (.transient, "failed_no_error") : (.transient, "unknown")
    }
    let ns = error as NSError

    // Network layer -> always transient (timeout, connection lost, DNS, 5xx-ish).
    if ns.domain == NSURLErrorDomain {
        return (.transient, "network_\(ns.code)")
    }
    if ns.domain == AVFoundationErrorDomain {
        if let mapped = hardAVCodes[ns.code] { return mapped }
        // Some AVFoundation errors wrap an underlying NSURLError — if so, honor it.
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSURLErrorDomain {
            return (.transient, "network_\(underlying.code)")
        }
        return (.transient, "av_\(ns.code)")
    }
    // Any other domain: unknown -> transient (never false-exclude).
    return (.transient, "\(ns.domain)_\(ns.code)")
}

// MARK: - Node failover (mirrors ResilientStreamLoader / Decision 034)

/// Shared session for the auxiliary /metadata + node-health probes. Capped per host
/// (archive.org refuses an IP that opens too many connections) and NOT the session
/// AVFoundation uses to load the media — this only fetches the node list + a 2-byte
/// health probe. Short timeouts so a dead node is abandoned fast.
let metaSession: URLSession = {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.timeoutIntervalForRequest = 20
    cfg.timeoutIntervalForResource = 25
    cfg.httpMaximumConnectionsPerHost = 3
    cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: cfg)
}()

/// The encoded `{file}` portion of an archive.org `/download/{id}/{file}` URL, kept
/// URL-encoded exactly as the app keeps it when building node-direct URLs. Returns
/// nil for a non-archive / non-/download URL (e.g. an HLS master on our own host) —
/// those have no node list to fail over to.
func archiveDownloadFile(_ url: URL) -> String? {
    let s = url.absoluteString
    guard (url.host?.hasSuffix("archive.org") ?? false),
          let r = s.range(of: "/download/") else { return nil }
    let after = s[r.upperBound...]
    guard let slash = after.firstIndex(of: "/") else { return nil }
    return String(after[after.index(after: slash)...])
}

/// Fetch the item's storage-node list from /metadata and build the node-DIRECT URLs
/// (`https://{server}{dir}/{file}`), preferred node first — exactly as
/// ResilientStreamLoader.loadAlternates does. Best-effort: [] when metadata is
/// unavailable or the URL isn't a /download URL, so the caller degrades gracefully.
func alternateNodeURLs(archiveID: String, originalURL: URL) async -> [URL] {
    guard let encFile = archiveDownloadFile(originalURL) else { return [] }
    let idEnc = archiveID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? archiveID
    guard let metaURL = URL(string: "https://archive.org/metadata/\(idEnc)") else { return [] }
    guard let (data, resp) = try? await metaSession.data(from: metaURL),
          let http = resp as? HTTPURLResponse, http.statusCode == 200,
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }

    var bases: [URL] = []
    var seen = Set<String>()
    func add(_ server: String?, _ dir: String?) {
        guard let server, let dir, !server.isEmpty,
              let u = URL(string: "https://\(server)\(dir)/\(encFile)"),
              seen.insert(server).inserted else { return }
        bases.append(u)
    }
    add(obj["server"] as? String, obj["dir"] as? String)
    if let alt = obj["alternate_locations"] as? [String: Any],
       let workable = alt["workable"] as? [[String: Any]] {
        for w in workable { add(w["server"] as? String, w["dir"] as? String) }
    }
    return bases
}

/// A cheap 2-byte ranged GET: does this node serve the file at all right now?
/// Used to skip a degraded node BEFORE spending the per-item deadline on a full
/// AVFoundation load — mirrors ResilientStreamLoader picking a "healthy known node".
func nodeServesBytes(_ url: URL) async -> Bool {
    var req = URLRequest(url: url)
    req.setValue("bytes=0-1", forHTTPHeaderField: "Range")
    req.timeoutInterval = 12
    guard let (_, resp) = try? await metaSession.data(for: req),
          let h = resp as? HTTPURLResponse else { return false }
    return (200...299).contains(h.statusCode)
}

// MARK: - Core verification

/// Verify a single already-resolved URL through AVFoundation the way the app does.
/// `deadline` caps the readyToPlay wait so failover across several nodes still fits
/// inside the per-item hard timeout.
func verify(id: String, targetURL: URL, isHLS: Bool, deadline: Date) async -> (Verdict, String, String) {
    let asset = AVURLAsset(url: targetURL, options: [
        AVURLAssetPreferPreciseDurationAndTimingKey: true
    ])

    // 1) Load core properties. A load failure here is usually the network fetch
    //    of the file/playlist header — classify (network -> transient).
    var duration = CMTime.zero
    do {
        let (playable, dur) = try await asset.load(.isPlayable, .duration)
        duration = dur
        if !playable {
            return (.not_playable, "asset_not_playable", "")
        }
    } catch {
        let ns = error as NSError
        let (v, r) = classify(error, hard: false)
        return (v, r, "avcode=\(ns.code); \(ns.localizedDescription)")
    }

    // 2) Video-track presence. HLS master track loading is unreliable until an
    //    item exists, so this hard check is MP4-only (HLS relies on readyToPlay).
    if !isHLS {
        do {
            let vids = try await asset.loadTracks(withMediaType: .video)
            if vids.isEmpty {
                return (.no_video_track, "no_video_track", "")
            }
        } catch {
            let ns = error as NSError
            let (v, r) = classify(error, hard: false)
            return (v, r, "avcode=\(ns.code); \(ns.localizedDescription)")
        }
    }

    // 3) Drive an AVPlayerItem to readyToPlay (or .failed). This is the exact
    //    signal the app watches (DetailView.setupPlayer). Poll status; the item
    //    only advances once attached to a player.
    let item = AVPlayerItem(asset: asset)
    let player = AVPlayer(playerItem: item)
    player.automaticallyWaitsToMinimizeStalling = true
    defer { player.replaceCurrentItem(with: nil) }

    // Cap this node's readyToPlay wait at 25s, but never past the item-wide
    // deadline (so origin + a couple failover nodes all fit the hard timeout).
    let statusDeadline = min(Date().addingTimeInterval(25), deadline)
    while Date() < statusDeadline {
        switch item.status {
        case .readyToPlay:
            // For HLS, readyToPlay IS the pass (the app plays HLS with no further
            // decode gate). For MP4, go on to the frame-decode check.
            if isHLS { return (.ok, "hls_ready", "") }
            return await decodeCheck(asset: asset, duration: duration)
        case .failed:
            let ns = item.error as NSError?
            let (v, r) = classify(item.error, hard: true)
            // classify returns either .transient (network/unknown -> retry) or a
            // SPECIFIC verdict (a hardAVCodes mapping incl. apple_container_error).
            // Return the specific verdict AS-IS — never collapse apple_container_error
            // or unsupported_codec into failed_permanent (the Python side needs the
            // distinction to ffprobe-disambiguate instead of blind-excluding). The
            // raw AVError code rides in `detail` as evidence.
            let detail = "avcode=\(ns?.code ?? 0); \(ns?.localizedDescription ?? "")"
            return (v, r, detail)
        default:
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }
    // Never reached readyToPlay or failed in time -> transient (retry), unless the
    // player already latched a hard error we can read.
    if item.status == .failed {
        let ns = item.error as NSError?
        let (v, r) = classify(item.error, hard: true)
        if v != .transient { return (v, r, "avcode=\(ns?.code ?? 0); \(ns?.localizedDescription ?? "")") }
    }
    return (.transient, "status_timeout", "no readyToPlay/failed within budget")
}

/// Decode a real frame at t~=0 and t~=duration/2. Catches truncated/corrupt/
/// wrong-codec MP4s that reach readyToPlay but cannot actually decode.
func decodeCheck(asset: AVURLAsset, duration: CMTime) async -> (Verdict, String, String) {
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    // Allow keyframe tolerance — we only need SOME frame to decode, not the exact
    // one; forcing exact frames false-fails keyframe-sparse encodes.
    gen.requestedTimeToleranceBefore = CMTime(seconds: 3, preferredTimescale: 600)
    gen.requestedTimeToleranceAfter = CMTime(seconds: 3, preferredTimescale: 600)

    let durSecs = duration.seconds.isFinite && duration.seconds > 0 ? duration.seconds : 0
    var times: [CMTime] = [CMTime(seconds: min(1.0, max(0.0, durSecs * 0.02)), preferredTimescale: 600)]
    if durSecs > 6 {
        times.append(CMTime(seconds: durSecs / 2.0, preferredTimescale: 600))
    }

    for t in times {
        do {
            _ = try await gen.image(at: t)
        } catch {
            // ADVISORY ONLY — a frame-decode failure NEVER excludes. Measured
            // (2026-07): remote AVAssetImageGenerator decode failures are FLAKY —
            // a slow storage node mid-seek surfaces as AVFoundation `decodeFailed`
            // (-11821) yet the same item decodes fine on retry. Since readyToPlay
            // already succeeded (AVFoundation parsed the moov + initial samples),
            // we PASS and record the soft signal in the reason rather than risk
            // false-excluding a playable film. Deterministic hard media failures
            // are caught by the AVPlayerItem `.failed` path, not here.
            let (_, r) = classify(error, hard: true)
            return (.ok, "ready_decode_soft", "frame decode soft-fail: \(r) — \((error as NSError).localizedDescription)")
        }
    }
    return (.ok, "decoded", "")
}

/// Verify the origin URL, and — on a network/availability failure (never a
/// deterministic media error) — fail over across the item's storage nodes exactly
/// as the app does. Returns:
///   * .ok / .ok_failover           — some node reached readyToPlay (PASS)
///   * a HARD verdict               — the origin, or a node that served bytes, has a
///                                     deterministic media problem (bad FILE)
///   * .unavailable_all_nodes       — origin + every known node failed with an
///                                     availability/network error (SOFT: Python
///                                     confirms across runs before excluding)
func verifyWithFailover(id: String, archiveID: String, target: URL,
                        isHLS: Bool, deadline: Date) async -> (Verdict, String, String) {
    let r0 = await verify(id: id, targetURL: target, isHLS: isHLS, deadline: deadline)
    if r0.0 == .ok { return r0 }                 // passed on the origin's node
    if isHardMedia(r0.0) { return r0 }           // bad file — a node switch won't help

    // Origin failed with a network/availability error. Fetch the node list and try
    // the healthy node-DIRECT URLs (skipping any node that can't even serve a byte).
    let alts = await alternateNodeURLs(archiveID: archiveID, originalURL: target)
    if alts.isEmpty {
        // No node list (metadata down, or a non-/download URL like an HLS master —
        // captioned playback has no failover in the app either). SOFT, not HARD.
        return (.unavailable_all_nodes, "no_alternates",
                "origin unavailable (\(r0.1)); no node list to fail over to")
    }
    var served = 0
    var lastReason = r0.1
    for node in alts {
        if Date() >= deadline { break }
        if !(await nodeServesBytes(node)) { continue }   // dead node — skip fast
        served += 1
        let rn = await verify(id: id, targetURL: node, isHLS: isHLS, deadline: deadline)
        if rn.0 == .ok {
            return (.ok_failover, "ok_failover", "recovered on node \(node.host ?? "?")")
        }
        if isHardMedia(rn.0) { return rn }        // node served bytes, file is bad
        lastReason = rn.1
    }
    return (.unavailable_all_nodes, "all_nodes_unavailable",
            "origin + \(alts.count) node(s) unavailable (served=\(served)); last=\(lastReason)")
}

/// Wrap one input: pick the URL the app would use, guard nil (url_invalid), and
/// race the verification (incl. node failover) against a hard per-item timeout so
/// nothing hangs.
func run(_ input: Input, timeout: Double) async -> VResult {
    let start = Date()
    let deadline = start.addingTimeInterval(timeout)
    let isHLS = (input.hls?.isEmpty == false)
    let rawForReport = isHLS ? (input.hls ?? "") : (input.url ?? "")

    let target: URL?
    if isHLS {
        target = hlsURL(input.hls)
    } else {
        target = playableURL(input.url)
    }
    guard let target else {
        return VResult(id: input.id, url: rawForReport, verdict: .url_invalid,
                       reason: isHLS ? "hls_url_nil" : "mp4_url_nil",
                       detail: "URL(string:) returned nil for the app's construction",
                       ms: Int(Date().timeIntervalSince(start) * 1000))
    }

    let verdictTuple: (Verdict, String, String) = await withTaskGroup(of: (Verdict, String, String)?.self) { group in
        // Leave the failover a ~1s margin under the race so it returns a clean
        // unavailable_all_nodes rather than the race's generic timeout.
        group.addTask {
            await verifyWithFailover(id: input.id, archiveID: input.id, target: target,
                                     isHLS: isHLS, deadline: deadline.addingTimeInterval(-1))
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            return (.transient, "timeout", "no verdict within \(Int(timeout))s")
        }
        let first = await group.next() ?? (.transient, "internal", "")
        group.cancelAll()
        return first ?? (.transient, "internal", "")
    }

    return VResult(id: input.id, url: target.absoluteString,
                   verdict: verdictTuple.0, reason: verdictTuple.1, detail: verdictTuple.2,
                   ms: Int(Date().timeIntervalSince(start) * 1000))
}

// MARK: - JSON I/O

func parseInput(_ line: String) -> Input? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return nil }
    if trimmed.hasPrefix("{"),
       let data = trimmed.data(using: .utf8),
       let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
        let url = obj["url"] as? String
        let hls = obj["hls"] as? String
        let id = (obj["id"] as? String) ?? url ?? hls ?? UUID().uuidString
        return Input(id: id, url: url, hls: hls)
    }
    // Bare URL line.
    return Input(id: trimmed, url: trimmed, hls: nil)
}

func emit(_ r: VResult) {
    let obj: [String: Any] = [
        "id": r.id, "url": r.url, "verdict": r.verdict.rawValue,
        "reason": r.reason, "detail": r.detail, "ms": r.ms
    ]
    if let data = try? JSONSerialization.data(withJSONObject: obj),
       let s = String(data: data, encoding: .utf8) {
        print(s)
        fflush(stdout)
    }
}

// MARK: - Entry

func main() async {
    var concurrency = 4
    var timeout = 90.0   // room for origin + node failover within one item
    var argvURLs: [String] = []
    let args = Array(CommandLine.arguments.dropFirst())
    var i = 0
    while i < args.count {
        let a = args[i]
        switch a {
        case "--concurrency":
            i += 1; if i < args.count { concurrency = max(1, Int(args[i]) ?? 4) }
        case "--timeout":
            i += 1; if i < args.count { timeout = Double(args[i]) ?? 45.0 }
        default:
            argvURLs.append(a)
        }
        i += 1
    }

    var inputs: [Input] = argvURLs.compactMap { parseInput($0) }
    while let line = readLine(strippingNewline: true) {
        if let inp = parseInput(line) { inputs.append(inp) }
    }
    if inputs.isEmpty { return }

    // Bounded concurrency: archive.org rate-limits an IP that storms its hosts
    // (Creation Studio "connection discipline"), so keep this LOW. Sequentially
    // fed task group capped at `concurrency`.
    var index = 0
    await withTaskGroup(of: VResult.self) { group in
        var running = 0
        func fill() {
            while running < concurrency && index < inputs.count {
                let inp = inputs[index]; index += 1; running += 1
                group.addTask { await run(inp, timeout: timeout) }
            }
        }
        fill()
        while let result = await group.next() {
            running -= 1
            emit(result)
            fill()
        }
    }
}

await main()
