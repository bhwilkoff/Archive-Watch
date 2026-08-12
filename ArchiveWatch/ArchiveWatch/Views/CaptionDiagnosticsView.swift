import SwiftUI
import AVFoundation
import MediaAccessibility

// Caption Diagnostics — the app reports its own caption behaviour, on screen.
//
// This exists because of how the tvOS 27 generated-subtitles bug survived three
// shipped fixes: an Apple TV is the only device that can answer whether tvOS
// captions a film, and its console cannot be read from a development machine,
// so every fix was verified on macOS and shipped on faith (Decision 067). This
// screen removes the faith. One viewing answers, in order: which caption tiers
// this DEVICE has at all, whether the system offers a subtitle track for the
// exact asset shape the app ships, whether selecting it takes, and whether text
// actually arrives — the four hypotheses that could previously only be guessed
// at from a Mac.
//
// It deliberately runs the SHIPPED decision points (`SystemCaptions.
// waitForLegibleOption` / `selectIfWanted`, `CaptionCapability`), not a
// reimplementation, so what it reports is what playback does. The one addition
// is a richer emission listener that captures the first cue's text — "text
// arrived" is more convincing with the words attached.
//
// The test film is fixed: a 1975 documentary with clear narration that the
// system is KNOWN to caption on macOS 27. That matters because the recognizer
// declines rough archival audio by design (Decision 063) — probing with a
// random film would conflate "this device cannot caption" with "this film's
// audio was declined", the exact confusion this screen exists to end.

@MainActor
@Observable
final class CaptionDiagnostics {
    struct Line: Identifiable {
        let id = UUID()
        let text: String
        let emphasis: Bool
    }
    private(set) var lines: [Line] = []
    private(set) var running = false

    private var player: AVPlayer?
    // The asset holds its resource-loader delegate WEAKLY; releasing this makes
    // every request fail "unsupported URL", which looks exactly like the loader
    // disqualifying the film. That mistake has already been made once, in the
    // harness this screen descends from.
    private var retainedLoader: AnyObject?
    private var startedAt = Date()

    static let testFilm = URL(string: "https://archive.org/download/"
        + "mantheincrediblemachine/mantheincrediblemachine.mp4")!

    private func log(_ text: String, emphasis: Bool = false) {
        let t = Int(Date().timeIntervalSince(startedAt))
        lines.append(Line(text: "t=\(t)s  \(text)", emphasis: emphasis))
    }

    func stop() {
        player?.pause()
        player = nil
        retainedLoader = nil
        running = false
    }

    func run() async {
        guard !running else { return }
        running = true
        lines = []
        startedAt = Date()
        defer { stop() }

        // ── The device, before any network is touched ────────────────────────
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        log("Archive Watch \(version) (\(build)) — \(osName) \(os)")

        switch MACaptionAppearanceGetDisplayType(.user) {
        case .alwaysOn:   log("Caption preference: always on")
        case .forcedOnly: log("Caption preference: FORCED ONLY — the app will not "
                              + "switch subtitle tracks on for you", emphasis: true)
        default:          log("Caption preference: automatic")
        }

        log(SystemCaptions.isAvailable
            ? "System-generated subtitles: this OS can generate them (27+)"
            : "System-generated subtitles: NOT on this OS version (needs 27)",
            emphasis: !SystemCaptions.isAvailable)

        let device = await CaptionCapability.shared.resolved()
        log(device
            ? "On-device transcription: this device has speech models"
            : "On-device transcription: NO speech models on this device"
              + (CaptionCapability.shared.report.map { " (\($0))" } ?? ""))
        if !device && !SystemCaptions.isAvailable {
            log("So this device can only show PUBLISHED subtitle files.", emphasis: true)
        }

        guard SystemCaptions.isAvailable else {
            log("Nothing further to test — the generated-subtitle probe needs 27.")
            return
        }

        // ── Probe 1: the exact shape the app ships for uncaptioned films ─────
        log("PROBE 1 — plain direct URL (what uncaptioned films play since "
            + "build 885)", emphasis: true)
        log("Film: The Incredible Machine (1975) — clear narration, known to "
            + "caption on macOS 27")
        let item = AVPlayerItem(url: Self.testFilm)
        let p = AVPlayer(playerItem: item)
        // Volume, not `isMuted`: muting can remove audio from the render
        // pipeline entirely, and a probe that silences the thing it measures
        // would report false negatives (the LiveCaptions tap lesson).
        p.volume = 0
        player = p
        p.play()

        guard await SystemCaptions.waitForLegibleOption(on: p) else {
            log("NO subtitle track was offered within 15s.", emphasis: true)
            log("VERDICT: this OS does not offer generated subtitles for a "
                + "remote progressive MP4 — the shape archive.org serves. "
                + "Report this line.", emphasis: true)
            return
        }
        log("Subtitle track offered: \(await optionNames(of: item).joined(separator: ", "))")

        guard await SystemCaptions.selectIfWanted(on: p) else {
            log("The track could NOT be switched on (stage: "
                + "\(SystemCaptions.Stage.notSelected.rawValue)).", emphasis: true)
            log("If the caption preference above says FORCED ONLY, that is why.")
            return
        }
        log("Track selected: \(await selectedName(of: item) ?? "?")")

        log("Listening for caption text — the system transcribes ahead before "
            + "showing anything, so allow up to 90s…")
        if let cue = await firstCue(on: item, within: 90) {
            log("TEXT ARRIVED: \u{201C}\(cue.prefix(70))\u{201D}", emphasis: true)
            log("VERDICT: generated subtitles WORK on this device. A film with "
                + "no subtitles will offer them in the player's subtitle menu.",
                emphasis: true)
        } else {
            log("No text within 90s, on a film the system captions in ~33s on "
                + "macOS 27.", emphasis: true)
            log("VERDICT: the track is offered and selected but produces "
                + "nothing here. Report this line.", emphasis: true)
        }
        player?.pause()

        // ── Probe 2: the control — the resilient loader must NOT be offered ──
        // If this ever reports a track, the loader has become captionable and
        // Decision 067's plain-URL trade should be revisited.
        log("PROBE 2 (control) — through the resilient loader", emphasis: true)
        let (asset, loader) = ResilientStreamLoader.makeAsset(for: Self.testFilm)
        retainedLoader = loader
        let controlItem = AVPlayerItem(asset: asset)
        let control = AVPlayer(playerItem: controlItem)
        control.volume = 0
        player = control
        control.play()
        if await SystemCaptions.waitForLegibleOption(on: control) {
            log("UNEXPECTED: the loader path was offered a track "
                + "(\(await optionNames(of: controlItem).joined(separator: ", "))). "
                + "Decision 067 assumed it never is — report this.", emphasis: true)
        } else {
            log("As expected: no track through the loader. This is why "
                + "uncaptioned films play the plain URL.")
        }
        log("Done.")
    }

