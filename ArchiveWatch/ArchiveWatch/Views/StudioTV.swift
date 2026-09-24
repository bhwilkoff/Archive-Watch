#if os(tvOS)
import AVFoundation
import SwiftUI

// The Studio at ten feet — tvOS-DESIGN §8.8: the player plus overlays.
//
// Everything here is sized for a television and a couch, which is a different
// problem from the phone's capsule: nobody leans in to read a bitrate on a TV,
// and there is no touch target to tap for detail. So the readout is LARGER,
// carries fewer numbers, and states a problem in words rather than a chip —
// §4's 29pt floor is a minimum, not a target, and this sits well above it.
//
// It is also anchored inside the 90×60 safe area (§6.1): a television overscans,
// and a health readout the viewer's TV has cropped away is worse than none,
// because the host believes they can see it.
struct StudioTVHealth: View {
    let health: StudioHealth
    let filmFramesPerSecond: Int
    /// The film HAS sound and it is not reaching the broadcast (§9.jjjj).
    /// Distinct from a silent film, which is normal here and says nothing.
    var audioProblem: String? = nil
    /// Camera frames in the last second. Mirrors `filmFramesPerSecond`: a
    /// counter that stops climbing is the only evidence a capture session has
    /// died, and on 2026-09-19 one died ten seconds into a Twitch broadcast
    /// while every other number stayed healthy and the screen said nothing.
    var cameraFramesPerSecond: Int = 0
    /// The host paused the film (the transport's play/pause, Rule 8.8c) — a
    /// still is then their choice, and "the film has stopped" would read as a
    /// fault on the television across the room.
    var filmPausedByHost = false

    private var isLive: Bool { health.showState.isOnAir }

    /// The single most important thing wrong, or nil. One line, because a
    /// viewer across a room reads one line.
    private var problem: String? {
        if let d = health.showState.detail { return d }
        // THE FILM ENDING OUTRANKS "the film has stopped": at that moment both
        // are true and only one is the reason, and "stopped" implies a fault
        // that is not there (owner item 13, §9.bbbbbb).
        if isLive && health.filmEnded {
            return "The film has ended — your audience sees a still. You are still on air."
        }
        if isLive && filmFramesPerSecond == 0 && !filmPausedByHost { return "The film has stopped — your audience sees a still picture" }
        if health.thermalState == "critical" { return "This Apple TV is too hot to keep streaming" }
        if health.thermalState == "serious" { return "This Apple TV is getting hot" }
        if let e = health.publisher.lastError { return e }
        // Above the frame-drop note: an audience that hears nothing at all is
        // worse off than one seeing a few dropped frames, and this one is
        // silent by construction rather than by congestion.
        if let audioProblem { return audioProblem }
        // A CAMERA THAT DIED MID-SHOW. Only ever true when one was attached,
        // so a film-only broadcast never sees it. Measured 2026-09-19: a
        // Continuity camera delivered a clean 30/s for ten seconds and then
        // stopped dead for the remaining eighty, and nothing on any surface
        // said so — the publisher was healthy, the film was fine, and the
        // host's audience was simply watching the film without them.
        // `cameraFramesReceived > 0` matters: between the attach and the first
        // delivered frame there is a second or two where a camera is attached
        // and its rate is legitimately zero, and without this the readout
        // flashes "stopped" during every normal start. The word is STOPPED, so
        // it may only appear for a camera that had started.
        if isLive, health.cameraAttached, health.cameraFramesReceived > 0,
           cameraFramesPerSecond == 0 {
            return "The camera has stopped — your audience sees the film without you"
        }
        if health.publisher.videoFramesDropped > 30 { return "Dropping frames — the connection is struggling" }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Circle()
                    .fill(isLive ? Color.red : Color.gray)
                    .frame(width: 18, height: 18)
                Text(health.showState.label)
                    .font(.system(size: 34, weight: .bold))
                Text("\(kbps) kbps")
                    .font(.system(size: 30, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
                // §D27 — how many are watching, once the platform says so.
                if let n = StudioSession.shared.audienceCount {
                    Label(n == 1 ? "1 watching" : "\(n.formatted()) watching",
                          systemImage: "person.2.fill")
                        .font(.system(size: 30, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            // §6.2, DEBUG only. The session's category is the one thing a
            // screenshot cannot otherwise show, and §6.2 could only ever be
            // verified by ABSENCE without it — no error meant nothing known.
            // A failed activation silently stops AVPlayer (§9), so what the
            // session actually IS belongs on the glass while it is being
            // proved. Not shipped: a host has no use for it.
            #if DEBUG
            Text("audio: \(health.audioSessionState)")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            // A television cannot reach the bench destination that gates the
            // machine-readable health line (owner item 8a), so the encoder's
            // identity is put on the GLASS where a screenshot can read it.
            Text("encoder: \(health.encoderIsHardware.map { $0 ? "hardware" : "SOFTWARE" } ?? "-")")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            #endif
            // §5's adaptive step, on its OWN line.
            //
            // Not folded into `problem`, because they are different facts: "no
            // destination is set" and "the picture is being sent at 3600
            // instead of 6000 kbps" can both be true, and whichever won a
            // single slot would hide the other. §4 says health is never
            // hidden, and a ten-foot readout has the room — the
            // one-chip-only rule is an iPhone constraint, where the capsule
            // truncates.
            if let note = health.qualityNote {
                HStack(spacing: 10) {
                    Image(systemName: "speedometer")
                    Text(note)
                }
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            }
            if let problem {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(problem)
                }
                .font(.system(size: 29, weight: .medium))     // §4's floor
                // Marquee orange, the brand's own accent — chrome, not
                // content meaning (CLAUDE.md's split). tvOS has no `Brand`
                // helper; the rest of this target uses Color(hex:).
                .foregroundStyle(Color(hex: "#FF5C35") ?? .orange)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 32).padding(.vertical, 22)
        .background(.black.opacity(0.62), in: .rect(cornerRadius: 18))
        // 90 × 60 safe area (§6.1) — a TV crops, and a readout the host
        // cannot see is worse than none.
        .padding(.leading, 90).padding(.top, 60)
    }

    private var kbps: Int {
        // The last seconds, not the whole show (see `encodedKbpsRecent`).
        if health.encodedKbpsRecent > 0 { return health.encodedKbpsRecent }
        let seconds = max(1, health.programFramesEncoded / max(1, StudioOutputSettings.frameRate))
        return max(0, health.encodedBytes * 8 / 1000 / seconds)
    }
}
#endif
