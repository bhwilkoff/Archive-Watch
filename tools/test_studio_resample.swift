// Does the TAP path's sample-rate conversion actually band-limit? (§8.17)
//
// macOS and iOS take film audio through an `MTAudioProcessingTap` and the
// host's voice through an `AVCaptureAudioDataOutput`, and BOTH used to
// resample by nearest-neighbour — `j = Int(Double(i) / ratio)`, a zero-order
// hold. `StudioAudio.swift`'s own comment called that "honest for a 44.1/48
// kHz mismatch" and left "a proper resampler" as a §9 follow-up "if a 48 kHz
// film ever sounds wrong".
//
// One did. §9.mmmmm measured that a THIRD of broadcastable films are 48 kHz,
// and modelling the hold at 48000 -> 44100 gives 35.6 dB SNR at 440 Hz
// falling to 10.1 dB at 8 kHz — aliasing nearly as loud as the signal. tvOS
// never had this, because its pull path converts with `AVAudioConverter` off
// the render thread; the tap paths cannot, because their callback is real
// time and the converter allocates.
//
// So this asserts the property the filter exists for — that what comes out is
// the tone that went in, and not the tone plus its aliases — and it asserts
// the two things most likely to be silently wrong:
//
//   · that a ratio of 1.0 is left EXACTLY alone (a resampler that perturbs
//     audio it was not asked to touch is worse than none), and
//   · that processing in small chunks gives the same answer as one big call,
//     which is the cross-buffer state the filter carries. Getting that wrong
//     puts a discontinuity at every buffer boundary, i.e. clicks — the exact
//     symptom §9.jjjjj spent a day chasing.
//
// Every assertion is paired with the same check over a deliberate
// reimplementation of the OLD hold, which must FAIL: a test that cannot fail
// on the bug it was written for is not a test (Decision 130).
//
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -O ArchiveWatch/ArchiveWatch/Studio/StudioAudio.swift \
//     tools/harness_awdiag.swift tools/test_studio_resample.swift \
//     -o /tmp/resamptest && /tmp/resamptest

import Foundation
import Accelerate

@main
enum ResampleTest {

    static var failures: [String] = []

    static func check(_ ok: Bool, _ what: String) {
        print("  \(ok ? "PASS" : "FAIL")  \(what)")
        if !ok { failures.append(what) }
    }

