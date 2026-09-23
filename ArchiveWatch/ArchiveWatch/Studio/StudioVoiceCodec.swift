// Opus for guest voice — SHAREPLAY §5/§7's codec, on Apple's own encoder.
//
// MEASURED BEFORE IT WAS WRITTEN (2026-09-20), because the design turns on it:
//
//   · `kAudioFormatOpus` is not merely a format id Apple can DECODE —
//     `AVAudioConverter` builds a real ENCODER, offering 6-28 kbps at 48 kHz
//     and 24 kHz mono.
//   · A full round trip through it costs **27.3 kbps** on the wire for 20 ms
//     frames at a 24 kbps ask, with **31 ms** of algorithmic delay.
//
// Those two numbers are why this is worth building. Four guests is ~110 kbps
// into the host, which is nothing beside the film's 4 Mbps; and 31 ms each way
// leaves ~90 ms of the 150 ms conversational budget (§5.3) for the network.
// **No third-party codec** — Decision 127's zero-dependency rule holds.
//
// WHY OPUS AND NOT THE AAC THIS PROJECT ALREADY ENCODES: AAC-LC's lowest
// offered rate here is 32 kbps and it carries a priming delay that FLV has
// nowhere to express — Android already had to subtract ~47 ms of it by hand
// (§9.qq). Opus was designed for this exact job and has packet-loss
// concealment built in, which matters on an unreliable transport where a lost
// frame must not become a gap.

import AVFoundation

/// One speaker's voice, in and out. Not thread-safe by design: each stream —
/// the local microphone, and each remote participant — owns its own.
public final class StudioVoiceCodec {

    /// 48 kHz is Opus's native rate; resampling into it would re-import the
    /// problem §8.17 exists to prevent.
    public static let sampleRate: Double = 48000
    /// 20 ms. Shorter costs bitrate for no perceptual gain; longer adds
    /// latency directly to a conversation.
    public static let frameSamples = 960
    public static let bitRate = 24000

    public private(set) var problem: String?

    private let pcmFormat: AVAudioFormat
    private let opusFormat: AVAudioFormat
    private let encoder: AVAudioConverter
    private let decoder: AVAudioConverter

    public init?() {
        guard let pcm = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: Self.sampleRate,
                                      channels: 1, interleaved: false) else { return nil }
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Self.sampleRate, mFormatID: kAudioFormatOpus, mFormatFlags: 0,
            mBytesPerPacket: 0, mFramesPerPacket: UInt32(Self.frameSamples),
            mBytesPerFrame: 0, mChannelsPerFrame: 1, mBitsPerChannel: 0, mReserved: 0)
        guard let opus = AVAudioFormat(streamDescription: &asbd),
              let e = AVAudioConverter(from: pcm, to: opus),
              let d = AVAudioConverter(from: opus, to: pcm) else { return nil }
        e.bitRate = Self.bitRate
        pcmFormat = pcm; opusFormat = opus; encoder = e; decoder = d
    }

    /// One 20 ms frame of mono Float samples in, one Opus packet out.
    ///
    /// Returns nil rather than throwing: a dropped frame on a voice path is a
    /// 20 ms gap Opus itself will conceal, and is not worth unwinding a call
    /// stack for.
    public func encode(_ samples: UnsafePointer<Float>, count: Int) -> Data? {
        guard count == Self.frameSamples else {
            problem = "a voice frame must be exactly \(Self.frameSamples) samples, got \(count)"
            return nil
        }
        guard let input = AVAudioPCMBuffer(pcmFormat: pcmFormat,
                                           frameCapacity: AVAudioFrameCount(count)) else { return nil }
        input.frameLength = AVAudioFrameCount(count)
        input.floatChannelData![0].update(from: samples, count: count)

        let packet = AVAudioCompressedBuffer(format: opusFormat, packetCapacity: 1,
                                             maximumPacketSize: 4000)
        var err: NSError?
        var supplied = false
        encoder.convert(to: packet, error: &err) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return input
        }
        if let err { problem = "encode: \(err.localizedDescription)"; return nil }
        guard packet.byteLength > 0 else { return nil }
        return Data(bytes: packet.data, count: Int(packet.byteLength))
    }

    /// One Opus packet in, one 20 ms frame out. `into` must hold
    /// `frameSamples`; returns how many were written.
    public func decode(_ packet: Data, into out: UnsafeMutablePointer<Float>) -> Int {
        guard !packet.isEmpty else { return 0 }
        let buf = AVAudioCompressedBuffer(format: opusFormat, packetCapacity: 1,
                                          maximumPacketSize: max(packet.count, 4000))
        // withUnsafeBytes, never a subscript: a `Data` off a transport is
        // routinely a SLICE whose startIndex is not zero, and `packet[0]`
        // traps on one. §8.18 is the case that bought that lesson.
        packet.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            buf.data.copyMemory(from: raw.baseAddress!, byteCount: packet.count)
        }
        buf.byteLength = UInt32(packet.count)
        buf.packetCount = 1
        buf.packetDescriptions?.pointee = AudioStreamPacketDescription(
            mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(packet.count))

        guard let output = AVAudioPCMBuffer(pcmFormat: pcmFormat,
                                            frameCapacity: AVAudioFrameCount(Self.frameSamples))
        else { return 0 }
        var err: NSError?
        var supplied = false
        decoder.convert(to: output, error: &err) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return buf
        }
        if let err { problem = "decode: \(err.localizedDescription)"; return 0 }
        let n = Int(output.frameLength)
        if n > 0 { out.update(from: output.floatChannelData![0], count: n) }
        return n
    }
}
