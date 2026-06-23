#if os(macOS)
import SwiftUI

// macOS Settings scene: account (CloudKit sync gate), content filter (Decision 012),
// the REQUIRED TMDb attribution (Decision 007), donate, version.

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AccountStore.self) private var account

    var body: some View {
        @Bindable var store = store
        TabView {
            Form {
                Section("Account") {
                    if account.isSignedIn {
                        LabeledContent("Signed in", value: "iCloud sync on")
                        Button("Sign Out") { account.signOut() }
                    } else {
                        Text("Sign in to sync favorites, playlists, and progress across your Apple devices.")
                            .foregroundStyle(.secondary)
                        Button("Sign in with Apple") { account.startSignIn() }
                    }
                    if let sync = CloudKitSyncService.shared.lastSyncAt {
                        LabeledContent("Last sync", value: sync.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                Section("Content") {
                    Toggle("Hide mature collections", isOn: $store.hideAdultContent)
                    Toggle("Hide watched on Home", isOn: $store.hideWatchedOnHome)
                }
                Section {
                    Picker("Autoplay next", selection: $store.autoplayMode) {
                        ForEach(AutoplayMode.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Playback")
                } footer: {
                    Text("When a film ends, automatically play a related title, one from the same era, or a surprise. TV episodes always continue to the next.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let cats = store.featured?.categories, !cats.isEmpty {
                    Section {
                        ForEach(cats) { cat in
                            Toggle(cat.displayName, isOn: categoryBinding(cat.id))
                        }
                    } header: {
                        Text("Show on Home & Browse")
                    } footer: {
                        Text("Hidden categories disappear from Home, Browse, and Search on this Mac.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section("Attribution") {
                    Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                        .foregroundStyle(.secondary)
                    Text("Metadata and artwork from The Movie Database, Wikidata, Wikimedia Commons, and the Library of Congress. Video hosted by the Internet Archive.")
                        .font(.callout).foregroundStyle(.secondary)
                    Link("Donate to the Internet Archive", destination: URL(string: "https://archive.org/donate")!)
                }
                Section {
                    LabeledContent("Catalog", value: "\(store.db?.itemCount.formatted() ?? "—") titles")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 420)
    }

    private func categoryBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { !store.hiddenCategories.contains(id) },
                set: { on in
                    if on { store.hiddenCategories.remove(id) }
                    else { store.hiddenCategories.insert(id) }
                })
    }
}
#endif
