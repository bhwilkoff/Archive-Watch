#if os(iOS)
import SwiftUI

// Settings: the required attribution (Decision 007), the mature-content toggle
// (Decision 012, default on), the donate link (Decision 010), and version. Native
// iOS `Form`. Account/CloudKit sign-in lands with the sync wiring (Phase 1 follow).
struct SettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section("Content") {
                Toggle("Show mature collections", isOn: Binding(
                    get: { !store.hideAdultContent },
                    set: { store.hideAdultContent = !$0 }))
                Text("Off by default — the Internet Archive includes adult-leaning collections.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Playback") {
                Picker("Autoplay next", selection: $store.autoplayMode) {
                    ForEach(AutoplayMode.allCases) { Text($0.label).tag($0) }
                }
                Text("When a film ends, what plays next. TV episodes always continue "
                     + "to the next episode.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Support") {
                Link(destination: URL(string: "https://archive.org/donate")!) {
                    Label("Support the Internet Archive", systemImage: "heart")
                }
                Text("Archive Watch is free and takes nothing for itself. If it's brought you "
                     + "something worth keeping, support the people who keep the films online.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Sources & Attribution") {
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                Text("Posters, backdrops, cast, and synopses come from The Movie Database (TMDb), "
                     + "with Wikidata, Wikimedia Commons, and the Library of Congress as fallbacks. "
                     + "Films, television, and ephemera are served by the Internet Archive. Every "
                     + "title is public domain or otherwise free to share.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                Text("No account, no tracking. Nothing leaves this device except requests to the "
                     + "public services above.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }
}

#endif
