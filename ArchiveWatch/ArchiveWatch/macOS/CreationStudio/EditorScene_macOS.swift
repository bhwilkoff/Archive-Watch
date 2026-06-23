#if os(macOS)
import SwiftUI
import SwiftData
import AppKit
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
    @State private var model: EditorModel
    @State private var inspectorShown = true
    @State private var exporter = ExportService()
    @State private var showBrowser = false

    init(document: ClipProjectDocument) {
        self.document = document
        _model = State(initialValue: EditorModel(document: document))
    }

    private var project: Binding<ClipProject> {
        Binding(get: { document.project }, set: { document.project = $0 })
    }

    var body: some View {
        NavigationSplitView {
            LibrarySidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            VSplitView {
                // Program monitor — the live preview (rebuild-and-swap composition, Rule 3b).
                ZStack {
                    Color.black
                    if document.project.timeline.clips.isEmpty {
                        ContentUnavailableView("Empty Timeline", systemImage: "timeline.selection")
                            .foregroundStyle(.white.opacity(0.5))
                    } else {
                        VideoPlayerNS(player: model.player)
                    }
                    if model.isBuildingPreview {
                        ProgressView().controlSize(.small).tint(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(10)
                    }
                }
                .frame(minHeight: 220)

                VStack(spacing: 0) {
                    transportBar
                    Divider()
                    ClipTimelineView(model: model)
                        .frame(minHeight: 170)
                        // Drag a clip from the Library onto the timeline. Magnetic single
                        // track, so the drop appends at the end regardless of drop x.
                        .dropDestination(for: ProxyClip.self) { proxies, _ in
                            proxies.forEach { model.addClip(from: $0) }
                            return !proxies.isEmpty
                        }
                }
            }
            .overlay(alignment: .bottom) { exportStatusBar }
        }
        .inspector(isPresented: $inspectorShown) {
            ProjectInspector(project: project)
                .inspectorColumnWidth(min: 220, ideal: 260, max: 340)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                TextField("Project title", text: project.title)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 200)
            }
            ToolbarItemGroup {
                Button { showBrowser = true } label: {
                    Label("Add Clip", systemImage: "plus.rectangle.on.folder")
                }
                Button { model.splitAtPlayhead() } label: {
                    Label("Split", systemImage: "scissors")
                }.disabled(document.project.timeline.clips.isEmpty)
                Button { export() } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(document.project.timeline.clips.isEmpty || exporter.isBusy)
                Button { inspectorShown.toggle() } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
            }
        }
        .task { if !document.project.timeline.clips.isEmpty { await model.rebuildPreview() } }
        .onChange(of: document.project.burnAttribution) { Task { await model.rebuildPreview() } }
        .sheet(isPresented: $showBrowser) {
            ClipBrowserSheet { proxy in addToLibraryAndTimeline(proxy) }
                .environment(store)
        }
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

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = document.project.title.isEmpty ? "Archive Watch.mp4"
            : "\(document.project.title).mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let project = document.project
        Task { await exporter.export(project, to: url) }
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
            RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                .frame(width: 44, height: 30)
                .overlay {
                    if let poster { AsyncImage(url: poster) { $0.resizable().scaledToFill() } placeholder: { Color.clear } }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
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

    var body: some View {
        Form {
            Section("Project") {
                LabeledContent("Clips", value: "\(project.timeline.clips.count)")
                LabeledContent("Duration", value: String(format: "%.1f s", project.timeline.durationSeconds))
                LabeledContent("Format", value: "v\(project.formatVersion)")
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
}
#endif
