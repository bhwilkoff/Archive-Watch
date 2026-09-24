import Foundation
import AVFoundation
import Observation

/// The HOST half of SHAREPLAY §11: watches an `AVPlayer` and publishes when
/// the film's state actually changes.
///
/// §11.1 is the whole design and this is where it is kept honest: **a host
/// never sends the playhead.** It publishes on play, pause, seek and rate —
/// and on nothing else. A timer here would turn a two-hour film from tens of
/// writes into thousands and put the feature outside the free tier it was
/// designed for, which is the constraint that chose this transport at all.
///
/// The mirror of `StudioSyncFollower`, and deliberately the same shape: it
/// owns the player observation, `StudioSyncClient` owns the wire, and
/// `StudioSync` owns nothing but arithmetic.
@MainActor
@Observable
public final class StudioRoomHost {

    public private(set) var code: String?
    public private(set) var problem: String?
    /// Friends in the room right now — joined devices seen in the last minute.
    /// Nil until the first read, and from a Worker that predates presence.
    public private(set) var present: Int?
    private var presenceLoop: Task<Void, Never>?

    private let client: StudioSyncClient
    private weak var player: AVPlayer?
    private var filmID: String = ""

    /// The link a guest opens with NO APP AT ALL (SHAREPLAY §11.6.2): the
    /// web's `#/together/<code>-<film>` route, which joins in any browser.
    public var inviteURL: URL? {
        guard let code, !filmID.isEmpty,
              let film = filmID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "https://archivewatch.org/#/together/\(code)-\(film)")
    }
    private var rateObserver: NSKeyValueObservation?
    private var timeObserver: Any?
    /// The last position we told the room about, so a SEEK can be told apart
    /// from ordinary playback. Without this the periodic observer would
    /// publish continuously and §11.1 would be a comment rather than a rule.
    private var lastPublishedPosition: Double = 0
    private var lastPublishedPaused = true
    private var lastPublishedRate: Double = 1
    private var lastPublishedAt = Date()

    /// A jump larger than this is a seek rather than the film advancing. One
    /// second is comfortably more than the observer's own interval, so normal
    /// playback can never trip it, and comfortably less than any deliberate
    /// skip a person would make.
    private static let seekThreshold = 1.0

    public init(config: StudioSyncClient.Config = .live) {
        client = StudioSyncClient(config: config)
    }

    public static let shared: StudioRoomHost = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["AW_TOGETHER_BASE"],
           let url = URL(string: raw) {
            return StudioRoomHost(config: .init(base: url))
        }
        #endif
        return StudioRoomHost()
    }()

    /// Open a room for the film this player is showing, and return the code to
    /// read aloud.
    @discardableResult
    public func start(player: AVPlayer, filmID: String) async -> String? {
        stop()
        self.player = player
        self.filmID = filmID
        let position = player.currentTime().seconds
        do {
            let code = try await client.createRoom(
                filmID: filmID,
                position: position.isFinite ? position : 0,
                paused: player.rate == 0)
            self.code = code
            problem = nil
            lastPublishedPosition = position.isFinite ? position : 0
            lastPublishedPaused = player.rate == 0
            lastPublishedRate = player.rate == 0 ? 1 : Double(player.rate)
            lastPublishedAt = Date()
            observe(player)
            startReadingPresence()
            return code
        } catch {
            problem = StudioSyncFollower.sentence(for: error)
            return nil
        }
    }

    /// For app termination. `stop()` ends the room from a Task, and a quitting
    /// process exits before that request leaves: room 127T stayed open on the
    /// live Worker after the Mac app quit (2026-09-23), so friends in it would
    /// have kept following a host that no longer existed. This waits — at
    /// most two seconds, so a dead network cannot hang the quit.
    public func endBeforeTermination() {
        guard code != nil else { return }
        presenceLoop?.cancel()
        let c = client
        code = nil
        let done = DispatchSemaphore(value: 0)
        Task.detached { await c.endRoom(); done.signal() }
        _ = done.wait(timeout: .now() + 2)
    }

    private func startReadingPresence() {
        presenceLoop?.cancel()
        presenceLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, !Task.isCancelled else { return }
                _ = try? await self.client.poll()
                let n = await self.client.lastPresent
                if n != self.present {
                    self.present = n
                    awdiag("AWROOM present=%@", n.map(String.init) ?? "unknown")
                }
            }
        }
    }

    public func stop() {
        presenceLoop?.cancel(); presenceLoop = nil
        present = nil
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        rateObserver = nil
        let c = code
        code = nil
        if c != nil { Task { await client.endRoom() } }
    }

    private func observe(_ player: AVPlayer) {
        // PLAY AND PAUSE, which are the two a guest notices instantly — and
        // the HOST'S INTENT, which is `rate`. This observed
        // `timeControlStatus`, whose `.waitingToPlayAtSpecifiedRate` is
        // BUFFERING: every hiccup on the host's connection went out as a
        // pause and froze every guest (launch audit, sync). A stall that
        // leaves the host behind is caught by `publishIfSeeked` instead, as
        // one position update.
        rateObserver = player.observe(\.rate, options: [.new]) {
            [weak self] p, _ in
            let rate = p.rate
            Task { @MainActor in self?.publishIfChanged(rate: rate) }
        }
        // AND SEEKS, which have no notification of their own. A periodic
        // observer is the only way to see one, and it publishes ONLY when the
        // position jumps — the interval is a sampling rate, not a send rate.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.publishIfSeeked() }
            }
    }

    private func publishIfSeeked() {
        guard let player, code != nil else { return }
        let now = player.currentTime().seconds
        guard now.isFinite else { return }
        // Off the room's timeline — a seek, or a stall that left the host
        // behind — by more than the threshold: say where the film really is.
        if StudioSync.hostShouldRepublish(position: now,
                                          lastPosition: lastPublishedPosition,
                                          lastPaused: lastPublishedPaused,
                                          lastRate: lastPublishedRate,
                                          secondsSincePublish: Date().timeIntervalSince(lastPublishedAt),
                                          threshold: Self.seekThreshold) {
            publish(position: now, paused: player.rate == 0)
        }
    }

    private func publishIfChanged(rate: Float) {
        guard let player, code != nil else { return }
        let paused = rate == 0
        let newRate = paused ? lastPublishedRate : Double(rate)
        guard paused != lastPublishedPaused || newRate != lastPublishedRate else { return }
        let now = player.currentTime().seconds
        publish(position: now.isFinite ? now : lastPublishedPosition, paused: paused)
    }

    private func publish(position: Double, paused: Bool) {
        lastPublishedPosition = position
        lastPublishedPaused = paused
        lastPublishedAt = Date()
        let rate = Double(player?.rate ?? 1)
        if rate != 0 { lastPublishedRate = rate }
        let film = filmID
        Task {
            try? await client.publish(filmID: film, position: position,
                                      rate: rate == 0 ? 1 : rate, paused: paused)
        }
    }
}
