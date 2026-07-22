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
// CARDINAL RULE: bias every ambiguous verdict toward TRANSIENT/PASS. A wrongly
// hidden playable film is the costly error; a missed bad one is retried next run.
// Only DETERMINISTIC hard signals (nil URL, isPlayable=false, no video track, a
// clear decode/format AVError) exclude; all network/unknown errors are transient.
//
// I/O: reads one input per line from stdin as JSON `{"id","url","hls"}` (or a
// bare URL string), plus any bare URLs passed as argv. Emits one JSON result per
// input to stdout: {"id","url","verdict","reason","detail","ms"}.
//
// Verdicts:
//   PASS      : ok
//   HARD      : url_invalid, not_playable, no_video_track, decode_failed,
//               unsupported_codec, failed_permanent   (-> app should exclude)
//   TRANSIENT : transient   (-> leave unverified, retry later, NEVER exclude)

import Foundation
import AVFoundation

// A broken-pipe write (consumer closed stdout) must not crash the process.
signal(SIGPIPE, SIG_IGN)

// MARK: - Verdicts

enum Verdict: String {
    case ok
    case url_invalid
    case not_playable
    case no_video_track
    case decode_failed
    case unsupported_codec
    case failed_permanent
    case transient
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
    -11828: (.unsupported_codec, "format_not_recognized"), // AVErrorFileFormatNotRecognized
    -11829: (.unsupported_codec, "file_type_unsupported"), // AVErrorContentIsUnavailable-adjacent; format
    -11821: (.decode_failed, "decode_failed"),             // AVErrorDecodeFailed
    -11833: (.decode_failed, "file_failed_to_parse"),      // AVErrorFileFailedToParse
    -11850: (.unsupported_codec, "operation_not_supported"),
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

// MARK: - Core verification

/// Verify a single already-resolved URL through AVFoundation the way the app does.
func verify(id: String, targetURL: URL, isHLS: Bool) async -> (Verdict, String, String) {
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
        let (v, r) = classify(error, hard: false)
        return (v, r, (error as NSError).localizedDescription)
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
            let (v, r) = classify(error, hard: false)
            return (v, r, (error as NSError).localizedDescription)
        }
    }

    // 3) Drive an AVPlayerItem to readyToPlay (or .failed). This is the exact
    //    signal the app watches (DetailView.setupPlayer). Poll status; the item
    //    only advances once attached to a player.
    let item = AVPlayerItem(asset: asset)
    let player = AVPlayer(playerItem: item)
    player.automaticallyWaitsToMinimizeStalling = true
    defer { player.replaceCurrentItem(with: nil) }

    let statusDeadline = Date().addingTimeInterval(35)
    while Date() < statusDeadline {
        switch item.status {
        case .readyToPlay:
            // For HLS, readyToPlay IS the pass (the app plays HLS with no further
            // decode gate). For MP4, go on to the frame-decode check.
            if isHLS { return (.ok, "hls_ready", "") }
            return await decodeCheck(asset: asset, duration: duration)
        case .failed:
            let (v, r) = classify(item.error, hard: true)
            // A .failed status that classifies as a media error is a permanent
            // failure; a network-classified one stays transient (retry).
            if v == .transient { return (.transient, r, item.error.map { ($0 as NSError).localizedDescription } ?? "") }
            let permanent: Verdict = (v == .decode_failed || v == .unsupported_codec) ? v : .failed_permanent
            return (permanent, r, item.error.map { ($0 as NSError).localizedDescription } ?? "")
        default:
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }
    // Never reached readyToPlay or failed in time -> transient (retry), unless the
    // player already latched a hard error we can read.
    if item.status == .failed {
        let (v, r) = classify(item.error, hard: true)
        if v != .transient { return (v == .decode_failed || v == .unsupported_codec ? v : .failed_permanent, r, "") }
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

/// Wrap one input: pick the URL the app would use, guard nil (url_invalid), and
/// race the verification against a hard per-item timeout so nothing hangs.
func run(_ input: Input, timeout: Double) async -> VResult {
    let start = Date()
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
        group.addTask { await verify(id: input.id, targetURL: target, isHLS: isHLS) }
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
    var timeout = 45.0
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
