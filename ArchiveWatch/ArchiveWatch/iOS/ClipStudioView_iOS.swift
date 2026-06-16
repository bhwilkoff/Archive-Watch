#if os(iOS)
import SwiftUI
import SwiftData
import AVKit
import AVFoundation
import CoreImage
import ImageIO
import UIKit

// Clip Studio — the iPhone/iPad content-creation surface (Decision 033 /
// docs/CREATE-STUDIO-PLAN.md). A modal task: prepare the source, trim on a
// filmstrip, reframe + caption, export an MP4 or GIF, save/share. The human
// makes every editorial choice; the engine handles the mechanical work.

@MainActor @Observable
final class ClipStudioModel {
    enum Phase { case preparing, editing, exporting, result }

    let item: Catalog.Item
    var phase: Phase = .preparing
    var exportProgress: Double = 0
    var errorMessage: String?

    // The REMOTE archive.org URL — we edit directly off the resilient stream,
    // never a full download (films can be hours long / multi-GB).
    var sourceURL: URL?
    var player: AVPlayer?
    private var sourceAsset: AVURLAsset?
    private var loader: ResilientStreamLoader?   // retained for the preview asset's lifetime
    var duration: Double = 0
    var thumbnails: [UIImage] = []

    var inSeconds: Double = 0
    var outSeconds: Double = 15
    var aspect: ClipAspect = .vertical
    var format: ClipFormat = .video
    var look: ClipLook = .none
    var speed: Double = 1
    var blurredFill: Bool = false
    var caption: String = ""
    var captionCues: [CaptionCue] = []
    var captionStyle = CaptionStyle()
    var transcribing = false

    var hasCaption: Bool { !caption.isEmpty || !captionCues.isEmpty }
    /// The caption text to show on the preview right now: the active timed cue
    /// at the playhead, else the static caption. Cue times are CLIP-RELATIVE
    /// (0-based — `transcribe` extracts the [in,out] audio to a clip that
    /// re-bases to 0), so match against the playhead's offset INTO the clip,
    /// not the absolute film time (which was the bug: an absolute playhead at
    /// e.g. 120s never fell inside cues at 0–15s, so nothing previewed).
    var activeCaption: String? {
        if !captionCues.isEmpty {
            let rel = playheadSeconds - inSeconds
            return captionCues.first { rel >= $0.start && rel < $0.end }?.text
        }
        return caption.isEmpty ? nil : caption
    }

    var playheadSeconds: Double = 0
    var isPlaying = false
    private var timeObserver: Any?

    var resultURL: URL?

    var clipDuration: Double { max(0, outSeconds - inSeconds) }
    /// Output length after speed (source selection ÷ speed).
    var outputDuration: Double { speed > 0 ? clipDuration / speed : clipDuration }
    var canExport: Bool { clipDuration >= 0.5 && sourceURL != nil }

    init(item: Catalog.Item) { self.item = item }

