// Does the film's audio ring hand back what was put into it, IN ORDER? (§8.15)
//
// This case exists because of the worst defect this feature has had, and
// because nothing could have caught it. `AudioRing.read` computed its start
// as `writeIndex - have` — the NEWEST `have` samples. The type has no read
// index at all, so every read returned the most recently written chunk and
// silently skipped everything buffered behind it, while `available -= have`
// kept FIFO books over a LIFO read. With 120-300 ms buffered against ~20 ms
// reads, the mixer took the newest 20 ms and discarded the rest, over and
// over.
//
// What went to air was real film audio, at the right film position, at the
// right level, with the right spectrum, no discontinuities, no overflow and
// no padding — and fragmented beyond recognition. Six instruments called it
// clean for a day (click detection, packet cadence, drift, levels, spectra, a
// throttle test) and every one was accurate and useless, because
// correctly-formed chunks in the wrong order have none of the symptoms any of
// them look for. The owner heard it immediately: "every single snippet of
// audio is being digitally re-rendered slower and with huge digital garbage
// being inserted in between."
//
// It was finally pinned by correlating the broadcast against the source film
// (0.139, where the correlator scores 1.000 against itself and 0.002 on
// unrelated content) and then bisecting with the decoder's own PCM
// (0.993-0.997, perfect). That is a lot of apparatus for something a ring
// buffer test would have caught in a millisecond.
//
// So this asserts the ONE property all of that was really about: bytes come
// out in the order they went in. Every assertion is paired with the same
// check run over a deliberately broken reimplementation of the old LIFO read,
// which must FAIL — a test that cannot fail on the bug it was written for is
// not a test (Decision 130).
//
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -O ArchiveWatch/ArchiveWatch/Studio/StudioAudio.swift \
//     tools/test_studio_ring.swift -o /tmp/ringtest && /tmp/ringtest

import Foundation

@main
enum RingTest {

    static var failures: [String] = []

    static func check(_ ok: Bool, _ what: String) {
        print("  \(ok ? "PASS" : "FAIL")  \(what)")
        if !ok { failures.append(what) }
    }

    /// Read every sample out of a ring in `chunk`-sized reads and return what
    /// arrived, in arrival order.
    static func drain(_ ring: AudioRing, chunk: Int, reads: Int) -> [Float] {
        var got: [Float] = []
        var buf = [Float](repeating: .nan, count: chunk)
        for _ in 0..<reads {
            let real = buf.withUnsafeMutableBufferPointer { p -> Int in
                ring.read(into: p.baseAddress!, count: chunk)
            }
            if real == 0 { break }
            got.append(contentsOf: buf[0..<real])
        }
        return got
    }

    /// THE OLD READ, reimplemented over a plain array so the control is
    /// honest: same arithmetic that shipped, `writeIndex - have`.
    static func lifoDrain(capacity: Int, written: [Float], chunk: Int, reads: Int) -> [Float] {
        var buffer = [Float](repeating: 0, count: capacity)
        var writeIndex = 0, available = 0
        for v in written {
            buffer[writeIndex % capacity] = v
            writeIndex = (writeIndex + 1) % capacity
            available = min(capacity, available + 1)
        }
        var got: [Float] = []
        for _ in 0..<reads {
            let have = min(available, chunk)
            if have == 0 { break }
            let start = ((writeIndex - have) % capacity + capacity) % capacity   // the bug
            for i in 0..<have { got.append(buffer[(start + i) % capacity]) }
            available -= have
        }
        return got
    }

    /// Is `xs` the ascending run 0,1,2,… with nothing skipped or repeated?
    static func isContiguousRamp(_ xs: [Float]) -> Bool {
        for (i, v) in xs.enumerated() where v != Float(i) { return false }
        return !xs.isEmpty
    }

    static func main() {
        print("§8.15 the film audio ring — does it return what it was given, in order?")
        print()

        let capacity = 8192
        let chunk = 441          // ~10 ms of stereo at 44.1 kHz, the shape the mixer reads in
        let writes = 4000        // far more than one read, which is the whole point

        // 1. FIFO. Write a ramp, read it back in small chunks.
        let ring = AudioRing(capacity: capacity)
        var ramp = (0..<writes).map { Float($0) }
        ramp.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: writes) }
        let got = drain(ring, chunk: chunk, reads: 40)
        check(isContiguousRamp(got),
              "FIFO: \(got.count) samples came back as a contiguous ascending run")
        check(got.count == writes,
              "nothing was skipped: got \(got.count) of \(writes)")

        // 1-CONTROL. The shipped LIFO arithmetic must FAIL both of those, or
        // this case proves nothing about the bug it was written for.
        let lifo = lifoDrain(capacity: capacity, written: ramp, chunk: chunk, reads: 40)
        check(!isContiguousRamp(lifo),
              "CONTROL: the old `writeIndex - have` read is NOT contiguous (it must fail)")
        check(lifo.first != 0,
              "CONTROL: the old read starts at the NEWEST sample (\(lifo.first ?? -1)), not 0")

        // 2. Reads never exceed what was written, and padding is accounted.
        let starved = AudioRing(capacity: capacity)
        var ten = (0..<10).map { Float($0) }
        ten.withUnsafeBufferPointer { starved.write($0.baseAddress!, count: 10) }
        var out = [Float](repeating: .nan, count: 100)
        let real = out.withUnsafeMutableBufferPointer { p -> Int in
            starved.read(into: p.baseAddress!, count: 100)
        }
        check(real == 10, "a starved read returns only what is real (\(real) of 100)")
        check(out[10...99].allSatisfy { $0 == 0 }, "the shortfall is silence, not stale memory")
        check(starved.framesPadded == 90, "padding is counted (\(starved.framesPadded))")

        // 3. Overflow is counted rather than silently swallowed. The pump is
        //    bounded by ring headroom for exactly this reason: a live
        //    broadcast showed `overflowed=427896 fill=0.95` once the read
        //    became FIFO and stopped hiding the imbalance.
        let flooded = AudioRing(capacity: capacity)
        var flood = (0..<(capacity * 2)).map { Float($0) }
        flood.withUnsafeBufferPointer { flooded.write($0.baseAddress!, count: capacity * 2) }
        check(flooded.framesOverflowed > 0,
              "writing twice the capacity counts overflow (\(flooded.framesOverflowed))")
        check(flooded.availableSamples == capacity,
              "available never exceeds capacity (\(flooded.availableSamples))")

        // 4. Wrapping. Fill, drain, refill across the boundary — the case the
        //    modulo arithmetic is most likely to get wrong.
        let wrap = AudioRing(capacity: 1000)
        for round in 0..<5 {
            var block = (0..<600).map { Float(round * 600 + $0) }
            block.withUnsafeBufferPointer { wrap.write($0.baseAddress!, count: 600) }
            let back = drain(wrap, chunk: 200, reads: 3)
            let expected = (0..<600).map { Float(round * 600 + $0) }
            if back != expected {
                check(false, "wrap round \(round): expected \(expected.first ?? -1)… got \(back.first ?? -1)…")
                break
            }
            if round == 4 { check(true, "wrapping: 5 fill/drain rounds of 600 across a 1000 ring") }
        }

        print()
        if failures.isEmpty {
            print("PASS — the ring is FIFO, accounts for padding and overflow, and wraps")
            exit(0)
        }
        print("FAIL — \(failures.count) assertion(s):")
        failures.forEach { print("   · \($0)") }
        exit(1)
    }
}
