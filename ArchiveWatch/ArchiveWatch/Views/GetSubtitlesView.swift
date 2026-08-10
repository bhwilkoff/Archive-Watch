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
//
// LAYOUT NOTE (why this doesn't use `Label`). On tvOS a sheet is a card sized to
// its content, so a `Label` whose title is a sentence reports an enormous ideal
// width, gets clamped, and TRUNCATES rather than wrapping — every explanatory
// line on this screen ended in "…" and said nothing. The rows below are built
// from an icon plus a `Text` that is explicitly allowed to grow vertically
// inside a definite width, which wraps on all three platforms.
struct GetSubtitlesView: View {
    let item: Catalog.Item
    @State private var finder = SubtitleFinder()
    @State private var account = SubtitleAccount.shared
    @State private var capability = CaptionCapability.shared
    @Environment(\.dismiss) private var dismiss
    @FocusState private var doneFocused: Bool

    #if os(tvOS)
    private let contentWidth: CGFloat = 1100
    private let rowSpacing: CGFloat = 24
    #else
    private let contentWidth: CGFloat = 460
    private let rowSpacing: CGFloat = 14
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            header

            switch finder.phase {
            case .ready(let message):
                row("checkmark.circle.fill", message, tint: .green)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .focused($doneFocused)

            case .failed(let message):
                row("exclamationmark.triangle", message, tint: .orange)
                choices

            case .searching:
                busy("Looking for subtitles\u{2026}")
            case .sizing, .downloading, .transcribing:
                // Unreachable now that captions are produced during playback;
                // kept so the switch stays exhaustive.
                busy("Working\u{2026}")

            case .idle:
                choices
            }
            Spacer(minLength: 0)
            #if os(tvOS)
            // tvOS has no swipe-to-dismiss and, when no account is connected,
            // nothing else here is focusable — without this the only way out of
            // this screen was the Menu button.
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .focused($doneFocused)
            #endif
        }
        .frame(width: contentWidth, alignment: .leading)
        .padding(panelPadding)
        #if os(tvOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.92).ignoresSafeArea())
        .onAppear { doneFocused = true }
        #endif
    }

    #if os(tvOS)
    private var panelPadding: CGFloat { 60 }
    #else
    private var panelPadding: CGFloat { 28 }
    #endif

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            #if os(tvOS)
            Text("Subtitles").font(.system(size: 44, weight: .bold))
            #else
            Text("Subtitles").font(.title2.weight(.semibold))
            #endif
            Text(item.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// From 27 the system captions films itself, with no app involvement —
    /// verified against a real archive.org MP4 played through our own resilient
    /// loader on macOS 27: "English (US) Transcribed" appears within a second.
    private var systemGeneratesSubtitles: Bool {
        if #available(iOS 27, tvOS 27, macOS 27, visionOS 27, *) { return true }
        return false
    }

    /// An icon and a sentence that is allowed to wrap.
    private func row(_ symbol: String, _ text: String,
                     tint: Color = .secondary, small: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(text)
                .foregroundStyle(tint)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(small ? .footnote : .body)
    }

    private func busy(_ label: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(label).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var choices: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            if SubtitleAccount.isAvailable {
                if account.isConnected {
                    Button {
                        finder.search(item)
                    } label: {
                        Label("Search OpenSubtitles", systemImage: "text.magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!SubtitleFinder.canSearch(item))
                    row("info.circle",
                        SubtitleFinder.canSearch(item)
                        ? "Human-made subtitles, matched on this film's IMDb entry. "
                          + "Counts against your own daily allowance."
                        : "This title has no IMDb match, so there's nothing reliable to look up.",
                        small: true)
                } else {
                    row("person.crop.circle.badge.plus",
                        "Connect a free OpenSubtitles account in Settings to search "
                        + "for human-made subtitles.",
                        small: true)
                }
            }

            Divider()
            // Only promise automatic captions where they can actually happen.
            // Apple ships the Speech APIs on tvOS but an Apple TV carries no
            // speech models and cannot install them (AssetInventory reports
            // `unsupported`), so this screen used to tell a living room its film
            // was being captioned while nothing appeared.
            if systemGeneratesSubtitles {
                // tvOS 27 generates subtitles for video that has none, on
                // device, in the player's own menu (WWDC26 session 256). It
                // needs nothing from us, so this screen should point at it
                // rather than claim the app is doing the work.
                row("captions.bubble",
                    "This device can generate subtitles as a film plays — choose "
                    + "them from the subtitles menu during playback, or turn "
                    + "captions on in Accessibility settings to get them "
                    + "automatically. Human-written subtitles, when they exist, "
                    + "are better.",
                    small: true)
            } else if capability.canAutoCaption == false {
                row("captions.bubble",
                    "This device can't caption films by itself, so human-written "
                    + "subtitles are the only ones it can show.",
                    small: true)
            } else {
                row("captions.bubble",
                    "This film is captioned automatically as it plays. Human-written "
                    + "subtitles, when they exist, are better — that is what a search "
                    + "here looks for.",
                    small: true)
            }
        }
    }
}
