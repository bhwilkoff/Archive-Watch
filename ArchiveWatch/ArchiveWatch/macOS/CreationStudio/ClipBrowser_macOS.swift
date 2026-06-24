#if os(macOS)
import SwiftUI
import AVKit
import AVFoundation
import Combine
import UniformTypeIdentifiers
import CoreTransferable

// Unit 4 — the source browser + mark-in/out (docs/macOS-DESIGN.md §7e "browser = Storyblocks
// UX minus licensing"). Browse the catalog for CLIPPABLE titles (Rule 5c — rights gate),
// mark an in/out window on a chosen title, and add it to the timeline (also saved to the
// proxy-clip Library for reuse). Phase 3's stock-shot index slots into this same browser.

// A ProxyClip is draggable (references only — Rule 4a) from the Library onto the timeline.
// (No @retroactive: ProxyClip is declared in THIS module, so the conformance isn't retroactive.)
extension ProxyClip: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

// MARK: - Browser sheet: pick a clippable title

struct ClipBrowserSheet: View {
    let onAdd: (ProxyClip) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var mode: Mode = .titles
    @State private var results: [Catalog.Item] = []
    @State private var stock: [StockShot] = []
    @State private var marking: Catalog.Item?

    enum Mode: String, CaseIterable, Identifiable { case titles = "Titles", stock = "Stock Shots"; var id: String { rawValue } }
    private let cols = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 14)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .frame(width: 260).padding(.vertical, 8)
                Divider()
                ScrollView {
                    if mode == .titles { titlesGrid } else { stockGrid }
                }
            }
            .navigationTitle("Add a Clip")
            .searchable(text: $query, prompt: mode == .titles ? "Films, shows, people…" : "Search shots by tag…")
            .onChange(of: query) { reload() }
            .onChange(of: mode) { reload() }
            .task { StockIndexBuilder.buildSampleIfNeeded(store: store); reload() }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .frame(minWidth: 680, minHeight: 500)
        }
        .sheet(item: $marking) { item in
            MarkClipView(item: item) { proxy in onAdd(proxy); marking = nil; dismiss() }
        }
    }

    @ViewBuilder private var titlesGrid: some View {
        if results.isEmpty {
            ContentUnavailableView(query.isEmpty ? "Browse for a clip" : "No clippable results",
                                   systemImage: "magnifyingglass",
                                   description: Text("Search the public-domain catalog, then mark an in/out point."))
                .padding(.top, 60)
        } else {
            LazyVGrid(columns: cols, spacing: 16) {
                ForEach(results) { item in
                    Button { marking = item } label: { BrowserCard(item: item) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("clipCard")
                        .accessibilityLabel("Clip \(item.title)")
                }
            }
            .padding()
        }
    }

    @ViewBuilder private var stockGrid: some View {
        if stock.isEmpty {
            ContentUnavailableView("No stock shots", systemImage: "square.grid.3x3",
                description: Text("Pre-cut shots from the archive — tap to add directly. (Sample index; the shot-mining pipeline lands in a later phase.)"))
                .padding(.top, 60)
        } else {
            LazyVGrid(columns: cols, spacing: 16) {
                ForEach(stock) { shot in
                    Button { onAdd(shot.proxyClip); dismiss() } label: {
                        StockCard(shot: shot, poster: store.item(shot.archiveID)?.posterURLParsed)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    private func reload() {
        switch mode {
        case .titles:
            let raw = query.trimmingCharacters(in: .whitespaces).isEmpty
                ? store.browse(sort: .popular, limit: 60) : store.search(query)
            results = raw.filter { $0.isClippable }
        case .stock:
            stock = StockIndex(path: StockIndex.sampleURL)?.query(query) ?? []
        }
    }
}

private struct StockCard: View {
    let shot: StockShot
    let poster: URL?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                .aspectRatio(16.0/9.0, contentMode: .fit)
                .overlay {
                    if let poster { AsyncImage(url: poster) { $0.resizable().scaledToFill() } placeholder: { Color.clear } }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .bottomTrailing) {
                    Text(String(format: "%.0fs", shot.durationSeconds))
                        .font(.caption2).padding(3).background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white).padding(4)
                }
            Text(shot.title).font(.caption).lineLimit(1)
            if let tag = shot.tags.first {
                Text(tag).font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}

private struct BrowserCard: View {
    let item: Catalog.Item
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                .aspectRatio(2.0/3.0, contentMode: .fit)
                .overlay {
                    if let u = item.posterURLParsed {
                        AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(item.title).font(.caption).lineLimit(1)
        }
    }
}

// MARK: - Mark in/out on a chosen title

// Thumbnail-first clip marking. archive.org ships a per-~60s thumbnail strip for EVERY video
// (ArchiveThumbnails) — tiny + universal even when the full film is 400 MB on a slow node. So
// you navigate the whole movie + mark in/out INSTANTLY via thumbnails; the full video loads in
// the background only to verify the exact frame. You never wait on the film just to find a clip.
struct MarkClipView: View {
    let item: Catalog.Item
    let onAdd: (ProxyClip) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var player = AVPlayer()
    @State private var loader: ResilientStreamLoader?
    @State private var thumbs: [ArchiveThumb] = []
    @State private var navSeconds = 0.0          // the scrubber position — the source of truth
    @State private var scrubbing = false
    @State private var videoReady = false
    @State private var videoFailed = false
    @State private var isPlaying = false
    @State private var duration = 0.0
    @State private var inSeconds = 0.0
    @State private var outSeconds = 8.0
    @State private var label = ""

    private let tick = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    private var totalDuration: Double {
        if duration > 1 { return duration }
        if let rt = item.runtimeSeconds, rt > 0 { return Double(rt) }
        if let last = thumbs.last { return last.seconds + 60 }
        return 1
    }
    private var nearestThumb: ArchiveThumb? {
        thumbs.min { abs($0.seconds - navSeconds) < abs($1.seconds - navSeconds) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Preview: the verified video frame once it's ready, else the nearest thumbnail (instant).
            ZStack {
                Color.black
                if videoReady {
                    VideoPlayerNS(player: player, controlsStyle: .none)
                } else if let t = nearestThumb {
                    AsyncImage(url: t.url) { $0.resizable().scaledToFit() } placeholder: { Color.black }
                    if !videoFailed {
                        VStack { Spacer(); HStack {
                            Label("Loading full video to verify…", systemImage: "arrow.down.circle")
                                .font(.caption).foregroundStyle(.white.opacity(0.8))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.black.opacity(0.45), in: Capsule())
                            Spacer()
                        } }.padding(10)
                    }
                } else {
                    ProgressView("Loading thumbnails…").controlSize(.large).tint(.white).foregroundStyle(.white)
                }
            }
            .frame(width: 720, height: 405)

            // Instant thumbnail scrubber — drag to navigate the whole movie.
            ThumbnailScrubber(thumbs: thumbs, total: totalDuration, position: $navSeconds, scrubbing: $scrubbing)
                .padding(.horizontal, 14).padding(.top, 8)
                .onChange(of: navSeconds) { _, s in if videoReady, scrubbing { seek(to: s, exact: false) } }
                .onChange(of: scrubbing) { _, on in
                    if on, videoReady { player.pause(); isPlaying = false }
                    if !on, videoReady { seek(to: navSeconds, exact: true) }   // lock the exact frame
                }

            HStack(spacing: 12) {
                Button { togglePlay() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 20)
                }
                .buttonStyle(.borderless).disabled(!videoReady)
                Text(timecode(navSeconds)).font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                Spacer()
                Text(timecode(totalDuration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .onReceive(tick) { _ in
                guard videoReady else { return }
                isPlaying = player.timeControlStatus == .playing
                let t = player.currentTime().seconds
                if t.isFinite, !scrubbing, isPlaying { navSeconds = t }
            }

            Form {
                HStack {
                    Button("Set In") { inSeconds = min(navSeconds, max(0, totalDuration - 0.2)) }
                    Text(timecode(inSeconds)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Text(timecode(outSeconds)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    Button("Set Out") { outSeconds = max(navSeconds, inSeconds + 0.2) }
                }
                LabeledContent("Length", value: String(format: "%.1f s", max(0, outSeconds - inSeconds)))
                TextField("Clip name", text: $label, prompt: Text(item.title))
            }
            .formStyle(.grouped).frame(height: 150)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add to Timeline") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(outSeconds <= inSeconds)
            }
            .padding(12)
        }
        .task { await loadThumbnails() }
        .task { await loadVideo() }
        .onDisappear { player.pause() }
        .frame(width: 720, height: 700)
    }

    private func togglePlay() {
        if player.timeControlStatus == .playing { player.pause() } else { player.play() }
    }
    private func seek(to seconds: Double, exact: Bool) {
        let t = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        if exact { player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) }
        else { player.seek(to: t) }
    }

    private func loadThumbnails() async {
        guard let url = item.videoURLParsed else { return }
        let t = await ArchiveThumbnails.strip(for: url)
        if !Task.isCancelled { thumbs = t }
    }

    // The full video loads in the BACKGROUND (it's just for verifying the exact frame). It never
    // blocks navigation — thumbnails already let you scrub + mark. On ready, it jumps to wherever
    // you navigated. Failure is non-fatal: you can still mark + add using thumbnail positions.
    private func loadVideo() async {
        guard let url = item.videoURLParsed else { videoFailed = true; return }
        let (asset, l) = ResilientStreamLoader.makeAsset(for: url)
        loader = l
        let pi = AVPlayerItem(asset: asset)
        pi.preferredForwardBufferDuration = 30
        player.replaceCurrentItem(with: pi)
        if let d = try? await asset.load(.duration), d.seconds.isFinite, d.seconds > 1 { duration = d.seconds }
        for _ in 0..<300 {            // poll up to ~60s; navigation works the whole time
            if Task.isCancelled { return }
            switch pi.status {
            case .readyToPlay:
                seek(to: navSeconds, exact: true)
                videoReady = true
                return
            case .failed:
                videoFailed = true; return
            default: break
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        if !videoReady { videoFailed = true }
    }

    private func add() {
        guard let url = item.videoURLParsed else { return }
        let name = label.trimmingCharacters(in: .whitespaces)
        let proxy = ProxyClip(
            catalogItemID: item.archiveID, sourceURL: url,
            sourceRange: TimeRange(startSeconds: inSeconds, durationSeconds: outSeconds - inSeconds),
            label: name.isEmpty ? item.title : name,
            posterFrameSeconds: inSeconds, title: item.title)
        onAdd(proxy)
        dismiss()
    }

    private func timecode(_ s: Double) -> String {
        let total = max(0, Int(s))
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d.%d", m, sec, Int((s.truncatingRemainder(dividingBy: 1)) * 10))
    }
}

// A draggable thumbnail strip spanning the whole movie — instant navigation (the images are a
// few KB each). Samples evenly-spaced thumbnails to fill the width + a red playhead.
private struct ThumbnailScrubber: View {
    let thumbs: [ArchiveThumb]
    let total: Double
    @Binding var position: Double
    @Binding var scrubbing: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                if thumbs.isEmpty {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                        .overlay { ProgressView().controlSize(.small) }
                } else {
                    HStack(spacing: 1) {
                        ForEach(sampled(width: w), id: \.id) { t in
                            AsyncImage(url: t.url) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.15) }
                                .frame(width: cell(w), height: 54).clipped()
                        }
                    }
                }
                Rectangle().fill(.red).frame(width: 2, height: 54)
                    .offset(x: total > 0 ? min(max(0, w - 2), w * position / total) : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in scrubbing = true; position = max(0, min(total, total * Double(v.location.x / max(1, w)))) }
                .onEnded { _ in scrubbing = false })
        }
        .frame(height: 54)
    }

    private func count(_ w: CGFloat) -> Int { max(1, min(thumbs.count, Int(w / 72))) }
    private func cell(_ w: CGFloat) -> CGFloat { w / CGFloat(count(w)) }
    private func sampled(width w: CGFloat) -> [ArchiveThumb] {
        let n = count(w)
        guard thumbs.count > n else { return thumbs }
        return (0..<n).map { thumbs[$0 * (thumbs.count - 1) / max(1, n - 1)] }
    }
}
#endif
