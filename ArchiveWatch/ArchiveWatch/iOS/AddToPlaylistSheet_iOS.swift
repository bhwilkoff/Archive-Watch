#if os(iOS)
import SwiftUI
import SwiftData

// Add to Playlist (PARITY §6) — the touch idiom for the tvOS AddToPlaylistSheet:
// a medium-detent sheet with a create field and a checkmark list. Same SwiftData
// Playlist model + sync nudges, so additions/removals propagate via CloudKit.
struct AddToPlaylistSheet: View {
    let archiveID: String
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Playlist.createdAt, order: .reverse) private var playlists: [Playlist]
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("New Playlist") {
                    HStack {
                        TextField("Name", text: $newName)
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
                                        .foregroundStyle(pl.contains(archiveID)
                                                         ? Brand.primary : .secondary)
                                    Text(pl.name).foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(pl.archiveIDs.count)")
                                        .foregroundStyle(.secondary).font(.subheadline)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggle(_ pl: Playlist) {
        if let i = pl.archiveIDs.firstIndex(of: archiveID) { pl.archiveIDs.remove(at: i) }
        else { pl.archiveIDs.append(archiveID) }
        pl.touch()                 // #11b: stamp so a removal wins on sync
        try? ctx.save()
        SyncNudge.nudge(ctx)
    }

    private func createAndAdd() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        ctx.insert(Playlist(name: name, archiveIDs: [archiveID]))
        try? ctx.save()
        SyncNudge.nudge(ctx)
        newName = ""
    }
}

#endif
