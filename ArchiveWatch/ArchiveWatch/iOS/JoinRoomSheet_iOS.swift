#if os(iOS)
import SwiftUI

/// JOIN A ROOM on the phone — SHAREPLAY §11.9.
///
/// **Why a toolbar item on Library and not a sixth segment.** §11.9 says the
/// Library surface, and Library's scope picker is already at its measured
/// limit: the code there records that at five scopes on a 390pt screen
/// "Downloads" rendered as "Downloa…", which is why that label became
/// "Offline". A sixth segment would break a constraint somebody already
/// measured. The toolbar is the surface's other affordance and costs no width.
///
/// **Not Settings** (§11.9): joining is a thing you DO, not a way the app
/// behaves.
struct JoinRoomButton_iOS: View {
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "person.2.wave.2")
        }
        .accessibilityLabel("Join a Watch Together room")
        .sheet(isPresented: $showing) { JoinRoomSheet_iOS() }
    }
}

struct JoinRoomSheet_iOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var typed = ""
    @State private var problem: String?
    @State private var working = false
    @FocusState private var focused: Bool

    private var canJoin: Bool { StudioRoom.normalize(typed) != nil && !working }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // What THIS device can do, derived rather than written, so
                // no surface can drift into advertising what it has not got.
                Text(WatchTogetherHere.summary)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Text("Enter the code your host reads out. The film plays here in step with theirs.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                TextField("Code", text: $typed)
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    // A code is Base32, so a full keyboard offers letters the
                    // alphabet does not contain and autocorrect would happily
                    // rewrite four characters into a word.
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onChange(of: typed) { _, new in
                        let cleaned = new.uppercased().filter { !$0.isWhitespace && $0 != "-" }
                        typed = String(cleaned.prefix(StudioRoom.codeLength))
                        problem = nil
                    }
                    .padding(.horizontal, 40)

                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(.orange)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }
                if working { ProgressView() }
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Join a room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") { attempt() }.disabled(!canJoin)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func attempt() {
        guard let code = StudioRoom.normalize(typed) else { return }
        working = true
        Task {
            let client = StudioSyncClient()
            do {
                let state = try await client.join(code: code)
                await client.leave()
                working = false
                guard let item = store.db?.item(state.filmID) else {
                    problem = "That room is watching a film this device does not have in its catalog yet."
                    return
                }
                // The player is where an `AVPlayer` exists, so the code waits
                // there — the same hand-off macOS and tvOS use.
                RoomJoin_iOS.shared.pending = code
                dismiss()
                router.push(item)
            } catch {
                working = false
                problem = StudioSyncFollower.sentence(for: error)
            }
        }
    }
}

@MainActor
final class RoomJoin_iOS {
    static let shared = RoomJoin_iOS()
    var pending: String?
    private init() {}
}
#endif
