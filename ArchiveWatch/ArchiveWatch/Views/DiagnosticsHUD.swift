#if os(tvOS)
import SwiftUI

// Reusable on-screen + console diagnostics (Phase 0 F3, tvOS-DESIGN debugging
// philosophy). We kept hand-rolling a green monospaced overlay for playback
// investigations; this generalizes it so any view can surface live key/value
// state during a sim/device investigation, and mirror it to the console for the
// owner's copy-paste workflow.
//
// Usage:
//   AWDiagnostics.enabled = true                      // flip on while investigating
//   SomeView().diagnostics("player") { [             // attach to any view
//       "ahead=\(ahead)s", "stalls=\(stalls)"
//   ] }
//
// Off by default so it never ships visible. Strip the .diagnostics call (or leave
// it — it's inert when disabled) before declaring a fix complete.
enum AWDiagnostics {
    /// Master switch. Off by default; set true during an investigation.
    /// MainActor-isolated: it's only ever read from the `.diagnostics()` view modifier (UI).
    @MainActor static var enabled = false
}

struct DiagnosticsHUD: View {
    let tag: String
    let interval: TimeInterval
    let lines: () -> [String]

    @State private var snapshot: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tag.uppercased())
                .font(.system(size: 20, weight: .bold, design: .monospaced))
            ForEach(snapshot, id: \.self) { line in
                Text(line).font(.system(size: 22, design: .monospaced))
            }
        }
        .foregroundStyle(.green)
        .padding(16)
        .background(.black.opacity(0.65), in: .rect(cornerRadius: 12))
        .allowsHitTesting(false)
        .onAppear { refresh() }
        // Native structured-concurrency refresh (replaces a Combine Timer.publish): cancelled on disappear.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { break }
                refresh()
            }
        }
    }

    private func refresh() {
        let current = lines()
        snapshot = current
        // Mirror to the console (grep "[AWDiag:") for the owner's paste workflow.
        print("[AWDiag:\(tag)] " + current.joined(separator: " | "))
    }
}

extension View {
    /// Overlay a live diagnostics panel when `AWDiagnostics.enabled` is on.
    /// Inert (zero overhead, nothing rendered or printed) when disabled.
    @ViewBuilder
    func diagnostics(_ tag: String,
                     interval: TimeInterval = 1,
                     alignment: Alignment = .topLeading,
                     _ lines: @escaping () -> [String]) -> some View {
        overlay(alignment: alignment) {
            if AWDiagnostics.enabled {
                DiagnosticsHUD(tag: tag, interval: interval, lines: lines)
                    .padding(60)
            }
        }
    }
}

#endif
