import Foundation

// Deterministic, seedable RNG (SplitMix64). Used by the channel scheduler and the
// date-seeded shelf/hero shuffles so a given seed always yields the same order
// across launches and platforms. Lives in Core so every consumer shares one impl.
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
