// Does the voice probe's wire format survive a Data SLICE? (§8.18)
//
// This case exists because of a crash that reached the owner's phones.
// `StudioVoiceProbe.handle` read `data[0]` and wrote `back[0] = 2`, and
// **`Data`'s subscript takes an ABSOLUTE INDEX, not an offset**. A `Data`
// handed back by a framework is routinely a SLICE whose `startIndex` is not
// zero, and `data[0]` on one of those traps with "Index out of range" — on
// EVERY inbound frame. Owner, 2026-09-20: "Lots of crashing."
//
// WHAT MADE IT SLIP THROUGH, and the reason this case is worth having:
// `count` reads correctly on a slice. So `guard data.count >= 5` passed
// cleanly and the very next line trapped — a guard that looked like it was
// protecting the thing it was not. No amount of reading the function would
// have shown it; feeding it a slice does, immediately.
//
// The parsing could not be tested where it lived, inside a method needing a
// live `GroupSessionMessenger` and therefore two people in a SharePlay call.
// So the one piece with an off-by-one in it was the one piece no test could
// reach. `VoiceFrame` is that logic pulled out; this is the test that pull
// bought.
//
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -O ArchiveWatch/ArchiveWatch/Studio/StudioVoiceProbe.swift \
//     tools/test_studio_voiceframe.swift -o /tmp/vftest && /tmp/vftest

import Foundation

@main
enum VoiceFrameTest {

    static var failures: [String] = []

    static func check(_ ok: Bool, _ what: String) {
        print("  \(ok ? "PASS" : "FAIL")  \(what)")
        if !ok { failures.append(what) }
    }

    static func main() {
        print("§8.18 the voice probe's wire format — does it survive a Data SLICE?")
        print()

        // 1. The plain case, so a failure below means something specific.
        let whole = VoiceFrame.encode(tag: VoiceFrame.tagProbe, seq: 4242, size: 80)
        check(whole.count == 80, "an 80-byte frame is 80 bytes (\(whole.count))")
        if let d = VoiceFrame.decode(whole) {
            check(d.tag == VoiceFrame.tagProbe, "tag round-trips on a whole buffer")
            check(d.seq == 4242, "sequence round-trips on a whole buffer (\(d.seq))")
        } else {
            check(false, "a whole buffer decodes at all")
        }

        // 2. THE CASE THAT CRASHED. A slice whose startIndex is NOT zero —
        //    which is what a framework hands back, and what `messages(of:)`
        //    gave us.
        let prefixed = Data([0xDE, 0xAD, 0xBE, 0xEF]) + whole
        let slice = prefixed.dropFirst(4)
        check(slice.startIndex != 0,
              "CONTROL: the test input really is a slice (startIndex \(slice.startIndex))")
        check(!slice.indices.contains(0),
              "CONTROL: index 0 is OUT OF RANGE on it — `data[0]` is what trapped")
        check(slice.count == 80, "the slice still reports the right count (\(slice.count)) — "
              + "which is exactly why the `count >= 5` guard gave no warning")
        if let d = VoiceFrame.decode(slice) {
            check(d.tag == VoiceFrame.tagProbe, "tag decodes correctly FROM A SLICE")
            check(d.seq == 4242, "sequence decodes correctly FROM A SLICE (\(d.seq))")
        } else {
            check(false, "a slice decodes at all")
        }

        // 3. The bounce must not mutate someone else's buffer, and must come
        //    back the same shape with only the tag changed.
        let bounced = VoiceFrame.bounce(slice, tag: VoiceFrame.tagEcho)
        check(bounced.count == slice.count,
              "the bounce is the same size (\(bounced.count) vs \(slice.count))")
        if let d = VoiceFrame.decode(bounced) {
            check(d.tag == VoiceFrame.tagEcho, "the bounce carries the ECHO tag")
            check(d.seq == 4242, "the bounce preserves the sequence, or a round trip "
                  + "can never be matched to its send (\(d.seq))")
        } else {
            check(false, "the bounce decodes")
        }
        if let original = VoiceFrame.decode(slice) {
            check(original.tag == VoiceFrame.tagProbe,
                  "and the ORIGINAL slice is untouched — bounce copies, never mutates")
        }

        // 4. Short frames are refused rather than read past the end.
        check(VoiceFrame.decode(Data([1, 2, 3])) == nil, "a 3-byte frame is refused")
        check(VoiceFrame.decode(Data()) == nil, "an empty frame is refused")
        let shortSlice = (Data([0xAA]) + Data([1, 2, 3])).dropFirst(1)
        check(VoiceFrame.decode(shortSlice) == nil, "a SHORT SLICE is refused too")

        // 5. Every sequence value, including the ones that exercise all four
        //    bytes — a little-endian read that is wrong only in the high byte
        //    passes every small-number test there is.
        var seqOK = true
        for s in [UInt32(0), 1, 255, 256, 65535, 65536, 16777215, 16777216, UInt32.max] {
            let f = (Data([0x11]) + VoiceFrame.encode(tag: 1, seq: s, size: 16)).dropFirst(1)
            if VoiceFrame.decode(f)?.seq != s { seqOK = false; break }
        }
        check(seqOK, "sequences round-trip across all four bytes, on slices")

        print()
        if failures.isEmpty {
            print("PASS — the wire format is offset-based and slice-safe")
            exit(0)
        }
        print("FAIL — \(failures.count) assertion(s):")
        failures.forEach { print("   · \($0)") }
        exit(1)
    }
}
