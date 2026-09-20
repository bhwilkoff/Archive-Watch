// Does the guest mixer survive a real network? (§8.20)
//
// SHAREPLAY §5.4: the host mixes every guest into the programme and sends each
// one a MIX-MINUS. This is the half of that which can be proved without a
// second person, a device, or a decision about the transport — packets arrive
// with a participant and a sequence, and the room behaves identically whether
// Apple's messenger or our own UDP delivered them.
//
// It asserts the three things a voice mixer gets wrong, each with a control
// that must come out the other way:
//
//  · ORDERING. An unreliable transport reorders, and a buffer that plays on
//    arrival scrambles a voice exactly as §9.jjjjj's LIFO ring scrambled a
//    film — real audio, right level, no discontinuities, unintelligible.
//  · GAPS. A lost packet must CONCEAL and still advance, or one loss
//    desynchronises that speaker for the rest of the call.
//  · CLIPPING. Four voices sum past 1.0, and a consumer converting to Int16
//    would wrap to the opposite sign.
//
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -O ArchiveWatch/ArchiveWatch/Studio/StudioVoiceCodec.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioVoiceRoom.swift \
//     tools/test_studio_voiceroom.swift -o /tmp/vrtest && /tmp/vrtest

import Foundation

@main
enum VoiceRoomTest {

    static var failures: [String] = []
    static func check(_ ok: Bool, _ what: String) {
        print("  \(ok ? "PASS" : "FAIL")  \(what)")
        if !ok { failures.append(what) }
    }

    static let N = StudioVoiceCodec.frameSamples

    /// A steady tone at `hz`, encoded frame by frame through one codec — so
    /// each speaker's packets carry that speaker's pitch and can be told apart
    /// in the mix.
    static func speaker(hz: Double, frames: Int, amplitude: Float = 0.3) -> [Data] {
        guard let codec = StudioVoiceCodec() else { return [] }
        var out: [Data] = []
        var phase = 0.0
        let step = 2.0 * Double.pi * hz / StudioVoiceCodec.sampleRate
        var buf = [Float](repeating: 0, count: N)
        for _ in 0..<frames {
            for i in 0..<N { buf[i] = amplitude * Float(sin(phase)); phase += step }
            if let p = buf.withUnsafeBufferPointer({ codec.encode($0.baseAddress!, count: N) }) {
                out.append(p)
            }
        }
        return out
    }

    static func energy(_ x: [Float], _ n: Int) -> Double {
        var e = 0.0
        for i in 0..<n { e += Double(x[i] * x[i]) }
        return e
    }

    /// Pull `count` frames and return the total energy heard.
    static func drain(_ room: StudioVoiceRoom, frames: Int,
                      excluding: VoiceParticipant? = nil) -> Double {
        var out = [Float](repeating: 0, count: N)
        var total = 0.0
        for _ in 0..<frames {
            let n = out.withUnsafeMutableBufferPointer { p -> Int in
                excluding == nil ? room.mix(into: p.baseAddress!, capacity: N)
                                 : room.mixMinus(excluding!, into: p.baseAddress!, capacity: N)
            }
            total += energy(out, n)
        }
        return total
    }

