import Foundation

/// WHAT "WATCH TOGETHER" MEANS ON *THIS* DEVICE — one answer, derived once.
///
/// Owner, 2026-09-21: *"let's make it super clear what 'Watch Together' means
/// on each platform (to the user). You shouldn't advertise features that don't
/// exist on the platform you are currently on, but you should definitely be
/// able to share what the current platform can do."*
///
/// That sharpens Decision 131. 131 said every surface must state which of the
/// three modes a device can do **and why it cannot do the others** — so a
/// television explained its own absences. The owner's rule is narrower and
/// better: **do not put a feature in front of somebody who cannot use it.**
/// An explanation of something unavailable is still an advertisement for it,
/// and on a device that will never gain the hardware it is just a list of
/// things this box is worse at.
///
/// It is a TYPE rather than a paragraph per platform because editorial rules
/// drift: five surfaces each describing the feature in their own words is five
/// chances to promise something. Here a surface asks what is true and renders
/// only that.
public enum WatchTogetherHere {

    public struct Mode: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let detail: String
        public let systemImage: String
    }

    /// Can this device HOST a broadcast — camera, microphone, an encoder?
    public static var canBroadcast: Bool {
        #if os(macOS) || os(iOS)
        return true
        #elseif os(tvOS)
        // A television has no camera of its own and borrows an iPhone through
        // Continuity, which is a real capability rather than a workaround.
        return true
        #else
        return false
        #endif
    }

    /// Can this device start a SharePlay call with the film in sync?
    public static var canSharePlay: Bool {
        #if os(macOS) || os(iOS)
        return true
        #else
        // tvOS has no `GroupActivitySharingController`: it can JOIN a
        // SharePlay session and cannot start the call.
        return false
        #endif
    }

    /// Can this device mix a call's audio into the broadcast — the third
    /// mode? Only where `AudioHardwareCreateProcessTap` exists.
    public static var canMixACall: Bool {
        #if os(macOS)
        if #available(macOS 14.2, *) { return true }
        return false
        #else
        return false
        #endif
    }

    /// Can this device JOIN somebody else's room? Everything can: a joiner
    /// contributes nothing to the programme (§11.10).
    public static var canJoinARoom: Bool { true }

    /// ONLY what is true here. Nothing is listed to be crossed out.
    public static var modes: [Mode] {
        var out: [Mode] = []
        if canSharePlay {
            out.append(Mode(
                id: "friends", title: "With Friends",
                detail: "A SharePlay call with the film in sync for everyone. Start it from the player.",
                systemImage: "person.2"))
        }
        if canBroadcast {
            out.append(Mode(
                id: "world", title: "With the World",
                detail: "A live broadcast to YouTube or Twitch, with your camera and microphone over the film.",
                systemImage: "dot.radiowaves.left.and.right"))
        }
        if canMixACall {
            out.append(Mode(
                id: "both", title: "With Friends and the World",
                detail: "Your call with friends — Zoom, Meet, FaceTime — mixed into the broadcast, with a room so they watch in step.",
                systemImage: "person.3"))
        }
        if canJoinARoom {
            out.append(Mode(
                id: "join", title: "Join someone's room",
                detail: "Enter a host's code and the film plays here in step with their broadcast.",
                systemImage: "person.badge.plus"))
        }
        return out
    }

    /// One sentence for the top of a Watch Together surface, true of THIS
    /// device and no other.
    public static var summary: String {
        if canMixACall {
            return "Watch a public-domain film with other people: on a call, with an audience, or both."
        }
        if canBroadcast {
            return "Broadcast a public-domain film with your camera and microphone, or join someone's room and watch in step."
        }
        return "Join someone's room and watch a public-domain film in step with them."
    }
}
