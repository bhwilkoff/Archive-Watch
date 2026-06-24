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
    @State private var showExportSheet = false

    init(document: ClipProjectDocument) {
        self.document = document
        _model = State(initialValue: EditorModel(document: document))
    }

    private var project: Binding<ClipProject> {
        Binding(get: { document.project }, set: { document.project = $0 })
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
            LibrarySidebar()
                .frame(width: 240)
            Divider()

            VSplitView {
                // Program monitor — the live preview (rebuild-and-swap composition, Rule 3b).
                ZStack {
                    Color.black
                    if document.project.timeline.clips.isEmpty {
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
                    if model.isBuildingPreview || !model.prepStatus.failures.isEmpty {
                        let s = model.prepStatus
                        VStack(spacing: 6) {
                            if model.isBuildingPreview {
                                ProgressView().controlSize(.small).tint(.white)
                                Text("Preparing clips — \(s.ready) of \(s.total) ready" +
                                     (s.caching > 0 ? " · \(s.caching) downloading" : ""))
                                    .font(.caption).foregroundStyle(.white.opacity(0.85))
                            }
                            if let fail = s.failures.first {
                                Label(s.failures.count == 1 ? "1 clip couldn’t load: \(fail)"
                                                            : "\(s.failures.count) clips couldn’t load: \(fail)",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        .padding(10).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
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
                }.disabled(document.project.timeline.clips.isEmpty)
                Button { model.addTextOverlay() } label: {
                    Label("Add Text", systemImage: "textformat")
                }.disabled(document.project.timeline.clips.isEmpty)
                Button { showSupercut = true } label: {
                    Label("Supercut", systemImage: "text.magnifyingglass")
                }
                Button { showExportSheet = true } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(document.project.timeline.clips.isEmpty || exporter.isBusy)
                Button { showPublishSheet = true } label: {
                    Label("Publish", systemImage: "icloud.and.arrow.up")
                }
                .disabled(document.project.timeline.clips.isEmpty || exporter.isBusy)
                Button { inspectorShown.toggle() } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
            }
        }
        .onAppear { model.undoManager = undoManager }   // ⌘Z + Edit menu drive our snapshot history
        .task {
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
                if mode == "editor", document.project.timeline.clips.isEmpty {
                    CreationStudioTest.populate(model, store)
                } else if mode == "markclip" {
                    testMark = CreationStudioTest.clippable(store)   // presents the Add-Clip scrubber
                }
            }
            model.loadFilmstrips()   // instant filmstrips for already-present (saved-project) clips
            if !document.project.timeline.clips.isEmpty { await model.rebuildPreview() }
        }
        .onChange(of: document.project.burnAttribution) { Task { await model.rebuildPreview() } }
        .sheet(isPresented: $showBrowser) {
            ClipBrowserSheet { proxy in addToLibraryAndTimeline(proxy) }
                .environment(store)
        }
        .sheet(item: $testMark) { MarkClipView(item: $0) { _ in }.environment(store) }
        .sheet(isPresented: $showExportSheet) {
            ExportSettingsSheet { format in runExport(format) }
        }
        .sheet(isPresented: $showPublishSheet) {
            PublishSheet(project: document.project, defaultTitle: documentName,
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
        let project = document.project
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

    var body: some View {
        GeometryReader { geo in
            let rect = fitRect(aspect: renderSize.width / max(1, renderSize.height), in: geo.size)
            ForEach(active) { ov in
                let selected = model.selectedOverlayID == ov.id
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
                    .position(x: rect.minX + ov.positionX * rect.width,
                              y: rect.minY + ov.positionY * rect.height)
                    .gesture(
                        // Drag in the CANVAS coordinate space (the GeometryReader), not the text's
                        // own space — otherwise value.location is relative to the small text frame
                        // and the overlay barely moves (#3).
                        DragGesture(coordinateSpace: .named("ovlCanvas"))
                            .onChanged { value in
                                guard rect.width > 1, rect.height > 1,
                                      var o = model.textOverlays.first(where: { $0.id == ov.id }) else { return }
                                model.selectedOverlayID = ov.id
                                o.positionX = min(1, max(0, (value.location.x - rect.minX) / rect.width))
                                o.positionY = min(1, max(0, (value.location.y - rect.minY) / rect.height))
                                model.updateOverlay(o)
                            }
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
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var ctx
    @Query(sort: \LibraryClip.addedAt, order: .reverse) private var clips: [LibraryClip]

    var body: some View {
        Group {
            if clips.isEmpty {
                ContentUnavailableView {
                    Label("No Clips Yet", systemImage: "film.stack")
                } description: {
                    Text("Use “Add Clip” to mark an in/out point on a public-domain title. Saved clips appear here — drag them onto the timeline.")
                }
            } else {
                List(clips) { clip in
                    LibraryRow(clip: clip, poster: store.item(clip.catalogItemID)?.posterURLParsed)
                        .draggable(clip.proxyClip ?? ProxyClip(
                            catalogItemID: clip.catalogItemID,
                            sourceURL: URL(string: clip.sourceURLString) ?? URL(fileURLWithPath: "/"),
                            sourceRange: TimeRange(startSeconds: clip.inSeconds,
                                                   durationSeconds: max(0.1, clip.outSeconds - clip.inSeconds)),
                            label: clip.label, title: clip.title))
                        .contextMenu {
                            Button("Delete", role: .destructive) { ctx.delete(clip); try? ctx.save() }
                        }
                }
            }
        }
        .navigationTitle("Library")
    }
}

private struct LibraryRow: View {
    let clip: LibraryClip
    let poster: URL?
    var body: some View {
        HStack(spacing: 10) {
            // The clip's actual in-point frame (archive.org thumbnail), poster as fallback.
            ClipThumbnailView(catalogItemID: clip.catalogItemID,
                              sourceURL: URL(string: clip.sourceURLString),
                              atSeconds: clip.inSeconds,
                              fallbackPoster: poster)
                .frame(width: 44, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(clip.label).font(.subheadline).lineLimit(1)
                Text(String(format: "%.1fs", max(0, clip.outSeconds - clip.inSeconds)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal").font(.caption2).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Inspector

private struct ProjectInspector: View {
    @Binding var project: ClipProject
    let model: EditorModel

    var body: some View {
        Form {
            // When a text overlay is selected, the inspector edits it (#3).
            if let id = model.selectedOverlayID,
               let ov = model.textOverlays.first(where: { $0.id == id }) {
                TextOverlayEditor(
                    overlay: Binding(
                        get: { model.textOverlays.first(where: { $0.id == id }) ?? ov },
                        set: { model.updateOverlay($0) }),
                    onDelete: { model.deleteOverlay(id) })
            } else if let clip = model.selectedClip {
                // When a clip is selected, edit its audio level (#4).
                Section("Clip") {
                    Text(clip.label).font(.subheadline).lineLimit(2)
                    LabeledContent("Audio") {
                        HStack {
                            Image(systemName: clip.audioVolume == 0 ? "speaker.slash" : "speaker.wave.2")
                                .foregroundStyle(.secondary)
                            Slider(value: Binding(get: { clip.audioVolume },
                                                  set: { model.setClipVolume(clip.id, $0) }),
                                   in: 0...1.5)
                            Text("\(Int(clip.audioVolume * 100))%").font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
                        }
                    }
                    // Fade up from / down to black (+ audio), over the clip's head/tail.
                    let maxFade = max(0.1, clip.sourceRange.duration.seconds / 2)
                    LabeledContent("Fade in") {
                        HStack {
                            Image(systemName: "circle.lefthalf.filled").foregroundStyle(.secondary)
                            Slider(value: Binding(get: { clip.fadeInSeconds },
                                                  set: { model.setClipFade(clip.id, fadeIn: $0) }),
                                   in: 0...maxFade)
                            Text(String(format: "%.1fs", clip.fadeInSeconds)).font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
                        }
                    }
                    LabeledContent("Fade out") {
                        HStack {
                            Image(systemName: "circle.righthalf.filled").foregroundStyle(.secondary)
                            Slider(value: Binding(get: { clip.fadeOutSeconds },
                                                  set: { model.setClipFade(clip.id, fadeOut: $0) }),
                                   in: 0...maxFade)
                            Text(String(format: "%.1fs", clip.fadeOutSeconds)).font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
                        }
                    }
                    // Color grade (Look) — baked into a cached graded source on rebuild.
                    Picker("Look", selection: Binding(get: { clip.look },
                                                      set: { model.setClipLook(clip.id, $0) })) {
                        ForEach(ClipLook.allCases) { Text($0.label).tag($0) }
                    }
                    // Transition from the PREVIOUS clip (only meaningful past the first clip).
                    if model.clips.first?.id != clip.id {
                        LabeledContent("Transition") {
                            HStack {
                                Image(systemName: "square.on.square.dashed").foregroundStyle(.secondary)
                                Slider(value: Binding(get: { clip.transitionInSeconds },
                                                      set: { model.setClipTransition(clip.id, $0) }),
                                       in: 0...maxFade)
                                Text(String(format: "%.1fs", clip.transitionInSeconds)).font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
                            }
                        }
                        if clip.transitionInSeconds > 0 {
                            Picker("Style", selection: Binding(get: { clip.transitionKind },
                                                               set: { model.setClipTransitionKind(clip.id, $0) })) {
                                ForEach(TransitionKind.allCases) { Text($0.label).tag($0) }
                            }
                        }
                    }
                }
            }
            Section("Project") {
                LabeledContent("Clips", value: "\(project.timeline.clips.count)")
                LabeledContent("Duration", value: String(format: "%.1f s", project.timeline.durationSeconds))
                LabeledContent("Format", value: "v\(project.formatVersion)")
            }
            Section("Music") {
                if let bed = model.musicBed {
                    LabeledContent("Track") { Text(bed.displayName).lineLimit(1) }
                    LabeledContent("Volume") {
                        HStack {
                            Image(systemName: bed.volume == 0 ? "speaker.slash" : "music.note")
                                .foregroundStyle(.secondary)
                            Slider(value: Binding(get: { bed.volume }, set: { model.setMusicVolume($0) }), in: 0...1.5)
                            Text("\(Int(bed.volume * 100))%").font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
                        }
                    }
                    Button("Remove Music", role: .destructive) { model.removeMusic() }
                } else {
                    Button("Add Music…") { pickMusic() }
                }
            }
            Section("Voiceover") {
                if let vo = model.voiceover {
                    LabeledContent("Volume") {
                        HStack {
                            Image(systemName: "mic").foregroundStyle(.secondary)
                            Slider(value: Binding(get: { vo.volume }, set: { model.setVoiceoverVolume($0) }), in: 0...1.5)
                            Text("\(Int(vo.volume * 100))%").font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
                        }
                    }
                    Button("Remove Voiceover", role: .destructive) { model.removeVoiceover() }
                } else if model.isRecordingVoiceover {
                    Button { model.stopVoiceover() } label: {
                        Label("Stop Recording", systemImage: "stop.circle.fill").foregroundStyle(.red)
                    }
                } else {
                    Button { model.startVoiceover() } label: {
                        Label("Record Voiceover", systemImage: "mic.circle")
                    }
                }
                if let err = model.voiceoverError {
                    Text(err).font(.caption).foregroundStyle(.orange)
                }
            }
            Section {
                Toggle("Burn in attribution credit", isOn: $project.burnAttribution)
            } header: {
                Text("Export")
            } footer: {
                Text("Adds a small “archivewatch.org · Public Domain” credit to the video. Turn off for a clean export.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Canvas") {
                LabeledContent("Frame rate", value: String(format: "%.0f fps", project.timeline.frameRate))
                LabeledContent("Render size", value: "\(Int(project.timeline.renderSize.width))×\(Int(project.timeline.renderSize.height))")
            }
            Section("Dates") {
                LabeledContent("Created", value: project.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Modified", value: project.modifiedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .formStyle(.grouped)
    }

    private func pickMusic() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Music"
        if panel.runModal() == .OK, let url = panel.url { model.importMusic(from: url) }
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
