#if os(macOS)
import SwiftUI
import SwiftData
import AppKit
import AVKit
import UniformTypeIdentifiers

// The Creation Studio editor scene (docs/macOS-DESIGN.md §2 — the DocumentGroup face,
// distinct from the WindowGroup Library face; Rule "Library ≠ Project"). The Mac-native NLE
// shell: a NavigationSplitView with the proxy-clip library on the leading side, a VSplitView
// detail column holding the program monitor (live preview) over the transport + AppKit
// timeline (ClipTimelineView), and a trailing .inspector(). All editor state + edits live in
// EditorModel; the document autosaves the .archiveproj. (Library sidebar grid + drag-onto-
// timeline = Unit 4; the "Add Clip" toolbar button is the Unit-3 stand-in.)

struct ProjectEditorView: View {
    @ObservedObject var document: ClipProjectDocument
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var ctx
    @Environment(\.undoManager) private var undoManager
    // The document's name on macOS IS its filename — SwiftUI's DocumentGroup shows it in the
    // window title bar and renames it via the title-bar proxy popover / File ▸ Rename / first ⌘S.
    // We READ it here (macOS 14+ `documentConfiguration.fileURL`) to seed export/publish names,
    // rather than keeping a second editable "title" field that competes with the filename.
    @Environment(\.documentConfiguration) private var documentConfiguration
    @State private var model: EditorModel
    @State private var inspectorShown = true
    @State private var exporter = ExportService()
    @State private var showBrowser = false
    @State private var showSupercut = false
    @State private var showPublishSheet = false
    @State private var publisher = PublishService()
    @State private var testMark: Catalog.Item?     // AW_CS_TEST=markclip presents this in a sheet
    @State private var markItem: Catalog.Item?     // "Open in Creation Studio" mark-in/out target
    @State private var showExportSheet = false

    init(document: ClipProjectDocument) {
        self.document = document
        _model = State(initialValue: EditorModel(document: document))
    }

    private var project: Binding<ClipProject> {
        Binding(get: { model.project }, set: { model.project = $0 })
    }

    /// The document's display name (filename minus extension) for seeding export/publish names.
    /// Empty for an as-yet-unsaved "Untitled" document — callers supply their own fallback.
    private var documentName: String {
        documentConfiguration?.fileURL?.deletingPathExtension().lastPathComponent ?? ""
    }

