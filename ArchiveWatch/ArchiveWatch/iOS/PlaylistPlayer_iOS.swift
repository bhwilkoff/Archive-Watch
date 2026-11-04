#if os(iOS)
import SwiftUI

/// One run through a playlist: its titles in the order they will play.
struct PlaylistRun: Identifiable {
    let id = UUID()
    let items: [Catalog.Item]
    let start: Int
}

/// A playlist played like a series (§4.3b, the §8.5 capsule). Previous and Next
/// rebuild the player through `.id`, as an episode does; each title keeps its
/// own place in watch history.
struct PlaylistPlayerContainer: View {
    let run: PlaylistRun
    @State private var index: Int
    @State private var handle = PlayerHandle()
    @State private var chrome = PlayerChromeTimer()
    @State private var unplayable: String?
    @Environment(\.dismiss) private var dismiss

    init(run: PlaylistRun) {
        self.run = run
        _index = State(initialValue: run.start)
    }

    private var hasPrev: Bool { index > 0 }
    private var hasNext: Bool { index + 1 < run.items.count }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PlayerView(playlist: run.items, at: index, onUnplayable: { message in
                if hasNext { step(1) } else { unplayable = message }
            }, onFinished: { dismiss() }) { _ in
                if hasNext { index += 1 }
            }
            .controlled(by: handle)
            .onTapVideo { chrome.toggle() }
            .id("\(index)-\(run.items[index].archiveID)")
            .ignoresSafeArea()
            PlayerChrome(timer: chrome) {
                HStack(spacing: 10) {
                    CaptionChoiceCapsule(handle: handle)
                    if run.items.count > 1 {
                        HStack(spacing: 18) {
                            Button { step(-1) } label: { Image(systemName: "backward.end.fill") }
                                .disabled(!hasPrev)
                                .accessibilityLabel("Previous")
                            Text(PlaylistPlay.position(index, of: run.items.count))
                                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                            Button { step(1) } label: { Image(systemName: "forward.end.fill") }
                                .disabled(!hasNext)
                                .accessibilityLabel("Next")
                        }
                        .font(.body)
                        .tint(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.black.opacity(0.45), in: .capsule)
                    }
                }
            }
        }
        .alert("Can't play this title", isPresented: Binding(
            get: { unplayable != nil }, set: { if !$0 { unplayable = nil } })) {
            Button("OK") { unplayable = nil }
        } message: {
            Text(unplayable ?? "")
        }
    }

    private func step(_ by: Int) {
        let target = index + by
        guard run.items.indices.contains(target) else { return }
        index = target
        chrome.show()
    }
}
#endif
