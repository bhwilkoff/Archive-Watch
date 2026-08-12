import SwiftUI
import AVFoundation
import AVKit
import MediaAccessibility

// Caption Diagnostics — the app reports its own caption behaviour, on screen.
//
// This exists because of how the tvOS 27 generated-subtitles bug survived three
// shipped fixes: an Apple TV is the only device that can answer whether tvOS
// captions a film, and its console cannot be read from a development machine,
// so every fix was verified on macOS and shipped on faith (Decision 067). This
// screen removes the faith: one run answers which tiers this DEVICE has,
// whether the system offers a track for the exact asset shape the app ships,
// whether selecting it takes, and whether text actually arrives.
//
// Two lessons from this screen's own first build (886) are load-bearing:
//
//   * State lives in a SINGLETON, not in the view. The first version kept it
//     in @State; on the owner's Apple TV the finished run showed an EMPTY log
//     and an idle Run button — any view recreation resets @State, and the one
//     device this screen was built for is where that happened. A singleton
//     also means reopening the sheet shows the LAST run instead of nothing.
//
//   * The probe player is VISIBLE, and the emission window is generous on
//     tvOS. The 75/90s windows were calibrated on an M-series Mac that emits
//     text in ~33s; an Apple TV's chip is far slower and first use may need a
//     model download, so a short window reports "declined" for a system that
//     is merely still working. And a probe that renders nothing is not the
//     shape real playback has — if generation is tied to active rendering
//     anywhere, a headless probe would be a false negative.
//
// The test film is fixed: a 1975 documentary with clear narration the system
// is KNOWN to caption on macOS 27. The recognizer declines rough archival
// audio by design (Decision 063) — probing with a random film would conflate
// "this device cannot caption" with "this film was declined", the exact
// confusion this screen exists to end.

@MainActor
@Observable
final class CaptionDiagnostics {
    /// One instance for the app. Results survive the sheet closing, the view
    /// being recreated, and focus-driven re-renders — the failure mode 886
    /// shipped with was a per-view @State copy losing everything it logged.
    static let shared = CaptionDiagnostics()

    struct Line: Identifiable {
        let id = UUID()
        let text: String
        let emphasis: Bool
    }
    private(set) var lines: [Line] = []
    private(set) var running = false
    /// The probe's player, exposed so the view can SHOW the film being tested.
    private(set) var player: AVPlayer?

    private var retainedLoader: AnyObject?
    private var startedAt = Date()

    static let testFilm = URL(string: "https://archive.org/download/"
        + "mantheincrediblemachine/mantheincrediblemachine.mp4")!

    /// How long to give the system before concluding it will not caption.
    /// tvOS gets much longer: slower silicon, a possible first-use model
    /// download, and no fallback engine that is waiting to start instead.
    static var emissionPatience: Double {
        #if os(tvOS)
        return 300
        #else
        return 90
        #endif
    }

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
        defer {
            log("Test finished. These results stay here — reopen this screen "
                + "any time to read or photograph them.")
            stop()
        }

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
            + "caption in ~33s on macOS 27")
        let item = AVPlayerItem(url: Self.testFilm)
        let p = AVPlayer(playerItem: item)
        // Volume, not `isMuted`: muting can remove audio from the render
        // pipeline entirely, and a probe that silences the thing it measures
        // would report false negatives (the LiveCaptions tap lesson).
        p.volume = 0
        player = p      // the view renders this, so the probe matches playback
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

        let window = Int(Self.emissionPatience)
        log("Listening for caption text — the system transcribes ahead before "
            + "showing anything, and first use may download a model. Allowing "
            + "up to \(window)s…")
        if let (cue, at) = await firstCue(on: item, within: Self.emissionPatience) {
            log("TEXT ARRIVED after \(at)s: \u{201C}\(cue.prefix(70))\u{201D}", emphasis: true)
            log("VERDICT: generated subtitles WORK on this device. A film with "
                + "no subtitles will offer them in the player's subtitle menu.",
                emphasis: true)
        } else {
            log("No text within \(window)s, on a film the system captions in "
                + "~33s on macOS 27.", emphasis: true)
            log("VERDICT: the track is offered and selected but produced "
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

    /// The first non-empty cue and how many seconds it took, or nil.
    /// Logs a heartbeat every 30s so a long window reads as "still working",
    /// not as the screen having died — the difference matters on the sofa.
    private func firstCue(on item: AVPlayerItem,
                          within seconds: Double) async -> (String, Int)? {
        let sink = CueSink()
        let output = AVPlayerItemLegibleOutput(mediaSubtypesForNativeRepresentation: [])
        output.suppressesPlayerRendering = false      // observe only
        output.setDelegate(sink, queue: .main)
        item.add(output)
        defer { item.remove(output) }
        let start = Date()
        let deadline = start.addingTimeInterval(seconds)
        var nextTick = 30.0
        while Date() < deadline {
            let elapsed = Date().timeIntervalSince(start)
            if let cue = sink.first { return (cue, Int(elapsed)) }
            if Task.isCancelled { return nil }
            if elapsed >= nextTick {
                log("…still listening (\(Int(elapsed))s, no text yet)")
                nextTick += 30
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return sink.first.map { ($0, Int(seconds)) }
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
    // The shared instance, NOT @State: view recreation must never blank the
    // log (it did, on the one device this screen exists for).
    private var diag: CaptionDiagnostics { .shared }
    private let bottomID = "log-bottom"

    var body: some View {
        VStack(spacing: 12) {
            if let player = diag.player, diag.running {
                // The film under test, visible — the probe then runs under the
                // same rendering conditions as real playback, and "is anything
                // happening?" answers itself.
                VideoPlayer(player: player)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .allowsHitTesting(false)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if diag.lines.isEmpty {
                            Text("Runs a test of every caption tier this device "
                                 + "supports, against a film the system is known "
                                 + "to caption. On Apple TV allow up to ~6 "
                                 + "minutes; nothing is uploaded. Results appear "
                                 + "here as they happen and stay until the next "
                                 + "run.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(diag.lines) { line in
                            Text(line.text)
                                .font(.caption.monospaced())
                                .fontWeight(line.emphasis ? .bold : .regular)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id(bottomID)
                    }
                    .padding(.horizontal)
                }
                // Auto-follow: on tvOS nothing but the buttons is focusable, so
                // the log cannot be scrolled by hand — the newest line must
                // bring itself into view.
                .onChange(of: diag.lines.count) {
                    withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) }
                }
            }
            HStack {
                Button(diag.running ? "Running…" : "Run Caption Test") {
                    Task { await diag.run() }
                }
                .disabled(diag.running)
                if diag.running { ProgressView() }
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()
        }
        .padding(.top)
    }
}
