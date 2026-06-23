#if os(macOS)
import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

// The Creation Studio editor scene (docs/macOS-DESIGN.md §2 — the DocumentGroup face,
// distinct from the WindowGroup Library face; Rule "Library ≠ Project"). This is the
// Mac-native NLE shell: a NavigationSplitView with the proxy-clip library on the leading
// side, the timeline + preview in the detail column, and a trailing .inspector().
//
// UNIT 1 SCAFFOLD: the library sidebar, the AppKit NSView+CALayer timeline (spike #2),
// the AVFoundation preview, and the cache-then-export engine (spike #3) land in Units 2–4.
// For now the detail column lists the timeline's clips and the toolbar can mutate the
// project — enough to prove the document seam (spike #1): open → edit title/clips →
// autosave the package → reopen with state intact.

struct ProjectEditorView: View {
    @ObservedObject var document: ClipProjectDocument
    @Environment(AppStore.self) private var store
    @State private var inspectorShown = true
    @State private var exporter = ExportService()

    private var project: Binding<ClipProject> {
        Binding(get: { document.project }, set: { document.project = $0 })
    }

    var body: some View {
        NavigationSplitView {
            LibrarySidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            TimelinePlaceholder(project: project)
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
                // UNIT-2 SCAFFOLD: pull a real archive.org title from the catalog and add an
                // ~8s window. Unit 4 replaces this with the real browser → library → drag.
                Button { addDemoClip() } label: {
                    Label("Add Clip", systemImage: "plus.rectangle.on.folder")
                }
                Button { export() } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(project.wrappedValue.timeline.clips.isEmpty || exporter.isBusy)
                Button { inspectorShown.toggle() } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
            }
        }
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

    private func addDemoClip() {
        guard let item = store.randomPlayable(), let url = item.videoURLParsed else { return }
        let start = document.project.timeline.durationSeconds
        let clip = TimelineClip(
            catalogItemID: item.archiveID, sourceURL: url,
            sourceRange: TimeRange(startSeconds: 3, durationSeconds: 8),
            timelineStart: TimeStamp(seconds: start), track: 0, label: item.title)
        document.project.timeline.clips.append(clip)
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
    @Query(sort: \LibraryClip.addedAt, order: .reverse) private var clips: [LibraryClip]

    var body: some View {
        Group {
            if clips.isEmpty {
                ContentUnavailableView {
                    Label("No Clips Yet", systemImage: "film.stack")
                } description: {
                    Text("Mark in/out on an archive.org title to build your clip library, then drag clips onto the timeline.")
                }
            } else {
                List(clips) { clip in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(clip.label).font(.subheadline).lineLimit(1)
                        Text(rangeLabel(clip)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Library")
    }

    private func rangeLabel(_ c: LibraryClip) -> String {
        String(format: "%@ · %.1fs", c.title, max(0, c.outSeconds - c.inSeconds))
    }
}

// MARK: - Timeline placeholder (Unit 3 replaces this with the AppKit NSView+CALayer NLE)

private struct TimelinePlaceholder: View {
    @Binding var project: ClipProject

    var body: some View {
        VStack(spacing: 0) {
            // Program monitor placeholder (Unit 2 wires the AVPlayer preview).
            ZStack {
                Rectangle().fill(.black)
                Image(systemName: "play.rectangle")
                    .font(.system(size: 44)).foregroundStyle(.white.opacity(0.25))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 280)

            Divider()

            // Timeline track listing (placeholder for the magnetic AppKit timeline).
            if project.timeline.clips.isEmpty {
                ContentUnavailableView {
                    Label("Empty Timeline", systemImage: "timeline.selection")
                } description: {
                    Text("Drag clips from the Library onto the timeline. (The AppKit timeline arrives in Unit 3.)")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(project.timeline.clips) { clip in
                        HStack {
                            Image(systemName: "rectangle.on.rectangle.angled")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(clip.label).font(.subheadline)
                                Text(String(format: "in %.1fs · %.1fs long · track %d",
                                            clip.sourceRange.start.seconds,
                                            clip.sourceRange.duration.seconds, clip.track))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "@ %.1fs", clip.timelineStart.seconds))
                                .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                        }
                    }
                    .onDelete { project.timeline.clips.remove(atOffsets: $0) }
                }
            }
        }
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
                Text("Adds a small “archivewatch.org · Public Domain” credit to the video. Turn off for a clean export — the archive.org source is still recorded in the file’s metadata.")
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
