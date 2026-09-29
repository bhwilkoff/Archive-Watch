import SwiftUI

/// The copies of a film as MENU CONTENT — the iPhone/iPad More-row menu and
/// the Mac's Choose Version control and its More submenu all render this, so
/// the room refusal, the empty state and the playing mark cannot drift apart.
struct VersionMenuContents: View {
    let archiveID: String
    let defaultURL: URL?
    let versions: [ArchiveVersions.Version]
    let loading: Bool
    @Binding var chosenName: String?

    var body: some View {
        if StudioRoomCopy.isActive(for: archiveID) {
            Text("In a Watch Together room, the host chooses the copy.")
        } else if versions.isEmpty {
            Text(loading ? "Loading…" : "No other copies")
        } else {
            ForEach(versions) { v in
                Button {
                    ArchiveVersions.choose(v, for: archiveID)
                    chosenName = v.choiceKey
                } label: {
                    Label(v.label, systemImage:
                        ArchiveVersions.isPlaying(v, chosen: chosenName, defaultURL: defaultURL)
                            ? "checkmark.circle.fill" : "circle")
                }
            }
            Divider()
            Button {
                ArchiveVersions.choose(nil, for: archiveID)
                chosenName = nil
            } label: { Label("Use the Default Copy", systemImage: "arrow.uturn.backward") }
        }
    }
}
