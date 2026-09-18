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

    private var isLive: Bool { health.showState.isOnAir }

    /// The single most important thing wrong, or nil. One line, because a
    /// viewer across a room reads one line.
    private var problem: String? {
        if let d = health.showState.detail { return d }
        if isLive && filmFramesPerSecond == 0 { return "The film has stopped — your audience sees a still picture" }
        if health.thermalState == "critical" { return "This Apple TV is too hot to keep streaming" }
        if health.thermalState == "serious" { return "This Apple TV is getting hot" }
        if let e = health.publisher.lastError { return e }
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
            #endif
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
        let seconds = max(1, health.programFramesEncoded / 30)
        return max(0, health.encodedBytes * 8 / 1000 / seconds)
    }
}
#endif
