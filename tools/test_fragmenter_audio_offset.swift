// Audio Sync (tvOS-DESIGN §8.2a) — `MP4Fragmenter.plan(audioOffset:)`.
//
// The viewer's Audio Sync moves the sound against the picture by rewriting
// only the sound track's tfdt in the remux. Three things must hold:
//   1. At 0 the output is exactly today's: same plan, same bytes.
//   2. Shifted, every sound run's tfdt is its sample's ORIGINAL decode time
//      plus the shift, exactly, and the video runs are untouched (so the
//      playlist, scrubber, seeking and captions cannot move).
//   3. Nothing is doubled or lost except, for an EARLIER sound, the opening
//      samples that would land before zero.
//
//   cp tools/test_fragmenter_audio_offset.swift /tmp/main.swift && swiftc -O \
//     ArchiveWatch/ArchiveWatch/Networking/MP4Fragmenter.swift /tmp/main.swift \
//     -o /tmp/fragoffset && /tmp/fragoffset <ftyp+moov file>
//
// Build the head file from any archive.org mp4 by concatenating its ftyp and
// moov boxes. Control: break the shift (e.g. apply it to the video track, or
// add it twice) and this must FAIL.
//
// Byte identity against the fragmenter BEFORE this parameter existed was
// checked once by hand (2026-11-21): HEAD~'s MP4Fragmenter.swift renamed to
// MP4FragmenterOld, both built every fragment of Hee Haw 1969 No 11 over the
// same fake media, and every byte matched.
import Foundation

func fail(_ s: String) -> Never { print("FAIL \(s)"); exit(1) }

let path = CommandLine.arguments.dropFirst().first ?? "head.bin"
guard let head = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
let movie = try MP4Fragmenter.parse(head: head)
guard let video = movie.tracks.first(where: { $0.handler == "vide" }),
      let audio = movie.tracks.first(where: { $0.handler == "soun" })
else { fail("needs a video and a sound track") }

// Deterministic stand-in for the source bytes: a sample's bytes name its offset.
func media(_ off: Int, _ len: Int) -> Data {
    Data((0..<len).map { UInt8(truncatingIfNeeded: off &+ $0 &* 31) })
}
func bytes(_ p: MP4Fragmenter.Plan) -> [Data] {
    [p.initSegment] + p.fragments.map { MP4Fragmenter.fragment(movie, $0, media: media) }
}
func runs(_ p: MP4Fragmenter.Plan, _ id: UInt32) -> [MP4Fragmenter.FragTrack] {
    p.fragments.flatMap { f in f.tracks.filter { $0.trackID == id } }
}

// 1. Offset 0 is today.
let base = MP4Fragmenter.plan(movie)
let zero = MP4Fragmenter.plan(movie, seconds: 2.0, audioOffset: 0)
guard bytes(base) == bytes(zero), base.totalLength == zero.totalLength else {
    fail("offset 0 changed the output")
}

// Every sound sample's original decode time.
var origin = [UInt64](repeating: 0, count: audio.samples.count + 1)
for (i, s) in audio.samples.enumerated() { origin[i + 1] = origin[i] + UInt64(s.duration) }

for offset in [1.0, -1.0, 0.1, -0.1, 2.0, -2.0] {
    let p = MP4Fragmenter.plan(movie, seconds: 2.0, audioOffset: offset)
    let shift = Int64((offset * Double(audio.timescale)).rounded())

    // 2a. The picture is untouched: same runs, same tfdt, same fragment count.
    let vBase = runs(base, video.id), vShift = runs(p, video.id)
    guard vBase.count == vShift.count,
          zip(vBase, vShift).allSatisfy({ $0.firstSample == $1.firstSample
              && $0.count == $1.count && $0.baseDecodeTime == $1.baseDecodeTime })
    else { fail("offset \(offset) moved the video") }

    // 2b. Every sound run starts at its sample's own time plus the shift.
    let a = runs(p, audio.id)
    for r in a {
        let want = Int64(origin[r.firstSample]) + shift
        guard want >= 0, Int64(r.baseDecodeTime) == want else {
            fail("offset \(offset) run at sample \(r.firstSample): tfdt \(r.baseDecodeTime), want \(want)")
        }
    }

    // 3. Runs tile the sound from the first kept sample to the end.
    guard let first = a.first?.firstSample else { fail("offset \(offset) has no sound") }
    var next = first
    for r in a {
        guard r.firstSample == next else { fail("offset \(offset) gap at sample \(next)") }
        next += r.count
    }
    // A later sound stops at the picture's end (so the item, and the
    // scrubber, keep their length); an earlier one runs to its last sample.
    var keep = audio.samples.count
    if offset > 0 {
        let videoEnd = Double(video.samples.reduce(UInt64(0)) { $0 + UInt64($1.duration) })
            / Double(video.timescale)
        let endTicks = Int64(videoEnd * Double(audio.timescale))
        keep = (0...audio.samples.count).last { Int64(origin[$0]) + shift <= endTicks } ?? 0
    }
    guard next == keep else { fail("offset \(offset) covered \(next), want \(keep) of \(audio.samples.count)") }
    let soundEnd = Double(Int64(origin[next]) + shift) / Double(audio.timescale)
    let pictureEnd = Double(video.samples.reduce(UInt64(0)) { $0 + UInt64($1.duration) })
        / Double(video.timescale)
    guard soundEnd <= pictureEnd + 0.001 else { fail("offset \(offset) sound ends after the picture") }
    let dropped = Double(origin[first]) / Double(audio.timescale)
    if offset >= 0 {
        guard first == 0 else { fail("offset \(offset) dropped sound it should not") }
    } else {
        guard dropped >= -offset, dropped < -offset + 0.05 else {
            fail("offset \(offset) dropped \(dropped) s of sound")
        }
    }

    // 2c. Each sound run still begins where its fragment's picture begins
    //     (in the shifted time), so a seek finds sound under the picture —
    //     except before the shifted sound has started.
    var worst = 0.0
    for f in p.fragments {
        guard let v = f.tracks.first(where: { $0.trackID == video.id }),
              let s = f.tracks.first(where: { $0.trackID == audio.id }) else { continue }
        let vStart = Double(v.baseDecodeTime) / Double(video.timescale)
        let sStart = Double(s.baseDecodeTime) / Double(audio.timescale)
        if vStart < max(offset, 0) + 0.001 { continue }
        worst = max(worst, abs(sStart - vStart))
    }
    guard worst <= 0.05 else { fail("offset \(offset) sound run starts \(worst) s from its picture") }

    // The bytes actually written carry the planned tfdt.
    for f in p.fragments.prefix(3) {
        let d = MP4Fragmenter.fragment(movie, f, media: media)
        for ft in f.tracks {
            let tag = Data("tfdt".utf8)
            var i = 0, found = false
            while let r = d.range(of: tag, in: i..<d.count) {
                let v = MP4Fragmenter.be64(d, r.upperBound + 4)
                if v == ft.baseDecodeTime { found = true; break }
                i = r.upperBound
            }
            guard found else { fail("offset \(offset) fragment \(f.sequence) tfdt not written") }
        }
    }
    print(String(format: "offset %+.1f: fragments=%d soundRuns=%d dropped=%.3f s worstRunStart=%.3f s",
                 offset, p.fragments.count, a.count, dropped, worst))
}
print("PASS")
