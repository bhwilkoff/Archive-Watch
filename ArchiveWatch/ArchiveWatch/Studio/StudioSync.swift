import Foundation

/// KEEPING THE FILM IN SYNC WITHOUT SHAREPLAY — SHAREPLAY §11.
///
/// Pure value types, deliberately: the arithmetic here is the part most likely
/// to be quietly wrong, and it can be exercised with controls on any machine
/// without a network, a player or a device. The transport and the players come
/// after, and they come after because of Decision 130 — a rule proved in a
/// harness has still not been proved where it RUNS, so the less that is
/// entangled with this, the smaller that remaining gap is.
public enum StudioSync {

    // MARK: - What the host publishes (§11.1)

    /// The state of the film, from which every client computes the rest.
    ///
    /// §11.1: a host never sends the playhead. A film is deterministic, so a
    /// position, the server time it was true, and a rate are enough for any
    /// client to work out where the film should be now. That is what makes a
    /// two-hour watch tens of messages instead of thousands.
    public struct State: Equatable, Sendable {
        public let filmID: String
        /// Seconds into the film.
        public let position: Double
        /// The SERVER's clock when `position` was true — never a client's,
        /// because two devices disagree by seconds (§11.2).
        public let atServerTime: Double
        public let rate: Double
        public let paused: Bool
        /// Bumped on every write, so a client can tell a changed record from
        /// a re-read of the same one, and back its polling off (§11.6).
        public let generation: Int

        public init(filmID: String, position: Double, atServerTime: Double,
                    rate: Double = 1.0, paused: Bool = false, generation: Int = 1) {
            self.filmID = filmID
            self.position = position
            self.atServerTime = atServerTime
            self.rate = rate
            self.paused = paused
            self.generation = generation
        }

        /// Where the film should be at `serverNow`.
        ///
        /// A PAUSED film does not advance — the obvious thing, and the one an
        /// elapsed-time formula gets wrong if it forgets to ask.
        public func expectedPosition(atServerTime serverNow: Double) -> Double {
            guard !paused else { return position }
            return position + max(0, serverNow - atServerTime) * rate
        }
    }

    // MARK: - Agreeing what time it is (§11.2)

    /// One request/response round trip against the server.
    public struct ClockSample: Equatable, Sendable {
        /// Client clock when the request left.
        public let sentAt: Double
        /// The server's own clock, as it reported it.
        public let serverTime: Double
        /// Client clock when the reply arrived.
        public let receivedAt: Double

        public init(sentAt: Double, serverTime: Double, receivedAt: Double) {
            self.sentAt = sentAt
            self.serverTime = serverTime
            self.receivedAt = receivedAt
        }

        public var roundTrip: Double { max(0, receivedAt - sentAt) }

        /// Cristian's algorithm: assume the request and the reply each took
        /// half the round trip.
        public var offset: Double { serverTime - (sentAt + receivedAt) / 2 }

        /// The bound on `offset`'s error. It is RTT/2 — which is WHY the
        /// fastest exchange is the best one.
        public var error: Double { roundTrip / 2 }
    }

    /// The offset to use, chosen from several samples.
    ///
    /// **THE SMALLEST ROUND TRIP, NEVER THE AVERAGE.** The error bound is
    /// RTT/2, so the fastest sample is the most accurate one; averaging mixes
    /// a good measurement with bad ones and throws the bound away — you end up
    /// with a number you cannot state an error for, which is worse than a
    /// slightly noisier one you can. §8.27 asserts this against an averaging
    /// control that a single slow sample drags off by hundreds of
    /// milliseconds.
    public static func bestOffset(from samples: [ClockSample]) -> ClockSample? {
        samples.min { $0.roundTrip < $1.roundTrip }
    }

    /// A client's own clock converted to server time.
    public static func serverTime(clientNow: Double, offset: Double) -> Double {
        clientNow + offset
    }

    // MARK: - Correcting drift (§11.3)

    public enum Correction: Equatable, Sendable {
        /// Inside human tolerance for a shared watch. Do nothing, which is a
        /// decision and not an omission.
        case none
        /// Play slightly fast or slow until aligned. `rate` is a MULTIPLIER of
        /// the state's own rate, not an absolute.
        case nudge(rate: Double)
        /// Too far to close by nudging.
        case seek(to: Double)
        /// The film's run state disagrees; apply it at once, never gradually.
        case setPaused(Bool)
    }

    /// Within this, a shared watch feels together. Below the threshold where
    /// two people in a call would notice they were out of step.
    public static let toleranceSeconds = 0.150
    /// Beyond this, a nudge would take longer than a viewer will accept: at 3%
    /// a 2 s gap already needs over a minute to close.
    public static let seekThresholdSeconds = 2.0
    public static let nudgeFast = 1.03
    public static let nudgeSlow = 0.97

    /// What a guest should do, given where they are and where the host says
    /// the film should be.
    ///
    /// Decision 081 is the reason this prefers a rate change: *a drift
    /// correction may not rewind the captions past the viewer*. A seek is
    /// visible, re-buffers, and is the one thing an audience actually
    /// notices; a 3% rate change is neither audible on speech nor visible at
    /// 24 fps.
    public static func correction(localPosition: Double,
                                  localPaused: Bool,
                                  state: State,
                                  serverNow: Double) -> Correction {
        // RUN STATE FIRST, and never nudged. A host who pressed pause wants
        // the film stopped now, not eased to a halt over thirty seconds.
        if state.paused != localPaused { return .setPaused(state.paused) }
        // A paused film cannot drift, so there is nothing to correct.
        if state.paused { return .none }

        let expected = state.expectedPosition(atServerTime: serverNow)
        let drift = expected - localPosition      // positive = the guest is BEHIND
        let magnitude = abs(drift)
        if magnitude <= toleranceSeconds { return .none }
        if magnitude >= seekThresholdSeconds { return .seek(to: expected) }
        return .nudge(rate: drift > 0 ? nudgeFast : nudgeSlow)
    }

    // MARK: - How often to ask (§11.6)

    public static let pollFastSeconds = 2.0
    public static let pollIdleSeconds = 10.0
    /// A room whose generation has not moved for this long is quiet.
    public static let idleAfterSeconds = 60.0

    /// Back off while nothing is happening, snap back the moment it does.
    ///
    /// A film nobody is touching is the common case in a two-hour watch, and
    /// paying 2-second polls for it is what would put this over a free tier.
    public static func pollInterval(secondsSinceGenerationChanged: Double) -> Double {
        secondsSinceGenerationChanged >= idleAfterSeconds ? pollIdleSeconds : pollFastSeconds
    }
}
