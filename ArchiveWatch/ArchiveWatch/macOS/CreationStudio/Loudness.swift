#if os(macOS)
import Foundation
import AVFoundation

// Per-clip loudness for the supercut (#9 polish). Word-clips assembled from different films vary
// wildly in level — one word booms, the next is a whisper. Measuring each clip's RMS lets the
// composer set its mix volume to a shared target, so the spoken sentence sounds even. On-device,
// native AVAssetReader (no third-party), measured on the already-cached local word window.
enum Loudness {
    /// Mean RMS (0…1, full-scale) of the audio in a local file, or nil if it has none.
    static func rms(url: URL) async -> Float? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        var sumSq = 0.0
        var count = 0
        while let sb = output.copyNextSampleBuffer() {
            if let bb = CMSampleBufferGetDataBuffer(sb) {
                var length = 0
                var ptr: UnsafeMutablePointer<Int8>?
                if CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil,
                                               totalLengthOut: &length, dataPointerOut: &ptr) == kCMBlockBufferNoErr,
                   let ptr {
                    let n = length / MemoryLayout<Int16>.size
                    ptr.withMemoryRebound(to: Int16.self, capacity: n) { p in
                        for i in 0..<n { let s = Double(p[i]) / 32768.0; sumSq += s * s }
                    }
                    count += n
                }
            }
            CMSampleBufferInvalidate(sb)
        }
        guard count > 0 else { return nil }
        return Float((sumSq / Double(count)).squareRoot())
    }

    /// A mix gain that brings `rms` toward `target`, clamped so quiet noise isn't over-amplified.
    static func gain(forRMS rms: Float, target: Float = 0.12) -> Double {
        guard rms > 0.005 else { return 1 }                  // near-silent — leave it
        return Double(min(3.0, max(0.35, target / rms)))
    }
}
#endif
