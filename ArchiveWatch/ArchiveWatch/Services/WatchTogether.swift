import AVFoundation
import Combine
import Foundation
import GroupActivities

// SharePlay — watching the same film together, in sync, across Apple devices.
//
// This app is an unusually clean fit for SharePlay: the catalog is public
// domain, served by archive.org, identical for every participant, with no
// account, no DRM and no regional licensing. There is no access check to write
// — if a peer has the app, they can play the film.
//
// The one thing that needed care is our own architecture. Every title plays
// through a private `aw-stream://` URL (Decision 072), so two participants
// almost never hold the same URL — and may not even hold the same archive.org
// copy, since Decision 077 can fall back to a different one mid-film. Apple
// documents this exact case on `identifierForPlayerItem`: it exists "to
// establish identity of two items created from different URLs". We answer with
// the archiveID, which is stable across both the custom scheme and a copy swap.
//
// Note this is NOT the AirPlay situation (Decision 051). There, the receiver
// must fetch the media itself, so a private scheme is unusable and we swap in a
// published URL. Coordination only exchanges rate and time; each participant
// loads its own asset locally, through whatever loader it likes.

struct WatchTogetherActivity: GroupActivity {
    static let activityIdentifier = "org.archivewatch.watchtogether"

    let archiveID: String
    let title: String
    let year: Int?

    var metadata: GroupActivityMetadata {
        get async {
            var m = GroupActivityMetadata()
            m.type = .watchTogether
            m.title = title
            m.subtitle = year.map { "\($0) · Archive Watch" } ?? "Archive Watch"
            // Lets a session started on an iPhone move to the Apple TV, which is
            // the flow this app is actually for — the phone is the remote, the
            // TV is the screen.
            m.supportsContinuationOnTV = true
            m.fallbackURL = URL(string: "https://archivewatch.org/item/\(archiveID)")
            return m
        }
    }
}

@MainActor
@Observable
final class WatchTogether {
    static let shared = WatchTogether()
    private init() {}

    private(set) var session: GroupSession<WatchTogetherActivity>?
    /// The film the active session is watching, or nil when not in one.
    private(set) var sharedArchiveID: String?
    /// A film a freshly-joined session wants opened. Each platform's root view
    /// observes this and routes; call `consumePendingJoin()` once it has.
    /// tvOS additionally gets the existing `IntentInbox` request, so it reuses
    /// the Top Shelf's already-exercised play routing.
    private(set) var pendingJoin: String?
    var isSharing: Bool { session != nil }

    func consumePendingJoin() { pendingJoin = nil }

    private let identity = CoordinatedItemIdentity()
    private var listening = false
    private var stateTask: Task<Void, Never>?
    /// The player currently attached, so a session that arrives while a film is
    /// already playing can be coordinated immediately rather than waiting for
    /// the next player build.
    private weak var attachedPlayer: AVPlayer?
    /// Set when WE start the session. The activation also comes back through
    /// `sessions()`, and without this the initiator would re-route to the film
    /// it is already watching and restart it.
    private var locallySharedArchiveID: String?

    /// Start listening for sessions other people begin. Call once at launch.
    func listen() {
        guard !listening else { return }
        listening = true
        Task { [weak self] in
            for await session in WatchTogetherActivity.sessions() {
                self?.adopt(session)
            }
        }
    }

    /// Offer this film to the current FaceTime/Messages group. Returns false when
    /// the user is not in a call, or declines — both are ordinary, not errors.
    @discardableResult
    func share(archiveID: String, title: String, year: Int?) async -> Bool {
        let activity = WatchTogetherActivity(archiveID: archiveID, title: title, year: year)
        // Apple's documented flow: ask first, and only activate when the system
        // says activation is preferred. `.activationDisabled` simply means the
        // user is not in a FaceTime call — ordinary, not an error.
        switch await activity.prepareForActivation() {
        case .activationPreferred:
            locallySharedArchiveID = archiveID
            let ok = (try? await activity.activate()) ?? false
            if !ok { locallySharedArchiveID = nil }
            return ok
        default:
            return false
        }
    }

