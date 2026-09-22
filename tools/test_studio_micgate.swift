// THE MICROPHONE GATE — WATCH-TOGETHER §8.38, roadmap #4.
//
// A pure value type, so the RULE can be exercised with no ring, no encoder and
// no clock — the shape `CameraStallRecovery` already uses and §8.23 already
// tests. A rule that can only be reached by starting a whole engine is a rule
// that gets argued about rather than measured.
//
// What is under test is not "does it multiply by a number". It is the three
// things that separate a gate that helps from a gate that makes a show worse:
// it must not CHATTER at the boundary, it must not CLIP the first syllable,
// and it must actually REACH zero rather than settling on a quiet copy of the
// room.
//
//   DEVELOPER_DIR=… xcrun swiftc -parse-as-library -O \
//     ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioAudio.swift \
//     tools/harness_awdiag.swift tools/test_studio_micgate.swift -o /tmp/awgate

import Foundation

@main
struct GateTest {
    nonisolated(unsafe) static var fail = false

    static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "  PASS  " : "  FAIL  ") + name + (detail.isEmpty ? "" : " — \(detail)"))
        if !ok { fail = true }
    }

    static func main() {
        print("Watch Together §8.38 — the microphone gate")
        print()

        // 1. DISABLED IS A PASS-THROUGH, exactly. A gate switched off must not
        //    touch the audio at all, at any level.
        var off = MicGate()
        var untouched = true
        for rms in stride(from: Float(0), through: 0.5, by: 0.01) {
            if off.tick(rms: rms) != 1 { untouched = false }
        }
        check("disabled passes everything through", untouched && off.isOpen)

        // 2. IT OPENS ON SPEECH and reaches full gain quickly. A gate that
        //    takes half a second to open eats the first word of every sentence.
        var g = MicGate(); g.enabled = true
        var blocksToOpen = 0
        var gain: Float = 0
        for i in 1...20 {
            gain = g.tick(rms: 0.08)               // conversational speech
            if gain > 0.95 { blocksToOpen = i; break }
        }
        check("opens on speech within 100 ms",
              blocksToOpen > 0 && blocksToOpen <= 5,
              "\(blocksToOpen) blocks (~\(blocksToOpen * 23) ms) to 95%")

        // 3. IT CLOSES ON ROOM TONE, and reaches ACTUAL zero. An exponential
        //    approach never arrives; a gate settling at 0.001 is still sending
        //    the room, quietly, forever.
        var closed = false
        for _ in 1...400 where !closed {
            if g.tick(rms: 0.004) == 0 { closed = true }   // film bleed
        }
        check("closes to exactly zero on room tone", closed && !g.isOpen,
              "gain \(g.gain)")

        // 4. IT DOES NOT CHATTER at the boundary. THIS IS THE ONE THAT
        //    MATTERS: a level sitting exactly on the threshold, without
        //    hysteresis, flips the gate on every block — which a listener
        //    hears as a stutter, and is how a gate becomes worse than none.
        var h = MicGate(); h.enabled = true
        _ = h.tick(rms: 0.08)                      // open it first
        for _ in 1...10 { _ = h.tick(rms: 0.08) }
        var flips = 0
        var previous = h.isOpen
        for _ in 1...200 {
            // Dither either side of the OPEN threshold by ±5%.
            let jitter = Float.random(in: -0.001...0.001)
            _ = h.tick(rms: 0.02 + jitter)
            if h.isOpen != previous { flips += 1; previous = h.isOpen }
        }
        check("does not chatter on a level sitting at the threshold",
              flips == 0, "\(flips) flips in 200 blocks")

        // 5. CONTROL — the chatter check can FAIL. Without hysteresis the same
        //    signal flips constantly, and asserting flips == 0 against a gate
        //    that cannot chatter would prove nothing (Decision 120's rule).
        var naive = true
        var naiveOpen = true
        var naiveFlips = 0
        for _ in 1...200 {
            let jitter = Float.random(in: -0.001...0.001)
            let open = (0.02 + jitter) > 0.02      // no hysteresis
            if open != naiveOpen { naiveFlips += 1; naiveOpen = open }
        }
        naive = naiveFlips > 10
        check("CONTROL — the same signal DOES chatter without hysteresis",
              naive, "\(naiveFlips) flips")

        // 6. A PAUSE BETWEEN WORDS does not close it. Release is ~400 ms on
        //    purpose; a gate that shuts in a comma chops sentences in half.
        var p = MicGate(); p.enabled = true
        for _ in 1...10 { _ = p.tick(rms: 0.08) }
        for _ in 1...6 { _ = p.tick(rms: 0.001) }   // ~140 ms of silence
        check("a short pause does not silence the host", p.gain > 0.5,
              "gain \(String(format: "%.2f", p.gain)) after ~140 ms")

        print()
        print(fail ? "FAILED" : "PASS: §8.38 — the gate opens on speech, closes on the room, and never chatters")
        exit(fail ? 1 : 0)
    }
}
