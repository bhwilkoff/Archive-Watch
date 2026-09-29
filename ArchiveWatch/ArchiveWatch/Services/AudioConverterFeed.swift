import AVFoundation

extension AVAudioConverter {
    /// Converts exactly ONE input buffer into `output`.
    ///
    /// `convert(to:error:withInputFrom:)` calls its input block synchronously,
    /// on the calling thread, before it returns — so the one-shot state below
    /// never crosses a thread. The 26 SDK nonetheless types the block as
    /// `@Sendable`, which made a captured `var` and a non-Sendable buffer
    /// warn in three copies of this pattern (captions, auto captions, the
    /// Studio's film audio); the holder is where that fact is stated once.
    func convertOnce(_ input: AVAudioBuffer, into output: AVAudioBuffer)
        -> (status: AVAudioConverterOutputStatus, error: NSError?) {
        final class OneShot: @unchecked Sendable {
            var buffer: AVAudioBuffer?
            init(_ b: AVAudioBuffer) { buffer = b }
        }
        let feed = OneShot(input)
        var err: NSError?
        let status = convert(to: output, error: &err) { _, outStatus in
            guard let b = feed.buffer else { outStatus.pointee = .noDataNow; return nil }
            feed.buffer = nil
            outStatus.pointee = .haveData
            return b
        }
        return (status, err)
    }
}
