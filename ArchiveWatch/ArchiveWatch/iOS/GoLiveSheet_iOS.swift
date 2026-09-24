#if os(iOS)
import AVFoundation
import SwiftUI

// Go Live — iOS-DESIGN §8.9, a §3.6 form sheet at the large detent.
//
// This is where a host decides to broadcast a public-domain film to the world
// under their own account, so three things are non-negotiable
// (docs/WATCH-TOGETHER.md §2, §4, §5):
//
//   1. It NEVER asks for a stream key. The key comes from the platform's own
//      API once the host has signed in. The only field that takes a URL is
//      the custom destination, which exists for diagnostics.
//   2. It states the rights policy IN A SENTENCE, and when a film is not
//      eligible it says WHY rather than greying a control out. "Films
//      published between 1964 and 1977 had their copyrights renewed
//      automatically" teaches a viewer something true about the public
//      domain; a disabled button teaches nothing (§2.3).
//   3. Nothing here is generated for the host. The title is pre-filled from
//      the catalog because that data is audited and theirs to edit, not
//      because a model wrote it.

struct GoLiveSheet: View {
    let film: Catalog.Item
    /// Called with a fully-formed destination once the host commits.
    let onGoLive: (GoLiveRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var platform: GoLivePlatform = .youtube
    @State private var title: String
    @State private var category = ""
    @State private var privacy: YouTubePrivacy = .unlisted
    @AppStorage(StudioSession.readYouTubeChatKey) private var readYouTubeChat = false
    @State private var customURL = ""
    @State private var customKey = ""
    /// Decision 136's third route: the host's own key from the platform's
    /// page, as OBS connects. No sign-in, no API call, no shared quota — and
    /// so no chat or viewer count. Held for this sheet only; never saved.
    @State private var connectWithKey = false
    @State private var platformKey = ""
    @State private var layout: StudioLayout = .corner
    @State private var showPolicy = false

    init(film: Catalog.Item, onGoLive: @escaping (GoLiveRequest) -> Void) {
        self.film = film
        self.onGoLive = onGoLive
        // Pre-filled from the catalog's own audited record — the host edits it.
        _title = State(initialValue: Self.suggestedTitle(for: film))
    }

    private var refusal: String? {
        StudioRights.refusal(rightsBucket: film.rightsBucket,
                             contentType: film.contentType,
                             year: film.year)
    }

    @State private var hostGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
            Form {
                filmSection
                if let refusal {
                    // NOT a disabled control with no explanation (§5).
                    Section {
                        Label {
                            Text(refusal)
                        } icon: {
                            Image(systemName: "hand.raised.fill")
                                .foregroundStyle(Brand.primary)
                        }
                        .font(.subheadline)
                    } header: {
                        Text("This film cannot be streamed")
                    } footer: {
                        Text(StudioRights.policy)
                    }
                } else {
                    destinationSection
                    hostSection
                    programSection
                    Section {
                        Text(StudioRights.policy)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    // What the gate CANNOT protect them from, before the
                    // first broadcast rather than after a strike (§3.4a).
                    Section {
                        Label {
                            Text(StudioRights.hostWarning)
                                .font(.footnote)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                    .id(Self.warningAnchor)
                }
            }
            // Verification hook only: `AW_GOLIVE_SCROLL=warning` brings
            // §3.4a's paragraph into view so it can be READ on a device.
            // It sits below the fold in the KEEP state — on an iPad the sheet
            // showed everything down to Privacy and no further — so a
            // screenshot of the sheet is not a screenshot of the warning.
            // No-op in production.
            .task {
                guard ProcessInfo.processInfo.environment["AW_GOLIVE_SCROLL"] == "warning",
                      refusal == nil else { return }
                // One frame, so the Form has laid out before we ask it to move.
                try? await Task.sleep(nanoseconds: 400_000_000)
                withAnimation(.none) { scroll.scrollTo(Self.warningAnchor, anchor: .bottom) }
            }
            }
            .navigationTitle("Go Live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go Live") { commit() }
                        .disabled(!canCommit)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        // IPAD-DESIGN §5a. Detents do not apply to an iPad form sheet, so
        // this sheet's SHORT state (a refused film) leaves ~40% of it blank
        // while the KEEP state fills it properly — both measured on an iPad
        // Pro 12.9-inch. `presentationSizing` is not the fix: `.fitted`
        // collapsed the sheet to ~140 pt wide, and `.form.fitted(vertical:)`
        // clipped the content to a strip. The empty region is cosmetic and
        // stays; the alternatives were functional regressions.
    }

    /// The §3.4a section's scroll id, shared by the section and the hook so
    /// the two cannot drift apart.
    private static let warningAnchor = "aw-host-warning"

    /// PUT ME IN THE SHOW — the camera and microphone, asked for HERE.
    ///
    /// The Studio's attach helper deliberately REPORTS rather than REQUESTS
    /// ("the Studio REPORTS, never REQUESTS" — `StudioSession`), so something
    /// has to do the asking, and this is the only surface where a viewer has
    /// chosen to broadcast. Same rule as tvOS §10.2b for sign-in and Android
    /// §9.6 for these very permissions: never at launch, never a precondition
    /// for browsing.
    ///
    /// Until 2026-09-20 nothing asked at all on iOS, and nothing attached
    /// either — an iPhone broadcast the film and nothing else while the Apple
    /// TV had had a Continuity camera for days.
    ///
    /// NEITHER IS REQUIRED. A refusal does not disable Go Live: §8.8's rule is
    /// that an absent camera is normal, so the show carries the film and the
    /// readout says why the host is not in it.
    @ViewBuilder
    private var hostSection: some View {
        Section {
            if hostGranted {
                Label("You are in the show — camera and microphone",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            } else if let refused = hostRefusal {
                // requestAccess returns at once, with no prompt, once a host
                // has said no — so the old button did nothing at all here.
                Text(refused).font(.footnote).foregroundStyle(.secondary)
                if AVCaptureDevice.authorizationStatus(for: .video) != .restricted,
                   AVCaptureDevice.authorizationStatus(for: .audio) != .restricted {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } else {
                Button("Put me in the show (camera and microphone)") {
                    AVCaptureDevice.requestAccess(for: .video) { _ in
                        AVCaptureDevice.requestAccess(for: .audio) { _ in
                            Task { @MainActor in hostGranted = hostIsAuthorised }
                        }
                    }
                }
                Text("Optional — the film broadcasts fine on its own.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("You")
        }
    }

    /// A sentence when the system will no longer ask, or nil.
    private var hostRefusal: String? {
        let v = AVCaptureDevice.authorizationStatus(for: .video)
        let a = AVCaptureDevice.authorizationStatus(for: .audio)
        let off = [v == .denied || v == .restricted ? "camera" : nil,
                   a == .denied || a == .restricted ? "microphone" : nil].compactMap { $0 }
        guard !off.isEmpty else { return nil }
        let what = off.joined(separator: " and ")
        if v == .restricted || a == .restricted {
            return "The \(what) is restricted on this iPhone."
        }
        return "Archive Watch is not allowed to use the \(what). Turn it on in Settings."
    }

    private var hostIsAuthorised: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    // MARK: Sections

    private var filmSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                PosterImage(url: film.posterURL.flatMap(URL.init(string:)), contentMode: .fill)
                    .frame(width: 58, height: 87)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 3) {
                    Text(film.title).font(.headline)
                    if let meta = Self.metaLine(for: film) {
                        Text(meta).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let prov = Self.provenanceLine(for: film) {
                        Text(prov)
                            .font(.caption).fontWeight(.medium)
                            .foregroundStyle(Brand.primary)
                    }
                }
            }
        } header: {
            Text("What you are streaming")
        }
    }

    private var destinationSection: some View {
        Section {
            Picker("Platform", selection: $platform) {
                ForEach(GoLivePlatform.allCases, id: \.self) { p in
                    Text(p.label).tag(p)
                }
            }
            if platform != .custom {
                Picker("Connect", selection: $connectWithKey) {
                    Text("Sign in").tag(false)
                    Text("Stream key").tag(true)
                }
                .pickerStyle(.segmented)
            }
            if platform != .custom, connectWithKey {
                SecureField("Stream key", text: $platformKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let page = platform.streamKeyPage {
                    Link("Find your stream key", destination: page)
                }
            }
            // Who the broadcast goes out AS. Above the title field, because
            // a host cannot usefully name a stream they cannot publish.
            if platform != .custom, !connectWithKey {
                StudioSignInRow(platform: authPlatform) { signedIn = $0 }
                    // ONE ROW PER PLATFORM. Without this SwiftUI reuses the
                    // row when the picker changes, carrying its @State across:
                    // the owner saw YouTube and Twitch "as the same account",
                    // and signing out of one looked like signing out of both
                    // (2026-09-23, Mac). The tokens were separate all along.
                    // tvOS has had this `.id` since the same bug there.
                    .id(authPlatform)
                    .task(id: signedIn) {
                        guard signedIn, platform != .custom, readiness == nil else { return }
                        readiness = try? await StudioPlatformAuth.readiness(for: authPlatform)
                    }
                    .onChange(of: platform) { _, _ in readiness = nil }
                // THE ROW SAYS IT; THIS SHEET ACTS ON IT. `StudioSignInRow`
                // already asks `readiness(for:)` at sign-in and draws the
                // answer as `blockedNote`, so this printed the same sentence
                // a second time directly beneath the first.  `blockedReason`
                // stays because `canCommit` needs it.
            }
            switch platform {
            case .youtube where connectWithKey, .twitch where connectWithKey:
                // Title, privacy and category are set on the platform's own
                // page for a keyed stream — this app makes no call to set them.
                EmptyView()
            case .youtube:
                TextField("Stream title", text: $title, axis: .vertical)
                    .lineLimit(1...3)
                Picker("Privacy", selection: $privacy) {
                    ForEach(YouTubePrivacy.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Show chat from YouTube", isOn: $readYouTubeChat)
            case .twitch:
                TextField("Stream title", text: $title, axis: .vertical)
                    .lineLimit(1...3)
                TextField("Category", text: $category)
                    .textInputAutocapitalization(.words)
            case .custom:
                // The diagnostic path. A real destination is never typed.
                TextField("rtmps://host/app", text: $customURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Stream key", text: $customKey)
            }
        } header: {
            Text("Where it goes")
        } footer: {
            Text(destinationFooter)
        }
    }

    /// Said once, and consistent with the sign-in row above it.
    private var destinationFooter: String {
        if platform == .custom {
            return "For testing against your own server. Keys typed here are kept for this session only and never saved."
        }
        if connectWithKey {
            return "Chat and the viewer count need sign-in. The key is never saved."
        }
        if StudioPlatformAuth.configurationProblem(for: authPlatform) != nil {
            return "Until that is set up, nothing can be published to \(platform.label) from this build."
        }
        return "You will be asked to sign in to \(platform.label) once. Archive Watch fetches the stream key from \(platform.label) itself — you never copy one."
    }

    private var programSection: some View {
        Section {
            Picker("Layout", selection: $layout) {
                ForEach(StudioLayout.allCases, id: \.self) { l in
                    Text(l.label).tag(l)
                }
            }
        } header: {
            Text("How it looks")
        }
    }

    // MARK: Commit

    private var canCommit: Bool {
        guard refusal == nil else { return false }
        if platform != .custom, connectWithKey {
            return !platformKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if platform == .custom {
            return URL(string: customURL)?.host != nil && !customKey.isEmpty
        }
        // SIGNED IN IS NOT READY. The platform can refuse a broadcast from a
        // channel that has never been enabled for live, and going live is four
        // WRITES whose first one creates a real object on the host's channel —
        // so "will this work?" is asked with a read, up front (§9.zzz). tvOS
        // got this first; leaving it there would have been the fourth time one
        // surface was fixed and its siblings were not (§9.ttt, §9.eeee).
        guard blockedReason == nil else { return false }
        // A build with no client id cannot publish anywhere, and a pressable
        // Go Live would fail somewhere the host cannot see. The sign-in row
        // directly above carries the reason, so this is not §5's unexplained
        // disabled control.
        // CONFIGURED IS NOT SIGNED IN — the third surface carrying this same
        // proxy (tvOS §9.ooo, macOS and here §9.ttt). It was true while no
        // client id existed anywhere; the day both were registered it went
        // permanently nil and Go Live enabled itself for a host who has not
        // signed in, which fails inside the auth boundary — the exact thing
        // the comment above says this gate exists to prevent.
        return signedIn
    }

    /// Mirrored from the sign-in row, because `isSignedIn` is a Keychain
    /// read rather than observable state.
    @State private var signedIn = false
    /// What the PLATFORM says about this channel, asked with a read before the
    /// host presses anything (§9.zzz). Nil means "not asked yet" and
    /// deliberately does NOT block Go Live: a slow API must not gate a control,
    /// and a host who presses through an unknown meets the real error anyway.
    /// Only a KNOWN-bad answer stops them, and it stops them with a sentence.
    @State private var readiness: StudioPlatformAuth.Readiness?

    /// Why a signed-in host still cannot broadcast, or nil.
    private var blockedReason: String? {
        guard platform != .custom, case .blocked(let why)? = readiness else { return nil }
        return why
    }


    private var authPlatform: StudioPlatformAuth.Platform {
        platform == .twitch ? .twitch : .youtube
    }

    private func commit() {
        guard canCommit else { return }
        onGoLive(GoLiveRequest(
            archiveID: film.archiveID,
            platform: platform,
            title: title.trimmingCharacters(in: .whitespaces),
            category: category.trimmingCharacters(in: .whitespaces),
            privacy: privacy,
            layout: layout,
            customServer: platform == .custom ? URL(string: customURL) : nil,
            customKey: platform == .custom ? customKey : nil,
            typedKey: platform != .custom && connectWithKey ? platformKey : nil))
        dismiss()
    }

    // MARK: Copy from the catalog's own record

    static func suggestedTitle(for film: Catalog.Item) -> String {
        var t = film.title
        if let y = film.year { t += " (\(y))" }
        return t + " — a public domain watch-along"
    }

    static func metaLine(for film: Catalog.Item) -> String? {
        var parts: [String] = []
        if let y = film.year { parts.append(String(y)) }
        if let d = film.director, !d.isEmpty { parts.append(d) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func provenanceLine(for film: Catalog.Item) -> String? {
        guard film.rightsBucket == "safe_pd_age", let y = film.year else { return nil }
        // The catalog knows the film's year, not its exact date of entry into
        // the public domain; say only what is true.
        return "Public domain — published \(y)"
    }
}

#endif
