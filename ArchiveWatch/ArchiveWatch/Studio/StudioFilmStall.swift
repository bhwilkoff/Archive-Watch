// WHY the film stopped reaching the programme (§4, §D21).
//
// This is a pure function over four facts a caller reads off `AVPlayer`,
// deliberately separated from the poll loop that reads them. The reason is
// Decision 130's: a five-branch sentence written inline in a `while` loop is a
// compile-time claim — it cannot be exercised without a running show, a real
// film and the specific fault it describes, so in practice it is never
// exercised at all, and the first time anybody reads one of its sentences is
// the day something is already wrong.
//
// Split out, every branch is reachable from a test in milliseconds, and the
// poll loop keeps the one job it can do: ask the player.

import Foundation

public enum StudioFilmStall {

    /// What the poll loop sees. Named rather than passed as four bare
    /// arguments, because `(false, true, 0, nil)` at a call site is how the
    /// wrong branch gets wired to the wrong condition.
    public struct Facts: Sendable, Equatable {
        public var hasPlayer: Bool
        public var hasItem: Bool
        public var rate: Float
        public var likelyToKeepUp: Bool
        public var errorDescription: String?

        public init(hasPlayer: Bool, hasItem: Bool, rate: Float,
                    likelyToKeepUp: Bool, errorDescription: String? = nil) {
            self.hasPlayer = hasPlayer
            self.hasItem = hasItem
            self.rate = rate
            self.likelyToKeepUp = likelyToKeepUp
            self.errorDescription = errorDescription
        }
    }

    /// ORDER MATTERS, and it is the order of how completely the thing is gone.
    /// A player with no item also has a rate of 0, so asking "is it paused"
    /// first would report a rebuilt window as a host who pressed pause — a
    /// sentence that sends somebody looking in the wrong place, which is worse
    /// than the silence it replaces.
    public static func reason(_ f: Facts) -> String {
        if !f.hasPlayer {
            return "the Studio is not holding a player for this film"
        }
        if !f.hasItem {
            // THE ONE THIS WAS WRITTEN FOR. A surface that is torn down nils
            // its item (§D12's stop-the-film fix), and an engine attached to
            // THAT player keeps a live object with nothing in it — which is
            // exactly what a healthy log looks like.
            return "the film's player has no item — its window was probably rebuilt"
        }
        if f.rate == 0 {
            return "the film is paused"
        }
        if !f.likelyToKeepUp {
            return "the film is still buffering"
        }
        if let e = f.errorDescription {
            return "the film stopped: \(e)"
        }
        return "the film is playing but no frames are reaching the programme"
    }

    /// How many consecutive silent seconds before the cause is named. One is a
    /// hiccup on a 24 fps transfer and the row already shows the rate.
    public static let secondsBeforeNaming = 3
}
