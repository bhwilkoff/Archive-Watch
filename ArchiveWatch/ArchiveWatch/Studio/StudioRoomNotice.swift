import SwiftUI

/// The guest's one line in a room (SHAREPLAY §11.6.1), over the film on
/// macOS, iOS and tvOS. Reads `StudioSyncFollower.notice`; draws nothing
/// while a guest is simply in step.
struct StudioRoomNotice: View {
    var body: some View {
        if let text = StudioSyncFollower.shared.notice {
            Text(text)
                #if os(tvOS)
                .font(.callout)
                .padding(.horizontal, 28).padding(.vertical, 14)
                #else
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 8)
                #endif
                .foregroundStyle(.white)
                .background(.black.opacity(0.75), in: Capsule())
                .accessibilityAddTraits(.updatesFrequently)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }
}
