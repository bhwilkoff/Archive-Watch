#if os(macOS)
import SwiftUI

// Go Live on the Mac — macOS-DESIGN Rule B13g, approved 2026-09-18.
//
// B13g says the command opens "the same form sheet as iOS §8.9", and §B13c's
// reasoning is why: it already chose mirroring over invention for the program
// panel, because a host who learned one should know the other. This sheet
// therefore carries exactly what the iPhone's does — the film it is about, the
// rights refusal IN A SENTENCE, where the program goes, how it looks, the
// policy, and §3.4a's warning — using the request types that became shared in
// §9.lll so no platform has to redefine what a broadcast is.
//
// Two questions B13g left open were not answered explicitly, so this takes the
// conservative reading and says so at each one.
struct GoLiveSheetMac: View {
    let film: Catalog.Item
    let onGoLive: (GoLiveRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var platform: GoLivePlatform = .youtube
    @State private var title: String
    @State private var category = ""
    @State private var privacy: YouTubePrivacy = .unlisted
    @State private var customURL = ""
    @State private var customKey = ""
    @State private var layout: StudioLayout = .corner

    init(film: Catalog.Item, onGoLive: @escaping (GoLiveRequest) -> Void) {
        self.film = film
        self.onGoLive = onGoLive
        _title = State(initialValue: Self.suggestedTitle(for: film))
        // AW_GOLIVE_CUSTOM=<rtmp url> pre-seeds the CUSTOM destination, so the
        // whole go-live path can be driven end to end without the owner's
        // client ids: the sheet's own canCommit, commit and destination
        // resolution all still run, and only the typing is skipped. The two
        // platform branches cannot be exercised until those ids exist (§9.mmm),
        // and this deliberately does not pretend otherwise.
        if let u = ProcessInfo.processInfo.environment["AW_GOLIVE_CUSTOM"], !u.isEmpty {
            _platform = State(initialValue: .custom)
            _customURL = State(initialValue: u)
            _customKey = State(initialValue: "macbench")
        }
    }

    private var refusal: String? {
        StudioRights.refusal(rightsBucket: film.rightsBucket,
                             contentType: film.contentType,
                             year: film.year)
    }

    private var authPlatform: StudioPlatformAuth.Platform {
        platform == .twitch ? .twitch : .youtube
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Go Live").font(.title2).bold().padding([.top, .horizontal], 20)
            Form {
                Section("What you are streaming") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(film.title).font(.headline)
                        if let meta = Self.metaLine(for: film) {
                            Text(meta).foregroundStyle(.secondary)
                        }
                        if let prov = Self.provenanceLine(for: film) {
                            Text(prov).font(.caption).bold()
                                .foregroundStyle(Color(hex: "#FF5C35") ?? .orange)
                        }
                    }
                }
                if let refusal {
                    // NOT a disabled control with no explanation (§5) — the same
                    // sentence the iPhone and the television show.
                    Section("This film cannot be streamed") {
                        Text(refusal)
                        Text(StudioRights.policy).font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Section("Where it goes") {
                        Picker("Platform", selection: $platform) {
                            ForEach(GoLivePlatform.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        if platform != .custom {
                            // B13g lists the sign-in row as content this sheet
                            // carries; it was missing, which is why the Mac
                            // could not reach a platform at all (§9.sss). The
                            // row itself renders all three states — no client
                            // id, signed out, signed in — so nothing here
                            // needs to restate them.
                            StudioSignInRow(platform: authPlatform) { signedIn = $0 }
                                .task(id: signedIn) {
                                    guard signedIn, platform != .custom, readiness == nil else { return }
                                    readiness = try? await StudioPlatformAuth.readiness(for: authPlatform)
                                }
                                .onChange(of: platform) { _, _ in readiness = nil }
                            if let blockedReason {
                                Label(blockedReason, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        switch platform {
                        case .youtube:
                            TextField("Stream title", text: $title)
                            Picker("Privacy", selection: $privacy) {
                                ForEach(YouTubePrivacy.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                        case .twitch:
                            TextField("Stream title", text: $title)
                            TextField("Category", text: $category)
                        case .custom:
                            // The diagnostic path. A real destination is never typed.
                            TextField("rtmps://host/app", text: $customURL)
                            SecureField("Stream key", text: $customKey)
                        }
                    }
                    Section("How it looks") {
                        Picker("Layout", selection: $layout) {
                            ForEach(StudioLayout.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                    }
                    Section {
                        Text(StudioRights.policy).font(.footnote).foregroundStyle(.secondary)
                        Label(StudioRights.hostWarning, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Go Live") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCommit)
            }
            .padding(20)
        }
        .frame(width: 520, height: 620)
    }

    /// Mirrored from the sign-in row: `isSignedIn` is a Keychain read, not
    /// observable state, so asking it directly here would leave Go Live
    /// disabled behind a row that already says "Signed in".
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


    private var canCommit: Bool {
        guard refusal == nil else { return false }
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
        // CONFIGURED IS NOT SIGNED IN. This read `configurationProblem == nil`,
        // which was a fair proxy only while no client id existed anywhere: the
        // day both were registered it became permanently nil, and Go Live
        // switched itself on for a Mac that has no way to obtain a token.
        // There is no macOS sign-in surface — `signInToYouTube` and
        // `beginTwitchSignIn` are called from exactly one file, and it is
        // `#if os(iOS)` — and tokens are `ThisDeviceOnly` and unsynchronised,
        // so a sign-in on the host's phone does not reach this machine.
        // Pressing Go Live would have failed inside the auth boundary, which
        // is the one thing §10.2b's principle says never to offer (§9.sss).
        return signedIn
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
            customKey: platform == .custom ? customKey : nil))
        dismiss()
    }

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
        return "Public domain — published \(y), before 1930"
    }
}
#endif
