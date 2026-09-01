#if os(iOS)
import SwiftUI
import SwiftData

// "Keep on this device" — the sheet that starts, watches and removes a download
// (Decision 099). iOS-DESIGN §3.6 (a transient picker is a sheet) + §4.5
// (medium detent, so the film stays visible behind the choice being made).
//
// It shows the REAL copies on the archive.org item with their real sizes,
// because that is the decision being made: a 2.4 GB uploader original and a
// 575 MB Archive derivative are the same film in different conditions, and on a
// phone with 9 GB free that difference is the whole question. Labelling them
// "High" and "Standard" would hide exactly the fact the viewer needs.
struct DownloadSheet: View {
    let item: Catalog.Item

    @Environment(\.dismiss) private var dismiss
    @Query private var downloads: [DownloadedFilm]
    @State private var versions: [ArchiveVersions.Version] = []
    @State private var loading = true
    @State private var startError: String?
    @State private var confirmingRemoval = false

    private var manager: DownloadManager { .shared }
    private var row: DownloadedFilm? { downloads.first { $0.archiveID == item.archiveID } }

    var body: some View {
        NavigationStack {
            List {
                if let row, row.state != .failed {
                    statusSection(row)
                } else {
                    if let startError {
                        Section {
                            Label(startError, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                    if let row, row.state == .failed, let why = row.errorText {
                        Section {
                            Label(why, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                    copiesSection
                }
                spaceSection
            }
            .navigationTitle("Keep on This Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            versions = await ArchiveVersions.list(itemID: item.archiveID)
            loading = false
        }
    }

    // MARK: - In flight / on disk

    @ViewBuilder private func statusSection(_ row: DownloadedFilm) -> some View {
        Section {
            switch row.state {
            case .completed:
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("On this device")
                        Text(subtitleFor(row)).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Button(role: .destructive) { confirmingRemoval = true } label: {
                    Label("Remove Download", systemImage: "trash")
                }
                .confirmationDialog("Remove this download?", isPresented: $confirmingRemoval) {
                    Button("Remove Download", role: .destructive) {
                        manager.remove(item.archiveID)
                        dismiss()
                    }
                } message: {
                    Text("\(item.title) will need to be downloaded again to watch it offline. "
                         + "It stays in your favorites and playlists.")
                }

            case .queued, .downloading:
                VStack(alignment: .leading, spacing: 8) {
                    Text(progressLine(row))
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let live = manager.progress(for: row.archiveID), live.expected > 0 {
                        ProgressView(value: live.fraction).tint(.orange)
                    } else if row.expectedBytes > 0 {
                        ProgressView(value: row.fraction).tint(.orange)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                }
                .padding(.vertical, 4)
                Button { manager.pause(row.archiveID) } label: {
                    Label("Pause", systemImage: "pause.circle")
                }
                Button(role: .destructive) { manager.remove(item.archiveID) } label: {
                    Label("Cancel Download", systemImage: "xmark.circle")
                }

            case .paused:
                Label("Paused — \(OfflineLibrary.byteText(row.receivedBytes)) of "
                      + "\(OfflineLibrary.byteText(row.expectedBytes)) downloaded",
                      systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
                Button { manager.resume(row.archiveID) } label: {
                    Label("Resume", systemImage: "play.circle")
                }
                Button(role: .destructive) { manager.remove(item.archiveID) } label: {
                    Label("Cancel Download", systemImage: "xmark.circle")
                }

            case .failed:
                EmptyView()
            }
        } header: {
            Text(item.title)
        }
    }

    private func subtitleFor(_ row: DownloadedFilm) -> String {
        var parts: [String] = []
        if let q = row.qualityLabel { parts.append(q) }
        else { parts.append(OfflineLibrary.byteText(OfflineLibrary.bytesUsed(by: row.archiveID))) }
        if row.hasSubtitles { parts.append("subtitles included") }
        return parts.joined(separator: " · ")
    }

    private func progressLine(_ row: DownloadedFilm) -> String {
        let live = manager.progress(for: row.archiveID)
        let received = live?.received ?? row.receivedBytes
        let expected = live?.expected ?? row.expectedBytes
        guard expected > 0 else { return "Downloading…" }
        return "\(OfflineLibrary.byteText(received)) of \(OfflineLibrary.byteText(expected))"
    }

    // MARK: - Choosing a copy

    @ViewBuilder private var copiesSection: some View {
        Section {
            if loading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Looking for copies…").foregroundStyle(.secondary)
                }
            } else if versions.isEmpty {
                // The item's file list could not be read — offline already, or
                // archive.org is slow. The catalog's own pick still works, and
                // offering it beats an empty sheet that explains nothing.
                if item.videoURLParsed != nil {
                    Button { start(nil) } label: {
                        Label("Download the standard copy", systemImage: "arrow.down.circle")
                    }
                    Text("The list of other copies could not be loaded.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("This title has no downloadable file.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(versions) { v in
                    Button { start(v) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.compactLabel)
                                Text(v.isDerivative ? "Archive derivative" : "Uploader original")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: OfflineLibrary.hasRoom(for: v.sizeBytes)
                                  ? "arrow.down.circle" : "exclamationmark.circle")
                                .foregroundStyle(OfflineLibrary.hasRoom(for: v.sizeBytes)
                                                 ? Color.accentColor : .orange)
                        }
                    }
                    .disabled(!OfflineLibrary.hasRoom(for: v.sizeBytes))
                }
            }
        } header: {
            Text("Choose a copy")
        } footer: {
            Text("Downloads use wifi only unless you turn on cellular downloads in Settings.")
        }
    }

    @ViewBuilder private var spaceSection: some View {
        Section {
            if let free = OfflineLibrary.availableBytes() {
                LabeledContent("Free space", value: OfflineLibrary.byteText(free))
            }
            let used = OfflineLibrary.bytesUsed()
            if used > 0 {
                LabeledContent("Used by downloads", value: OfflineLibrary.byteText(used))
            }
        }
        .font(.footnote)
    }

    private func start(_ version: ArchiveVersions.Version?) {
        startError = manager.start(item: item, version: version)
    }
}
#endif
