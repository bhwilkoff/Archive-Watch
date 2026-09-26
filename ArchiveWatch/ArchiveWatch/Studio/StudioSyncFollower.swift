import Foundation
import AVFoundation
import Observation

/// The platform layer for SHAREPLAY §11 on Apple: it owns an `AVPlayer` and a
/// `StudioSyncClient`, polls, and APPLIES what comes back.
///
/// §11.2a: nobody is ever asked to do anything. A guest whose host pauses
/// simply sees the film pause. This is the code that makes that true — the
/// thin caller that `StudioSync` deliberately is not, so that the rule stays
/// testable without a player and the player stays testable without a rule.
///
/// It drives macOS, iOS and tvOS, because `AVPlayer` is all three. Android and
/// the web need their own callers over the same `StudioSync` arithmetic, and
/// that is the point of the split rather than a gap in it.
@MainActor
@Observable
public final class StudioSyncFollower {

    public enum Status: Equatable, Sendable {
        case idle
        case joining
        case following(code: String, filmID: String)
        case ended
        case failed(String)
    }

    public private(set) var status: Status = .idle
    /// What the follower last did, for a diagnostics line. A correction that
    /// happens invisibly is right for a viewer and useless for debugging "we
    /// are out of step", so it is recorded even though nothing shows it.
    @ObservationIgnored public private(set) var lastCorrection: StudioSync.Correction?

    /// The ONE sentence a guest's player shows, or nil (SHAREPLAY §11.6.1).
    /// Three cases, and only these: the guest tried to move the film (said
    /// for three seconds, after the room has already put it back); the host
    /// ended the room; or joining failed. Nothing is said while all is well —
    /// a guest in step needs no caption telling them so.
    public private(set) var notice: String? {
        didSet {
            #if DEBUG
            if notice != oldValue { awdiag("AWFOLLOW notice=%@", notice ?? "none") }
            #endif
        }
    }
    @ObservationIgnored private var noticeClear: Task<Void, Never>?
    /// When WE last moved the player, so our own seeks and pauses are not
    /// mistaken for the guest's.
    @ObservationIgnored private var appliedAt = Date.distantPast
    /// When following began: the app is still loading and positioning the
    /// film for the first seconds, and none of that is the guest's.
    @ObservationIgnored private var followingSince = Date.distantFuture
    @ObservationIgnored private var rateObservation: NSKeyValueObservation?
    @ObservationIgnored private var jumpObserver: NSObjectProtocol?
    @ObservationIgnored private let client: StudioSyncClient
    @ObservationIgnored private weak var player: AVPlayer?
    @ObservationIgnored private var loop: Task<Void, Never>?
    /// The rate the host says, so a nudge can be undone to the RIGHT value
    /// rather than to a hardcoded 1.0 — a host watching at 1.25 would
    /// otherwise be silently corrected to normal speed every few seconds.
    /// Seconds a seek takes on this device (§11): the next one aims this far ahead.
    @ObservationIgnored private var seekLead: Double = 0.5
    /// Seeks requested and not yet completed (a superseded seek completes too,
    /// with `done == false`, so this counts rather than flags). The
    /// seek's own time-jump can reach `guestMoved` BEFORE the completion's
    /// task stamps `appliedAt`, so a seek slower than the 1.5 s window read as
    /// the guest's move: measured on Ben Bedroom 2026-09-24, a host seek into
    /// unbuffered film took 2.18 s, the guest was told "The host controls the
    /// film." and seeked again, landing 2 s past the host.
    @ObservationIgnored private var seeksInFlight = 0
    @ObservationIgnored private var hostRate: Double = 1.0

    public init(config: StudioSyncClient.Config = .live) {
        client = StudioSyncClient(config: config)
    }

