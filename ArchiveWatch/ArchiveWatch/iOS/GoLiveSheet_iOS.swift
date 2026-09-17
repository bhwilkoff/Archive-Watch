#if os(iOS)
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
    @State private var customURL = ""
    @State private var customKey = ""
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

    var body: some View {
        NavigationStack {
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
                    programSection
                    Section {
                        Text(StudioRights.policy)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
        } footer: {
            Text("Your audience sees this title, year and director on screen, from the catalog's own checked record.")
        }
    }

    private var destinationSection: some View {
        Section {
            Picker("Platform", selection: $platform) {
                ForEach(GoLivePlatform.allCases, id: \.self) { p in
                    Text(p.label).tag(p)
                }
            }
            switch platform {
            case .youtube:
                TextField("Stream title", text: $title, axis: .vertical)
                    .lineLimit(1...3)
                Picker("Privacy", selection: $privacy) {
                    ForEach(YouTubePrivacy.allCases, id: \.self) { Text($0.label).tag($0) }
                }
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
            Text(platform == .custom
                 ? "For testing against your own server. Keys typed here are kept for this session only and never saved."
                 : "You will be asked to sign in to \(platform.label) once. Archive Watch fetches the stream key from \(platform.label) itself — you never copy one.")
        }
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
        } footer: {
            Text("You can change the layout, the faders and the cards at any time while you are live.")
        }
    }

    // MARK: Commit

    private var canCommit: Bool {
        guard refusal == nil else { return false }
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if platform == .custom {
            return URL(string: customURL)?.host != nil && !customKey.isEmpty
        }
        return true
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
        return "Public domain — published \(y), before 1930"
    }
}

// MARK: - The request

struct GoLiveRequest: Sendable, Equatable {
    let archiveID: String
    let platform: GoLivePlatform
    let title: String
    let category: String
    let privacy: YouTubePrivacy
    let layout: StudioLayout
    let customServer: URL?
    let customKey: String?
}

enum GoLivePlatform: String, CaseIterable, Sendable {
    case youtube, twitch, custom
    var label: String {
        switch self {
        case .youtube: return "YouTube"
        case .twitch: return "Twitch"
        case .custom: return "Custom server"
        }
    }
}

enum YouTubePrivacy: String, CaseIterable, Sendable {
    case `public`, unlisted, `private`
    var label: String {
        switch self {
        case .public: return "Public"
        case .unlisted: return "Unlisted"
        case .private: return "Private"
        }
    }
}

extension StudioLayout {
    /// User-facing names. The raw values are wire/diagnostic words.
    var label: String {
        switch self {
        case .film: return "Film only"
        case .corner: return "Film with you in the corner"
        case .theatre: return "Theatre row (you along the bottom)"
        case .side: return "Side by side"
        case .host: return "You, with the film inset"
        }
    }
}
#endif
