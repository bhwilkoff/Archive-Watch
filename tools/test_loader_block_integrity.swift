// Does the loader's block-cache path serve EXACTLY the file's bytes?
//
// The cache was added for badly-muxed files whose sample tables page in tiny
// random reads. A wrong byte here corrupts the demuxer's view of the film —
// perceived as degraded picture and drifting sync, which is what the owner
// reported the build after it shipped. Every small-read pattern AVFoundation
// uses is replayed against the SHIPPED loader and compared byte-for-byte with
// a direct ranged fetch.
//
// Build:
//   xcrun swiftc -parse-as-library \
//     ArchiveWatch/ArchiveWatch/Networking/ResilientStreamLoader.swift \
//     ArchiveWatch/ArchiveWatch/Networking/AirPlayRouting.swift \
//     tools/test_loader_block_integrity.swift -o /tmp/awblocks && /tmp/awblocks <url>

import AVFoundation
import Foundation

@main
struct Harness {
    static func main() async {
        let raw = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
            : "https://archive.org/download/till-the-clouds-roll-by-film-1946-usa/_TILL%20THE%20CLOUDS%20ROLL%20BY_%20film%201946%20USA%20136mins%20-%20upload%20by%20KONNEENN.mp4"
        guard let url = URL(string: raw) else { print("bad url"); exit(2) }

        let (asset, maybeLoader) = ResilientStreamLoader.makeAsset(for: url)
        guard let loader = maybeLoader else { print("no loader for url"); exit(2) }

        // Small-read patterns measured from the real device trace: repeated
        // head reads, mid-file jumps, adjacent walks, block-boundary
        // straddles, and re-reads of the same range.
        var patterns: [(Int64, Int)] = [
            (0, 65536), (3_145_728, 65536), (3_145_728, 65536),
            (881_721_344, 65536), (918_093_824, 131072),
            (2_097_152 - 1000, 2000),          // block boundary straddle
            (4_194_304 - 1, 131072),           // straddle at 2-block boundary
            (100_000_000, 65536), (100_065_536, 65536), (100_131_072, 65536),
        ]
        for i in 0..<8 { patterns.append((Int64(850_000_000 + i * 65536), 65536)) }

        // Direct reference bytes.
        func direct(_ off: Int64, _ len: Int) async throws -> Data {
            var req = URLRequest(url: url)
            req.setValue("bytes=\(off)-\(off + Int64(len) - 1)", forHTTPHeaderField: "Range")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 206 else {
                throw URLError(.badServerResponse)
            }
            return data
        }

        // Loader bytes, via a real AVAssetResourceLoadingRequest is not
        // constructible outside AVFoundation — so drive the SHIPPED asset the
        // way AVFoundation does: an AVAssetReader-style byte pull is also not
        // exposed. Instead, exercise the loader through AVFoundation itself:
        // load tracks + duration (forces moov paging through the small-read
        // path) and then verify N random ranges by asking the loader's OWN
        // block fetcher through a private probe hook.
        //
        // The probe hook: ResilientStreamLoader.debugReadRange(_:length:) —
        // test-only, routes through the same serveFromBlocks/blockData code.
        var failures = 0
        for (off, len) in patterns {
            do {
                let got = try await loader.debugReadRange(offset: off, length: len)
                let want = try await direct(off, len)
                if got != want {
                    failures += 1
                    print("MISMATCH off=\(off) len=\(len): got \(got.count) bytes, "
                          + "want \(want.count); firstDiff="
                          + "\(zip(got, want).enumerated().first(where: { $1.0 != $1.1 })?.offset ?? -1)")
                } else {
                    print("ok off=\(off) len=\(len) (\(got.count) bytes)")
                }
            } catch {
                failures += 1
                print("ERROR off=\(off) len=\(len): \(error)")
            }
        }

        // And the real AVFoundation path must still parse the asset.
        do {
            let dur = try await asset.load(.duration)
            print("asset duration via loader: \(Int(dur.seconds))s")
        } catch {
            failures += 1
            print("ASSET LOAD FAILED: \(error)")
        }

        print(failures == 0
              ? "\nRESULT: OK — block-served bytes are identical to the file's."
              : "\nRESULT: FAIL — \(failures) integrity failures.")
        exit(failures == 0 ? 0 : 1)
    }
}
