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
            } else {
                SignInWithAppleButton(.signIn,
                    onRequest: account.configure,
                    onCompletion: { result in
                        account.handle(result)
                        Task { await CloudKitSyncService.shared.sync(modelContext) }
                    })
                .signInWithAppleButtonStyle(.white)
                .frame(height: 64)

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
        } header: {
            Text("Playback")
        } footer: {
            Text("When a film ends, automatically play another. Off by default. You can also change this for the current video from its transport menu. TV episodes always continue to the next episode.")
        }
    }

    private var autoplayBinding: Binding<AutoplayMode> {
        Binding(get: { store.autoplayMode }, set: { store.autoplayMode = $0 })
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
