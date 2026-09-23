import Foundation

/// The client half of SHAREPLAY §11 — the thing that actually polls.
///
/// It joins `StudioSync`'s arithmetic (§8.27) to the Worker's routes (§8.30),
/// and owns exactly two jobs: keep an estimate of the server's clock, and say
/// what the film should do. **It does not touch a player.** The caller applies
/// the correction, because a player is `AVPlayer` on three platforms,
/// `ExoPlayer` on another and an `<video>` element on the web, and a type that
/// knew about any of them could not be tested without one.
///
/// That separation is the same reasoning as `StudioCameraStall` and
/// `StudioLayout`: the rule is a value, the platform is a caller.
public actor StudioSyncClient {

    public struct Config: Sendable {
        public var base: URL
        public init(base: URL) { self.base = base }
        /// Production.
        ///
        /// THE WORKER IS NOT ON archivewatch.org. That host is GitHub Pages;
        /// the Worker answers at its own `workers.dev` origin, which is where
        /// the privacy counter has always posted (`AW_BEACON_ORIGIN` in
        /// watch.js). Pointing this at the site would have reached Pages and
        /// 404'd on every route — found by looking at what was actually
        /// deployed rather than at what the name suggested.
        ///
        /// Still no third party in the path: it is the owner's own Worker,
        /// sharing a deployment with the counter.
        public static let live = Config(
            base: URL(string: "https://archivewatch-pulse.benwilkoff.workers.dev")!)
    }

    public enum JoinError: Error, Sendable {
        case noSuchRoom
        case ended
        case badCode
        case transport(String)
    }

    private let config: Config
    private let session: URLSession
    /// The best clock sample so far — §11.2 keeps the one with the SMALLEST
    /// round trip, never an average.
    private var clock: StudioSync.ClockSample?
    private(set) public var code: String?
    /// THE CREDENTIAL, held only by the host's own app and never displayed.
    ///
    /// The code is read aloud on a call, so it cannot also be what drives the
    /// film — the lesson Tidbits Trivia puts on its own screen: "the room
    /// code alone cannot drive the show". A guest has the code and that is
    /// deliberately not enough.
    private var hostKey: String?
    private(set) public var lastState: StudioSync.State?
    /// How many joined devices the room saw in the last minute (anonymous
    /// tokens only — owner, 2026-09-23). Nil from a Worker that predates it.
    private(set) public var lastPresent: Int?
    private var lastGenerationChangeAt: Date?
    private var lastGeneration: Int?

    public init(config: Config = .live, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// The offset in use, and how far it can be wrong. Exposed because a host
    /// debugging "we are out of step" needs to know whether the clock or the
    /// film is the suspect.
    public var clockOffset: (offset: Double, error: Double)? {
        clock.map { ($0.offset, $0.error) }
    }

    /// This client's best guess at the server's clock right now.
    public var serverNow: Double {
        StudioSync.serverTime(clientNow: Date().timeIntervalSince1970,
                              offset: clock?.offset ?? 0)
    }

    // MARK: Joining

    public func join(code typed: String) async throws -> StudioSync.State {
        guard let code = StudioRoom.normalize(typed) else { throw JoinError.badCode }
        self.code = code
        return try await poll()
    }

    public func leave() { code = nil; lastState = nil }

    // MARK: Polling

    /// One request: the state AND a clock sample, because they arrive in the
    /// same response (§11.6). Measuring the round trip around this very
    /// request is what makes the offset free.
    @discardableResult
    public func poll() async throws -> StudioSync.State {
        guard let code else { throw JoinError.noSuchRoom }
        let url = config.base.appendingPathComponent("together").appendingPathComponent(code)
        let sentAt = Date().timeIntervalSince1970
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(from: url) }
        catch { throw JoinError.transport("\(error)") }
        let receivedAt = Date().timeIntervalSince1970

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { throw JoinError.noSuchRoom }
            if http.statusCode == 410 { throw JoinError.ended }
            guard (200..<300).contains(http.statusCode) else {
                throw JoinError.transport("HTTP \(http.statusCode)")
            }
        }
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let filmID = o["filmID"] as? String,
              let position = o["position"] as? Double,
              let atServerTime = o["atServerTime"] as? Double,
              let serverTime = o["serverTime"] as? Double else {
            throw JoinError.transport("the room's answer could not be read")
        }

        // KEEP THE FASTEST SAMPLE, not the newest. A slow exchange is not
        // merely imprecise — its error bound is RTT/2, so replacing a 20 ms
        // sample with an 800 ms one makes the clock WORSE while looking like
        // an update. Superseded only when a genuinely faster one arrives.
        let sample = StudioSync.ClockSample(sentAt: sentAt, serverTime: serverTime,
                                            receivedAt: receivedAt)
        if let best = clock {
            if sample.roundTrip < best.roundTrip { clock = sample }
        } else {
            clock = sample
        }

        let state = StudioSync.State(
            filmID: filmID, position: position, atServerTime: atServerTime,
            rate: (o["rate"] as? Double) ?? 1.0,
            paused: (o["paused"] as? Bool) ?? false,
            generation: (o["generation"] as? Int) ?? 1)
        if state.generation != lastGeneration {
            lastGeneration = state.generation
            lastGenerationChangeAt = Date()
        }
        lastState = state
        lastPresent = o["present"] as? Int
        return state
    }

    /// A joined device saying it is here: an anonymous token, made fresh per
    /// join, tied to nothing. Only a COUNT is ever read back. Best-effort — a
    /// missed ping only makes the count lag.
    public func sayHere(token: String) async {
        guard let code else { return }
        var r = URLRequest(url: config.base.appendingPathComponent("together")
                              .appendingPathComponent(code).appendingPathComponent("here"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token])
        _ = try? await session.data(for: r)
    }

    /// How long to wait before polling again (§11.6). Backs off while nothing
    /// is happening, which is the common case in a two-hour watch and is what
    /// keeps this inside a free tier.
    public var nextPollDelay: Double {
        let quiet = lastGenerationChangeAt.map { Date().timeIntervalSince($0) } ?? 0
        return StudioSync.pollInterval(secondsSinceGenerationChanged: quiet)
    }

    /// What the caller's player should do now. Nil until a state has arrived.
    public func correction(localPosition: Double, localPaused: Bool) -> StudioSync.Correction? {
        guard let lastState else { return nil }
        return StudioSync.correction(localPosition: localPosition,
                                     localPaused: localPaused,
                                     state: lastState,
                                     serverNow: serverNow)
    }

    // MARK: Hosting

    /// Create a room for a film, returning the code to read aloud.
    public func createRoom(filmID: String, position: Double,
                           rate: Double = 1, paused: Bool = false) async throws -> String {
        var r = URLRequest(url: config.base.appendingPathComponent("together/new"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: [
            "filmID": filmID, "position": position, "rate": rate, "paused": paused])
        let (data, _) = try await session.data(for: r)
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = o["code"] as? String else {
            throw JoinError.transport("the room could not be created")
        }
        self.code = code
        // Returned ONCE, at creation. A poll never carries it back.
        self.hostKey = o["hostKey"] as? String
        return code
    }

    /// Publish a state change. Called on play, pause, seek and rate — NEVER on
    /// a timer, which is what keeps a two-hour film at tens of writes (§11.1).
    public func publish(filmID: String, position: Double,
                        rate: Double = 1, paused: Bool = false) async throws {
        guard let code else { throw JoinError.noSuchRoom }
        var r = URLRequest(url: config.base.appendingPathComponent("together")
                              .appendingPathComponent(code))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let hostKey { r.setValue(hostKey, forHTTPHeaderField: "x-aw-host-key") }
        r.httpBody = try? JSONSerialization.data(withJSONObject: [
            "filmID": filmID, "position": position, "rate": rate, "paused": paused])
        _ = try await session.data(for: r)
    }

    /// End the room. A DELETE on the server: nothing about a watch outlives it.
    public func endRoom() async {
        guard let code else { return }
        var r = URLRequest(url: config.base.appendingPathComponent("together")
                              .appendingPathComponent(code))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let hostKey { r.setValue(hostKey, forHTTPHeaderField: "x-aw-host-key") }
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["end": true])
        _ = try? await session.data(for: r)
        self.code = nil
        self.hostKey = nil
    }
}
