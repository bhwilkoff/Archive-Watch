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
    var prepProgress: Double = 0
    var exportProgress: Double = 0
    var errorMessage: String?

    var localSource: URL?
    var player: AVPlayer?
    private var sourceAsset: AVURLAsset?
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
    var transcribing = false

    var resultURL: URL?

    var clipDuration: Double { max(0, outSeconds - inSeconds) }
    /// Output length after speed (source selection ÷ speed).
    var outputDuration: Double { speed > 0 ? clipDuration / speed : clipDuration }
    var canExport: Bool { clipDuration >= 0.5 && localSource != nil }

    init(item: Catalog.Item) { self.item = item }

    func prepare() async {
        guard let remote = item.videoURLParsed else {
            errorMessage = "This title has no video to clip."
            return
        }
        do {
            let (stream, cont) = AsyncStream.makeStream(of: Double.self)
            let pt = Task { for await p in stream { self.prepProgress = p } }
            let local = try await ClipExporter.shared.prepareSource(
                remote: remote, archiveID: item.archiveID) { cont.yield($0) }
            cont.finish(); pt.cancel()
            localSource = local
            try await loadAsset(local)
            phase = .editing
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadAsset(_ url: URL) async throws {
        let asset = AVURLAsset(url: url)
        sourceAsset = asset
        let dur = try await asset.load(.duration).seconds
        duration = dur.isFinite ? dur : 0
        outSeconds = min(duration, 15)
        player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        await generateThumbnails(asset: asset)
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
        let n = 12
        let times = (0..<n).map { CMTime(seconds: duration * Double($0) / Double(n), preferredTimescale: 600) }
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

    func export(into ctx: ModelContext) async {
        guard let local = localSource else { return }
        phase = .exporting
        exportProgress = 0
        let spec = ClipSpec(
            sourceURL: local, archiveID: item.archiveID, title: item.title,
            sourceDetailsURL: item.sourceDetailsURL, creditLine: item.clipCreditLine,
            inSeconds: inSeconds, durationSeconds: clipDuration, aspect: aspect,
            caption: caption.trimmingCharacters(in: .whitespacesAndNewlines), format: format,
            look: look, speed: speed, blurredFill: blurredFill, captionCues: captionCues)
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
        guard let local = localSource, !transcribing else { return }
        transcribing = true
        defer { transcribing = false }
        do {
            captionCues = try await ClipExporter.shared.transcribe(
                sourceURL: local, inSeconds: inSeconds, duration: clipDuration)
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
    @State private var rangeTask: Task<Void, Never>?
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
        .onDisappear { rangeTask?.cancel(); model.player?.pause() }
    }

    // MARK: Phases

    private var preparing: some View {
        VStack(spacing: 16) {
            ProgressView(value: model.prepProgress)
                .progressViewStyle(.linear).tint(Brand.primary).frame(maxWidth: 240)
            Text("Preparing clip…").font(.subheadline).foregroundStyle(.secondary)
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
                labeled("Caption") {
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
                }
                Button { rangeTask?.cancel(); Task { await model.export(into: ctx) } } label: {
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

    private var preview: some View {
        ZStack {
            if let player = model.player {
                VideoPlayer(player: player)
            } else { Color.black }
            VStack {
                Spacer()
                if !model.caption.isEmpty {
                    Text(model.caption).font(.headline.bold()).foregroundStyle(.white)
                        .multilineTextAlignment(.center).shadow(radius: 4)
                        .padding(.horizontal).padding(.bottom, 4)
                }
                Text(model.item.clipCreditLine).font(.caption2)
                    .foregroundStyle(.white.opacity(0.85)).shadow(radius: 3).padding(.bottom, 6)
            }
        }
        .aspectRatio(model.aspect.ratio ?? (16.0 / 9.0), contentMode: .fit)
        .frame(maxHeight: 300)
        .background(Color.black)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(alignment: .bottomTrailing) {
            Button { playRange() } label: {
                Image(systemName: "play.circle.fill").font(.title)
                    .symbolRenderingMode(.palette).foregroundStyle(.white, Brand.primary)
            }.padding(10)
        }
    }

    private var trim: some View {
        VStack(spacing: 6) {
            TrimStrip(thumbnails: model.thumbnails, duration: model.duration,
                      inSeconds: $model.inSeconds, outSeconds: $model.outSeconds,
                      maxClip: model.format.maxDuration) { model.seek(to: $0) }
            HStack {
                Text(timecode(model.inSeconds))
                Spacer()
                Text(model.speed == 1
                     ? String(format: "%.1fs", model.clipDuration)
                     : String(format: "%.1fs→%.1fs", model.clipDuration, model.outputDuration))
                    .foregroundStyle(Brand.primary).bold()
                Spacer()
                Text(timecode(model.outSeconds))
            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
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

    private func playRange() {
        guard let p = model.player else { return }
        model.seek(to: model.inSeconds)
        p.play()
        let dur = model.clipDuration
        rangeTask?.cancel()
        rangeTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(dur * 1_000_000_000))
            p.pause()
        }
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

// Two-handle trim selection over a thumbnail filmstrip. Dragging a handle
// sets the in/out point (clamped to a 0.5s minimum and the format's max),
// and scrubs the preview to the handle's time.
private struct TrimStrip: View {
    let thumbnails: [UIImage]
    let duration: Double
    @Binding var inSeconds: Double
    @Binding var outSeconds: Double
    let maxClip: Double
    var onScrub: (Double) -> Void

    private let stripHeight: CGFloat = 56
    private let handleW: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let safeDur = max(duration, 0.001)
            let inX = CGFloat(inSeconds / safeDur) * w
            let outX = CGFloat(outSeconds / safeDur) * w
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, img in
                        Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: w / CGFloat(max(thumbnails.count, 1)), height: stripHeight)
                            .clipped()
                    }
                }
                .frame(width: w, height: stripHeight)
                .clipShape(.rect(cornerRadius: 8))
                .background(Color.black)

                Rectangle().fill(.black.opacity(0.55)).frame(width: inX, height: stripHeight)
                Rectangle().fill(.black.opacity(0.55))
                    .frame(width: max(0, w - outX), height: stripHeight).offset(x: outX)
                RoundedRectangle(cornerRadius: 6).stroke(Brand.primary, lineWidth: 3)
                    .frame(width: max(0, outX - inX), height: stripHeight).offset(x: inX)

                handle.offset(x: inX - handleW / 2)
                    .gesture(DragGesture().onChanged { v in
                        let raw = Double(v.location.x / w) * duration
                        let t = min(max(raw, 0), outSeconds - 0.5)
                        let clamped = max(t, outSeconds - maxClip)
                        inSeconds = clamped; onScrub(clamped)
                    })
                handle.offset(x: outX - handleW / 2)
                    .gesture(DragGesture().onChanged { v in
                        let raw = Double(v.location.x / w) * duration
                        let t = min(max(raw, inSeconds + 0.5), duration)
                        let clamped = min(t, inSeconds + maxClip)
                        outSeconds = clamped; onScrub(clamped)
                    })
            }
        }
        .frame(height: stripHeight)
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 4).fill(Brand.primary)
            .frame(width: handleW, height: stripHeight + 10)
            .overlay(Image(systemName: "equal").font(.system(size: 11, weight: .black))
                .foregroundStyle(.white).rotationEffect(.degrees(90)))
            .shadow(radius: 2)
    }
}
#endif
