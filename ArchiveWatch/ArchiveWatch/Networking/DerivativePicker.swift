import Foundation

// MARK: - DerivativePicker
//
// Pure, testable logic for choosing the best playable video file from
// an Archive item's files[] array. This is the trickiest part of the
// Archive layer — items routinely ship 5–15 derivatives, and picking
// the wrong one gets you a 2GB original when a 400MB h.264 would play
// perfectly, or vice versa.
//
// Ranking:
//   1. h.264 MP4 derivative                     (preferred; native AVPlayer)
//   2. Any other MP4 derivative
//   3. 512Kb MPEG4 derivative                   (smaller fallback)
//   4. Any MPEG4 derivative
//   5. WebM / Matroska / Ogg derivative
//   6. MP4 or H.264 original                    (accept heavier bytes)
//   7. Any video original                       (last resort)
//
// Within each tier, prefer files whose `original` field references a
// known-good original — that avoids picking a broken derivative — then
// prefer the largest file (higher bitrate = better quality).

enum DerivativePicker {

    struct Pick: Sendable {
        let file: ArchiveFile
        let tier: Int
        let reason: String
    }

    /// Select the preferred playable file from an Archive files list.
    static func pick(from files: [ArchiveFile]) -> Pick? {
        let videoFiles = files.filter { $0.isVideo }
        guard !videoFiles.isEmpty else { return nil }

        let tiers: [(Int, String, (ArchiveFile) -> Bool)] = [
            (1, "h.264 MP4 derivative",   { f in f.isDerivative && f.isH264MP4 }),
            (2, "MP4 derivative",         { f in f.isDerivative && f.isMP4 }),
            (3, "512Kb MPEG4 derivative", { f in f.isDerivative && f.is512KbMPEG4 }),
            (4, "MPEG4 derivative",       { f in f.isDerivative && f.isMPEG4 }),
            (5, "WebM/Matroska/Ogg derivative", { f in f.isDerivative && f.isAltStreamable }),
            (6, "MP4/H.264 original",     { f in f.isOriginal && (f.isH264MP4 || f.isMP4) }),
            (7, "Any video original",     { f in f.isOriginal })
        ]

        for (tier, reason, predicate) in tiers {
            let matches = videoFiles.filter(predicate)
            if let best = matches.max(by: { ($0.sizeBytes ?? 0) < ($1.sizeBytes ?? 0) }) {
                return Pick(file: best, tier: tier, reason: reason)
            }
        }

        // Shouldn't hit this given the filter above, but fall back to largest.
        let largest = videoFiles.max(by: { ($0.sizeBytes ?? 0) < ($1.sizeBytes ?? 0) })
        return largest.map { Pick(file: $0, tier: 99, reason: "Any video") }
    }
}

// MARK: - Format predicates (kept close to the picker for clarity)

private extension ArchiveFile {
    var isMP4: Bool {
        guard let f = format?.lowercased() else { return false }
        return f.contains("mp4")
    }

    var isH264MP4: Bool {
        guard let f = format?.lowercased() else { return false }
        return f.contains("h.264") || f.contains("h264")
    }

    var isMPEG4: Bool {
        guard let f = format?.lowercased() else { return false }
        return f.contains("mpeg4") || f.contains("mpeg-4")
    }

    var is512KbMPEG4: Bool {
        guard let f = format?.lowercased() else { return false }
        return f.contains("512kb") && f.contains("mpeg4")
    }

    var isAltStreamable: Bool {
        guard let f = format?.lowercased() else { return false }
        return f.contains("webm") || f.contains("matroska") || f.contains("ogg")
    }
}
