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
import AVKit
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
    /// DEBUG ONLY — `AW_STUDIO_DEST` offers a bench server beside the real
    /// platforms, so the commit chain this screen exists to trigger
    /// (request → `StudioGoLive.destination` → engine → `RTMPPublisher`) can be
    /// RUN before any host has a platform account. iOS has carried a `.custom`
    /// destination in the shipping sheet since §8.9; a television cannot type a
    /// URL, so here it is an environment variable and a DEBUG build.
    ///
    /// It is a real destination, not a bypass: the request goes through the
    /// same `onGoLive`, the same resolver and the same publisher. What it skips
    /// is the platform's key exchange, which is the only part that needs an
    /// account.
    @State private var useBench = false
    @State private var showCameraPicker = false
    @State private var cameraPaired = false
    private static var benchDestination: URL? {
        #if DEBUG
        ProcessInfo.processInfo.environment["AW_STUDIO_DEST"].flatMap(URL.init(string:))
        #else
        nil
        #endif
    }
    /// What YouTube says about this channel's ability to broadcast at all.
    /// Nil means "not asked yet", which deliberately does NOT block Go live:
    /// a slow API call must not gate the control, and a host who presses
    /// through an unknown answer meets the real error either way. Only a
    /// KNOWN-bad answer stops them, and it stops them with a sentence.
    @State private var readiness: StudioPlatformAuth.Readiness?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case platform(String), title, privacy(String), camera, goLive, cancel }

    init(film: Catalog.Item,
         onGoLive: @escaping (GoLiveRequest) -> Void,
         onCancel: @escaping () -> Void) {
        self.film = film
        self.onGoLive = onGoLive
        self.onCancel = onCancel
        _title = State(initialValue: Self.suggestedTitle(for: film))
        _platform = State(initialValue: Self.configured.first ?? .youtube)
    }

    /// The reason a signed-in host still cannot broadcast, or nil.
    private var blockedReason: String? {
        guard case .blocked(let why)? = readiness else { return nil }
        return why
    }

    /// The request this screen produces. ONE definition, used by the button and
    /// by the verification door below — a door that built its own request would
    /// be measuring a code path the product does not have.
    private func request() -> GoLiveRequest {
        GoLiveRequest(
            archiveID: film.archiveID,
            platform: useBench ? .custom : (platform == .twitch ? .twitch : .youtube),
            title: trimmedTitle,
            // Rule 8.8a: "no category for Twitch" — it is changeable on the
            // platform and is not worth a d-pad form.
            category: "",
            privacy: privacy,
            layout: .corner,
            customServer: useBench ? Self.benchDestination : nil,
            customKey: useBench
                ? (ProcessInfo.processInfo.environment["AW_STUDIO_KEY"] ?? "awbench")
                : nil)
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
                // WHY Go live is greyed, in the reading column rather than the
                // control column. It went below the buttons first (clipped by
                // the bottom of the screen) and then above them (which clipped
                // the BUTTONS instead) — the control column cannot hold both,
                // and this is reading matter, which is what the left column is
                // for. Three layout attempts on one screen, each judged by a
                // capture: a ten-foot column does not fit by reasoning.
                if signedIn, let blockedReason {
                    Label(blockedReason, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(StudioSignInRow.signedInAccent)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                    cameraRow
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
            readiness = nil
        }
        // Asked once the host is signed in, because it needs their token, and
        // re-asked when they sign in later. Read-only: it creates no broadcast
        // (§9.zzz) — the whole point is to answer before anything is created.
        .task(id: signedIn) {
            guard signedIn, readiness == nil else { return }
            readiness = try? await StudioPlatformAuth.readiness(for: platform)
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
        // DEBUG verification door — `AW_STUDIO_TV_GOLIVE=1` with
        // `AW_STUDIO_DEST`. It presses nothing and proves nothing about the
        // button; what it exercises is the COMMIT CHAIN behind it — the same
        // `request()` the button builds, the same `onGoLive`, and from there
        // `StudioGoLive.destination` → `StudioEngine` → `RTMPPublisher`.
        //
        // It exists because that chain had never run on this platform: the
        // surface is verified on the glass, and everything past the press was
        // compiled and unrun. Driving a d-pad blind over a remote could not
        // establish it reliably — four presses moved no visible focus — and a
        // chain measured through a server's own recording is better evidence
        // than a focus ring anyway.
        //
        // Bench only. It refuses to fire at a real platform, so it can never
        // put a broadcast on anybody's channel.
        .task {
            let door = ProcessInfo.processInfo.environment["AW_STUDIO_TV_GOLIVE"] ?? ""
            guard !door.isEmpty else { return }
            switch door {
            case "1":
                // The bench server: no account, no platform, no broadcast.
                guard Self.benchDestination != nil else { return }
                useBench = true
            case "twitch", "youtube":
                // A REAL platform. Only reachable in a DEBUG build, only when
                // that platform is both configured and signed in, and only when
                // its own readiness says the channel can actually broadcast —
                // the same three gates the button is behind, so this cannot
                // reach a channel the product would refuse.
                let p: StudioPlatformAuth.Platform = door == "twitch" ? .twitch : .youtube
                // EVERY REFUSAL SAYS WHY. These guards used to return in
                // silence, which reads in a log exactly like a door that never
                // fired — so a YouTube run that was refused for want of a token
                // and one where the door was never set produced the same
                // evidence: nothing at all.
                guard Self.configured.contains(p) else {
                    awdiag("AWDOOR %@ REFUSED: no client id configured in this build", door)
                    return
                }
                guard StudioPlatformAuth.isSignedIn(p) else {
                    awdiag("AWDOOR %@ REFUSED: not signed in on this device", door)
                    return
                }
                platform = p
                useBench = false
                signedIn = true
                readiness = try? await StudioPlatformAuth.readiness(for: p)
                guard case .ready? = readiness else {
                    awdiag("AWDOOR %@ REFUSED: readiness=%@", door,
                           String(describing: readiness))
                    return
                }
                awdiag("AWDOOR %@ READY — going live", door)
            default:
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            onGoLive(request())
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
            if Self.benchDestination != nil {
                Button {
                    useBench.toggle()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: useBench
                              ? "largecircle.fill.circle" : "circle")
                        Text("Bench server (debug)")
                    }
                    .padding(.horizontal, 8)
                }
                .focused($focus, equals: .platform("bench"))
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

    /// PAIRING BELONGS HERE, immediately before going live.
    ///
    /// Owner, 2026-09-18: "You should be able to enable continuity camera when
    /// (or just before) you start a stream." Before this, a television with no
    /// paired phone simply had no camera tile and said nothing about it — the
    /// only way to pair was to leave the app and find the system picker, which
    /// is not a thing a host does mid-thought.
    ///
    /// `continuityDevicePicker` is AVKit's own (tvOS 17+), so the phone, its
    /// permissions and the two-factor check are all Apple's to handle; the
    /// device becomes visible to `StudioContinuity`'s discovery and the
    /// existing attach path picks it up unchanged.
    ///
    /// It is never REQUIRED. §8.8 already treats an absent camera as normal,
    /// and a host who wants only the film should not have to dismiss anything.
    private var cameraRow: some View {
        Button {
            showCameraPicker = true
        } label: {
            HStack {
                Label(cameraPaired ? "iPhone camera and microphone are ready"
                                   : "Use an iPhone as camera and microphone",
                      systemImage: cameraPaired ? "checkmark.circle.fill" : "iphone")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if !cameraPaired {
                    Text("Optional").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.borderless)
        .focused($focus, equals: .camera)
        .continuityDevicePicker(isPresented: $showCameraPicker) { device in
            // The device is now visible system-wide; discovery finds it.
            cameraPaired = device != nil
            awdiag("AWCONT picker connected=%@", device == nil ? "nil" : "yes")
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 24) {
                Button {
                    onGoLive(request())
                } label: {
                    Label(useBench ? "Go live to the bench server"
                                   : "Go live on \(platform.displayName)",
                          systemImage: "dot.radiowaves.left.and.right")
                        .padding(.horizontal, 12)
                }
                // The bench needs no token and no channel: it is a server on
                // this network, and the gates above are about a platform.
                .disabled(!useBench && (!signedIn || blockedReason != nil))
                .focused($focus, equals: .goLive)

                Button("Not now", role: .cancel) { onCancel() }
                    .focused($focus, equals: .cancel)
            }
            if !signedIn {
                Text("Sign in above to go live. Nothing is broadcast until you "
                     + "press Go live.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if blockedReason == nil {
                Text("Nothing is broadcast until you press Go live.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .focusSection()
    }
}
#endif
