import SwiftUI
import SwiftData
import CoreImage.CIFilterBuiltins
import AuthenticationServices

// Settings / About — built on a dark grouped `List`, the idiomatic tvOS settings
// pattern (Apple's own Settings app is a grouped list). Two reasons it must be a
// List, not a hand-rolled ScrollView of Text (the previous version's bugs):
//   • tvOS ScrollViews only scroll to FOCUSABLE elements — plain Text at the
//     bottom (attribution, version) was unreachable. Every List row IS focusable,
//     so scrolling reaches the end.
//   • The earlier custom layout left a non-black strip on the trailing edge; the
//     List sits on a full-screen black backdrop with the system list background
//     hidden, so the whole surface is black.
// The title is pinned ABOVE the List (not a navigationTitle, which scrolled
// behind content on tvOS).
//
// Binding decisions surfaced here: TMDb attribution (007, verbatim), the mature
// filter toggle (012), and the donate-to-Archive link (010, a QR since tvOS has
// no browser).

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteAccount = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.system(size: 54, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
                .padding(.horizontal, 80)
                .padding(.top, 40)
                .padding(.bottom, 12)

            List {
                accountSection
                visibilitySection
                homeSection
                playbackSection
                matureSection
                attributionSection
                aboutSection
                donateSection   // last: its focusable row is the bottom scroll anchor
            }
            .listStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.black.ignoresSafeArea())
        // Sync once sign-in completes (no-op until CloudKit is enabled).
        .onChange(of: account.isSignedIn) { _, signedIn in
            if signedIn { Task { await CloudKitSyncService.shared.sync(modelContext) } }
        }
    }

    // MARK: - Sections

    private var visibilitySection: some View {
        Section {
            ForEach(store.featured?.categories ?? []) { cat in
                Toggle(isOn: categoryBinding(cat.id)) {
                    ToggleLabel(title: cat.displayName, accent: Color(hex: cat.accent) ?? .accentColor)
                }
            }
        } header: {
            Text("Show on Home & Browse")
        } footer: {
            Text("Turn a category off to hide it everywhere. Favorites and Continue Watching are unaffected.")
        }
    }

    // #17 (tvOS-DESIGN §10.3)
    private var homeSection: some View {
        Section {
            Toggle(isOn: hideWatchedBinding) {
                ToggleLabel(title: "Hide Watched on Home")
            }
        } header: {
            Text("Home")
        } footer: {
            Text("On by default. Finished titles stay out of Home shelves but remain in Search, Browse, and Continue Watching.")
        }
    }

    // #11 (Decision 022): Sign in with Apple — gates only cross-Apple-TV sync.
    private var accountSection: some View {
        Section {
            if account.isSignedIn {
                LabeledContent {
                    Text("Signed in").foregroundStyle(.white.opacity(0.6))
                } label: {
                    Label("Apple ID", systemImage: "person.crop.circle.fill.badge.checkmark")
                        .foregroundStyle(.white)
                }
                Button(role: .destructive) { account.signOut() } label: {
                    Text("Sign Out")
                }
                // App Review 5.1.1(v): account creation requires in-app deletion.
                Button(role: .destructive) { showDeleteAccount = true } label: {
                    Text("Delete Account")
                }
                .alert("Delete Account?", isPresented: $showDeleteAccount) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete Account", role: .destructive) {
                        Task {
                            _ = await CloudKitSyncService.shared.deleteAllCloudData()
                            account.signOut()
                        }
                    }
                } message: {
                    Text("This permanently deletes your synced favorites, playlists, and watch progress from iCloud and signs you out. Titles saved on this Apple TV stay on this device.")
                }
            } else {
                // Custom button driving our own ASAuthorizationController
                // (SwiftUI's SignInWithAppleButton does nothing on tvOS — see
                // AccountStore). Apple-logo + standard title keeps it recognizable.
                Button { account.startSignIn() } label: {
                    Label("Sign in with Apple", systemImage: "applelogo")
                }
                .buttonStyle(AppleSignInButtonStyle())
                .listRowBackground(Color.clear)

                if let err = account.signInError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Sign in with Apple to sync your favorites, playlists, and watch progress across your Apple TVs. Optional — browsing and playback work without it; nothing leaves your device until you sign in.")
        }
    }

    // #10 (tvOS-DESIGN §8.5)
    private var playbackSection: some View {
        Section {
            Picker(selection: autoplayBinding) {
                ForEach(AutoplayMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            } label: {
                ToggleLabel(title: "Autoplay Next")
            }
            Picker(selection: commercialLengthBinding) {
                Text("Off").tag(-1)
                Text("30 sec").tag(30)
                Text("1 min").tag(60)
                Text("2 min").tag(120)
                Text("3 min").tag(180)
                Text("Full length").tag(0)
            } label: {
                ToggleLabel(title: "Commercial Breaks on Channels")
            }
            Toggle(isOn: idleSaverBinding) {
                ToggleLabel(title: "Idle Screensaver")
            }
            Toggle(isOn: vhsBinding) {
                ToggleLabel(title: "VHS Screensaver Look")
            }
        } header: {
            Text("Playback")
        } footer: {
            Text("When a film ends, automatically play another. Off by default. You can also change this for the current video from its transport menu. TV episodes always continue to the next episode. Commercial breaks play vintage public-domain ads between programs on Channels — the 1990s-TV feel. The idle screensaver shows the cover-art wall after a few minutes of inactivity (never during playback). The VHS look gives the screensaver an analog tape/CRT veneer — scanlines, chroma bleed, and tracking shimmer — fitting for archival film and TV.")
        }
    }

    private var idleSaverBinding: Binding<Bool> {
        Binding(get: { store.screensaverIdleEnabled }, set: { store.screensaverIdleEnabled = $0 })
    }

    private var vhsBinding: Binding<Bool> {
        Binding(get: { store.screensaverVHS }, set: { store.screensaverVHS = $0 })
    }

    private var autoplayBinding: Binding<AutoplayMode> {
        Binding(get: { store.autoplayMode }, set: { store.autoplayMode = $0 })
    }

    /// Maps the on/off + max-length pair to a single Picker selection.
    /// -1 = Off, 0 = Full length, otherwise the cap in seconds.
    private var commercialLengthBinding: Binding<Int> {
        Binding(
            get: { store.channelCommercialBreaks ? store.commercialBreakMaxSeconds : -1 },
            set: { v in
                if v == -1 { store.channelCommercialBreaks = false }
                else { store.channelCommercialBreaks = true; store.commercialBreakMaxSeconds = v }
            }
        )
    }

    private var matureSection: some View {
        Section {
            Toggle(isOn: showMatureBinding) {
                ToggleLabel(title: "Show Mature Collections")
            }
        } header: {
            Text("Mature Content")
        } footer: {
            Text("Off by default — the Archive includes adult-leaning collections. Leave off on a shared TV.")
        }
    }

    private var attributionSection: some View {
        Section {
            HStack(spacing: 16) {
                Text("TMDB")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(
                        LinearGradient(colors: [Color(hex: "#0d253f") ?? .blue,
                                                Color(hex: "#01b4e4") ?? .cyan],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 8))
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Posters, backdrops, cast, and synopses come from The Movie Database (TMDb), with Wikidata, Wikimedia Commons, and the Library of Congress as fallbacks. Films, television, and ephemera are served by the Internet Archive. Every title is public domain or otherwise free to share.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Sources & Attribution")
        }
    }

    private var donateSection: some View {
        Section {
            // A Button (no-op — tvOS has no browser; the QR is the mechanism) so
            // this row is FOCUSABLE. As the last focusable element it's the bottom
            // scroll anchor: focusing it scrolls the attribution + About rows above
            // it into view, which plain-Text rows alone could never do on tvOS.
            Button { } label: {
                HStack(alignment: .center, spacing: 28) {
                    QRCode(string: "https://archive.org/donate")
                        .frame(width: 150, height: 150)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Archive Watch is free and takes nothing for itself.")
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("If it's brought you something worth keeping, support the people who keep the films online. Scan to donate, or visit:")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("archive.org/donate")
                            .font(.system(.title3, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color(hex: "#FF5C35") ?? .orange)
                    }
                }
            }
        } header: {
            Text("Support the Internet Archive")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: versionString)
            Text("No account, no sign-in, no tracking. Nothing leaves this device except requests to the public services above.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("About")
        }
    }

    // MARK: - Bindings

    private var showMatureBinding: Binding<Bool> {
        Binding(get: { !store.hideAdultContent },
                set: { store.hideAdultContent = !$0 })
    }

    private var hideWatchedBinding: Binding<Bool> {
        Binding(get: { store.hideWatchedOnHome },
                set: { store.hideWatchedOnHome = $0 })
    }

    private func categoryBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !store.hiddenCategories.contains(id) },
            set: { visible in
                if visible { store.hiddenCategories.remove(id) }
                else { store.hiddenCategories.insert(id) }
            }
        )
    }

    private var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }
}