    func prepare() async {
        guard let remote = item.videoURLParsed else {
            errorMessage = "This title has no video to clip."
            return
        }
        do {
            sourceURL = remote
            // Edit off the resilient remote stream — no download (Decision 021).
            let (asset, loader) = ClipExporter.openSource(remote)
            self.loader = loader
            sourceAsset = asset
            let dur = try await asset.load(.duration).seconds
            duration = dur.isFinite ? dur : 0
            outSeconds = min(duration > 0 ? duration : 15, 15)
            player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            phase = .editing                       // show the editor immediately…
            await generateThumbnails(asset: asset) // …the filmstrip fills in as frames arrive
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Live grade preview — set a Core Image videoComposition on the player so
    /// the selected look shows in the preview. iOS 26/27 API:
    /// `AVVideoComposition(applyingFiltersTo:applier:)` (async).
    func applyLookPreview() {
        guard let item = player?.currentItem, let asset = sourceAsset else { return }
        guard look != .none else { item.videoComposition = nil; return }
        let look = self.look
        Task {
            let vc = try? await AVVideoComposition(applyingFiltersTo: asset, applier: { request in
                let graded = look.apply(to: request.sourceImage.clampedToExtent())
                    .cropped(to: request.sourceImage.extent)
                return AVCIImageFilteringResult(resultImage: graded)
            })
            if let vc, player?.currentItem === item { item.videoComposition = vc }
        }
    }

    private func generateThumbnails(asset: AVAsset) async {
        guard duration > 0 else { return }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 160, height: 160)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        let n = 30
        let times = (0..<n).map { CMTime(seconds: duration * (Double($0) + 0.5) / Double(n), preferredTimescale: 600) }
        var imgs: [UIImage] = []
        for await result in gen.images(for: times) {
            if case let .success(_, image, _) = result { imgs.append(UIImage(cgImage: image)) }
        }
        thumbnails = imgs
    }

    /// Switching to GIF clamps the selection to the tighter GIF length cap.
    func setFormat(_ f: ClipFormat) {
        format = f
        if clipDuration > f.maxDuration { outSeconds = inSeconds + f.maxDuration }
    }

    func seek(to t: Double) {
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Tolerant seek for fluid live scrubbing. Clip BOUNDS stay frame-accurate
    /// because Set Start/End and the export use the exact scroll/handle time
    /// (`playheadSeconds` / in / out) — only the preview frame is approximate.
    private func seekFast(to t: Double) {
        let tol = CMTime(seconds: 0.12, preferredTimescale: 600)
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 600),
                     toleranceBefore: tol, toleranceAfter: tol)
    }

    /// User scrubbed the timeline — stop playback and move the preview to `t`.
    func scrub(to t: Double) {
        if isPlaying { pause() }
        let c = max(0, min(t, duration))
        playheadSeconds = c
        seekFast(to: c)
    }

    /// A trim handle moved: adopt the new bounds and show the dragged edge.
    func trim(inSeconds newIn: Double, outSeconds newOut: Double, previewAt: Double) {
        if isPlaying { pause() }
        inSeconds = newIn
        outSeconds = newOut
        playheadSeconds = previewAt
        seekFast(to: previewAt)
    }

    /// Mark the clip's start / end at the current playhead (no handle dance).
    func setStart() {
        inSeconds = max(0, min(playheadSeconds, outSeconds - 0.5))
        if clipDuration > format.maxDuration { outSeconds = inSeconds + format.maxDuration }
    }
    func setEnd() {
        outSeconds = min(duration, max(playheadSeconds, inSeconds + 0.5))
        if clipDuration > format.maxDuration { inSeconds = outSeconds - format.maxDuration }
    }

    func togglePlay() {
        guard let p = player else { return }
        if isPlaying { pause(); return }
        installTimeObserver()
        if playheadSeconds < inSeconds || playheadSeconds >= outSeconds - 0.05 {
            seek(to: inSeconds); playheadSeconds = inSeconds
        }
        p.play(); isPlaying = true
    }

    func pause() { player?.pause(); isPlaying = false }

