#if os(iOS)
import SwiftUI
import SwiftData

// Settings: the required attribution (Decision 007), the mature-content toggle
// (Decision 012, default on), the donate link (Decision 010), and version. Native
// iOS `Form`. Account/CloudKit sign-in lands with the sync wiring (Phase 1 follow).
struct SettingsView: View {
    @State private var removingAll = false
    @Environment(AppStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.modelContext) private var ctx
    @State private var showDeleteAccount = false

    var body: some View {
        @Bindable var store = store
        Form {
            accountSection
            SubtitleAccountSection()
            AutoCaptionsSettingsSection()
            Section("Content") {
                Toggle("Show mature collections", isOn: Binding(
                    get: { !store.hideAdultContent },
                    set: { store.hideAdultContent = !$0 }))
                Text("Off by default — the Internet Archive includes adult-leaning collections.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Hide watched titles on Home", isOn: $store.hideWatchedOnHome)
                ForEach(store.featured?.categories ?? []) { cat in
                    Toggle(cat.displayName, isOn: categoryBinding(cat.id))
                }
            } header: {
                Text("Home & Categories")
            } footer: {
                Text("Hidden categories disappear from Home, Browse, and Search on this device.")
            }

            Section("Playback") {
                Picker("Autoplay next", selection: $store.autoplayMode) {
                    ForEach(AutoplayMode.allCases) { Text($0.label).tag($0) }
                }
                Text("When a film ends, what plays next. TV episodes always continue "
                     + "to the next episode.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            downloadsSection

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
                Text("No tracking. Nothing leaves this device except requests to the public "
                     + "services above — and, only if you sign in, your own iCloud (never us).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        // Pull synced state the moment the user signs in (Decision 022).
        .onChange(of: account.isSignedIn) { _, signedIn in
            if signedIn { Task { await CloudKitSyncService.shared.sync(ctx) } }
        }
    }

    // #11 (Decision 022): Sign in with Apple — optional, gates only cross-device sync.
    /// Downloads (Decision 099). Two facts and two actions: how much space the
    /// films are using, whether they may use cellular, and a way out of both.
    @ViewBuilder private var downloadsSection: some View {
        Section("Downloads") {
            Toggle("Download over cellular", isOn: Binding(
                get: { DownloadManager.shared.allowsCellular },
                set: { DownloadManager.shared.allowsCellular = $0 }))
            Text("Off by default — a feature film is often several hundred megabytes.")
                .font(.footnote).foregroundStyle(.secondary)
            let used = OfflineLibrary.bytesUsed()
            if used > 0 {
                LabeledContent("Space used", value: OfflineLibrary.byteText(used))
                Button(role: .destructive) { removingAll = true } label: {
                    Text("Remove All Downloads")
                }
                .confirmationDialog("Remove every download?", isPresented: $removingAll) {
                    Button("Remove All Downloads", role: .destructive) {
                        DownloadManager.shared.removeAll()
                    }
                } message: {
                    Text("Frees \(OfflineLibrary.byteText(used)). Your favorites, playlists "
                         + "and watch history are not affected.")
                }
            } else {
                Text("Nothing downloaded yet. Use the download button on a film's page "
                     + "to keep it on this device.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var accountSection: some View {
        Section {
            if account.isSignedIn {
                LabeledContent {
                    Text("Signed in").foregroundStyle(.secondary)
                } label: {
                    Label("Apple ID", systemImage: "person.crop.circle.fill.badge.checkmark")
                }
                // Sync status + manual kick — a failing sync must be visible,
                // not swallowed (the old silent catch hid a never-working pull).
                if let err = CloudKitSyncService.shared.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                } else if let at = CloudKitSyncService.shared.lastSyncAt {
                    LabeledContent("Last sync") {
                        Text(at, format: .relative(presentation: .named))
                    }
                }
                Button("Sync Now") {
                    Task { await CloudKitSyncService.shared.sync(ctx) }
                }
                Button(role: .destructive) { account.signOut() } label: { Text("Sign Out") }
                // App Review 5.1.1(v): account creation requires in-app deletion.
                Button(role: .destructive) { showDeleteAccount = true } label: { Text("Delete Account") }
                    .alert("Delete Account?", isPresented: $showDeleteAccount) {
                        Button("Cancel", role: .cancel) { }
                        Button("Delete Account", role: .destructive) {
                            Task {
                                _ = await CloudKitSyncService.shared.deleteAllCloudData()
                                account.signOut()
                            }
                        }
                    } message: {
                        Text("This permanently deletes your synced favorites, playlists, and watch "
                             + "progress from iCloud and signs you out. Titles saved on this device stay here.")
                    }
            } else {
                // Apple's canonical white-on-dark sign-in button. The app runs
                // dark, so the old `.bordered` style drew #0047FF accent text on
                // dark gray — unreadable (owner report 2026-06-10).
                Button { account.startSignIn() } label: {
                    Label("Sign in with Apple", systemImage: "applelogo")
                        .fontWeight(.semibold)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                if let err = account.signInError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Account & Sync")
        } footer: {
            Text("Sign in with Apple to sync favorites, playlists, and watch progress across your "
                 + "Apple devices — including your Apple TV. Optional: browsing and playback work "
                 + "without it; nothing leaves this device until you sign in.")
        }
    }

    private func categoryBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { !store.hiddenCategories.contains(id) },
                set: { on in
                    if on { store.hiddenCategories.remove(id) }
                    else { store.hiddenCategories.insert(id) }
                })
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }
}

#endif
