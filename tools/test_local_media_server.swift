// Does the LocalMediaServer serve BYTE-IDENTICAL content to origin, with
// exact HTTP semantics, and does AVPlayer reach readyToPlay through it?
//
// This is the Phase-1 gate (Decision 079) and the audio-static conviction
// test (task #46): if bytes through the proxy differ from origin anywhere,
// the transport is guilty; if they never differ while static persists, the
// transport is exonerated.
//
// Build:
//   xcrun swiftc -parse-as-library \
//     ArchiveWatch/ArchiveWatch/Networking/LocalMediaServer.swift \
//     ArchiveWatch/ArchiveWatch/Networking/ResilientStreamLoader.swift \
//     ArchiveWatch/ArchiveWatch/Networking/AirPlayRouting.swift \
//     tools/test_local_media_server.swift -o /tmp/awproxy && /tmp/awproxy <url>
import AVFoundation
import Foundation

@main
struct Harness {
    static func main() async {
        let origin = URL(string: CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "https://archive.org/download/his_girl_friday/his_girl_friday_512kb.mp4")!
        guard let proxy = LocalMediaServer.shared.proxyURL(for: origin) else {
            print("FAIL: server did not start"); exit(1)
        }
        print("proxy: \(proxy)")

        var failures = 0

        // 1. HEAD + total length agreement
        let originLen = await contentLength(origin)
        let proxyLen = await contentLength(proxy)
        print("length: origin=\(originLen ?? -1) proxy=\(proxyLen ?? -1)")
        if originLen == nil || originLen != proxyLen { failures += 1; print("FAIL length") }

        // 2. Byte-diff a spread of ranges (start, moov-tail, mid, odd offsets,
        //    a large sequential chunk) — the patterns AVFoundation issues.
        let total = originLen ?? 0
        var ranges: [(Int64, Int64)] = [(0, 65_535), (1, 17), (4_096, 4_095 + 131_072)]
        if total > 3_000_000 {
            ranges.append((total - 300_000, total - 1))          // moov-at-end read
            ranges.append((total / 2, total / 2 + 2_000_000))    // mid seek
            ranges.append((77, 77 + 8_388_607))                  // big sequential
        }
        for (lo, hi) in ranges {
            async let a = fetchRange(origin, lo, hi)
            async let b = fetchRange(proxy, lo, hi)
            let (o, p) = await (a, b)
            guard let o, let p else { failures += 1; print("FAIL fetch \(lo)-\(hi)"); continue }
            if o != p {
                failures += 1
                let firstDiff = zip(o, p).enumerated().first { $1.0 != $1.1 }?.offset ?? min(o.count, p.count)
                print("FAIL bytes differ \(lo)-\(hi) at +\(firstDiff) (o:\(o.count) p:\(p.count))")
            } else {
                print("ok \(lo)-\(hi) (\(o.count) bytes)")
            }
        }

        // 2b. STRESS: the same bytes, fetched CONCURRENTLY and repeatedly, in
        //     the interleaved pattern AVFoundation actually uses on a badly
        //     muxed file — separate audio and video cursors walking the same
        //     region, plus small random reads between big sequential ones.
        //
        //     This is the instrument for the owner's audio-static report. The
        //     loader serves small reads from aligned cached blocks, and a
        //     stale or misaligned block would corrupt a sample without failing
        //     any request — silent, and exactly what static sounds like. If
        //     every byte matches origin under concurrency, the loader is
        //     EXONERATED and the static comes from somewhere else (the caption
        //     scout has produced audio artifacts twice: Decisions 071 and 075).
        if total > 12_000_000 {
            print("\nstress: 24 concurrent interleaved reads x 3 rounds")
            var stressFail = 0
            for round in 1...3 {
                var probes: [(Int64, Int64)] = []
                // Two cursors walking the same region, as A/V demux does.
                for i in 0..<8 {
                    let base = total / 4 + Int64(i) * 262_144
                    probes.append((base, base + 65_535))              // "video" cursor
                    probes.append((base + 131_072, base + 147_455))   // "audio" cursor, interleaved
                }
                // Small odd-offset reads between them — the pattern that made
                // the block cache thrash on Till the Clouds Roll By.
                for i in 0..<8 {
                    let off = total / 3 + Int64(i) * 7_919
                    probes.append((off, off + 4_095))
                }
                let results = await withTaskGroup(of: (Int64, Int64, Data?, Data?).self) { group in
                    for (lo, hi) in probes {
                        group.addTask {
                            async let o = fetchRange(origin, lo, hi)
                            async let p = fetchRange(proxy, lo, hi)
                            return await (lo, hi, o, p)
                        }
                    }
                    var acc: [(Int64, Int64, Data?, Data?)] = []
                    for await r in group { acc.append(r) }
                    return acc
                }
                for (lo, hi, o, p) in results {
                    guard let o, let p else { stressFail += 1
                        print("  FAIL fetch \(lo)-\(hi)"); continue }
                    if o != p {
                        stressFail += 1
                        let d = zip(o, p).enumerated().first { $1.0 != $1.1 }?.offset ?? -1
                        print("  FAIL round \(round) bytes differ \(lo)-\(hi) at +\(d)")
                    }
                }
                print("  round \(round): \(probes.count) reads, \(stressFail) mismatches so far")
            }
            failures += stressFail
            if stressFail == 0 {
                print("  stress OK — byte-identical under concurrency")
            }
        }

        // 3. AVPlayer reaches readyToPlay through the proxy and plays.
        let item = AVPlayerItem(url: proxy)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.play()
        let deadline = Date().addingTimeInterval(45)
        while item.status != .readyToPlay, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if item.status == .readyToPlay {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            let t = player.currentTime().seconds
            print("player: readyToPlay, t=\(String(format: "%.1f", t)) after 6s")
            if t < 2 { failures += 1; print("FAIL playback did not advance") }
        } else {
            failures += 1
            print("FAIL player never ready: \(String(describing: item.error))")
        }

        print(failures == 0 ? "\nRESULT: OK — proxy is byte-identical and playable."
                            : "\nRESULT: FAIL — \(failures) failures.")
        exit(failures == 0 ? 0 : 1)
    }

    static func contentLength(_ url: URL) async -> Int64? {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return nil }
        if let l = http.value(forHTTPHeaderField: "Content-Length"), let v = Int64(l), v > 0 { return v }
        return http.expectedContentLength > 0 ? http.expectedContentLength : nil
    }

    static func fetchRange(_ url: URL, _ lo: Int64, _ hi: Int64) async -> Data? {
        var req = URLRequest(url: url)
        req.setValue("bytes=\(lo)-\(hi)", forHTTPHeaderField: "Range")
        req.timeoutInterval = 120
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 206 else { return nil }
        return data
    }
}
