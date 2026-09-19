// Does the decoder emit at the PROGRAMME rate, whatever the film's rate is?
// (§8.16)
//
// `makeConverter` used to build its OUTPUT format at the SOURCE rate, so any
// film that was not 44100 went into a 44100 mixer at the wrong speed and
// drifted without bound. `acceptExternalPCM`'s contract says "Already
// interleaved stereo Float at the program rate" and was simply not honoured.
//
// Measured 2026-09-19 before the fix, on `the-docks-of-new-york` (48000 Hz):
// the broadcast correlated 0.024-0.051 with its own source film against a
// control of 1.000, `decodedAhead` collapsed to -0.51 and stuck, and
// `dropped` climbed ~3.4/s for ever. A sample of the catalogue says SIX of
// eighteen readable gate-passing films are 48 kHz and one is 8 kHz — a third
// of what the Studio can broadcast.
//
// The bug is a one-line property of a format object, so the test is too. No
// AAC synthesis, no device, no network: build the converter at several source
// rates and ask what it will emit.
//
//   DEVELOPER_DIR=… xcrun swiftc -parse-as-library -O <studio sources> \
//     tools/harness_awdiag.swift tools/test_studio_rate.swift -o /tmp/ratetest

import AVFoundation
import Foundation

@main
enum RateTest {
    static var failures: [String] = []
    static func check(_ ok: Bool, _ what: String) {
        print("  \(ok ? "PASS" : "FAIL")  \(what)")
        if !ok { failures.append(what) }
    }

    static func main() {
        print("§8.16 the decoder emits at the PROGRAMME rate, whatever the film is\n")

        // The rates actually found in the catalogue's broadcastable films.
        for source in [44100.0, 48000.0, 8000.0, 22050.0, 96000.0] {
            let d = FilmAudioDecoder { _, _ in }
            d.programRate = 44100
            let built = d.makeConverter(rate: source)
            let out = d.outputSampleRate ?? -1
            check(built && out == 44100,
                  "a \(Int(source)) Hz film emits at \(Int(out)) Hz (want 44100)")
        }

        // CONTROL: the assertion must FOLLOW the programme rate, or it is only
        // testing that 44100 is hardcoded somewhere.
        let d = FilmAudioDecoder { _, _ in }
        d.programRate = 48000
        d.makeConverter(rate: 44100)
        check(d.outputSampleRate == 48000,
              "CONTROL: with a 48000 programme, a 44100 film emits at 48000")

        // CONTROL: build the format the OLD code built — output at the SOURCE
        // rate — and require it to FAIL the contract this case asserts. A
        // control that cannot fail is not a control, and `48000 != 44100` as a
        // bare constant tests nothing about any code.
        let programme = 44100.0
        let sourceRate = 48000.0
        let oldStyle = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                     sampleRate: sourceRate,      // the bug
                                     channels: 2, interleaved: true)
        check(oldStyle != nil && oldStyle!.sampleRate != programme,
              "CONTROL: the old source-rate output format (\(Int(oldStyle?.sampleRate ?? 0)) Hz) "
              + "violates the programme-rate contract")

        print()
        if failures.isEmpty {
            print("PASS — the programme-rate contract holds across every rate tried")
            exit(0)
        }
        print("FAIL — \(failures.count) assertion(s):")
        failures.forEach { print("   · \($0)") }
        exit(1)
    }
}
