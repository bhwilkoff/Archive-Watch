// The television's go-live confirmation (tvOS-DESIGN Rule 8.8a).
//
// Rule 8.8a, binding since the owner answered its three open questions on
// 2026-09-18: "the 'with the world' menu item opens a FOCUS-DRIVEN
// confirmation, not a form. It states the film, the destination platform, and
// §3.4a's warning, and its default action goes live."
//
// What the owner's answers changed, against what this document recommended:
//
//   1. The title IS editable here. The recommendation was pre-filled only —
//      a remote keyboard is the worst text-entry surface in the house — and
//      the owner's answer was that never offering it is the worse cost. So
//      the field is focusable and pre-filled from the catalog's own audited
//      record (Decision 124): the default still costs no typing.
//   2. `unlisted` stays the default, matching iPhone.
//   3. Sign-in happens ON the television. tvOS no longer refuses and points
//      at another device, which is why `StudioSignInRow` is here rather than
//      a sentence explaining that this is a phone's job.
//
// WHY THE WARNING IS ON THIS SCREEN rather than in the alert that used to
// carry it: that alert existed because "a television has no moment where Go
// Live is pressed, so it asks". It has one now. Two copies of the same
// paragraph back to back would be worse than either, and iOS and macOS both
// render it on the surface itself.

#if os(tvOS)
import SwiftUI

struct GoLiveTV: View {

    let film: Catalog.Item
    /// Called with a complete request. The caller starts the Studio; this
    /// view never touches the engine, the player or the Keychain.
    let onGoLive: (GoLiveRequest) -> Void
    let onCancel: () -> Void

    /// The platforms this BUILD can reach at all — one client id, one entry.
    /// A host is never shown a choice that cannot be taken (§10.2b): with a
    /// single configured platform there is no choice to make and the screen
    /// states the destination instead of offering it.
    private static var configured: [StudioPlatformAuth.Platform] {
        StudioPlatformAuth.Platform.allCases.filter {
            StudioPlatformAuth.configurationProblem(for: $0) == nil
        }
    }

    /// The catalog's own record, which Decision 124 has already checked. The
    /// same shape iOS pre-fills, so a host who broadcasts from both sees the
    /// same name on their channel.
    static func suggestedTitle(for film: Catalog.Item) -> String {
        var t = film.title
        if let y = film.year { t += " (\(y))" }
        return t + " — a public domain watch-along"
    }