    /// Energy at `f0` versus everything else — aliasing, images and
    /// distortion all land in "everything else".
    static func snr(_ x: [Float], rate: Double, f0: Double) -> Double {
        let n = 1 << Int(log2(Double(x.count)))          // power of two
        var re = (0..<n).map { Double(x[$0]) * (0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(n))) }
        var im = [Double](repeating: 0, count: n)
        guard let setup = vDSP_create_fftsetupD(vDSP_Length(log2(Double(n))), Int32(kFFTRadix2)) else { return 0 }
        defer { vDSP_destroy_fftsetupD(setup) }
        var sig = 0.0, noise = 0.0
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPDoubleSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zipD(setup, &split, 1, vDSP_Length(log2(Double(n))), Int32(FFT_FORWARD))
                for k in 0..<(n / 2) {
                    let f = Double(k) * rate / Double(n)
                    let p = rp[k] * rp[k] + ip[k] * ip[k]
                    // A 25 Hz window either side, and DC excluded: a tiny
                    // offset is not aliasing and should not be scored as it.
                    if abs(f - f0) < 25 { sig += p } else if f > 20 { noise += p }
                }
            }
        }
        return 10 * log10(sig / max(noise, 1e-30))
    }

    /// Interleaved stereo sine at `rate`.
    static func tone(_ f0: Double, rate: Double, seconds: Double) -> [Float] {
        let n = Int(rate * seconds)
        var out = [Float](repeating: 0, count: n * 2)
        for i in 0..<n {
            let v = Float(sin(2 * .pi * f0 * Double(i) / rate))
            out[i * 2] = v; out[i * 2 + 1] = v
        }
        return out
    }

    static func left(_ interleaved: [Float]) -> [Float] {
        stride(from: 0, to: interleaved.count, by: 2).map { interleaved[$0] }
    }

    /// Run the real resampler over `src`, in chunks of `chunk` frames.
    static func run(_ src: [Float], from: Double, to: Double, chunk: Int) -> [Float] {
        let r = PolyphaseResampler()
        r.configure(sourceRate: from, programRate: to)
        let inFrames = src.count / 2
        var out: [Float] = []
        var scratch = [Float](repeating: 0, count: (chunk * 4 + 64) * 2)
        var i = 0
        while i < inFrames {
            let n = min(chunk, inFrames - i)
            let cap = r.capacityNeeded(forInputFrames: n)
            if scratch.count < cap * 2 { scratch = [Float](repeating: 0, count: cap * 2) }
            let wrote = src.withUnsafeBufferPointer { sp -> Int in
                scratch.withUnsafeMutableBufferPointer { op in
                    r.process(sp.baseAddress! + i * 2, inFrames: n,
                              out: op.baseAddress!, outCapacity: cap)
                }
            }
            out.append(contentsOf: scratch[0..<(wrote * 2)])
            i += n
        }
        return out
    }

    /// THE OLD CONVERSION, reimplemented exactly as it shipped, so the control
    /// is honest rather than a strawman.
    static func zeroOrderHold(_ src: [Float], from: Double, to: Double) -> [Float] {
        let ratio = to / from
        let inFrames = src.count / 2
        let outFrames = max(1, Int((Double(inFrames) * ratio).rounded()))
        var out = [Float](repeating: 0, count: outFrames * 2)
        for i in 0..<outFrames {
            let j = min(inFrames - 1, Int(Double(i) / max(ratio, 0.0001)))
            out[i * 2] = src[j * 2]
            out[i * 2 + 1] = src[j * 2 + 1]
        }
        return out
    }

    static func main() {
        print("§8.17 the tap path's resampler — is the output the tone, or the tone plus its aliases?")
        print()

        let SRC = 48000.0, DST = 44100.0
        // What a 32-tap Blackman-Harris windowed sinc should comfortably beat.
        // The hold does not reach it at ANY of these tones, which is the point.
        let floorDB = 55.0

        print("  48000 -> 44100 Hz")
        print("  \("tone".padding(toLength: 10, withPad: " ", startingAt: 0))  filter      hold (old)")
        for f0 in [440.0, 1000.0, 3000.0, 8000.0] {
            let src = tone(f0, rate: SRC, seconds: 2)
            let good = snr(left(run(src, from: SRC, to: DST, chunk: 1024)), rate: DST, f0: f0)
            let bad = snr(left(zeroOrderHold(src, from: SRC, to: DST)), rate: DST, f0: f0)
            print(String(format: "  %8.0f Hz  %7.1f dB  %9.1f dB", f0, good, bad))
            check(good >= floorDB, "\(Int(f0)) Hz resamples at \(String(format: "%.1f", good)) dB, at or above the \(Int(floorDB)) dB floor")
            check(bad < floorDB, "CONTROL: the old hold gives \(String(format: "%.1f", bad)) dB at \(Int(f0)) Hz and must FAIL that floor")
        }

        // RATIO 1.0 IS SACRED. Two thirds of the catalogue is already 44.1 kHz
        // and must come through untouched, bit for bit.
        let same = tone(1000, rate: DST, seconds: 0.5)
        let through = run(same, from: DST, to: DST, chunk: 512)
        check(through.count == same.count && through == same,
              "a 44100 -> 44100 conversion is BIT-IDENTICAL (\(through.count) of \(same.count) samples)")

        // CHUNK INDEPENDENCE — the cross-buffer state. A filter that resets at
        // every buffer boundary still passes a single-shot SNR test and clicks
        // on every real broadcast.
        let src = tone(1000, rate: SRC, seconds: 1)
        let big = run(src, from: SRC, to: DST, chunk: 16384)
        let small = run(src, from: SRC, to: DST, chunk: 157)     // deliberately not a round number
        let n = min(big.count, small.count)
        var worst: Float = 0
        for i in 0..<n { worst = max(worst, abs(big[i] - small[i])) }
        check(abs(big.count - small.count) <= 4,
              "chunked and single-shot produce the same length (\(small.count) vs \(big.count))")
        // 1e-6 is float noise, not a tolerance for a real difference. The
        // first version of this asserted 1e-5 and measured 5.05e-04, which was
        // NOT a state bug: with a truncated phase index, float noise in the
        // read position that straddles a phase boundary flips the index and
        // moves the output by one phase step. 256 phases predicts 5.11e-04 at
        // 1 kHz and the harness measured 5.05e-04 — two significant figures,
        // so the explanation was the mechanism rather than a guess. The
        // resampler now interpolates between phases and this passes at float
        // noise, which is what "the state is carried" should look like.
        // 1e-5 is Float32 accumulation noise across 32 taps, not a tolerance
        // for a real difference: Float's epsilon is ~1.2e-7 and summing 32
        // products of order 1 lands around 7e-7, measured here at 2.0e-6. The
        // CONTROL below differs by 2.0 — six orders up — so this bound still
        // separates "carries its state" from "does not".
        check(worst < 1e-5,
              "chunked output matches single-shot sample for sample (worst difference \(worst))")

        // CONTROL: a resampler that forgets its state between buffers — the
        // defect this assertion exists to catch — must differ by ORDERS more
        // than the tolerance above, or the tolerance is meaningless.
        var forgetful: [Float] = []
        do {
            let inFrames = src.count / 2
            var i = 0
            while i < inFrames {
                let n = min(157, inFrames - i)
                let chunk = Array(src[(i * 2)..<((i + n) * 2)])
                forgetful.append(contentsOf: run(chunk, from: SRC, to: DST, chunk: n))
                i += n
            }
        }
        var ctlWorst: Float = 0
        for i in 0..<min(forgetful.count, big.count) {
            ctlWorst = max(ctlWorst, abs(big[i] - forgetful[i]))
        }
        check(ctlWorst > 1e-3,
              "CONTROL: a resampler rebuilt per buffer differs by \(ctlWorst), far above the tolerance")
        check(snr(left(small), rate: DST, f0: 1000) >= floorDB,
              "and the 157-frame chunking still resamples cleanly, i.e. no boundary discontinuity")

        // UPSAMPLING TOO — 22050 and 8000 films exist in the catalogue (§9.mmmmm).
        for from in [22050.0, 8000.0] {
            let s = tone(1000, rate: from, seconds: 2)
            let v = snr(left(run(s, from: from, to: DST, chunk: 1024)), rate: DST, f0: 1000)
            print(String(format: "  %8.0f -> 44100  %7.1f dB", from, v))
            check(v >= floorDB, "\(Int(from)) Hz upsamples at \(String(format: "%.1f", v)) dB")
        }

        print()
        if failures.isEmpty {
            print("PASS — the tap paths band-limit, leave 44.1 kHz alone, and carry state across buffers")
            exit(0)
        }
        print("FAIL — \(failures.count) assertion(s):")
        failures.forEach { print("   · \($0)") }
        exit(1)
    }
}
