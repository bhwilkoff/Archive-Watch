#if os(tvOS)
import SwiftUI

/// JOIN A ROOM on the television — SHAREPLAY §11.9.
///
/// This is the device the owner's own case is about: on a call on a laptop,
/// watching the film on the big screen. §11.10 is what makes it possible —
/// Decision 132 gates HOSTING on a camera and a microphone, and a television
/// has neither; joining needs neither, because a joiner contributes nothing
/// to the programme.
///
/// **No keyboard.** tvOS's `TextField` raises the system keyboard, which is a
/// grid a person drives one character at a time with a remote — for four
/// characters read aloud on a call, that is the wrong instrument. This is a
/// focus grid of the alphabet itself: press a character, it appends; the code
/// completes at four and joins. Rule 8.8's ten-foot constraint, and the same
/// reasoning Decision 119 used for codes in the other direction.
struct JoinRoomTV: View {
    @Environment(Router.self) private var router
    @Environment(AppStore.self) private var store

    @State private var typed = ""
    @State private var problem: String?
    @State private var working = false
    @FocusState private var focused: String?

    /// The alphabet, in rows a remote can cross without thinking. Eight wide
    /// so the grid is four rows — a full sweep is never more than a few
    /// presses from anywhere.
    private let rows: [[Character]] = {
        let all = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        return stride(from: 0, to: all.count, by: 8).map { Array(all[$0..<min($0 + 8, all.count)]) }
    }()

    var body: some View {
        VStack(spacing: 34) {
            VStack(spacing: 10) {
                Text("Watch Together").font(.largeTitle.bold())
                // WHAT THIS DEVICE CAN DO, and nothing else. Owner: "You
                // shouldn't advertise features that don't exist on the
                // platform you are currently on, but you should definitely be
                // able to share what the current platform can do." An Apple TV
                // can broadcast (it borrows an iPhone as camera and mic) and
                // can join; it cannot START a SharePlay call and cannot mix a
                // call's audio, and neither absence is mentioned, because an
                // explanation of something unavailable is still an advert for
                // it.
                Text(WatchTogetherHere.summary)
                    .font(.title3).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
                Text("Ask the host to read out their four-character code.")
                    .font(.title3).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
            }

            // The code so far, as four slots. Empty slots are drawn rather
            // than implied: from a sofa, "how many more do I type" must be
            // answerable at a glance.
            HStack(spacing: 18) {
                ForEach(0..<StudioRoom.codeLength, id: \.self) { i in
                    let ch = i < typed.count
                        ? String(Array(typed)[i]) : ""
                    Text(ch.isEmpty ? " " : ch)
                        .font(.system(size: 78, weight: .bold, design: .monospaced))
                        .frame(width: 96, height: 120)
                        .background(.white.opacity(ch.isEmpty ? 0.06 : 0.14),
                                    in: .rect(cornerRadius: 14))
                }
            }

            if let problem {
                Text(problem).font(.title3).foregroundStyle(.orange)
                    .multilineTextAlignment(.center).frame(maxWidth: 900)
            }
            if working { ProgressView().scaleEffect(1.4) }

            VStack(spacing: 14) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 14) {
                        ForEach(rows[r], id: \.self) { ch in
                            Button {
                                append(ch)
                            } label: {
                                Text(String(ch))
                                    .font(.system(size: 34, weight: .semibold, design: .monospaced))
                                    .frame(width: 84, height: 74)
                            }
                            // NEVER `.plain` on tvOS — it destroys focusability
                            // (CLAUDE.md). `.borderless` keeps the focus halo.
                            .buttonStyle(.borderless)
                            .focused($focused, equals: String(ch))
                        }
                    }
                }
                HStack(spacing: 20) {
                    Button("Delete") { if !typed.isEmpty { typed.removeLast(); problem = nil } }
                        .buttonStyle(.borderless)
                        .disabled(typed.isEmpty)
                    Button("Cancel") { router.tab = .home }
                        .buttonStyle(.borderless)
                }
                .padding(.top, 6)
            }
        }
        .padding(60)
        .onAppear { focused = "0" }
    }

    private func append(_ ch: Character) {
        guard typed.count < StudioRoom.codeLength else { return }
        problem = nil
        typed.append(ch)
        if typed.count == StudioRoom.codeLength { attempt() }
    }

    private func attempt() {
        guard let code = StudioRoom.normalize(typed) else {
            problem = "That is not a room code."
            typed = ""
            return
        }
        working = true
        Task {
            let client = StudioSyncClient()
            do {
                let state = try await client.join(code: code)
                await client.leave()
                working = false
                guard let item = store.db?.item(state.filmID) else {
                    problem = "That room is watching a film this Apple TV does not have in its catalogue yet."
                    typed = ""
                    return
                }
                // The player is where an AVPlayer exists, so the code is
                // handed over rather than followed here — the same shape the
                // Mac uses.
                RoomJoinTV.shared.pending = code
                // tvOS navigates to DETAIL and the host presses Play — the
                // platform's own shape, rather than dropping someone into a
                // player they did not ask to open. The code is held until an
                // `AVPlayer` exists.
                router.tab = .home
                router.push(item)
            } catch {
                working = false
                problem = StudioSyncFollower.sentence(for: error)
                typed = ""
            }
        }
    }
}

/// The hand-off from this screen to the player, which is the one place an
/// `AVPlayer` exists. A value rather than a notification: two surfaces, one
/// hand-off, nothing to unsubscribe.
@MainActor
final class RoomJoinTV {
    static let shared = RoomJoinTV()
    var pending: String?
    private init() {}
}
#endif
