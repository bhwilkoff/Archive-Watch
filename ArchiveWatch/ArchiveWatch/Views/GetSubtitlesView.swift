import SwiftUI

// The "Get subtitles" sheet — one view for tvOS, iOS and macOS.
//
// It offers ONE thing: a search for HUMAN-written subtitles.
//
// The "transcribe on this device" option is gone. It downloaded a whole film to
// do offline what LiveCaptions now does while that film streams, for free — so
// it asked the viewer to wait for something they were already getting. Human
// subtitles remain worth fetching: they are better than any machine transcript
// and they persist.
struct GetSubtitlesView: View {
    let item: Catalog.Item
    @State private var finder = SubtitleFinder()
    @State private var account = SubtitleAccount.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            switch finder.phase {
            case .ready(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)

            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                choices

            case .searching:
                busy("Looking for subtitles…")
            case .sizing, .downloading, .transcribing:
                // Unreachable now that captions are produced during playback;
                // kept so the switch stays exhaustive.
                busy("Working…")

            case .idle:
                choices
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: 720, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Subtitles").font(.title2.weight(.semibold))
            Text(item.title).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func busy(_ label: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(label).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var choices: some View {
        VStack(alignment: .leading, spacing: 14) {
            if SubtitleAccount.isAvailable {
                if account.isConnected {
                    Button {
                        finder.search(item)
                    } label: {
                        Label("Search OpenSubtitles", systemImage: "text.magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!SubtitleFinder.canSearch(item))
                    Text(SubtitleFinder.canSearch(item)
                         ? "Human-made subtitles, matched on this film's IMDb entry. Counts against your own daily allowance."
                         : "This title has no IMDb match, so there's nothing reliable to look up.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Label("Connect a free OpenSubtitles account in Settings to search for human-made subtitles.",
                          systemImage: "person.crop.circle.badge.plus")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Divider()
            // Live captions already transcribe while the film streams, so there
            // is nothing to download and nothing to wait for. What this screen is
            // still for is HUMAN subtitles, which are better than any machine
            // transcript and are worth fetching when they exist.
            Label("This film is captioned automatically as it plays. "
                  + "Human-written subtitles, when they exist, are better — that "
                  + "is what a search here looks for.",
                  systemImage: "captions.bubble")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
