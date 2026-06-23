#if os(macOS)
import SwiftUI
import SwiftData

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
    @State private var inspectorShown = true

    private var project: Binding<ClipProject> {
        Binding(get: { document.project }, set: { document.project = $0 })
    }

    var body: some View {
        NavigationSplitView {
            LibrarySidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            TimelinePlaceholder(project: project)
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
                Button {
                    inspectorShown.toggle()
                } label: { Label("Inspector", systemImage: "sidebar.trailing") }
            }
        }
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
