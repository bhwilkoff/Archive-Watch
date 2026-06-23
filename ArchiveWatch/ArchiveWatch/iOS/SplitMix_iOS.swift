// Shared by iOS and macOS (pointer/AppKit sibling of UIKit; tvOS has its own variant).
#if os(iOS) || os(macOS)
import Foundation

// iOS copy of the seeded RNG used by the shared ChannelScheduler (the tvOS copy
// lives in a tvOS-guarded view file).
struct SplitMix: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
#endif