    @State private var platform: StudioPlatformAuth.Platform
    @State private var title: String
    @State private var privacy: YouTubePrivacy = .unlisted
    @State private var signedIn = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case platform(String), title, privacy(String), goLive, cancel }

    init(film: Catalog.Item,
         onGoLive: @escaping (GoLiveRequest) -> Void,
         onCancel: @escaping () -> Void) {
        self.film = film
        self.onGoLive = onGoLive
        self.onCancel = onCancel
        _title = State(initialValue: Self.suggestedTitle(for: film))
        _platform = State(initialValue: Self.configured.first ?? .youtube)
    }

    private var trimmedTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? Self.suggestedTitle(for: film) : t
    }

    private var meta: String {
        [film.year.map(String.init), film.director, film.genres.first]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    // TWO COLUMNS, because one did not fit. The first build of this screen
    // was a single scrolling column and the capture from Ben Bedroom
    // (2026-09-18) showed the consequence plainly: "Go live" was below the
    // fold. A television has no scrollbar and no thumb — a viewer eight feet
    // away cannot see that there is more, and the one control the whole
    // screen exists to offer was the part they could not see.
    //
    // So the reading matter (what film, what risk) goes left and everything
    // focusable goes right, which also means focus never has to leave one
    // column — there is nothing focusable on the left to get lost in.
    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            VStack(alignment: .leading, spacing: 32) {
                header
                warning
                Spacer(minLength: 0)
            }
            .frame(width: 620, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    platformSection
                    // `.id` so switching platform builds a NEW row: the row
                    // reads the Keychain once in its own `onAppear`, and a
                    // reused one would report YouTube's answer for Twitch.
                    StudioSignInRow(platform: platform) { signedIn = $0 }
                        .id(platform.rawValue)
                    titleField
                    if platform == .youtube { privacyChoice }
                    actions
                }
                .padding(.vertical, 6)
            }
            .frame(width: 820, alignment: .leading)
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 50)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.94).ignoresSafeArea())
        .onAppear { signedIn = StudioPlatformAuth.isSignedIn(platform) }
        .onChange(of: platform) { _, new in
            signedIn = StudioPlatformAuth.isSignedIn(new)
        }
        // Default focus alone is unreliable here (CLAUDE.md, commit 1f789b1),
        // and the target depends on state: claiming Go Live while it is
        // disabled claims nothing and leaves focus wherever tvOS put it, so
        // the claim is only made when there is something to claim.
        .onChange(of: signedIn) { _, isIn in
            if isIn { focus = .goLive }
        }
        .task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if signedIn { focus = .goLive }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WATCH TOGETHER")
                .font(.caption).fontWeight(.semibold).kerning(2)
                .foregroundStyle(StudioSignInRow.signedInAccent)
            Text("Go live with the world")
                .font(.system(size: 48, weight: .bold))
            Text(film.title)
                .font(.title2).fontWeight(.medium)
                .foregroundStyle(.white)
            if !meta.isEmpty {
                Text(meta).font(.headline).foregroundStyle(.secondary)
            }
        }
    }

    /// Where the broadcast goes — ALWAYS stated, whether or not there is a
    /// choice to make, and always saying what is missing rather than quietly
    /// leaving it out.
    ///
    /// A first version showed this section only when more than one platform was
    /// configured. With the Apple TV's Google client not yet registered that
    /// left a screen with no destination on it at all, and YouTube absent with
    /// no explanation — which is exactly the defect Decision 128 names: "the
    /// unconfigured state was written as an absence rather than as a screen
    /// somebody reads". A host who cannot find YouTube here deserves to learn
    /// WHY on this screen, not to wonder.
    private var platformSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Where it goes").font(.headline).foregroundStyle(.secondary)
            if Self.configured.count > 1 {
                platformChoice
            } else if let only = Self.configured.first {
                Text(only.displayName).font(.title3).fontWeight(.medium)
            }
            ForEach(Self.unconfigured, id: \.rawValue) { p in
                Text(StudioPlatformAuth.configurationProblem(for: p) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .focusSection()
    }

    /// The platforms this build canNOT reach, so the screen can say so.
    private static var unconfigured: [StudioPlatformAuth.Platform] {
        StudioPlatformAuth.Platform.allCases.filter {
            StudioPlatformAuth.configurationProblem(for: $0) != nil
        }
    }

    private var platformChoice: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 24) {
                ForEach(Self.configured, id: \.rawValue) { p in
                    Button {
                        platform = p
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: p == platform
                                  ? "largecircle.fill.circle" : "circle")
                            Text(p.displayName)
                        }
                        .padding(.horizontal, 8)
                    }
                    .focused($focus, equals: .platform(p.rawValue))
                }
            }
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What it is called").font(.headline).foregroundStyle(.secondary)
            TextField("Broadcast title", text: $title)
                .focused($focus, equals: .title)
            Text("Pre-filled from this film's record. Leave it as it is, or "
                 + "press to rename the show.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var privacyChoice: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Who can find it").font(.headline).foregroundStyle(.secondary)
            HStack(spacing: 24) {
                ForEach(YouTubePrivacy.allCases, id: \.rawValue) { p in
                    Button {
                        privacy = p
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: p == privacy
                                  ? "largecircle.fill.circle" : "circle")
                            Text(p.label)
                        }
                        .padding(.horizontal, 8)
                    }
                    .focused($focus, equals: .privacy(p.rawValue))
                }
            }
            Text("Unlisted means anyone with the link can watch and YouTube "
                 + "does not list it. You can change this on YouTube afterwards.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .focusSection()
    }

    private var warning: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Before you go live", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(StudioSignInRow.signedInAccent)
            Text(StudioRights.hostWarning)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 24) {
                Button {
                    onGoLive(GoLiveRequest(
                        archiveID: film.archiveID,
                        platform: platform == .twitch ? .twitch : .youtube,
                        title: trimmedTitle,
                        // Rule 8.8a: "no category for Twitch" — it is
                        // changeable on the platform and is not worth a
                        // d-pad form.
                        category: "",
                        privacy: privacy,
                        layout: .corner,
                        customServer: nil,
                        customKey: nil))
                } label: {
                    Label("Go live on \(platform.displayName)",
                          systemImage: "dot.radiowaves.left.and.right")
                        .padding(.horizontal, 12)
                }
                .disabled(!signedIn)
                .focused($focus, equals: .goLive)

                Button("Not now", role: .cancel) { onCancel() }
                    .focused($focus, equals: .cancel)
            }
            if !signedIn {
                Text("Sign in above to go live. Nothing is broadcast until you "
                     + "press Go live.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .focusSection()
    }
}
#endif
