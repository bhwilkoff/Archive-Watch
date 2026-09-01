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
                SubtitleAccountSection()
                AutoCaptionsSettingsSection()
                // Downloads (Decision 099). A Mac has no cellular question, so
                // this is space and a way to reclaim it.
                Section("Downloads") {
                    let used = OfflineLibrary.bytesUsed()
                    if used > 0 {
                        LabeledContent("Space used", value: OfflineLibrary.byteText(used))
                        Button("Remove All Downloads", role: .destructive) {
                            DownloadManager.shared.removeAll()
                        }
                        Text("Favorites, playlists and watch history are not affected.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Nothing downloaded yet. Use Download on a film's page to keep "
                             + "it on this Mac and play it with no internet.")
                            .font(.footnote).foregroundStyle(.secondary)
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

            PublishingSettings()
                .tabItem { Label("Publishing", systemImage: "square.and.arrow.up") }
        }
        .frame(width: 480, height: 420)
    }

    @ViewBuilder private func PublishingSettings() -> some View { PublishingSettingsView() }

    private func categoryBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { !store.hiddenCategories.contains(id) },
                set: { on in
                    if on { store.hiddenCategories.remove(id) }
                    else { store.hiddenCategories.insert(id) }
                })
    }
}

// archive.org IAS3 ("S3-like") keys for publishing finished edits (Creation Studio #7).
// Stored in the login Keychain via IAS3Keychain — never UserDefaults/iCloud.
private struct PublishingSettingsView: View {
    @State private var access = ""
    @State private var secret = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                Text("Publish finished edits to your Internet Archive account. These are your personal S3-like keys — they stay in this Mac's Keychain.")
                    .font(.callout).foregroundStyle(.secondary)
                Link("Get your keys (archive.org/account/s3.php)",
                     destination: URL(string: "https://archive.org/account/s3.php")!)
            }
            Section {
                TextField("Access key", text: $access).autocorrectionDisabled()
                SecureField("Secret key", text: $secret)
                HStack {
                    Button("Save") {
                        IAS3Keychain.save(access: access.trimmingCharacters(in: .whitespaces),
                                          secret: secret.trimmingCharacters(in: .whitespaces))
                        saved = true
                    }
                    .disabled(access.isEmpty || secret.isEmpty)
                    if !access.isEmpty || !secret.isEmpty {
                        Button("Remove", role: .destructive) {
                            IAS3Keychain.clear(); access = ""; secret = ""; saved = false
                        }
                    }
                    Spacer()
                    if saved { Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            } header: {
                Text("Internet Archive S3 keys")
            } footer: {
                Text("Uploaded edits are dedicated to the public domain (CC0) and stamped with their archive.org sources.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if let c = IAS3Keychain.load() { access = c.access; secret = c.secret; saved = true }
        }
    }
}
#endif
