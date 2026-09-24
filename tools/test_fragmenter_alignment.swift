// §8.71 — every fragment's non-video tracks start where its video starts.
//
// `MP4Fragmenter.plan` used to cut each audio run to "at least this fragment's
// video span", measured per fragment. Each run overshot by up to one AAC
// frame and the overshoot ACCUMULATED: on Abraham Lincoln (1930), 2-s
// fragments, the audio inside a fragment led its video by ~7 s at 20 minutes.
// Linear playback is unaffected (tfdt is right), but a SEEK loads the segment
// the playlist names for the video time and the audio clock lands seconds
// later — measured on Ben Bedroom 2026-09-24 as a room guest re-seeking every
// poll, 7-9 s ahead of the host.
//
//   cp tools/test_fragmenter_alignment.swift /tmp/main.swift && swiftc -O \
//     ArchiveWatch/ArchiveWatch/Networking/MP4Fragmenter.swift /tmp/main.swift -o /tmp/fragalign && /tmp/fragalign <ftyp+moov file>
//
// Build the head file from any non-faststart archive.org mp4 by concatenating
// its ftyp and moov boxes. Control: run against the pre-fix fragmenter
// (git show <rev>:.../MP4Fragmenter.swift) — it must FAIL.
import Foundation

let path = CommandLine.arguments.dropFirst().first ?? "head.bin"
guard let head = FileManager.default.contents(atPath: path) else {
    print("FAIL cannot read \(path)"); exit(1)
}
let movie = try MP4Fragmenter.parse(head: head)
let plan = MP4Fragmenter.plan(movie)
guard let video = movie.tracks.first(where: { $0.handler == "vide" }) else {
    print("FAIL no video track"); exit(1)
}
var worst = 0.0, worstAt = 0.0
for f in plan.fragments {
    guard let v = f.tracks.first(where: { $0.trackID == video.id }) else { continue }
    let vStart = Double(v.baseDecodeTime) / Double(video.timescale)
    for ft in f.tracks where ft.trackID != video.id {
        guard let t = movie.tracks.first(where: { $0.id == ft.trackID }) else { continue }
        let lead = Double(ft.baseDecodeTime) / Double(t.timescale) - vStart
        if abs(lead) > abs(worst) { worst = lead; worstAt = vStart }
    }
}
// Nothing dropped or doubled: each track's runs tile its samples exactly.
for t in movie.tracks {
    var next = 0
    for f in plan.fragments {
        for ft in f.tracks where ft.trackID == t.id {
            guard ft.firstSample == next else { print("FAIL track \(t.id) gap at sample \(next)"); exit(1) }
            next += ft.count
        }
    }
    guard next == t.samples.count else { print("FAIL track \(t.id) covered \(next)/\(t.samples.count)"); exit(1) }
}
print(String(format: "fragments=%d worst audio-minus-video start=%.3f s at %.0f s",
             plan.fragments.count, worst, worstAt))
// One AAC frame at 44.1 kHz is 23 ms; allow two.
if abs(worst) <= 0.05 { print("PASS") } else { print("FAIL"); exit(1) }
