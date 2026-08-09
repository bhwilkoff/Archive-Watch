import SwiftUI

// The "Get subtitles" sheet — one view for tvOS, iOS and macOS.
//
// It shows BOTH sources and what each costs, rather than running a ladder
// silently. Looking a film up is free and gives a human transcript; transcribing
// downloads the whole film first (AVFoundation will not read a remote asset for
// anything but playback) and produces a machine one. Those are different enough
// that the viewer should pick, and the second states its price in megabytes
// before it starts.
struct GetSubtitlesView: View {
    let item: Catalog.Item
    @State private var finder = SubtitleFinder()
    @State private var account = SubtitleAccount.shared
    @State private var downloadBytes: Int64?
    @State private var confirmingTranscribe = false
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
            case .sizing:
                busy("Checking the download size…")
            case .downloading(let p):
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: p)
                    Text(downloadBytes.map {
                        "Downloading the film — \(Int(p * 100))% of \(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file))"
                    } ?? "Downloading the film — \(Int(p * 100))%")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Cancel") { finder.cancel() }.buttonStyle(.bordered)
                }
            case .transcribing:
                busy("Transcribing on this device. Nothing is uploaded.")

            case .idle:
                choices
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: 720, alignment: .leading)
        .confirmationDialog("Transcribe on this device?",
                            isPresented: $confirmingTranscribe, titleVisibility: .visible) {
            Button("Download and transcribe") { finder.transcribe(item) }
            Button("Not now", role: .cancel) { }
        } message: {
            Text(transcribeCost)
        }
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

            if SubtitleFinder.canTranscribe(item) {
                Divider()
                Button {
                    Task {
                        downloadBytes = await finder.measureDownload(item)
                        confirmingTranscribe = true
                    }
                } label: {
                    Label("Transcribe on this device", systemImage: "waveform")
                }
                .buttonStyle(.bordered)
                Text("Machine-made, and sometimes wrong on old soundtracks. The film is downloaded first — nothing is sent anywhere.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if AutoCaptions.isSupported && item.isSilent {
                Text("This is a silent film, so there's no dialogue to transcribe.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var transcribeCost: String {
        let size = downloadBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        let minutes = (item.runtimeSeconds ?? 0) / 60
        var s = "The whole film has to be downloaded before it can be transcribed"
        if let size { s += " — about \(size)" }
        s += "."
        if minutes > 0 { s += " It runs \(minutes) minutes, so this will take a while." }
        s += " Best on Wi-Fi."
        return s
    }
}
