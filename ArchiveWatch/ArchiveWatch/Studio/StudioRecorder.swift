import AVFoundation
import Foundation

/// Writes the program's ALREADY-ENCODED samples to an MP4 (macOS-DESIGN §D35).
///
/// Passthrough, not a second encode: the H.264 AVCC frames and AAC packets the
/// publisher sends are wrapped as `CMSampleBuffer`s with format descriptions
/// built from the stream's own `avcC` and AudioSpecificConfig. The file begins
/// at the first keyframe, so it plays from its first frame.
public actor StudioRecorder {
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput
    private let videoFormat: CMVideoFormatDescription
    private let audioFormat: CMAudioFormatDescription
    private var started = false
    private var sessionStart: CMTime?
    public private(set) var framesWritten = 0
    private var reportedFailure = false
    private func report(_ what: String) {
        guard !reportedFailure else { return }
        reportedFailure = true
        awdiag("AWRECORD %@ failed — status=%d error=%@", what, writer.status.rawValue,
               writer.error.map { "\($0)" } ?? "none")
    }
    public let url: URL

    public init(url: URL, config: RTMPStreamConfig) throws {
        self.url = url
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        var vf: CMVideoFormatDescription?
        let atoms: [String: Any] = ["avcC": config.avcC as NSData]
        let ext: [String: Any] = [
            kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String: atoms,
        ]
        guard CMVideoFormatDescriptionCreate(
                allocator: kCFAllocatorDefault, codecType: kCMVideoCodecType_H264,
                width: Int32(config.width), height: Int32(config.height),
                extensions: ext as CFDictionary, formatDescriptionOut: &vf) == noErr,
              let vf else { throw StudioPlatformError.badResponse("recorder: no video format") }
        videoFormat = vf

        var asbd = AudioStreamBasicDescription(
            mSampleRate: config.audioSampleRate, mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0, mBytesPerPacket: 0, mFramesPerPacket: 1024,
            mBytesPerFrame: 0, mChannelsPerFrame: UInt32(config.audioChannels),
            mBitsPerChannel: 0, mReserved: 0)
        var af: CMAudioFormatDescription?
        let cookie = config.audioSpecificConfig
        let status = cookie.withUnsafeBytes { raw in
            CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
                magicCookieSize: cookie.count, magicCookie: raw.baseAddress,
                extensions: nil, formatDescriptionOut: &af)
        }
        guard status == noErr, let af else { throw StudioPlatformError.badResponse("recorder: no audio format") }
        audioFormat = af

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: vf)
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: af)
        videoInput.expectsMediaDataInRealTime = true
        audioInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
            throw StudioPlatformError.badResponse("recorder: inputs refused")
        }
        writer.add(videoInput)
        writer.add(audioInput)
        guard writer.startWriting() else {
            throw StudioPlatformError.badResponse("recorder: \(writer.error.map { "\($0)" } ?? "could not start")")
        }
    }

    public func append(video frame: EncodedVideoFrame) {
        if !started {
            guard frame.isKeyframe else { return }
            writer.startSession(atSourceTime: frame.presentationTime)
            sessionStart = frame.presentationTime
            started = true
        }
        guard videoInput.isReadyForMoreMediaData else { return }
        guard let sb = Self.sample(frame.avccData, format: videoFormat,
                                   pts: frame.presentationTime, dts: frame.decodeTime,
                                   keyframe: frame.isKeyframe) else { report("video sample build"); return }
        if videoInput.append(sb) { framesWritten += 1 } else { report("video append") }
    }

    public func append(audio packet: Data, at pts: CMTime) {
        guard started, audioInput.isReadyForMoreMediaData else { return }
        // The tracks count from different origins; audio from before the
        // file's first keyframe has nowhere to go.
        guard let start = sessionStart, CMTimeCompare(pts, start) >= 0 else { return }
        guard let sb = Self.audioSample(packet, format: audioFormat, pts: pts) else {
            report("audio sample build"); return
        }
        if !audioInput.append(sb) { report("audio append") }
    }

    /// Finishes the file. Returns it, or nil if nothing was ever written.
    public func finish() async -> URL? {
        videoInput.markAsFinished()
        audioInput.markAsFinished()
        await writer.finishWriting()
        awdiag("AWRECORD finish status=%d frames=%d error=%@", writer.status.rawValue,
               framesWritten, writer.error.map { "\($0)" } ?? "none")
        return (writer.status == .completed && framesWritten > 0) ? url : nil
    }

    /// AAC is variable-size compressed audio: its sample buffer needs a
    /// PACKET DESCRIPTION, or the writer refuses it (-16364, measured
    /// 2026-09-23 after 16 video frames had been accepted).
    private static func audioSample(_ data: Data, format: CMAudioFormatDescription,
                                    pts: CMTime) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: data.count,
                blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                dataLength: data.count, flags: 0, blockBufferOut: &block) == noErr,
              let block else { return nil }
        let copied = data.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: data.count)
        }
        guard copied == noErr else { return nil }
        var packet = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0,
                                                  mDataByteSize: UInt32(data.count))
        var sb: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                sampleCount: 1, presentationTimeStamp: pts, packetDescriptions: &packet,
                sampleBufferOut: &sb) == noErr else { return nil }
        return sb
    }

    private static func sample(_ data: Data, format: CMFormatDescription,
                               pts: CMTime, dts: CMTime, keyframe: Bool) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: data.count,
                blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                dataLength: data.count, flags: 0, blockBufferOut: &block) == noErr,
              let block else { return nil }
        let copied = data.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: data.count)
        }
        guard copied == noErr else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: pts,
                                        decodeTimeStamp: dts)
        var size = data.count
        var sb: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sb) == noErr,
              let sb else { return nil }
        if !keyframe, let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true),
           CFArrayGetCount(arr) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(arr, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sb
    }
}
