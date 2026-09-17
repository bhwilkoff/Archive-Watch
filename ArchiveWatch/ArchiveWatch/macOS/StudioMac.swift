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
    let onEnd: () -> Void

    private var isLive: Bool { health.showState.isOnAir }
    /// `Brand` is iOS-only; the Mac views spell the marquee orange out, as
    /// ChannelsView_macOS already notes.
    private let marquee = Color(hex: "#FF5C35") ?? .orange

    /// Same order as the tvOS readout: the show's own state first, because
    /// `notEncoding` outranks anything a counter can say (§9).
    private var problem: String? {
        if let d = health.showState.detail { return d }
        if isLive && filmFramesPerSecond == 0 { return "The film has stopped — your audience sees a still picture" }
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
                Button("End", action: onEnd)
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .foregroundStyle(marquee)
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
#endif
