import Foundation
import AVFoundation

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
    public private(set) var lastCorrection: StudioSync.Correction?

    private let client: StudioSyncClient
    private weak var player: AVPlayer?
    private var loop: Task<Void, Never>?
    /// The rate the host says, so a nudge can be undone to the RIGHT value
    /// rather than to a hardcoded 1.0 — a host watching at 1.25 would
    /// otherwise be silently corrected to normal speed every few seconds.
    private var hostRate: Double = 1.0

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
        self.player = player
        do {
            let state = try await client.join(code: typed)
            status = .following(code: (await client.code) ?? typed, filmID: state.filmID)
            onFilm(state.filmID)
            startFollowing()
        } catch {
            status = .failed(Self.sentence(for: error))
        }
    }

    public func leave() {
        loop?.cancel()
        loop = nil
        player?.rate = Float(hostRate)
        Task { await client.leave() }
        status = .idle
    }

    // MARK: The loop

    private func startFollowing() {
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
            if case StudioSyncClient.JoinError.noSuchRoom = error { status = .ended; loop?.cancel(); return }
            if case StudioSyncClient.JoinError.ended = error { status = .ended; loop?.cancel(); return }
            // Anything else is transient: a poll that failed is a poll, not a
            // reason to tear a viewer out of a film. The next one will try.
            return
        }
        guard let player, let state = await client.lastState else { return }
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

    /// SILENTLY, and this is the whole of §11.2a in one function.
    private func apply(_ c: StudioSync.Correction, to player: AVPlayer) {
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
            player.seek(to: CMTime(seconds: to, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
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
