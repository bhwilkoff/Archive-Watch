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
                        if platform != .custom, let problem = StudioPlatformAuth.configurationProblem(for: authPlatform) {
                            Text(problem).font(.footnote).foregroundStyle(.secondary)
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

    private var canCommit: Bool {
        guard refusal == nil else { return false }
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if platform == .custom {
            return URL(string: customURL)?.host != nil && !customKey.isEmpty
        }
        return StudioPlatformAuth.configurationProblem(for: authPlatform) == nil
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