// MARK: - Focus-aware toggle label
//
// A List row's focus paints the pill white; without this the white label text
// vanished on the white pill. Reading @Environment(\.isFocused) inside the
// Toggle's label flips the text to black exactly when the row is focused.

private struct ToggleLabel: View {
    @Environment(\.isFocused) private var isFocused
    let title: String
    var accent: Color? = nil

    var body: some View {
        HStack(spacing: 14) {
            if let accent {
                Circle().fill(accent).frame(width: 16, height: 16)
            }
            Text(title)
                .foregroundStyle(isFocused ? .black : .white)
        }
    }
}

// MARK: - QR code (CoreImage)

struct QRCode: View {   // shared: Settings donate + Detail share (#16)
    let string: String

    var body: some View {
        if let image = Self.generate(from: string) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(10)
        } else {
            Color.white
        }
    }

    private static func generate(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// Sign in with Apple button — black field, white Apple-logo + title, focus-aware.
// A plain Label row washed out to all-white on focus (the tvOS List row highlight
// behind white text). This style paints its own opaque black field so the label
// stays legible focused or not, and reads focus for a ring + lift instead.
struct AppleSignInButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        SignInLabel(configuration: configuration)
    }

    private struct SignInLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused
        var body: some View {
            configuration.label
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(isFocused ? 0.95 : 0.30),
                                lineWidth: isFocused ? 4 : 1)
                )
                .scaleEffect(isFocused ? 1.03 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                .opacity(configuration.isPressed ? 0.7 : 1.0)
        }
    }
}
