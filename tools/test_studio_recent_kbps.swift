// §8.67 — the readout's bitrate is RECENT, not the whole show's average.
//
// An hour at 4,000 kbps followed by a collapse to 500 kbps: the lifetime
// average the iOS, tvOS and Mac readouts used still reads ~3,950 a minute
// later. The recent window must read the collapse.
import Foundation

@main
struct RecentKbps {
    static func main() {
        var failures = 0
        func check(_ ok: Bool, _ what: String) { print(ok ? "OK: \(what)" : "FAIL: \(what)"); if !ok { failures += 1 } }
        let t0 = Date(timeIntervalSince1970: 0)
        // One hour at 4000 kbps = 500 kB/s.
        let hourBytes = 3600 * 500_000
        // Then 60 s at 500 kbps = 62.5 kB/s.
        var samples: [(Date, Int)] = []
        for i in 0...5 {
            let t = 3600 + 55 + i
            samples.append((t0.addingTimeInterval(Double(t)), hourBytes + (t - 3600) * 62_500))
        }
        let recent = StudioEngine.kbps(over: samples)
        check(abs(recent - 500) <= 5, "recent window reads the collapse (\(recent) kbps)")
        let lifetime = (samples.last!.1 * 8 / 1000) / (3600 + 60)
        check(lifetime > 3000, "control: the lifetime average hides it (\(lifetime) kbps)")
        check(StudioEngine.kbps(over: [samples[0]]) == 0, "one sample is not a rate")
        print(failures == 0 ? "PASS" : "FAILED (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }
}
