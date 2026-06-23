#if os(macOS)
import SwiftUI
import SwiftData

// Add to Playlist (parity with iOS AddToPlaylistSheet / tvOS) — a Mac-native sheet
// with a create field and a checkmark list. Same shared SwiftData Playlist model, so
// additions/removals propagate via CloudKit (recency merge, #11b touch()). Writes save
// directly; the app's foreground/sign-in sync triggers push them (macOS has no
// iOS-only SyncNudge).
struct AddToPlaylistSheet: View {
    let archiveID: String
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Playlist.createdAt, order: .reverse) private var playlists: [Playlist]
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add to Playlist").font(.headline)
                Spacer()
            }
            .padding(12)
            Divider()

            List {
                Section("New Playlist") {
                    HStack {
                        TextField("Name", text: $newName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { createAndAdd() }
                        Button("Create") { createAndAdd() }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if !playlists.isEmpty {
                    Section("Your Playlists") {
                        ForEach(playlists) { pl in
                            Button { toggle(pl) } label: {
                                HStack {
                                    Image(systemName: pl.contains(archiveID)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(pl.contains(archiveID) ? .orange : .secondary)
                                    Text(pl.name)
                                    Spacer()
                                    Text("\(pl.archiveIDs.count)")
                                        .foregroundStyle(.secondary).font(.subheadline)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 420, height: 380)
    }

    private func toggle(_ pl: Playlist) {
        if let i = pl.archiveIDs.firstIndex(of: archiveID) { pl.archiveIDs.remove(at: i) }
        else { pl.archiveIDs.append(archiveID) }
        pl.touch()                 // #11b: stamp so a removal wins on sync
        try? ctx.save()
    }

    private func createAndAdd() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        ctx.insert(Playlist(name: name, archiveIDs: [archiveID]))
        try? ctx.save()
        newName = ""
    }
}
#endif
