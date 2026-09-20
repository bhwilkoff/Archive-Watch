// Does Apple's own Opus carry a voice at conversational cost? (§8.19)
//
// SHAREPLAY §5 and §7 both hang on this. If Apple ships a usable Opus encoder
// then guest voice costs no third-party dependency (Decision 127) and the
// only open question is the transport; if it does not, the codec becomes
// AAC-LC at a higher rate with a priming delay FLV cannot express — which
// Android already had to subtract by hand (§9.qq).
//
// So this asserts the three things the DESIGN depends on, not merely that the
// API returns non-nil: the wire cost, the delay, and that what comes back is
// the signal that went in. Each has a control.
//
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -O ArchiveWatch/ArchiveWatch/Studio/StudioVoiceCodec.swift \
//     tools/test_studio_voicecodec.swift -o /tmp/vctest && /tmp/vctest

import Foundation
import AVFoundation

@main
enum VoiceCodecTest {

    static var failures: [String] = []

    static func check(_ ok: Bool, _ what: String) {
        print("  \(ok ? "PASS" : "FAIL")  \(what)")
        if !ok { failures.append(what) }
    }

    /// A voice-shaped signal: a fundamental around speech pitch with two
    /// harmonics. A pure sine is the one thing every codec handles well and
    /// so proves the least.
    static func voice(_ n: Int, rate: Double) -> [Float] {
        (0..<n).map { i in
            let t = Double(i) / rate
            return Float(0.4 * sin(2.0 * Double.pi * 220 * t)
                       + 0.2 * sin(2.0 * Double.pi * 440 * t)
                       + 0.1 * sin(2.0 * Double.pi * 880 * t))
        }
    }

    static func energy(_ x: ArraySlice<Float>) -> Double {
        x.reduce(0.0) { $0 + Double($1 * $1) }
    }

    static func main() {
        print("§8.19 guest voice on Apple's Opus — cost, delay, and does it survive?")
        print()

        guard let codec = StudioVoiceCodec() else {
            print("  FAIL  Apple would not build an Opus encoder AND decoder")
            print("\nFAIL — the codec this design assumes does not exist here")
            exit(1)
        }
        check(true, "AVAudioConverter builds both an Opus encoder and a decoder")

        let frame = StudioVoiceCodec.frameSamples
        let rate = StudioVoiceCodec.sampleRate
        let src = voice(frame * 50, rate: rate)          // one second

        var bytes = 0, encoded = 0
        var back = [Float]()
        var scratch = [Float](repeating: 0, count: frame)
        for f in 0..<50 {
            let packet: Data? = src.withUnsafeBufferPointer {
                codec.encode($0.baseAddress! + f * frame, count: frame)
            }
            guard let packet else { continue }
            bytes += packet.count; encoded += 1
            let n = scratch.withUnsafeMutableBufferPointer {
                codec.decode(packet, into: $0.baseAddress!)
            }
            back.append(contentsOf: scratch[0..<n])
        }

        check(encoded >= 45, "encoded \(encoded) of 50 frames")

        // 1. THE WIRE COST. Four guests must be negligible beside a 4 Mbps film.
        let kbps = Double(bytes) * 8 / (Double(encoded) * 0.020) / 1000
        print(String(format: "       %.1f kbps per speaker (%d bytes over %d frames)",
                     kbps, bytes, encoded))
        check(kbps < 40, String(format: "a speaker costs %.1f kbps — four guests is %.0f kbps",
                                kbps, kbps * 4))
        // CONTROL: the alternative this rejected. AAC-LC's lowest offered rate
        // here is 32 kbps for ONE channel, before its priming delay.
        check(kbps < 32, "CONTROL: and it beats AAC-LC's lowest offered rate (32 kbps)")

        // 2. THE SIGNAL SURVIVES. Opus is PERCEPTUAL, so waveform SNR is the
        //    wrong instrument — it deliberately does not preserve a waveform.
        //    What must hold is that the energy comes back.
        let inE = energy(src[2000..<40000])
        let outE = energy(back[2000..<min(40000, back.count)])
        let ratio = outE / max(inE, 1e-12)
        print(String(format: "       energy out/in = %.2f", ratio))
        check(ratio > 0.5 && ratio < 2.0,
              String(format: "the decoded voice carries the same energy (%.2f)", ratio))
        // CONTROL: silence in must NOT come back as energy, or the check above
        // would pass on a codec that invents sound.
        //
        // ON A FRESH CODEC, and that is the whole point of this comment. The
        // first version reused the instance that had just carried a second of
        // voice, and measured energy 27.8 — which is not the codec inventing
        // sound, it is OPUS BEING STATEFUL: the decoder's overlap-add tail
        // from the preceding frames, decaying through the silent one. The
        // control was measuring codec state and calling it a defect. A voice
        // codec that produced nothing after a voice would be the broken one.
        let fresh = StudioVoiceCodec()
        var qe = Double.nan
        if let fresh {
            var quiet = [Float](repeating: 0, count: frame)
            var qout = [Float](repeating: 0, count: frame)
            var qn = 0
            // Several frames, because the FIRST packet out of any codec is
            // its own warm-up and proves nothing either way.
            for _ in 0..<5 {
                if let qp = quiet.withUnsafeBufferPointer({
                    fresh.encode($0.baseAddress!, count: frame) }) {
                    qn = qout.withUnsafeMutableBufferPointer { fresh.decode(qp, into: $0.baseAddress!) }
                }
            }
            qe = energy(qout[0..<max(qn, 1)])
        }
        check(qe < 1e-3, String(format: "CONTROL: silence into a FRESH codec decodes to "
                                + "silence (energy %.2e)", qe))

        // 3. THE DELAY, which is spent straight out of §5.3's 150 ms budget.
        var bestLag = 0, bestScore = -1.0
        for lag in 0...1500 where lag + 6000 < back.count {
            var dot = 0.0
            for i in stride(from: 2000, to: 6000, by: 4) {
                dot += Double(src[i]) * Double(back[i + lag])
            }
            if dot > bestScore { bestScore = dot; bestLag = lag }
        }
        let ms = Double(bestLag) / rate * 1000
        print(String(format: "       algorithmic delay %.1f ms", ms))
        check(ms < 60, String(format: "the codec costs %.0f ms each way, leaving ~%.0f ms "
                              + "of the 150 ms budget for the network", ms, 150 - 2 * ms))

        // 4. A SHORT FRAME IS REFUSED rather than silently mis-encoded.
        var stub = [Float](repeating: 0, count: 100)
        let bad: Data? = stub.withUnsafeBufferPointer { codec.encode($0.baseAddress!, count: 100) }
        check(bad == nil, "a frame that is not exactly 20 ms is refused")

        print()
        if failures.isEmpty {
            print("PASS — Apple's Opus carries a voice; only the TRANSPORT is unknown")
            exit(0)
        }
        print("FAIL — \(failures.count) assertion(s):")
        failures.forEach { print("   · \($0)") }
        exit(1)
    }
}
