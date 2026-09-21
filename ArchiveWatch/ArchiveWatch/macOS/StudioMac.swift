#if os(macOS)
import SwiftUI

// The Studio's health readout on macOS — macOS-DESIGN §B13d.
//
// Pinned top-leading OVER the player, deliberately outside AVPlayerView's own
// floating HUD (§B3a): the HUD auto-hides after a few seconds and health may
// never be hidden (docs/WATCH-TOGETHER.md §4). A host is responsible for a
// broadcast and cannot be responsible for something they cannot see.
//
// It also states the ONE current problem in words rather than as a chip. On a
// phone the capsule has a tap target to open a sheet; a Mac host is often
// looking at another window entirely, so the sentence has to be on the glass.

struct StudioMacReadout: View {
    let health: StudioHealth
    let filmFramesPerSecond: Int
    /// Camera frames in the last second — 0 while live, for a camera that HAS
    /// delivered, is the tile-went-dark signature.
    let cameraFramesPerSecond: Int
    let onEnd: () -> Void
    let onOpenControls: () -> Void

    private var isLive: Bool { health.showState.isOnAir }
    /// `Brand` is iOS-only; the Mac views spell the marquee orange out, as
    /// ChannelsView_macOS already notes.
    private let marquee = Color(hex: "#FF5C35") ?? .orange

    /// Same order as the tvOS readout: the show's own state first, because
    /// `notEncoding` outranks anything a counter can say (§9).
    private var problem: String? {
        if let d = health.showState.detail { return d }
        if isLive && filmFramesPerSecond == 0 { return "The film has stopped — your audience sees a still picture" }
        // A CAMERA THAT DIED MID-SHOW — the guard the television has carried
        // since 2026-09-19, when a Continuity camera ran a clean 30/s for ten
        // seconds and then stopped dead for eighty while every other number
        // stayed healthy. `cameraFramesReceived > 0` matters: between the
        // attach and the first delivered frame a camera is legitimately
        // attached at zero, and without it this flashes during every normal
        // start. The word is STOPPED, so it may only appear for a camera that
        // had started.
        // BEFORE the camera: an audience hearing nothing is worse off than an
        // audience not seeing the host. tvOS has shown this since §9.jjjj and
        // macOS asked for it nowhere.
        if isLive, let audio = StudioSession.shared.filmAudioProblem { return audio }
        if isLive, health.cameraAttached, health.cameraFramesReceived > 0,
           cameraFramesPerSecond == 0 {
            return "The camera has stopped — your audience sees the film without you"
        }
        if let f = health.encoderFault { return f }
        if health.thermalState == "critical" { return "This Mac is too hot to keep streaming" }
        if health.thermalState == "serious" { return "This Mac is getting hot" }
        if let e = health.publisher.lastError { return e }
        if health.publisher.videoFramesDropped > 30 { return "Dropping frames — the connection is struggling" }
        return nil
    }

    private var kbps: Int {
        let seconds = max(1, health.programFramesEncoded / 30)
        return max(0, health.encodedBytes * 8 / 1000 / seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle()
                    .fill(isLive ? Color.red : Color.secondary)
                    .frame(width: 9, height: 9)
                Text(health.showState.label)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                Divider().frame(height: 11)
                Text("\(kbps) kbps")
                    .font(.caption).monospacedDigit()
                Text("\(String(format: "%.1f", health.averageRenderMilliseconds)) ms")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
                Divider().frame(height: 11)
                Button("Controls", action: onOpenControls)
                    .font(.caption)
                    .buttonStyle(.borderless)
                Button("End", action: onEnd)
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .foregroundStyle(marquee)
            }
            // §5's adaptive step, on its OWN line rather than folded into
            // `problem`: "no destination is set" and "the picture is being
            // sent at 3600 instead of 6000 kbps" can both be true, and
            // whichever won a single slot would hide the other.
            if let note = health.qualityNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem {
                Text(problem)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // The width belongs to the CONTAINER, not to the problem text. With it
        // on the text, the two rows sized independently and the capsule drew
        // as a ragged two-tone box with "is set." hanging off a narrower
        // second tier (seen on the glass, macOS 27, 2026-09-17).
        .frame(width: 330, alignment: .leading)
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(.black.opacity(0.62), in: .rect(cornerRadius: 10))
        .padding(16)
    }
}

// The program PANEL that used to live here is gone: macOS-DESIGN §D1 replaced
// it with a real Studio window (`StudioWindow_macOS.swift`). A sheet is modal
// to one window and disappears when the player goes full-screen, which is
// exactly when a host most needs the controls — and it cannot hold a preview,
// an input list and a mixer at once.
#endif