    private func installTimeObserver() {
        guard let p = player, timeObserver == nil else { return }
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            guard let self, self.isPlaying else { return }
            let s = t.seconds
            self.playheadSeconds = s
            if s >= self.outSeconds {
                self.pause(); self.seek(to: self.outSeconds); self.playheadSeconds = self.outSeconds
            }
        }
    }

    func teardown() {
        if let o = timeObserver { player?.removeTimeObserver(o); timeObserver = nil }
        player?.pause()
    }

    func export(into ctx: ModelContext) async {
        guard let source = sourceURL else { return }
        phase = .exporting
        exportProgress = 0
        let spec = ClipSpec(
            sourceURL: source, archiveID: item.archiveID, title: item.title,
            sourceDetailsURL: item.sourceDetailsURL, creditLine: item.clipCreditLine,
            inSeconds: inSeconds, durationSeconds: clipDuration, aspect: aspect,
            caption: caption.trimmingCharacters(in: .whitespacesAndNewlines), format: format,
            look: look, speed: speed, blurredFill: blurredFill, captionCues: captionCues,
            captionStyle: captionStyle)
        do {
            let (stream, cont) = AsyncStream.makeStream(of: Double.self)
            let pt = Task { for await p in stream { self.exportProgress = p } }
            let url: URL
            switch format {
            case .video: url = try await ClipExporter.shared.exportVideo(spec) { cont.yield($0) }
            case .gif:   url = try await ClipExporter.shared.exportGIF(spec) { cont.yield($0) }
            }
            cont.finish(); pt.cancel()
            resultURL = url
            persist(url: url, into: ctx)
            phase = .result
        } catch {
            errorMessage = error.localizedDescription
            phase = .editing
        }
    }

    private func persist(url: URL, into ctx: ModelContext) {
        let clip = VideoClip(
            sourceArchiveID: item.archiveID, sourceTitle: item.title,
            inSeconds: inSeconds, durationSeconds: clipDuration,
            aspect: aspect.rawValue, format: format.rawValue,
            caption: caption, renderFilename: url.lastPathComponent)
        ctx.insert(clip)
        try? ctx.save()
    }

    func saveToPhotos() async {
        guard let url = resultURL else { return }
        do { try await ClipExporter.shared.saveToPhotos(url, format: format) }
        catch { errorMessage = error.localizedDescription }
    }

    func autoCaption() async {
        guard let source = sourceURL, !transcribing else { return }
        transcribing = true
        defer { transcribing = false }
        do {
            captionCues = try await ClipExporter.shared.transcribe(
                sourceURL: source, inSeconds: inSeconds, duration: clipDuration)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearCaptions() { captionCues = [] }
}

struct ClipStudioView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var model: ClipStudioModel
    @State private var saved = false

    init(item: Catalog.Item) { _model = State(initialValue: ClipStudioModel(item: item)) }

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .preparing: preparing
                case .editing:   editing
                case .exporting: rendering
                case .result:    resultView
                }
            }
            .navigationTitle("Clip Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if model.phase == .result {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .alert("Couldn’t finish", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(model.errorMessage ?? "") }
        }
        .preferredColorScheme(.dark)
        .task { if model.phase == .preparing { await model.prepare() } }
        .onDisappear { model.teardown() }
    }

    // MARK: Phases

    private var preparing: some View {
        VStack(spacing: 16) {
            ProgressView().tint(Brand.primary)
            Text("Loading clip…").font(.subheadline).foregroundStyle(.secondary)
            Text(model.item.title).font(.caption).foregroundStyle(.tertiary)
                .lineLimit(1).padding(.horizontal)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rendering: some View {
        VStack(spacing: 16) {
            ProgressView(value: model.exportProgress)
                .progressViewStyle(.linear).tint(Brand.primary).frame(maxWidth: 240)
            Text("Rendering \(model.format.label)…").font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editing: some View {
        ScrollView {
            VStack(spacing: 18) {
                preview
                trim
                labeled("Format") {
                    Picker("Format", selection: Binding(
                        get: { model.format }, set: { model.setFormat($0) })) {
                        ForEach(ClipFormat.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                }
                labeled("Frame") {
                    Picker("Frame", selection: $model.aspect) {
                        ForEach(ClipAspect.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                    if model.aspect != .original {
                        Toggle("Blurred-fill background", isOn: $model.blurredFill)
                            .font(.subheadline).tint(Brand.primary)
                    }
                }
                labeled("Look") {
                    Picker("Look", selection: Binding(
                        get: { model.look }, set: { model.look = $0; model.applyLookPreview() })) {
                        ForEach(ClipLook.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.menu).tint(Brand.primary)
                }
                labeled("Speed") {
                    Picker("Speed", selection: $model.speed) {
                        Text("0.5×").tag(0.5); Text("1×").tag(1.0); Text("2×").tag(2.0)
                    }.pickerStyle(.segmented)
                }
                labeled("Captions") {
                    if model.captionCues.isEmpty {
                        TextField("Add a caption (optional)", text: $model.caption, axis: .vertical)
                            .lineLimit(1...2).textFieldStyle(.roundedBorder)
                        Button { Task { await model.autoCaption() } } label: {
                            Label(model.transcribing ? "Transcribing…" : "Auto-caption from speech",
                                  systemImage: "captions.bubble")
                                .font(.subheadline)
                        }
                        .disabled(model.transcribing || model.clipDuration < 0.5)
                    } else {
                        HStack {
                            Label("\(model.captionCues.count) timed captions", systemImage: "captions.bubble.fill")
                                .font(.subheadline).foregroundStyle(Brand.primary)
                            Spacer()
                            Button("Clear") { model.clearCaptions() }.font(.subheadline)
                        }
                    }
                    if model.hasCaption {
                        Picker("Font", selection: $model.captionStyle.font) {
                            ForEach(CaptionFont.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented)
                        HStack(spacing: 10) {
                            Picker("Size", selection: $model.captionStyle.sizeScale) {
                                Text("S").tag(0.8); Text("M").tag(1.0); Text("L").tag(1.3)
                            }.pickerStyle(.segmented)
                            Picker("Color", selection: $model.captionStyle.color) {
                                ForEach(CaptionColor.allCases) { Text($0.label).tag($0) }
                            }.pickerStyle(.segmented)
                        }
                        Picker("Background", selection: $model.captionStyle.background) {
                            ForEach(CaptionBackground.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented)
                        Text("Drag the caption on the preview to place it (on the video or in the bars).")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Button { model.pause(); Task { await model.export(into: ctx) } } label: {
                    Label("Create \(model.format.label)", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Brand.primary)
                .controlSize(.large).disabled(!model.canExport)

                attribution
            }.padding()
        }
    }

    private var resultView: some View {
        VStack(spacing: 18) {
            if let url = model.resultURL {
                resultPreview(url)
                HStack(spacing: 12) {
                    Button { Task { await model.saveToPhotos(); saved = true } } label: {
                        Label(saved ? "Saved" : "Save", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).controlSize(.large).disabled(saved)
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(Brand.primary).controlSize(.large)
                }
                Button("Make another") { saved = false; model.phase = .editing }
                    .font(.subheadline).foregroundStyle(.secondary)
                attribution
            }
        }.padding()
    }

    // MARK: Pieces

    // Controls-free AVPlayerLayer preview (the timeline is the only scrubber).
    // Tap to play/pause the selection; a play glyph shows when paused. The
    // caption renders LIVE in the chosen style and is DRAGGABLE to position it
    // (matches the burn-in because the preview box shares the export aspect).
    private var preview: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            ZStack {
                PlayerLayerView(player: model.player)
                VStack {
                    Spacer()
                    Text(model.item.clipCreditLine).font(.caption2)
                        .foregroundStyle(.white.opacity(0.85)).shadow(radius: 3).padding(.bottom, 6)
                }
                if let text = model.activeCaption {
                    captionPreview(text, boxWidth: W)
                        .position(x: model.captionStyle.position.x * W,
                                  y: model.captionStyle.position.y * H)
                        .gesture(DragGesture().onChanged { v in
                            model.captionStyle.position = CGPoint(
                                x: min(0.95, max(0.05, v.location.x / W)),
                                y: min(0.97, max(0.03, v.location.y / H)))
                        })
                }
                if !model.isPlaying {
                    Image(systemName: "play.circle.fill").font(.system(size: 50))
                        .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.35))
                        .shadow(radius: 6).allowsHitTesting(false)
                }
            }
            .frame(width: W, height: H)
            .background(Color.black)
            .clipShape(.rect(cornerRadius: 12))
            .contentShape(Rectangle())
            .onTapGesture { model.togglePlay() }
        }
        .aspectRatio(model.aspect.ratio ?? (16.0 / 9.0), contentMode: .fit)
        .frame(maxHeight: 300)
    }

    @ViewBuilder private func captionPreview(_ text: String, boxWidth: CGFloat) -> some View {
        let s = model.captionStyle
        let size = max(11, boxWidth * 0.05 * s.sizeScale)
        Text(text)
            .font(s.font.swiftUIFont(size: size))
            .foregroundStyle(s.color.swiftUIColor)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .shadow(color: s.background == .shadow ? .black.opacity(0.9) : .clear,
                    radius: s.background == .shadow ? size * 0.14 : 0, y: size * 0.04)
            .padding(.horizontal, s.background == .box ? size * 0.5 : 0)
            .padding(.vertical, s.background == .box ? size * 0.35 : 0)
            .background {
                if s.background == .box {
                    RoundedRectangle(cornerRadius: size * 0.4).fill(.black.opacity(0.55))
                }
            }
            .frame(maxWidth: boxWidth * 0.86)
    }

    // CapCut-style timeline: scroll the filmstrip to scrub (preview follows the
    // playhead), pinch to zoom, mark Set Start/End at the playhead, or drag the
    // band handles.
    private var trim: some View {
        VStack(spacing: 8) {
            HStack {
                Text(timecode(model.playheadSeconds)).foregroundStyle(.white)
                Spacer()
                Text(model.speed == 1
                     ? "Clip \(String(format: "%.1fs", model.clipDuration))"
                     : "Clip \(String(format: "%.1fs→%.1fs", model.clipDuration, model.outputDuration))")
                    .foregroundStyle(Brand.primary).bold()
                Spacer()
                Text(timecode(model.duration)).foregroundStyle(.secondary)
            }.font(.caption.monospacedDigit())

            ClipTimelineView(
                duration: model.duration, thumbnails: model.thumbnails,
                inSeconds: model.inSeconds, outSeconds: model.outSeconds,
                playheadSeconds: model.playheadSeconds, isPlaying: model.isPlaying,
                maxClip: model.format.maxDuration,
                onScrub: { model.scrub(to: $0) },
                onTrim: { i, o, p in model.trim(inSeconds: i, outSeconds: o, previewAt: p) }
            )
            .frame(height: 92)

            HStack(spacing: 12) {
                Button { model.setStart() } label: {
                    Label("Set Start", systemImage: "arrow.left.to.line").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
                Button { model.setEnd() } label: {
                    Label("Set End", systemImage: "arrow.right.to.line").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            }
            Text("Drag the filmstrip to scrub · pinch to zoom · mark Set Start/End at the playhead, or drag the handles.")
                .font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
    }

    private var attribution: some View {
        Text("Clips carry an archivewatch.org · public-domain credit and the source link in their file metadata. Source: \(model.item.title).")
            .font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
    }

    @ViewBuilder private func resultPreview(_ url: URL) -> some View {
        if model.format == .video {
            VideoPlayer(player: AVPlayer(url: url))
                .aspectRatio(model.aspect.ratio ?? (16.0 / 9.0), contentMode: .fit)
                .frame(maxHeight: 340).clipShape(.rect(cornerRadius: 12))
        } else if let img = Self.firstFrame(url) {
            Image(uiImage: img).resizable().aspectRatio(contentMode: .fit)
                .frame(maxHeight: 340).clipShape(.rect(cornerRadius: 12))
                .overlay(alignment: .bottomTrailing) {
                    Text("GIF").font(.caption2.bold()).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white).padding(10)
                }
        }
    }

    @ViewBuilder private func labeled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timecode(_ s: Double) -> String {
        let total = Int(s.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func firstFrame(_ url: URL) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// SwiftUI mappings for the caption style (the engine's UIKit mappings live in
// ClipExporter); kept in lockstep so the live preview matches the burn-in.
extension CaptionFont {
    func swiftUIFont(size: CGFloat) -> Font {
        let design: Font.Design
        switch self {
        case .system: design = .default
        case .rounded: design = .rounded
        case .serif: design = .serif
        case .mono: design = .monospaced
        }
        return .system(size: size, weight: .bold, design: design)
    }
}
extension CaptionColor {
    var swiftUIColor: Color {
        switch self {
        case .white: return .white
        case .yellow: return Color(red: 1, green: 0.84, blue: 0.04)
        case .black: return .black
        }
    }
}

#endif