    /// One follower, because there is one player at a time. The landing page
    /// and the player are different views and the hand-off between them is a
    /// code, so the thing that does the following cannot belong to either.
    ///
    /// `AW_TOGETHER_BASE` points it at a local `wrangler dev` — the same door
    /// §8.30 and §8.31 use, so the product path can be driven against the
    /// transport before anything is deployed.
    public static let shared: StudioSyncFollower = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["AW_TOGETHER_BASE"],
           let url = URL(string: raw) {
            return StudioSyncFollower(config: .init(base: url))
        }
        #endif
        return StudioSyncFollower()
    }()

    // MARK: Joining

    public func join(code typed: String, player: AVPlayer,
                     onFilm: @escaping (String) -> Void) async {
        status = .joining
        notice = nil
        self.player = player
        do {
            let state = try await client.join(code: typed)
            StudioRoomCopy.set(film: state.filmID, copy: state.copy)
            status = .following(code: (await client.code) ?? typed, filmID: state.filmID)
            followingSince = Date()
            onFilm(state.filmID)
            watchForGuestMoves(on: player)
            startFollowing()
            #if DEBUG
            // `AW_ROOM_GUEST_PAUSE=<s>`: the guest presses pause once, s
            // seconds in — a guest's own move, without a synthesized click.
            if let s = ProcessInfo.processInfo.environment["AW_ROOM_GUEST_PAUSE"].flatMap(Double.init) {
                Task { [weak player] in
                    try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
                    awdiag("AWFOLLOW door: the guest presses pause")
                    player?.pause()
                }
            }
            #endif
        } catch {
            let why = Self.sentence(for: error)
            status = .failed(why)
            // Said on the player: the film plays on alone, and a guest who
            // is not told would think they were watching with the room.
            notice = why
        }
    }

    /// Leave only if a room is actually being followed — a player going away
    /// calls this unconditionally, and `leave()` sets the rate of the player
    /// it last followed.
    public func leaveIfFollowing() {
        if case .idle = status { return }
        leave()
    }

    public func leave() {
        hereLoop?.cancel()
        loop?.cancel()
        loop = nil
        stopWatchingForGuestMoves()
        noticeClear?.cancel()
        notice = nil
        followingSince = .distantFuture
        player?.rate = Float(hostRate)
        Task { await client.leave() }
        StudioRoomCopy.clear()
        status = .idle
    }

    // MARK: The loop

    @ObservationIgnored private var hereLoop: Task<Void, Never>?

    /// A GUEST'S OWN pause or scrub is answered at once (§11.6.1). The
    /// player's controls stay — volume, captions, full screen are the
    /// guest's — so a guest can still press pause or drag the bar, and the
    /// room used to undo it on the next poll, up to ten seconds later. Same
    /// rule as the web's `follow`.
    private func watchForGuestMoves(on player: AVPlayer) {
        stopWatchingForGuestMoves()
        // A PAUSE is a PLAYING player stopping: `old > 0`, `new == 0`. The
        // first version fired on `rate == 0` alone, and a player starting up
        // reports exactly that — measured on the iPhone 12, 2026-09-24: "The
        // host controls the film." at the moment of joining, with nobody
        // having touched anything.
        rateObservation = player.observe(\.rate, options: [.old, .new]) { [weak self] _, change in
            let old = change.oldValue ?? 0, new = change.newValue ?? 0
            Task { @MainActor in
                guard let self, old > 0, new == 0 else { return }
                self.guestMoved()
            }
        }
        jumpObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.timeJumpedNotification, object: nil, queue: .main) { [weak self] note in
            guard (note.object as AnyObject?) === player.currentItem else { return }
            Task { @MainActor in self?.guestMoved() }
        }
    }

    private func stopWatchingForGuestMoves() {
        rateObservation?.invalidate(); rateObservation = nil
        if let jumpObserver { NotificationCenter.default.removeObserver(jumpObserver) }
        jumpObserver = nil
    }

    /// An event only RAISES the question; the answer is whether the guest
    /// is actually out of step. The player reports rate changes and time
    /// jumps of its own — loading, resuming, our own seeks landing late — and
    /// every event-shaped filter tried first still spoke over a guest who had
    /// touched nothing (iPhone 12, 2026-09-24). So a notice needs a
    /// correction that only a guest's move produces: paused while the host
    /// plays, or far enough off that the room must seek.
    private func guestMoved() {
        guard case .following = status,
              Date().timeIntervalSince(followingSince) > 5,
              seeksInFlight == 0,
              Date().timeIntervalSince(appliedAt) > 1.5 else { return }
        // A pause the HOST asked for is not the guest's.
        if let s = lastKnownState, s.paused { return }
        // Nor is the film reaching its end.
        if let item = player?.currentItem, item.duration.isNumeric,
           item.currentTime().seconds >= item.duration.seconds - 1 { return }
        Task { [weak self] in
            guard let self, let player = self.player else { return }
            let local = player.currentTime().seconds
            guard local.isFinite else { return }
            // Intent, not buffering: a stalled player still has a rate.
            guard let c = await self.client.correction(localPosition: local,
                                                       localPaused: player.rate == 0) else { return }
            switch c {
            case .seek, .setPaused:
                self.say("The host controls the film.", for: 3)
                self.lastCorrection = c
                self.apply(c, to: player)
            case .none, .nudge:
                return
            }
        }
    }

    private func say(_ text: String, for seconds: Double?) {
        noticeClear?.cancel()
        notice = text
        guard let seconds else { return }
        noticeClear = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    @ObservationIgnored private var lastKnownState: StudioSync.State?

    /// Says "I'm here" every 30 s so the host can see friends arrive — an
    /// anonymous token, new for each join (owner, 2026-09-23).
    private func startSayingHere() {
        hereLoop?.cancel()
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        hereLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.client.sayHere(token: token)
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private func startFollowing() {
        startSayingHere()
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = await self.client.nextPollDelay
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled { return }
                await self.tick()
            }
        }
    }

    private func tick() async {
        do { _ = try await client.poll() }
        catch {
            // A room that ended is not a failure to report as one — the host
            // finished, which is a normal way for this to stop.
            if case StudioSyncClient.JoinError.noSuchRoom = error { roomEnded(); return }
            if case StudioSyncClient.JoinError.ended = error { roomEnded(); return }
            // Anything else is transient: a poll that failed is a poll, not a
            // reason to tear a viewer out of a film. The next one will try.
            return
        }
        guard let player, let state = await client.lastState else { return }
        StudioRoomCopy.set(film: state.filmID, copy: state.copy)
        lastKnownState = state
        hostRate = state.rate

        let local = player.currentTime().seconds
        guard local.isFinite else { return }
        let isPlaying = player.timeControlStatus == .playing
        guard let correction = await client.correction(localPosition: local,
                                                       localPaused: !isPlaying) else { return }
        lastCorrection = correction
        #if DEBUG
        awdiag("AWFOLLOW local=%.1f playing=%@ correction=%@", local,
               isPlaying ? "y" : "n", "\(correction)")
        #endif
        apply(correction, to: player)
    }

    /// The host finished. The film keeps playing — it is the guest's now —
    /// and the guest is told, rather than left believing they are in step.
    private func roomEnded() {
        StudioRoomCopy.clear()
        status = .ended
        loop?.cancel(); hereLoop?.cancel()
        stopWatchingForGuestMoves()
        say("The host ended the room.", for: 8)
    }

    /// SILENTLY, and this is the whole of §11.2a in one function.
    private func apply(_ c: StudioSync.Correction, to player: AVPlayer) {
        switch c {
        case .seek, .setPaused: appliedAt = Date()
        default: break
        }
        switch c {
        case .none:
            // BACK TO THE HOST'S RATE, not to 1.0. A nudge left in place is a
            // film that plays 3% fast for the rest of the show, and the drift
            // it was correcting is already gone.
            if player.rate != 0, Double(player.rate) != hostRate {
                player.rate = Float(hostRate)
            }
        case .nudge(let multiplier):
            player.rate = Float(hostRate * multiplier)
        case .seek(let to):
            // Tolerances chosen so a seek lands where it was asked rather than
            // at the nearest keyframe — which on a long GOP can be seconds
            // away, i.e. the very error being corrected.
            //
            // AND AIMED AHEAD by how long a seek takes here. The host keeps
            // playing while this one seeks, so a seek to where the host WAS
            // lands behind: measured on an iPhone 12 joining a Studio room
            // (2026-09-23), 0.9 s behind, then ~30 s of a 3% nudge to catch
            // up. The lead is each device's own last measured seek time.
            // No lead onto a PAUSED frame: nothing moves while the seek runs,
            // and a lead would land past it and seek again every poll.
            let lead = player.rate == 0 ? 0 : seekLead * hostRate
            let started = Date()
            seeksInFlight += 1
            player.seek(to: CMTime(seconds: to + lead, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] done in
                let took = Date().timeIntervalSince(started)
                Task { @MainActor in
                    guard let self else { return }
                    self.seeksInFlight = max(0, self.seeksInFlight - 1)
                    guard done else { return }
                    // Our own seek's time-jump can land after it COMPLETES —
                    // measured 2.2 s after it started — so the "this was us"
                    // window runs from completion, not from the request.
                    self.appliedAt = Date()
                    self.seekLead = min(3, max(0, took))
                    #if DEBUG
                    awdiag("AWFOLLOW seek aimed +%.2fs, took %.2fs", lead, took)
                    #endif
                }
            }
        case .setPaused(let paused):
            if paused { player.pause() } else { player.rate = Float(hostRate) }
        }
    }

    // MARK: Words

    static func sentence(for error: Error) -> String {
        guard let e = error as? StudioSyncClient.JoinError else { return "\(error)" }
        switch e {
        case .badCode:
            return "That is not a room code. They are four characters — ask the host to read it again."
        case .noSuchRoom:
            return "No room with that code. It may have ended, or a character may have been misheard."
        case .ended:
            return "That room has ended."
        case .transport(let why):
            return "Could not reach the room — \(why)"
        }
    }
}