    private var osName: String {
        #if os(tvOS)
        return "tvOS"
        #elseif os(macOS)
        return "macOS"
        #else
        return "iOS/iPadOS"
        #endif
    }

    // `AVAsset` / `AVMediaSelectionGroup` are not Sendable; both are read-only
    // here, so the same narrow box SystemCaptions uses is the honest bridge.
    private struct GroupProbe: @unchecked Sendable {
        let asset: AVAsset
        func group() async -> Box { Box(g: try? await asset.loadMediaSelectionGroup(for: .legible)) }
        struct Box: @unchecked Sendable { let g: AVMediaSelectionGroup? }
    }

    private func optionNames(of item: AVPlayerItem) async -> [String] {
        let box = await GroupProbe(asset: item.asset).group()
        return box.g?.options.map(\.displayName) ?? []
    }

    private func selectedName(of item: AVPlayerItem) async -> String? {
        let box = await GroupProbe(asset: item.asset).group()
        guard let g = box.g else { return nil }
        return item.currentMediaSelection.selectedMediaOption(in: g)?.displayName
    }

    /// The first non-empty cue the player's legible output delivers, or nil.
    /// Richer than `SystemCaptions.emitsCaptions` (which answers only yes/no)
    /// because a diagnostic is more convincing with the words attached.
    private func firstCue(on item: AVPlayerItem, within seconds: Double) async -> String? {
        let sink = CueSink()
        let output = AVPlayerItemLegibleOutput(mediaSubtypesForNativeRepresentation: [])
        output.suppressesPlayerRendering = false      // observe only
        output.setDelegate(sink, queue: .main)
        item.add(output)
        defer { item.remove(output) }
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let cue = sink.first { return cue }
            if Task.isCancelled { return nil }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return sink.first
    }

    private final class CueSink: NSObject, AVPlayerItemLegibleOutputPushDelegate,
                                 @unchecked Sendable {
        private let lock = NSLock()
        private var _first: String?
        var first: String? { lock.lock(); defer { lock.unlock() }; return _first }
        func legibleOutput(_ output: AVPlayerItemLegibleOutput,
                           didOutputAttributedStrings strings: [NSAttributedString],
                           nativeSampleBuffers: [Any], forItemTime itemTime: CMTime) {
            let text = strings.map(\.string).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            lock.lock(); if _first == nil { _first = text }; lock.unlock()
        }
    }
}

struct CaptionDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var diag = CaptionDiagnostics()

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    if diag.lines.isEmpty {
                        Text("Runs a ~2 minute test of every caption tier this "
                             + "device supports, against a film the system is "
                             + "known to caption. Nothing is uploaded; results "
                             + "appear here as they happen.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(diag.lines) { line in
                        Text(line.text)
                            .font(.caption.monospaced())
                            .fontWeight(line.emphasis ? .bold : .regular)
                    }
                    if diag.running {
                        ProgressView()
                    }
                } header: {
                    Text("Caption Diagnostics")
                }
            }
            HStack {
                Button(diag.running ? "Running…" : "Run Caption Test") {
                    Task { await diag.run() }
                }
                .disabled(diag.running)
                Spacer()
                Button("Done") { diag.stop(); dismiss() }
            }
            .padding()
        }
        .onDisappear { diag.stop() }
    }
}
