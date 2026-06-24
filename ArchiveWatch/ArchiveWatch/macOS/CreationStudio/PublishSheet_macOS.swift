#if os(macOS)
import SwiftUI

// Publish a finished edit to the Internet Archive (Creation Studio #7). Exports the project to
// a temp H.264 file, then uploads it to a NEW archive.org item via the user's IAS3 keys, stamping
// the clips' source URLs as provenance. The whole create→edit→SHARE loop, on-brand (the Archive).
struct PublishSheet: View {
    let project: ClipProject
    /// The document's filename (from the title bar), used to seed the upload title — the macOS
    /// document name is the single source of truth, not a separate in-project title field.
    var defaultTitle: String = ""
    @Bindable var publisher: PublishService
    @Bindable var exporter: ExportService
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var desc: String = ""
    @State private var stage: Stage = .form
    @State private var resultURL: URL?

    enum Stage: Equatable { case form, exporting, publishing, done, failed(String) }

    private var sources: [String] {
        var seen = Set<String>(), out: [String] = []
        for c in project.timeline.clips where seen.insert(c.catalogItemID).inserted {
            out.append("https://archive.org/details/\(c.catalogItemID)")
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Publish to the Internet Archive").font(.title3).bold()

            switch stage {
            case .form:
                if !publisher.hasCredentials {
                    Label("Add your archive.org S3 keys in Settings ▸ Publishing first.",
                          systemImage: "key.fill")
                        .foregroundStyle(.orange).font(.callout)
                }
                Form {
                    TextField("Title", text: $title)
                    TextField("Description", text: $desc, axis: .vertical).lineLimit(2...5)
                    LabeledContent("Sources", value: "\(sources.count) public-domain title\(sources.count == 1 ? "" : "s")")
                }
                .formStyle(.grouped)
                Text("Your edit is dedicated to the public domain (CC0) and credits its archive.org sources.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Publish") { Task { await run() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!publisher.hasCredentials || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }

            case .exporting:
                progress("Rendering your edit…", value: exporter.progress)
            case .publishing:
                progress(publishLabel, value: publishFraction)
            case .done:
                VStack(alignment: .leading, spacing: 10) {
                    Label("Published to the Internet Archive", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.headline)
                    if let resultURL {
                        Text(resultURL.absoluteString).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        HStack {
                            Button("Open") { NSWorkspace.shared.open(resultURL) }
                            Button("Copy Link") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(resultURL.absoluteString, forType: .string)
                            }
                            Spacer()
                            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                        }
                    }
                    Text("Note: the Archive may take a few minutes to process the video before it plays.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .failed(let msg):
                VStack(alignment: .leading, spacing: 10) {
                    Label("Couldn’t publish", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.headline)
                    Text(msg).font(.callout).foregroundStyle(.secondary)
                    HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.defaultAction) }
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { if title.isEmpty { title = defaultTitle.isEmpty ? "My Archive Watch Edit" : defaultTitle } }
    }

    private func progress(_ label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
            ProgressView(value: value)
        }.frame(maxWidth: .infinity)
    }

    private var publishLabel: String {
        switch publisher.phase {
        case .creating: return "Creating the Archive item…"
        case .uploading: return "Uploading…"
        default: return "Publishing…"
        }
    }
    private var publishFraction: Double {
        if case .uploading(let f) = publisher.phase { return f }
        return 0
    }

    private func run() async {
        // 1) Render to a temp H.264 file.
        stage = .exporting
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("aw-publish-\(UUID().uuidString.prefix(6)).mp4")
        await exporter.export(project, to: tmp, format: .h264)
        guard case .done = exporter.phase else {
            if case .failed(let m) = exporter.phase { stage = .failed(m) } else { stage = .failed("Export failed.") }
            return
        }
        // 2) Upload to a new archive.org item.
        stage = .publishing
        do {
            let salt = String(UUID().uuidString.prefix(6)).lowercased()
            let url = try await publisher.publish(fileURL: tmp, title: title, description: desc,
                                                  sources: sources, salt: salt)
            resultURL = url
            stage = .done
            try? FileManager.default.removeItem(at: tmp)
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }
}
#endif
