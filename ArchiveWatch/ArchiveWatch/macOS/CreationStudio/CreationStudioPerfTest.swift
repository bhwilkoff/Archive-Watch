#if os(macOS)
import Foundation
import AVFoundation

// Env-gated performance MEASUREMENT (AW_CS_PERFTEST=1) for the "long movies take ~1 min to
// load" problem. For a real >1hr archive.org film it measures: is the file faststart (moov at
// front)?; how long to OPEN it (= fetch the moov index) via native AVFoundation vs our
// ResilientStreamLoader; and how long to EXTRACT a deep 8s window each way. Tells us exactly
// where the minute goes before we change the pipeline. Logs to stderr + a result file.
@MainActor
enum CreationStudioPerfTest {
    static func run(store: AppStore) async {
        let resultFile = ProjectMediaCache.directory.appendingPathComponent("perf-result.txt")
        func log(_ s: String) {
            let line = "AWCS PERF: \(s)\n"
            FileHandle.standardError.write(Data(line.utf8))
            if let h = try? FileHandle(forWritingTo: resultFile) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
            else { try? line.data(using: .utf8)?.write(to: resultFile) }
        }
        try? "".write(to: resultFile, atomically: true, encoding: .utf8)

        var t = 0
        while store.randomPlayable() == nil && t < 60 { try? await Task.sleep(for: .seconds(1)); t += 1 }

        // Measure several >1hr films to see the distribution: faststart vs not, which
        // derivative the catalog chose, open time, deep-window extract time.
        var measured = 0, attempts = 0
        var seen = Set<String>()
        while measured < 7 && attempts < 5000 {
            attempts += 1
            guard let it = store.randomPlayable(), let rt = it.runtimeSeconds, rt > 3600,
                  let url = it.videoURLParsed, !seen.contains(it.archiveID) else { continue }
            seen.insert(it.archiveID); measured += 1

            let fs = await faststart(url)
            let (ra, rl) = ResilientStreamLoader.makeAsset(for: url)
            let r1 = Date()
            let rd = (try? await ra.load(.duration).seconds) ?? -1
            let openMs = ms(r1)
            withExtendedLifetime(rl) {}

            let deep = max(0, min(rd > 60 ? rd - 60 : 1800, 1800))
            let (ra2, rl2) = ResilientStreamLoader.makeAsset(for: url)
            let e1 = Date()
            let ok = await extract(ra2, CMTimeRange(start: CMTime(seconds: deep, preferredTimescale: 600),
                                                    duration: CMTime(seconds: 8, preferredTimescale: 600)))
            let exMs = ms(e1)
            withExtendedLifetime(rl2) {}

            log("[\(measured)] open=\(openMs) extract@\(Int(deep))s=\(exMs) ok=\(ok) · \(url.lastPathComponent) · \(fs)")
        }
        log("DONE measured=\(measured)")
    }

    private static func ms(_ t: Date) -> String { "\(Int(Date().timeIntervalSince(t) * 1000))ms" }

    private static func extract(_ asset: AVURLAsset, _ range: CMTimeRange) async -> Bool {
        guard let s = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { return false }
        s.timeRange = range
        let out = ProjectMediaCache.directory.appendingPathComponent("perf-\(UUID().uuidString.prefix(6)).mp4")
        try? FileManager.default.removeItem(at: out)
        do { try await s.export(to: out, as: .mp4); try? FileManager.default.removeItem(at: out); return true }
        catch { return false }
    }

    private static func faststart(_ url: URL) async -> String {
        var req = URLRequest(url: url); req.setValue("bytes=0-131071", forHTTPHeaderField: "Range")
        req.timeoutInterval = 30
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return "range-fetch-failed" }
        let b = [UInt8](data); var off = 0; var order: [String] = []
        while off + 8 <= b.count && order.count < 8 {
            let size32 = UInt64(b[off]) << 24 | UInt64(b[off+1]) << 16 | UInt64(b[off+2]) << 8 | UInt64(b[off+3])
            let type = String(bytes: b[(off+4)..<(off+8)], encoding: .ascii) ?? "????"
            var sz = size32; var hdr = 8
            if size32 == 1, off + 16 <= b.count {
                sz = 0; for i in 0..<8 { sz = sz << 8 | UInt64(b[off+8+i]) }; hdr = 16
            }
            order.append("\(type):\(sz)")
            if type == "moov" { return "FASTSTART moov-early [\(order.joined(separator: " "))]" }
            if type == "mdat" { return "NON-faststart mdat-first, moov at END [\(order.joined(separator: " "))]" }
            if sz < UInt64(hdr) { break }
            off += Int(sz)
        }
        return "inconclusive-in-128KB [\(order.joined(separator: " "))]"
    }
}
#endif