    var body: some View {
        // A fixed 3-pane editor — NOT NavigationSplitView/.inspector (whose columns stay
        // user-draggable and let the window inflate). Fixed-width side panels + a flexible
        // center, so the window resizes like a normal Mac window with the panels pinned.
        HStack(spacing: 0) {
            LibrarySidebar(model: model)
                .frame(width: 240)
            Divider()

            VSplitView {
                // Program monitor — the live preview (rebuild-and-swap composition, Rule 3b).
                ZStack {
                    Color.black
                    if model.project.timeline.clips.isEmpty {
                        ContentUnavailableView("Empty Timeline", systemImage: "timeline.selection")
                            .foregroundStyle(.white.opacity(0.5))
                    } else {
                        VideoPlayerNS(player: model.player, controlsStyle: .none)   // transport bar is the only transport
                            .allowsHitTesting(false)   // the AVPlayerView must NOT swallow the overlay's drag
                        // Live text overlays — the Core Animation tool is EXPORT-only, so render
                        // them here (timed to the playhead, placed in the 16:9 video frame) so the
                        // preview is WYSIWYG and "Add Text" is visible.
                        TextOverlayPreview(model: model, renderSize: model.project.timeline.renderSize)
                    }
                    if model.isBuildingPreview || model.isRefining || !model.prepStatus.failures.isEmpty || model.supercutVerifyNote != nil || model.previewBlockedReason != nil {
                        let s = model.prepStatus
                        VStack(spacing: 6) {
                            if let note = model.supercutVerifyNote {
                                Label(note, systemImage: "checkmark.seal")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.85))
                            }
                            if let blocked = model.previewBlockedReason {
                                // Whole-pass failure: archive.org is refusing connections (rate-limited)
                                // or you're offline. Clear, not a frozen progress number; auto-retries.
                                Label("Can’t load clips — \(blocked). Retrying…", systemImage: "wifi.slash")
                                    .font(.caption).foregroundStyle(.orange)
                                    .multilineTextAlignment(.center)
                                Text("archive.org limits how many videos load at once — give it a moment.")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.6))
                                    .multilineTextAlignment(.center)
                            } else if model.isBuildingPreview {
                                ProgressView().controlSize(.small).tint(.white)
                                Text("Preparing clips — \(s.ready) of \(s.total) ready" +
                                     (s.caching > 0 ? " · \(s.caching) downloading" : "") +
                                     (s.failures.count > 0 ? " · \(s.failures.count) failed" : ""))
                                    .font(.caption).foregroundStyle(.white.opacity(0.85))
                            }
                            if model.previewBlockedReason == nil, let fail = s.failures.first {
                                Label(s.failures.count == 1 ? "1 clip couldn’t load: \(fail)"
                                                            : "\(s.failures.count) clips couldn’t load: \(fail)",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                            if model.isRefining {
                                ProgressView(value: Double(model.verifyDone),
                                             total: Double(max(1, model.verifyTotal)))
                                    .controlSize(.small).tint(.white).frame(width: 170)
                                Label("Verifying each clip speaks the phrase — \(model.verifyDone) of \(model.verifyTotal)",
                                      systemImage: "waveform.badge.magnifyingglass")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        .padding(8).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                        // Pin the status to a CORNER and make it non-interactive, so it never covers the
                        // video or blocks the user from scrubbing/editing while the last clips finish in
                        // the background (owner: "a persistent note … stops the user from doing anything").
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(10)
                        .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 220)

                VStack(spacing: 0) {
                    transportBar
                    Divider()
                    ClipTimelineView(model: model)
                        .frame(minHeight: 200)   // video lane + Titles/Music/Voiceover lanes
                        // Drag a clip from the Library onto the timeline. Magnetic single
                        // track, so the drop appends at the end regardless of drop x.
                        .dropDestination(for: ProxyClip.self) { proxies, _ in
                            proxies.forEach { model.addClip(from: $0) }
                            return !proxies.isEmpty
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) { exportStatusBar }

            if inspectorShown {
                Divider()
                ProjectInspector(project: project, model: model)
                    .frame(width: 280)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItemGroup {
                Button { showBrowser = true } label: {
                    Label("Add Clip", systemImage: "plus.rectangle.on.folder")
                }
                Button { model.splitAtPlayhead() } label: {
                    Label("Split", systemImage: "scissors")
                }.disabled(model.project.timeline.clips.isEmpty)
                Button { model.addTextOverlay() } label: {
                    Label("Add Text", systemImage: "textformat")
                }.disabled(model.project.timeline.clips.isEmpty)
                Button { pickMusic() } label: {
                    Label("Add Music", systemImage: "music.note")
                }
                if model.isRecordingVoiceover {
                    Button { model.stopVoiceover() } label: {
                        Label("Stop", systemImage: "stop.circle.fill")
                    }.tint(.red)
                } else {
                    // Opens the voiceover SETUP in the inspector (pick a mic) — doesn't record yet (#9).
                    Button { inspectorShown = true; model.armVoiceover() } label: {
                        Label("Voiceover", systemImage: "mic")
                    }
                }
                Button { showSupercut = true } label: {
                    Label("Supercut", systemImage: "text.magnifyingglass")
                }
                Button { showExportSheet = true } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(model.project.timeline.clips.isEmpty || exporter.isBusy)
                Button { model.pause(); showPublishSheet = true } label: {
                    Label("Publish", systemImage: "icloud.and.arrow.up")
                }
                .disabled(model.project.timeline.clips.isEmpty || exporter.isBusy)
                Button { inspectorShown.toggle() } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
            }
        }
        .onAppear { model.undoManager = undoManager }   // ⌘Z + Edit menu drive our snapshot history
        .task {
            // The Add-a-Clip browser (TV Episodes filter + live stock shots) needs the FULL
            // catalog, not the bundled seed. The editor can open as the first window (File ▸ New),
            // so RootView's load() may not have run — kick the (coalescing, idempotent) load here
            // too. Without this, opening Creation Studio first leaves Add-a-Clip on the seed:
            // no tv-episode items and a tiny live stock-shot pool.
            await store.load()
            // A title queued by Detail's "Open in Creation Studio" — present its mark-in/out editor.
            if let pending = store.pendingClipItem {
                store.pendingClipItem = nil
                markItem = pending
            }
            // Screenshot/test hooks (AW_CS_TEST) — the DocumentGroup reliably opens this editor
            // window on launch, so we populate it here for CLI visual verification.
            // The self-test/perf harness normally rides RootView's .task, but in a doc-app
            // launch RootView may not open — kick it here too (one-shot guarded).
            if ProcessInfo.processInfo.environment["AW_CS_PUBTEST"] == "1" { PublishService.selfTest() }
            if ProcessInfo.processInfo.environment["AW_CS_SUPERTEST"] == "1" { await store.load(); await SubtitleIndexBuilder.selfTest(store: store) }
            if CreationStudioSelfTest.isEnabled { await store.load(); await CreationStudioSelfTest.run(store: store) }
            if let mode = CreationStudioTest.mode {
                await store.load()                                   // RootView may not open in a doc-app launch
                var t = 0; while store.randomPlayable() == nil && t < 90 { try? await Task.sleep(for: .seconds(1)); t += 1 }
                if mode == "editor", model.project.timeline.clips.isEmpty {
                    CreationStudioTest.populate(model, store)
                } else if mode == "markclip" {
                    testMark = CreationStudioTest.clippable(store)   // presents the Add-Clip scrubber
                }
            }
            model.loadFilmstrips()   // instant filmstrips for already-present (saved-project) clips
            if !model.project.timeline.clips.isEmpty { await model.rebuildPreview() }
            // Supercut benchmark (AW_CS_BENCH=50) runs HERE — on the VISIBLE editor's bound model —
            // so the REAL UI load (per-clip filmstrips, timeline render, sidebar) contends exactly as
            // when a user adds clips by hand. Running it on a standalone model would measure the
            // pipeline in isolation and miss that contention (owner 2026-06-27).
            if CreationStudioBench.isEnabled {
                await store.load()
                await CreationStudioBench.run(model: model, store: store)
            }
            // Feature audit (AW_CS_AUDIT=1) — exercises every editor action on this VISIBLE model and
            // asserts the PREVIEW composition reflects each edit (not just the timeline model), so a
            // regression like "trim grows the block but the preview never changes" is caught.
            if CreationStudioFeatureAudit.isEnabled {
                await store.load()
                await CreationStudioFeatureAudit.run(model: model, store: store)
            }
            // Robustness stress harness (AW_CS_STRESS=50) — real multi-film supercut + verify, sampling
            // the preview-available / timeline==preview / no-hang invariants.
            if CreationStudioStress.isEnabled {
                await store.load()
                await CreationStudioStress.run(model: model, store: store)
            }
            // Real-project audit (AW_CS_PROJECTS=1) — loads each .archiveproj the owner provided (copied
            // into the container Documents) and proves every feature against the REAL multi-source clips.
            if CreationStudioProjectAudit.isEnabled {
                await store.load()
                await CreationStudioProjectAudit.run(model: model, store: store)
            }
            // Supercut-path audit (AW_CS_SUPERCUT=1) — builds a 50-clip supercut from the owner's phrases
            // and proves processing completes + the overlay clears + dead clips are removed + it plays through.
            if CreationStudioSupercutAudit.isEnabled {
                await store.load()
                await CreationStudioSupercutAudit.run(model: model, store: store)
            }
        }
        .onChange(of: model.project.burnAttribution) { Task { await model.rebuildPreview() } }
        .sheet(isPresented: $showBrowser) {
            ClipBrowserSheet { proxy in addToLibraryAndTimeline(proxy) }
                .environment(store)
        }
        .sheet(item: $testMark) { MarkClipView(item: $0) { _ in }.environment(store) }
        .sheet(item: $markItem) { item in
            MarkClipView(item: item) { proxy in addToLibraryAndTimeline(proxy) }.environment(store)
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSettingsSheet { format in runExport(format) }
        }
        .sheet(isPresented: $showPublishSheet) {
            PublishSheet(project: model.project, defaultTitle: documentName,
                         publisher: publisher, exporter: exporter)
        }
        .sheet(isPresented: $showSupercut) {
            SupercutSheet(model: model).environment(store)
        }
        .background(WindowFitter())     // keep the window within the screen (DocumentGroup ignores .defaultSize)
    }

    /// A marked clip joins the proxy-clip Library (for reuse) and the timeline.
    private func addToLibraryAndTimeline(_ proxy: ProxyClip) {
        ctx.insert(LibraryClip(from: proxy))
        try? ctx.save()
        model.addClip(from: proxy)
    }

    /// Import an audio file as a NEW music clip (multiple allowed). A toolbar ACTION, not inspector state.
    private func pickMusic() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Music"
        if panel.runModal() == .OK, let url = panel.url { model.addMusic(from: url) }
    }

    private var transportBar: some View {
        HStack(spacing: 14) {
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
            }
            .keyboardShortcut(.space, modifiers: [])
            Text(timecode(model.playheadSeconds) + " / " + timecode(model.totalDuration))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Spacer()
            Button { model.zoom(by: 1.0 / 1.5) } label: { Image(systemName: "minus.magnifyingglass") }
            Button { model.zoom(by: 1.5) } label: { Image(systemName: "plus.magnifyingglass") }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
    }

    private func timecode(_ s: Double) -> String {
        String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }

    @ViewBuilder private var exportStatusBar: some View {
        switch exporter.phase {
        case .idle:
            EmptyView()
        case .done:
            if let url = exporter.outputURL {
                HStack {
                    Label("Exported", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Spacer()
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                .padding(10).background(.ultraThinMaterial).padding(12)
            }
        case .failed(let message):
            HStack {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Spacer()
            }
            .padding(10).background(.ultraThinMaterial).padding(12)
        default:
            HStack(spacing: 12) {
                ProgressView(value: exporter.progress).frame(maxWidth: 240)
                Text(phaseLabel).font(.caption).foregroundStyle(.secondary)
            }
            .padding(10).background(.ultraThinMaterial).padding(12)
        }
    }

    private var phaseLabel: String {
        switch exporter.phase {
        case .caching: "Caching clips…"
        case .composing: "Composing…"
        case .exporting: "Exporting…"
        default: ""
        }
    }

    private func runExport(_ format: ExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == .h264 ? .mpeg4Movie : .quickTimeMovie]
        // Seed the Save panel from the document's own name (its filename); "Archive Watch" only
        // when the project hasn't been saved yet (no filename to borrow).
        let base = documentName.isEmpty ? "Archive Watch" : documentName
        panel.nameFieldStringValue = "\(base).\(format.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.pause()                 // an export must not leave the preview playing (owner 2026-06-29)
        let project = model.project
        Task { await exporter.export(project, to: url, format: format) }
    }
}

// Keeps the editor window within the visible screen and at a sensible opening size — the
// DocumentGroup ignores .defaultSize, so a new window can open wider than a smaller display
// (clipping the inspector). Runs once: caps an oversized window to fit, centered; never shrinks
// a window the user has already sized down, and never fights manual resizes afterward.
private struct WindowFitter: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { FitView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class FitView: NSView {
        private var fitted = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !fitted, window != nil else { return }
            fitted = true
            // Run AFTER state restoration has set the window's frame, else we'd cap a
            // not-yet-restored size and restoration would re-inflate it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.fit() }
        }
        private func fit() {
            guard let window, let vis = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
            var f = window.frame
            let maxW = min(1280, vis.width - 40), maxH = min(840, vis.height - 40)
            if f.width <= maxW && f.height <= maxH && vis.contains(f) { return }
            f.size.width = min(f.width, maxW)
            f.size.height = min(f.height, maxH)
            f.origin.x = max(vis.minX + 20, min(f.origin.x, vis.maxX - f.width - 20))
            f.origin.y = max(vis.minY + 20, min(f.origin.y, vis.maxY - f.height - 20))
            window.setFrame(f, display: true, animate: false)
        }
    }
}

// Renders the active text overlays over the program monitor (the export bakes them via the
// Core Animation tool, which can't run in live playback). Placed inside the 16:9 video frame so
// position matches the export; shown only while the playhead is inside each overlay's range.
private struct TextOverlayPreview: View {
    let model: EditorModel
    let renderSize: RenderSize
    // Live drag position (canvas coords) for the overlay being dragged. Driving `.position` from
    // LOCAL @State guarantees the text follows the cursor immediately while PAUSED — the model
    // round-trip (updateOverlay → overlayRevision) alone didn't repaint mid-drag (#8).
    @State private var dragID: UUID?
    @State private var dragPoint: CGPoint = .zero

    var body: some View {
        // Establish a dependency on the TRACKED overlay-revision token so this body re-evaluates
        // when an overlay's position/text/etc. changes even while the preview is PAUSED.
        let _ = model.overlayRevision
        return GeometryReader { geo in
            let rect = fitRect(aspect: renderSize.width / max(1, renderSize.height), in: geo.size)
            ForEach(active) { ov in
                let selected = model.selectedOverlayID == ov.id
                let px = dragID == ov.id ? dragPoint.x : rect.minX + ov.positionX * rect.width
                let py = dragID == ov.id ? dragPoint.y : rect.minY + ov.positionY * rect.height
                Text(ov.text)
                    .font(.system(size: max(8, rect.width * ov.fontScale), weight: .bold))
                    .foregroundStyle(Color(CompositionBuilder.cgColor(hex: ov.colorHex)))
                    .shadow(color: ov.hasBackground ? .black.opacity(0.85) : .clear,
                            radius: max(1, rect.width * ov.fontScale * 0.06), x: 0, y: 1)
                    .multilineTextAlignment(.center)
                    .padding(4)
                    .overlay {     // selection ring + drag affordance
                        if selected {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                    }
                    .frame(maxWidth: rect.width * 0.92)
                    .contentShape(Rectangle())   // the whole padded box is grabbable, not just the glyphs
                    .position(x: px, y: py)
                    .gesture(
                        // Drag in the CANVAS coordinate space (the GeometryReader), not the text's
                        // own space — otherwise value.location is relative to the small text frame.
                        DragGesture(coordinateSpace: .named("ovlCanvas"))
                            .onChanged { value in
                                guard rect.width > 1, rect.height > 1 else { return }
                                model.selection = .overlay(ov.id)
                                let cx = min(rect.maxX, max(rect.minX, value.location.x))
                                let cy = min(rect.maxY, max(rect.minY, value.location.y))
                                dragID = ov.id; dragPoint = CGPoint(x: cx, y: cy)   // move LIVE
                                if var o = model.textOverlays.first(where: { $0.id == ov.id }) {
                                    o.positionX = (cx - rect.minX) / rect.width
                                    o.positionY = (cy - rect.minY) / rect.height
                                    model.updateOverlay(o)                          // persist
                                }
                            }
                            .onEnded { _ in dragID = nil }
                    )
            }
        }
        .coordinateSpace(.named("ovlCanvas"))
    }

    // While editing, the SELECTED overlay is always shown (so you can drag it even when the
    // playhead is outside its time range); others show only within their range.
    private var active: [TextOverlay] {
        let t = model.playheadSeconds
        return model.textOverlays.filter {
            $0.id == model.selectedOverlayID ||
            (t >= $0.timelineRange.start.seconds && t <= $0.timelineRange.endSeconds)
        }
    }
    private func fitRect(aspect: Double, in size: CGSize) -> CGRect {
        let a = max(0.1, aspect)
        var w = size.width, h = w / a
        if h > size.height { h = size.height; w = h * a }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
}

// MARK: - Export settings (#5)

private struct ExportSettingsSheet: View {
    let onExport: (ExportFormat) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var format: ExportFormat = .h264

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Export").font(.title2.bold()).padding([.top, .horizontal], 18)
            Form {
                Picker("Format", selection: $format) {
                    ForEach(ExportFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Text(format.blurb).font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Choose Destination…") { dismiss(); onExport(format) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 420)
    }
}

// MARK: - Library sidebar (proxy-clip library — Unit 4 wires the real grid + drag-drop)

private struct LibrarySidebar: View {
    let model: EditorModel
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var ctx
    @Query(sort: \LibraryClip.addedAt, order: .reverse) private var clips: [LibraryClip]
    // Manual selection by clip.id — NOT List(selection:). On macOS, List captures in-bounds drags
    // for range-selection, so a .draggable inside a List never starts a drag (it just multi-selects).
    // A ScrollView+LazyVStack has no such capture, so .draggable works for drag-to-timeline and we
    // handle selection ourselves: plain click = one, ⌘-click = toggle, ⇧-click = range.
    @State private var selection: Set<String> = []
    @State private var anchor: String?

    private func proxy(for clip: LibraryClip) -> ProxyClip {
        clip.proxyClip ?? ProxyClip(
            catalogItemID: clip.catalogItemID,
            sourceURL: URL(string: clip.sourceURLString) ?? URL(fileURLWithPath: "/"),
            sourceRange: TimeRange(startSeconds: clip.inSeconds,
                                   durationSeconds: max(0.1, clip.outSeconds - clip.inSeconds)),
            label: clip.label, title: clip.title, caption: clip.caption)
    }

    /// The clips a context action applies to: the full selection if the acted-on clip is part of
    /// it, otherwise just that clip (the standard Finder/Photos right-click behavior).
    private func targets(for clip: LibraryClip) -> [LibraryClip] {
        selection.contains(clip.id) && selection.count > 1 ? selectedClips : [clip]
    }

    private func addToTimeline(_ items: [LibraryClip]) {
        items.forEach { model.addClip(from: proxy(for: $0)) }
    }

    private func delete(_ items: [LibraryClip]) {
        items.forEach { ctx.delete($0) }
        selection.subtract(items.map(\.id))
        try? ctx.save()
    }

    private var selectedClips: [LibraryClip] { clips.filter { selection.contains($0.id) } }

    /// Click selection with the standard macOS modifiers (read live from NSEvent).
    private func selectOnTap(_ clip: LibraryClip) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.contains(clip.id) { selection.remove(clip.id) } else { selection.insert(clip.id) }
            anchor = clip.id
        } else if flags.contains(.shift), let a = anchor,
                  let i = clips.firstIndex(where: { $0.id == a }),
                  let j = clips.firstIndex(where: { $0.id == clip.id }) {
            selection.formUnion(clips[min(i, j)...max(i, j)].map(\.id))
        } else {
            selection = [clip.id]; anchor = clip.id
        }
    }

    @ViewBuilder private func clipRow(_ clip: LibraryClip) -> some View {
        LibraryRow(clip: clip,
                   poster: store.item(clip.catalogItemID)?.posterURLParsed,
                   selected: selection.contains(clip.id),
                   onAdd: { model.addClipAtPlayhead(from: proxy(for: clip)) })
            .contentShape(Rectangle())
            .onTapGesture { selectOnTap(clip) }            // single-tap selects (＋ adds)
            .draggable(containerItemID: proxy(for: clip).id)   // ProxyClip.ID (UUID); part of the drag container
            .contextMenu {
                let t = targets(for: clip)
                Button { addToTimeline(t) } label: { Label("Add \(t.count) to Timeline", systemImage: "plus") }
                Divider()
                Button(role: .destructive) { delete(t) } label: {
                    Label("Delete\(t.count > 1 ? " \(t.count)" : "")", systemImage: "trash")
                }
            }
    }

    var body: some View {
        Group {
            if clips.isEmpty {
                ContentUnavailableView {
                    Label("No Clips Yet", systemImage: "film.stack")
                } description: {
                    Text("Use “Add Clip” to mark an in/out point on a public-domain title. Saved clips appear here — drag a clip onto the timeline, or use ＋.")
                }
            } else {
                VStack(spacing: 0) {
                    // ScrollView + LazyVStack (NOT List) so .draggable actually starts a drag instead
                    // of being eaten by List's range-selection. The whole row is the drag source and
                    // selection is handled in selectOnTap — both work because we're out of List.
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            // Drag-CONTAINER multi-drag (macOS 26+): dragging a SELECTED row carries
                            // the WHOLE selection as a native stack; a non-selected row drags just
                            // itself. The container maps the dragged ids back to proxies; the
                            // timeline's dropDestination adds them all.
                            ForEach(clips) { clip in clipRow(clip) }
                                .dragContainer(for: ProxyClip.self) { ids in
                                    clips.map { proxy(for: $0) }.filter { ids.contains($0.id) }
                                }
                                .dragContainerSelection(selectedClips.map { proxy(for: $0).id })
                        }
                        .padding(8)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    // Batch action bar — operates on the multi-selection.
                    if !selection.isEmpty {
                        Divider()
                        HStack(spacing: 8) {
                            Text("\(selection.count) selected").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { addToTimeline(selectedClips) } label: {
                                Label("Add", systemImage: "plus").labelStyle(.iconOnly)
                            }.help("Add selected clips to the timeline")
                            Button(role: .destructive) { delete(selectedClips) } label: {
                                Label("Delete", systemImage: "trash").labelStyle(.iconOnly)
                            }.help("Delete selected clips from the Library")
                        }
                        .buttonStyle(.borderless)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.bar)
                    }
                }
                // ⌫ deletes the selection (standard macOS list behavior).
                .onDeleteCommand { delete(selectedClips) }
            }
        }
        .navigationTitle("Library")
    }
}

private struct LibraryRow: View {
    let clip: LibraryClip
    let poster: URL?
    let selected: Bool
    let onAdd: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            // The clip's actual in-point frame (the row itself is the drag source — see the ForEach).
            ClipThumbnailView(catalogItemID: clip.catalogItemID,
                              sourceURL: URL(string: clip.sourceURLString),
                              atSeconds: clip.inSeconds,
                              fallbackPoster: poster)
                .frame(width: 44, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                // Film title — word-wraps so longer titles read fully (owner #5).
                Text(clip.title.isEmpty ? clip.label : clip.title)
                    .font(.subheadline).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                // The spoken text/dialogue in the clip (supercut cue), when present — word-wrapped.
                if !clip.caption.isEmpty {
                    Text("“\(clip.caption)”")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                Text(String(format: "%.1fs", max(0, clip.outSeconds - clip.inSeconds)))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            // Add this clip to the timeline at the playhead. A Button (not a tap gesture) so it
            // never interferes with row selection.
            Button(action: onAdd) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
            .help("Add to the timeline at the playhead")
        }
        .padding(.vertical, 5).padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.20) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

// MARK: - Inspector

// The inspector edits ONLY the current selection — a video clip, a text overlay, an audio clip,
// or (nothing selected) the project itself. Every control is live-editable; no read-only stats /
// dates kitchen sink. Adding music/voiceover/clips/text are TOOLBAR actions, not inspector state.
// Voiceover setup + record, in the inspector (owner #9). Choose the mic, then Record; Stop is always
// visible while recording. Recording begins at the playhead.
private struct VoiceoverPanel: View {
    @Bindable var model: EditorModel
    var body: some View {
        Section {
            Picker("Microphone", selection: $model.selectedAudioInputID) {
                if model.audioInputs.isEmpty { Text("No microphones found").tag(String?.none) }
                ForEach(model.audioInputs) { Text($0.name).tag(Optional($0.id)) }
            }
            .disabled(model.isRecordingVoiceover)
            Text("Records onto a new voiceover track starting at the playhead.")
                .font(.caption).foregroundStyle(.secondary)
            if let err = model.voiceoverError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                if model.isRecordingVoiceover {
                    Button { model.stopVoiceover() } label: {
                        Label("Stop", systemImage: "stop.circle.fill")
                    }.tint(.red).keyboardShortcut(.defaultAction)
                    Label("Recording…", systemImage: "record.circle.fill")
                        .font(.caption).foregroundStyle(.red).symbolEffect(.pulse)
                } else {
                    Button { model.startVoiceover() } label: {
                        Label("Record", systemImage: "record.circle")
                    }.tint(.red).disabled(model.selectedAudioInputID == nil)
                    Button("Cancel") { model.cancelVoiceover() }
                }
            }
        } header: {
            Label("Voiceover", systemImage: "mic")
        }
    }
}

private struct ProjectInspector: View {
    @Binding var project: ClipProject
    let model: EditorModel

    var body: some View {
        Form {
            // Voiceover setup/record lives HERE (owner #9) — pick the mic, then Record/Stop, so the
            // controls are always visible and you configure the input BEFORE recording.
            if model.voiceoverPhase != .idle {
                VoiceoverPanel(model: model)
            }
            // Multi-selection banner — bulk delete; the focused element's editor stays below so you
            // can still tweak it (HIG: a multi-selection shows a count + the common action).
            if model.selectedIDs.count > 1 {
                Section {
                    Button("Delete \(model.selectedIDs.count) Items", systemImage: "trash", role: .destructive) {
                        model.deleteSelection()
                    }
                } header: {
                    Label("\(model.selectedIDs.count) items selected", systemImage: "checklist")
                }
            }
            // The SELECTION editor (if anything is selected).
            switch model.selection {
            case .overlay(let id):
                if let ov = model.textOverlays.first(where: { $0.id == id }) {
                    TextOverlayEditor(
                        overlay: Binding(get: { model.textOverlays.first(where: { $0.id == id }) ?? ov },
                                         set: { model.updateOverlay($0) }),
                        onDelete: { model.deleteOverlay(id) })
                }
            case .clip:
                if let clip = model.selectedClip { clipInspector(clip) }
            case .audio:
                if let a = model.selectedAudio { audioInspector(a) }
            case .none:
                EmptyView()
            }
            // The PROJECT settings are ALWAYS available (owner ask: global project info —
            // canvas, frame rate, burned-in attribution — was only reachable with nothing
            // selected). A collapsible group so it never crowds the selection editor.
            projectSettings
        }
        .formStyle(.grouped)
    }

    // MARK: Clip selection

    @ViewBuilder private func clipInspector(_ clip: TimelineClip) -> some View {
        Section {
            sliderRow("Audio", icon: clip.audioVolume == 0 ? "speaker.slash" : "speaker.wave.2",
                      value: Binding(get: { clip.audioVolume }, set: { model.setClipVolume(clip.id, $0) }),
                      range: 0...1.5, format: { "\(Int($0 * 100))%" })
            let maxFade = max(0.1, clip.sourceRange.duration.seconds / 2)
            sliderRow("Fade in", icon: "circle.lefthalf.filled",
                      value: Binding(get: { clip.fadeInSeconds }, set: { model.setClipFade(clip.id, fadeIn: $0) }),
                      range: 0...maxFade, format: { String(format: "%.1fs", $0) })
            sliderRow("Fade out", icon: "circle.righthalf.filled",
                      value: Binding(get: { clip.fadeOutSeconds }, set: { model.setClipFade(clip.id, fadeOut: $0) }),
                      range: 0...maxFade, format: { String(format: "%.1fs", $0) })
            Picker("Look", selection: Binding(get: { clip.look }, set: { model.setClipLook(clip.id, $0) })) {
                ForEach(ClipLook.allCases) { Text($0.label).tag($0) }
            }
            if model.clips.first?.id != clip.id {
                sliderRow("Transition", icon: "square.on.square.dashed",
                          value: Binding(get: { clip.transitionInSeconds }, set: { model.setClipTransition(clip.id, $0) }),
                          range: 0...maxFade, format: { String(format: "%.1fs", $0) })
                if clip.transitionInSeconds > 0 {
                    Picker("Style", selection: Binding(get: { clip.transitionKind },
                                                       set: { model.setClipTransitionKind(clip.id, $0) })) {
                        ForEach(TransitionKind.allCases) { Text($0.label).tag($0) }
                    }
                }
            }
        } header: {
            Label(clip.label, systemImage: "film").lineLimit(1)
        }
        Section {
            Button("Delete Clip", systemImage: "trash", role: .destructive) { model.deleteClip(clip.id) }
        }
    }

    // MARK: Audio selection (music / voiceover) — fully editable

    @ViewBuilder private func audioInspector(_ a: AudioClip) -> some View {
        Section {
            TextField("Name", text: Binding(get: { a.displayName }, set: { model.renameAudio(a.id, $0) }))
            sliderRow("Volume", icon: a.volume == 0 ? "speaker.slash" : a.kind.symbol,
                      value: Binding(get: { a.volume }, set: { model.setAudioVolume(a.id, $0) }),
                      range: 0...1.5, format: { "\(Int($0 * 100))%" })
            LabeledContent("Start") {
                Stepper(value: Binding(get: { a.startSeconds }, set: { model.setAudioStart(a.id, $0) }),
                        in: 0...max(1, model.totalDuration), step: 0.5) {
                    Text(String(format: "%.1fs", a.startSeconds)).font(.callout.monospacedDigit())
                }
            }
            let maxFade = max(0.5, (a.sourceDuration > 0 ? a.sourceDuration : 8) / 2)
            sliderRow("Fade in", icon: "circle.lefthalf.filled",
                      value: Binding(get: { a.fadeInSeconds }, set: { model.setAudioFade(a.id, fadeIn: $0) }),
                      range: 0...maxFade, format: { String(format: "%.1fs", $0) })
            sliderRow("Fade out", icon: "circle.righthalf.filled",
                      value: Binding(get: { a.fadeOutSeconds }, set: { model.setAudioFade(a.id, fadeOut: $0) }),
                      range: 0...maxFade, format: { String(format: "%.1fs", $0) })
        } header: {
            Label(a.kind.label, systemImage: a.kind.symbol)
        }
        Section {
            Button("Delete \(a.kind.label)", systemImage: "trash", role: .destructive) { model.removeAudio(a.id) }
        }
    }

    // MARK: No selection — the PROJECT itself (canvas / frame rate / attribution), all editable

    @ViewBuilder private var projectSettings: some View {
        Section {
            Picker("Aspect", selection: Binding(get: { model.matchedCanvasPreset },
                                                set: { model.setRenderSize($0.size) })) {
                ForEach(EditorModel.canvasPresets) { Text($0.name).tag($0) }
                if model.matchedCanvasPreset.isCustom {
                    Text("Custom (\(Int(project.timeline.renderSize.width))×\(Int(project.timeline.renderSize.height)))")
                        .tag(model.matchedCanvasPreset)
                }
            }
            Picker("Frame rate", selection: Binding(get: { Int(project.timeline.frameRate.rounded()) },
                                                    set: { model.setFrameRate(Double($0)) })) {
                Text("24 fps").tag(24); Text("30 fps").tag(30); Text("60 fps").tag(60)
            }
        } header: {
            Label("Project · Canvas", systemImage: "rectangle.3.group")
        }
        Section {
            Toggle("Burn in attribution credit", isOn: $project.burnAttribution)
        } header: {
            Label("Project · Export", systemImage: "square.and.arrow.up")
        } footer: {
            Text("Adds a small “archivewatch.org · Public Domain” credit to the video. Turn off for a clean export.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if case .none = model.selection {
            Section {
                Text("Select a clip, title, or audio track to edit it here — these project settings stay available no matter what’s selected.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// A labeled icon + slider + value readout row (the inspector's workhorse control).
    private func sliderRow(_ title: String, icon: String, value: Binding<Double>,
                           range: ClosedRange<Double>, format: @escaping (Double) -> String) -> some View {
        LabeledContent(title) {
            HStack {
                Image(systemName: icon).foregroundStyle(.secondary)
                Slider(value: value, in: range)
                Text(format(value.wrappedValue)).font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary).frame(width: 46, alignment: .trailing)
            }
        }
    }
}

// MARK: - Text overlay editor (#3)

private struct TextOverlayEditor: View {
    @Binding var overlay: TextOverlay
    let onDelete: () -> Void

    var body: some View {
        Section {
            TextField("Text", text: $overlay.text, axis: .vertical).lineLimit(1...3)
            Picker("Position", selection: positionPreset) {
                Text("Top").tag("top"); Text("Center").tag("center"); Text("Lower Third").tag("lower")
            }
            // Continuous X/Y (0…1) — the precise complement to dragging the overlay on screen (#3).
            LabeledContent("X") {
                HStack { Slider(value: $overlay.positionX, in: 0...1)
                    Text("\(Int(overlay.positionX * 100))%").font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary).frame(width: 38, alignment: .trailing) }
            }
            LabeledContent("Y") {
                HStack { Slider(value: $overlay.positionY, in: 0...1)
                    Text("\(Int(overlay.positionY * 100))%").font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary).frame(width: 38, alignment: .trailing) }
            }
            Picker("Color", selection: $overlay.colorHex) {
                ForEach([("White", "#FFFFFF"), ("Black", "#000000"), ("Yellow", "#FFD60A"),
                         ("Red", "#FF453A"), ("Blue", "#0A84FF")], id: \.1) { name, hex in
                    Text(name).tag(hex)
                }
            }
            HStack { Text("Size"); Slider(value: $overlay.fontScale, in: 0.025...0.12) }
            Toggle("Legibility shadow", isOn: $overlay.hasBackground)
            LabeledContent("Start") {
                HStack { Text(String(format: "%.1fs", startBinding.wrappedValue)); Stepper("", value: startBinding, in: 0...3600, step: 0.5).labelsHidden() }
            }
            LabeledContent("Length") {
                HStack { Text(String(format: "%.1fs", lengthBinding.wrappedValue)); Stepper("", value: lengthBinding, in: 0.2...3600, step: 0.5).labelsHidden() }
            }
            Button("Remove Text", role: .destructive) { onDelete() }
        } header: {
            Text("Text Overlay")
        }
    }

    private var positionPreset: Binding<String> {
        Binding(get: {
            switch overlay.positionY {
            case ..<0.3: "top"; case 0.3..<0.7: "center"; default: "lower"
            }
        }, set: {
            overlay.positionY = $0 == "top" ? 0.14 : ($0 == "center" ? 0.5 : 0.85)
        })
    }
    private var startBinding: Binding<Double> {
        Binding(get: { overlay.timelineRange.start.seconds },
                set: { overlay.timelineRange = TimeRange(startSeconds: max(0, $0),
                                                         durationSeconds: overlay.timelineRange.duration.seconds) })
    }
    private var lengthBinding: Binding<Double> {
        Binding(get: { overlay.timelineRange.duration.seconds },
                set: { overlay.timelineRange = TimeRange(startSeconds: overlay.timelineRange.start.seconds,
                                                         durationSeconds: max(0.2, $0)) })
    }
}
#endif
