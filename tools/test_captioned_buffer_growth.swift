// DOES `preferredForwardBufferDuration` BOUND THE CAPTIONED PATH?
//
// Decision 070 measured, on Apple TV, that the captioned single-segment HLS
// wrapper declares the whole MP4 as ONE segment — and a segment is
// AVFoundation's atomic buffering unit, so `loadedTimeRanges` climbed to
// 5,300s against a 300s request and mediaserverd died (-11819) at ~100s.
// The fix (D070) was applied to tvOS ONLY; iOS and macOS still ship the
// wrapper, and the memory note that recorded that says in as many words:
// "low-RAM iPhones plausibly have the same bomb."
//
// A viewer on a phone reported The Grapes of Wrath — a 2.19 GB film WITH a
// published subtitle track, so the wrapper is the branch it takes — playing
// for about five minutes and then stopping. This harness measures the
// mechanism rather than the crash: does the buffer obey the 300s ceiling?
//
// Two shapes, same film, same process-fresh player, so the comparison is
// like-for-like:
//   A  CaptionedHLSLoader  — the iOS/macOS captioned branch
//   B  ResilientStreamLoader — what tvOS plays instead (the control)
//
// Compile the real sources, not copies:
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library \
//     ArchiveWatch/ArchiveWatch/Networking/AirPlayRouting.swift \
//     ArchiveWatch/ArchiveWatch/Networking/ResilientStreamLoader.swift \
//     ArchiveWatch/ArchiveWatch/Networking/CaptionedHLSLoader.swift \
//     tools/test_captioned_buffer_growth.swift -o /tmp/awbuf && /tmp/awbuf

import AVFoundation
import Foundation

@main
struct Harness {
    static let hls = URL(string: "https://archivewatch.org/subs/the-grapes-of-wrath-1940/master.m3u8")!
    static let mp4 = URL(string: "https://archive.org/download/the-grapes-of-wrath-1940/The%20Grapes%20Of%20Wrath%20%281940%29.mp4")!
    static let want: Double = 300          // what both shapes ASK for
    static let seconds = 90                // how long to watch each shape
    static var retained: AnyObject?        // AVURLAsset holds its delegate WEAKLY

    static func buffered(_ item: AVPlayerItem) -> Double {
        item.loadedTimeRanges.reduce(0) { $0 + CMTimeGetSeconds($1.timeRangeValue.duration) }
    }

    /// Bytes this process has pulled off the network, from the task metrics we
    /// can see: URLSession's own counters are private to AVFoundation, so read
    /// the process footprint instead — that is the quantity that kills.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    static func watch(_ label: String, item: AVPlayerItem) async -> (peak: Double, mb: Double) {
        item.preferredForwardBufferDuration = want
        let player = AVPlayer(playerItem: item)
        player.play()
        var peak = 0.0, mb = 0.0
        print("\n  \(label)")
        for tick in 1...seconds {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let b = buffered(item)
            peak = max(peak, b); mb = max(mb, footprintMB())
            if tick % 10 == 0 {
                let pos = CMTimeGetSeconds(player.currentTime())
                print(String(format: "    t=%3ds  played=%6.1fs  buffered=%7.1fs  footprint=%6.1f MB  status=%d",
                             tick, pos, b, footprintMB(), item.status.rawValue))
            }
            if let e = item.error { print("    ITEM FAILED at t=\(tick)s: \(e.localizedDescription)"); break }
        }
        player.pause(); player.replaceCurrentItem(with: nil)
        return (peak, mb)
    }

    /// ONE SHAPE PER PROCESS, deliberately. The first run of this harness played
    /// both in sequence and the control's opening footprint readings — 1079 MB,
    /// 541 MB, 147 MB, falling — were the WRAPPER's memory still being
    /// reclaimed, which made the control's "peak" read as 1.5 GB of its own.
    /// The same trap Decision 065 records: four asset shapes probed in one
    /// process, and a previous player's leftovers counted as the current one's.
    static func main() async {
        let shape = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "both"
        if shape == "both" {
            print("Asking both shapes for a \(Int(want))s forward buffer, \(seconds)s each,")
            print("in SEPARATE PROCESSES so neither sees the other's memory.\n")
            let me = URL(fileURLWithPath: CommandLine.arguments[0])
            var codes: [Int32] = []
            for s in ["wrapper", "loader"] {
                let p = Process(); p.executableURL = me; p.arguments = [s]
                try? p.run(); p.waitUntilExit(); codes.append(p.terminationStatus)
            }
            print("\n  ── verdict ──")
            print(codes[0] == 0
                  ? "  The wrapper RESPECTS the ceiling. The five-minute stop is something else."
                  : "  The wrapper IGNORES the ceiling (see its multiple above).")
            print(codes[1] == 0
                  ? "  The resilient loader respects it, which is the control this needed."
                  : "  THE CONTROL FAILED — the loader overran too, so the wrapper is not the difference.")
            exit(codes[0] == 0 && codes[1] == 0 ? 0 : 1)
        }

        let item: AVPlayerItem
        let label: String
        if shape == "wrapper" {
            let (asset, loader) = await CaptionedHLSLoader.makeAsset(hls: hls, downloadURL: mp4)
            retained = loader                        // the delegate is held weakly
            item = AVPlayerItem(asset: asset)
            label = "A — CaptionedHLSLoader (the iOS/macOS captioned branch)"
        } else {
            let (asset, loader) = ResilientStreamLoader.makeAsset(for: mp4)
            retained = loader
            item = AVPlayerItem(asset: asset)
            label = "B — ResilientStreamLoader (what tvOS plays instead — the control)"
        }
        let r = await watch(label, item: item)
        let bounded = r.peak <= want * 1.5
        print(String(format: "    peak buffer %7.1fs (asked %.0fs, %.1fx)   peak footprint %6.1f MB   %@",
                     r.peak, want, r.peak / want, r.mb, bounded ? "WITHIN" : "OVER"))
        exit(bounded ? 0 : 1)
    }
}