    /// Attach the MAIN player to the session.
    ///
    /// NEVER pass the caption scout here. Live captions run a second, muted
    /// player ahead at 2x (Decisions 058/069/072); coordinating it would drag
    /// the whole group to 2x. Captions stay a local concern on every device.
    ///
    /// Safe to call on every player build: a player rebuilt by the Decision-077
    /// fallback brings a NEW coordinator that has to be re-attached, and it
    /// keeps the same archiveID so the group still considers it the same film.
    func attach(_ player: AVPlayer, archiveID: String) {
        identity.archiveID = archiveID
        attachedPlayer = player
        player.playbackCoordinator.delegate = identity
        guard let session else { return }
        player.playbackCoordinator.coordinateWithSession(session)
    }

    /// A stall on our side should make the group WAIT rather than drift. Bracket
    /// the recovery: begin when playback stalls, end when it resumes.
    func beginStallSuspension(_ player: AVPlayer) -> AVCoordinatedPlaybackSuspension? {
        guard session != nil else { return nil }
        return player.playbackCoordinator
            .beginSuspension(for: .stallRecovery)
    }

    func leave() {
        session?.leave()
        session = nil
        sharedArchiveID = nil
        stateTask?.cancel()
        stateTask = nil
    }

    private func adopt(_ s: GroupSession<WatchTogetherActivity>) {
        session = s
        sharedArchiveID = s.activity.archiveID

        // A session we started ourselves also arrives here. We are already on
        // that film, so routing again would restart it.
        let weStartedThis = (s.activity.archiveID == locallySharedArchiveID)
        locallySharedArchiveID = nil

        // Apple's documented order is: configure the player's coordinator, then
        // join. When a film is already on screen we can do that right now;
        // otherwise `attach` does it when the player is built.
        if let p = attachedPlayer, identity.archiveID == s.activity.archiveID {
            p.playbackCoordinator.coordinateWithSession(s)
        }

        // Only a JOINER needs routing; the initiator is already on the film and
        // re-routing would restart it. Everything below this point (state
        // observation, join) applies to both, so the skip is scoped to routing
        // rather than being an early return.
        if !weStartedThis {
            pendingJoin = s.activity.archiveID
            #if os(tvOS)
            // `playItem` is the same request the Top Shelf's Play button uses,
            // so tvOS routing already exists and is already exercised.
            // IntentInbox is tvOS-only, which is why the cross-platform hook
            // above exists at all.
            IntentInbox.shared.request = .playItem(s.activity.archiveID)
            #endif
        }

        stateTask?.cancel()
        stateTask = Task { [weak self] in
            for await state in s.$state.values {
                if case .invalidated = state {
                    self?.session = nil
                    self?.sharedArchiveID = nil
                    return
                }
            }
        }
        s.join()
    }
}

/// Establishes that two player items are the same film even when their URLs
/// differ. Ours is always a private `aw-stream://` URL; a peer's may be a plain
/// https URL, or a different archive.org copy of the same title.
///
/// The callback can arrive off the main actor, so the value is lock-guarded
/// rather than actor-isolated.
private final class CoordinatedItemIdentity: NSObject, AVPlayerPlaybackCoordinatorDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _archiveID: String?

    var archiveID: String? {
        get { lock.withLock { _archiveID } }
        set { lock.withLock { _archiveID = newValue } }
    }

    func playbackCoordinator(_ coordinator: AVPlayerPlaybackCoordinator,
                             identifierFor playerItem: AVPlayerItem) -> String {
        // Falling back to a per-item UUID means "this is not the same content",
        // which is the correct failure: better a group that refuses to sync than
        // one that syncs two different films.
        archiveID ?? UUID().uuidString
    }
}
