import SwiftUI
import AVFoundation
import AVKit
import MediaAccessibility

// Caption Diagnostics — the app reports its own caption behaviour, on screen
// AND on stdout, so a paired Apple TV can be read from a development machine
// (`devicectl device process launch --console`, env AW_CAPTION_DIAG=1).
//
// This exists because of how the tvOS 27 generated-subtitles bug survived three
// shipped fixes: everything was verified on macOS and shipped on faith
// (Decision 067). The first run on the real Apple TV then contradicted the Mac
// twice over — tvOS offered NO track for a plain remote MP4 that macOS captions
// in 33s — which is why this screen now probes THREE shapes rather than
// asserting one:
//
//   1. LOCAL FILE — a bundled 60s narration clip (verified to caption in 14s
//      on macOS). Apple's own words are "HLS and file-based content"; a local
//      file is the canonical file-based case. If THIS produces nothing, the
//      device does not generate subtitles for this app at all, and no asset
//      shape will fix it.
//   2. PLAIN REMOTE MP4 — what uncaptioned films actually play (Decision 067).
//   3. HLS WRAPPER — a playlist synthesized around the same MP4. Offered-but-
//      silent on macOS; tvOS has already proven the platforms differ.
//
// Each probe LISTENS AND POLLS CONCURRENTLY for its whole window. The 887
// probe waited 15s for a track to be OFFERED before doing anything else — but
// the test film's opening is silent, and if the system only offers a track
// once it has HEARD something, a fixed offer-first gate can never survive a
// quiet opening. Emission is judged per-item (text through an item's own
// legible output cannot come from another probe), which is what makes running
// three shapes in one process tolerable — "offered" readings can contaminate
// across shapes (measured on macOS), emitted text cannot.

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

    static let remoteFilm = URL(string: "https://archive.org/download/"
        + "mantheincrediblemachine/mantheincrediblemachine.mp4")!

    /// Per-shape observation window. tvOS gets much longer: slower silicon, a
    /// possible first-use model download, and no fallback engine waiting.
    static var patience: Double {
        #if os(tvOS)
        return 240
        #else
        return 100
        #endif
    }

    private func log(_ text: String, emphasis: Bool = false) {
        let t = Int(Date().timeIntervalSince(startedAt))
        lines.append(Line(text: "t=\(t)s  \(text)", emphasis: emphasis))
        // stdout as well: with the app launched via
        //   xcrun devicectl device process launch --console
        // these lines land on the development Mac, which is what finally makes
        // the Apple TV a readable oracle instead of a photographed one.
        print("[AWDIAG] t=\(t)s \(text)")
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

        guard SystemCaptions.isAvailable else {
            log("Nothing further to test — the generated-subtitle probe needs 27.")
            return
        }

        // ── Shape 1: LOCAL FILE — the canonical "file-based content" case ────
        var results: [(String, Bool)] = []
        if let clip = Bundle.main.url(forResource: "caption-probe", withExtension: "mp4") {
            log("SHAPE 1 — LOCAL FILE: bundled 60s narration clip (captions in "
                + "14s on macOS)", emphasis: true)
            let ok = await probe(item: AVPlayerItem(url: clip),
                                 window: min(Self.patience, 180))
            results.append(("local file", ok))
            if !ok {
                log("The local file did not caption. That is Apple's own "
                    + "canonical case — if this fails, no asset shape will "
                    + "succeed, and the cause is the device/OS, not the app.",
                    emphasis: true)
            }
        } else {
            log("Bundled probe clip missing — skipping the local-file shape.",
                emphasis: true)
        }

        // ── Shape 2: PLAIN REMOTE MP4 — what uncaptioned films play ──────────
        log("SHAPE 2 — PLAIN REMOTE MP4 (what uncaptioned films play since "
            + "build 885)", emphasis: true)
        let plain = await probe(item: AVPlayerItem(url: Self.remoteFilm),
                                window: Self.patience)
        results.append(("plain remote MP4", plain))

        // ── Shape 3: HLS WRAPPER — offered-but-silent on macOS; tvOS differs ─
        log("SHAPE 3 — HLS WRAPPER around the same MP4", emphasis: true)
        let (asset, loader) = DiagnosticHLSWrapper.makeAsset(
            mp4: Self.remoteFilm, durationSeconds: 1715)
        retainedLoader = loader
        let wrapped = await probe(item: AVPlayerItem(asset: asset),
                                  window: min(Self.patience, 180))
        results.append(("HLS wrapper", wrapped))
        retainedLoader = nil

        // ── Shape 4: OUR OWN ENGINE — because this device just changed ──────
        // Decision 060 recorded that tvOS has no speech models, measured on
        // tvOS 26. The first on-device 27 run reported 45 SUPPORTED locales
        // (0 installed) — so the question is no longer "does the API exist"
        // but "does the install actually complete and produce cues here".
        // If it does, the iOS/macOS live-transcription engine lights up on
        // Apple TV too, under our control, independent of the system track.
        if LiveCaptions.isSupported,
           let clip = Bundle.main.url(forResource: "caption-probe", withExtension: "mp4") {
            log("SHAPE 4 — OUR ENGINE: SpeechAnalyzer scout on the bundled clip",
                emphasis: true)
            let lc = LiveCaptions()
            await lc.start(url: clip, from: .zero)
            let engineStart = Date()
            var lastNotice = ""
            var engineGot = false
            while Date().timeIntervalSince(engineStart) < 180, !Task.isCancelled {
                let n = lc.notice
                if !n.isEmpty, n != lastNotice {
                    lastNotice = n
                    log("  engine: \(n)")
                }
                if let first = lc.transcript().first {
                    log("  ENGINE CUE after \(Int(Date().timeIntervalSince(engineStart)))s: "
                        + "\u{201C}\(first.text.prefix(60))\u{201D}", emphasis: true)
                    engineGot = true
                    break
                }
                if !lc.isRunning {
                    log("  engine stopped without cues"
                        + (lastNotice.isEmpty ? "" : " — last notice: \(lastNotice)"),
                        emphasis: true)
                    break
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            lc.stop()
            results.append(("our engine (SpeechAnalyzer)", engineGot))
        }

        // ── The verdict table ────────────────────────────────────────────────
        log("RESULTS:", emphasis: true)
        for (name, ok) in results {
            log("  \(ok ? "CAPTIONED " : "no text   ")  \(name)", emphasis: ok)
        }
        if let best = results.first(where: { $0.1 }) {
            log("VERDICT: the system generates subtitles here via \(best.0).",
                emphasis: true)
        } else {
            log("VERDICT: no shape produced text on this device. Generated "
                + "subtitles are not reaching this app at all — report this "
                + "whole screen.", emphasis: true)
        }
    }

    /// One shape: play it, and for the whole window LISTEN for text while
    /// POLLING for a legible option to appear and selecting it the moment it
    /// does. No offer-first gate — a film with a silent opening must not be
    /// able to defeat detection (the 887 probe gave up at 15s for exactly
    /// that reason).
    private func probe(item: AVPlayerItem, window: Double) async -> Bool {
        let p = AVPlayer(playerItem: item)
        // Volume, not `isMuted`: muting can remove audio from the render
        // pipeline entirely, and a probe that silences the thing it measures
        // would report false negatives (the LiveCaptions tap lesson).
        p.volume = 0
        player = p
        p.play()

        let sink = CueSink()
        let output = AVPlayerItemLegibleOutput(mediaSubtypesForNativeRepresentation: [])
        output.suppressesPlayerRendering = false      // observe only
        output.setDelegate(sink, queue: .main)
        item.add(output)
        defer { item.remove(output); p.pause(); player = nil }

        let start = Date()
        let deadline = start.addingTimeInterval(window)
        var offeredLogged = false
        var selectedLogged = false
        var statusLogged = false
        var nextTick = 30.0
        while Date() < deadline {
            let elapsed = Date().timeIntervalSince(start)
            if let cue = sink.first {
                log("TEXT after \(Int(elapsed))s: \u{201C}\(cue.prefix(60))\u{201D}",
                    emphasis: true)
                return true
            }
            if Task.isCancelled { return false }

            if !statusLogged, item.status != .unknown {
                statusLogged = true
                log(item.status == .readyToPlay
                    ? "  playing (item ready at \(Int(elapsed))s)"
                    : "  item FAILED: \(item.error?.localizedDescription ?? "?")",
                    emphasis: item.status == .failed)
                if item.status == .failed { return false }
            }
            // Track detection runs alongside listening, never in front of it.
            let box = await LegibleProbe(asset: item.asset).group()
            if let group = box.g, !group.options.isEmpty {
                if !offeredLogged {
                    offeredLogged = true
                    log("  track offered at \(Int(elapsed))s: "
                        + group.options.map(\.displayName).joined(separator: ", "))
                }
                if !selectedLogged {
                    if item.currentMediaSelection.selectedMediaOption(in: group) != nil {
                        selectedLogged = true
                        log("  track is already selected")
                    } else if let opt = AVMediaSelectionGroup.mediaSelectionOptions(
                                from: group.options, with: Locale.current).first
                                ?? group.options.first {
                        // Selected UNCONDITIONALLY here, unlike real playback:
                        // this is a test of whether the system CAN caption, and
                        // the first on-device run silently skipped selection
                        // because the device was in forced-only mode — turning
                        // a viewer preference into a false "stayed silent".
                        item.select(opt, in: group)
                        selectedLogged = true
                        let respectful = MACaptionAppearanceGetDisplayType(.user) != .forcedOnly
                        log("  selected: \(opt.displayName)"
                            + (respectful ? "" : " (display preference is forced-only —"
                               + " real playback would NOT auto-show this)"))
                    }
                }
            } else if !offeredLogged, Int(elapsed) % 30 == 1 {
                // What the asset DOES claim, while nothing legible is offered —
                // nil group vs empty group vs other characteristics is exactly
                // the structural detail a remote log can act on.
                let chars = (try? await item.asset.load(
                    .availableMediaCharacteristicsWithMediaSelectionOptions)) ?? []
                log("  asset legible group: \(box.g == nil ? "nil" : "empty"); "
                    + "selection characteristics: "
                    + (chars.isEmpty ? "none" : chars.map(\.rawValue).joined(separator: ",")))
            }
            #if compiler(>=6.4)
            // Built with the beta toolchain (dev-loop installs only — the App
            // Store archive uses the released Xcode and never compiles this):
            // also ask the 27-only ITEM-level API, in case tvOS surfaces the
            // generated track there rather than in the asset's group.
            if #available(tvOS 27, iOS 27, macOS 27, *), !offeredLogged, let group = box.g {
                let itemLevel = item.selectableMediaSelectionOptions(in: group)
                if !itemLevel.isEmpty {
                    log("  ITEM-level options at \(Int(elapsed))s (asset group empty): "
                        + itemLevel.map(\.displayName).joined(separator: ", "),
                        emphasis: true)
                }
            }
            #endif
            if elapsed >= nextTick {
                log("  …listening (\(Int(elapsed))s"
                    + (offeredLogged ? ", track offered" : ", no track yet") + ")")
                nextTick += 30
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        log("  no text within \(Int(window))s"
            + (offeredLogged ? " (track was offered but stayed silent)"
                             : " (no track was ever offered)"), emphasis: true)
        return false
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
    private struct LegibleProbe: @unchecked Sendable {
        let asset: AVAsset
        func group() async -> Box { Box(g: try? await asset.loadMediaSelectionGroup(for: .legible)) }
        struct Box: @unchecked Sendable { let g: AVMediaSelectionGroup? }
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

/// The Config-C shape in miniature: master + media playlist served through a
/// custom scheme, media segment left as a direct https URL AVFoundation owns.
/// Kept app-side (not a harness copy) so the diagnostics can exercise it on a
/// real Apple TV — it failed on macOS (offered but silent), and tvOS has
/// already proven the platforms differ.
private final class DiagnosticHLSWrapper: NSObject, AVAssetResourceLoaderDelegate,
                                          @unchecked Sendable {
    static let scheme = "aw-diag-hls"
    private let queue = DispatchQueue(label: "aw.diag.hls")
    private let mp4: URL
    private let duration: Int

    private init(mp4: URL, duration: Int) {
        self.mp4 = mp4
        self.duration = duration
    }

    static func makeAsset(mp4: URL, durationSeconds: Int) -> (AVURLAsset, DiagnosticHLSWrapper) {
        let loader = DiagnosticHLSWrapper(mp4: mp4, duration: durationSeconds)
        let asset = AVURLAsset(url: URL(string: "\(scheme)://local/master.m3u8")!)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        return (asset, loader)
    }

    func resourceLoader(_ rl: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource
                        req: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = req.request.url else { return false }
        let body: String
        if url.path.hasSuffix("master.m3u8") {
            body = "#EXTM3U\n#EXT-X-VERSION:6\n"
                + "#EXT-X-STREAM-INF:BANDWIDTH=2000000\nvideo.m3u8\n"
        } else if url.path.hasSuffix("video.m3u8") {
            body = "#EXTM3U\n#EXT-X-VERSION:6\n#EXT-X-TARGETDURATION:\(duration)\n"
                + "#EXT-X-PLAYLIST-TYPE:VOD\n#EXTINF:\(duration).0,\n"
                + "\(mp4.absoluteString)\n#EXT-X-ENDLIST\n"
        } else {
            return false
        }
        let data = Data(body.utf8)
        req.contentInformationRequest?.contentType = "application/vnd.apple.mpegurl"
        req.contentInformationRequest?.contentLength = Int64(data.count)
        req.contentInformationRequest?.isByteRangeAccessSupported = false
        req.dataRequest?.respond(with: data)
        req.finishLoading()
        return true
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
                            Text("Probes three ways of playing a film to find "
                                 + "which one this device generates subtitles "
                                 + "for. On Apple TV allow up to ~10 minutes; "
                                 + "nothing is uploaded. Results appear here as "
                                 + "they happen and stay until the next run.")
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