    static func main() {
        print("§8.20 the guest mixer — ordering, gaps, mix-minus, clipping")
        print()

        let alice = VoiceParticipant("alice")
        let bob = VoiceParticipant("bob")
        let a = speaker(hz: 220, frames: 20)
        let b = speaker(hz: 660, frames: 20)
        check(a.count >= 18 && b.count >= 18, "two speakers encoded (\(a.count), \(b.count) frames)")

        // 1. BOTH VOICES REACH THE MIX.
        do {
            let room = StudioVoiceRoom()
            for (i, p) in a.enumerated() { room.receive(p, from: alice, sequence: UInt32(i)) }
            for (i, p) in b.enumerated() { room.receive(p, from: bob, sequence: UInt32(i)) }
            check(room.participants.count == 2, "the room knows both speakers")
            let both = drain(room, frames: 15)
            check(both > 0.1, String(format: "two speakers mixed carry energy (%.2f)", both))
        }

        // 2. MIX-MINUS. What Alice is sent must NOT contain Alice.
        do {
            let room = StudioVoiceRoom()
            for (i, p) in a.enumerated() { room.receive(p, from: alice, sequence: UInt32(i)) }
            let selfHeard = drain(room, frames: 12, excluding: alice)
            check(selfHeard < 1e-6,
                  String(format: "Alice alone hears NOTHING of herself (%.2e)", selfHeard))
            // CONTROL: the same room, not excluding her, must be loud — or the
            // check above passes on a mixer that outputs nothing at all.
            let room2 = StudioVoiceRoom()
            for (i, p) in a.enumerated() { room2.receive(p, from: alice, sequence: UInt32(i)) }
            let heard = drain(room2, frames: 12)
            check(heard > 0.1, String(format: "CONTROL: without the minus she IS heard (%.2f)", heard))
        }

        // 3. ORDERING. Deliver shuffled; the room must play in sequence.
        do {
            let ordered = StudioVoiceRoom()
            for (i, p) in a.enumerated() { ordered.receive(p, from: alice, sequence: UInt32(i)) }
            var inOrder = [Float](repeating: 0, count: N)
            _ = inOrder.withUnsafeMutableBufferPointer { ordered.mix(into: $0.baseAddress!, capacity: N) }

            let shuffled = StudioVoiceRoom()
            for i in [3, 1, 4, 0, 2] { shuffled.receive(a[i], from: alice, sequence: UInt32(i)) }
            for i in 5..<a.count { shuffled.receive(a[i], from: alice, sequence: UInt32(i)) }
            var reordered = [Float](repeating: 0, count: N)
            _ = reordered.withUnsafeMutableBufferPointer { shuffled.mix(into: $0.baseAddress!, capacity: N) }

            var worst: Float = 0
            for i in 0..<N { worst = max(worst, abs(inOrder[i] - reordered[i])) }
            check(worst < 1e-6,
                  "packets delivered 3,1,4,0,2 play as 0,1,2,3,4 (worst difference \(worst))")
            check(shuffled.framesDroppedLate == 0,
                  "and nothing was thrown away as late (\(shuffled.framesDroppedLate))")
        }

        // 4. A GAP IS CONCEALED, AND THE SEQUENCE STILL ADVANCES.
        //
        // SIX FRAMES, NOT TWENTY, and the difference is the finding. The first
        // version pushed all twenty in before pulling any, which overran
        // `maxDepth` — so the runaway guard binned packet 2 along with
        // everything below 12, playback began at 12, and there was no gap left
        // to conceal. The room was right and the test was wrong. It also
        // exposed that the guard was evicting SILENTLY; it now counts, and the
        // assertion below checks that nothing was binned, so this case can
        // never again pass or fail for that reason without saying so.
        do {
            let room = StudioVoiceRoom()
            for i in 0..<6 where i != 2 {
                room.receive(a[i], from: alice, sequence: UInt32(i))
            }
            _ = drain(room, frames: 6)
            check(room.framesConcealed == 1,
                  "one lost packet concealed exactly once (\(room.framesConcealed))")
            check(room.framesPlayed == 6,
                  "and playback kept its cadence — \(room.framesPlayed) frames out of 6 pulls")
            check(room.framesDroppedOverflow == 0,
                  "and the runaway guard binned nothing, so the gap above is a real gap "
                  + "(\(room.framesDroppedOverflow))")
        }

        // 5. A PACKET WHOSE TURN HAS PASSED IS DROPPED, not played out of order.
        do {
            let room = StudioVoiceRoom()
            for (i, p) in a.enumerated() { room.receive(p, from: alice, sequence: UInt32(i)) }
            _ = drain(room, frames: 5)
            room.receive(a[0], from: alice, sequence: 0)        // far too late
            check(room.framesDroppedLate == 1,
                  "a packet arriving after its turn is dropped (\(room.framesDroppedLate))")
        }

        // 6. CLIPPING. Four loud speakers must not exceed the rails.
        do {
            let room = StudioVoiceRoom()
            for (idx, hz) in [180.0, 240.0, 320.0, 480.0].enumerated() {
                let loud = speaker(hz: hz, frames: 10, amplitude: 0.95)
                let who = VoiceParticipant("loud\(idx)")
                for (i, p) in loud.enumerated() { room.receive(p, from: who, sequence: UInt32(i)) }
            }
            var out = [Float](repeating: 0, count: N)
            var peak: Float = 0
            for _ in 0..<6 {
                let n = out.withUnsafeMutableBufferPointer { room.mix(into: $0.baseAddress!, capacity: N) }
                for i in 0..<n { peak = max(peak, abs(out[i])) }
            }
            check(peak <= 1.0001, String(format: "four loud speakers stay on the rails (peak %.3f)", peak))
            // CONTROL: they really did exceed 1.0 before clipping, or the
            // check above is vacuous.
            check(peak > 0.9, String(format: "CONTROL: and they were loud enough to need it (%.3f)", peak))
        }

        // 7. LEAVING. A departed speaker must not conceal forever.
        do {
            let room = StudioVoiceRoom()
            for (i, p) in a.enumerated() { room.receive(p, from: alice, sequence: UInt32(i)) }
            room.remove(alice)
            check(room.participants.isEmpty, "a speaker who leaves is gone from the room")
            let before = room.framesConcealed
            _ = drain(room, frames: 5)
            check(room.framesConcealed == before,
                  "and an empty room conceals nothing (\(room.framesConcealed))")
        }

        print()
        if failures.isEmpty {
            print("PASS — the room reorders, conceals, minuses and clips")
            exit(0)
        }
        print("FAIL — \(failures.count) assertion(s):")
        failures.forEach { print("   · \($0)") }
        exit(1)
    }
}
