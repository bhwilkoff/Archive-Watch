import SwiftUI
import CoreImage.CIFilterBuiltins

// Settings / About — rewritten to match the rest of the app (#6). The previous
// version used a native `Form`, which on tvOS renders a light grouped list with
// its own background and a navigation title that scrolls oddly — completely
// unlike Home/Browse/Search/Surprise. This is a dark, full-height ScrollView
// with the app's serif title, section cards, and focusable rows, per
// docs/tvos-playbook.md (dark-first, 90/60 safe area, focus does the work).
//
// Earns its place against three binding decisions:
//   • Decision 007 — TMDb attribution is REQUIRED, rendered verbatim below.
//   • Decision 012 — the mature-content filter is user-toggleable (default on).
//   • Decision 010 — a donate-to-the-Archive link (QR, since tvOS has no browser).

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @FocusState private var focused: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 44) {
                Text("Settings")
                    .font(.system(size: 54, weight: .heavy, design: .serif))
                    .foregroundStyle(.white)
                    .padding(.top, 56)

                visibilitySection
                matureSection
                attributionSection
                donateSection
                aboutSection
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 80)
            .frame(maxWidth: 1500, alignment: .leading)
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            focused = "mature"
        }
    }

    // MARK: - Sections

    private var visibilitySection: some View {
        SettingsCard(title: "Show on Home & Browse",
                     footer: "Turn a category off to hide it everywhere. Favorites and Continue Watching are unaffected.") {
            VStack(spacing: 0) {
                ForEach(store.featured?.categories ?? []) { cat in
                    SettingsToggleRow(
                        title: cat.displayName,
                        accent: Color(hex: cat.accent) ?? .accentColor,
                        isOn: categoryBinding(cat.id)
                    )
                    .focused($focused, equals: "cat-\(cat.id)")
                }
            }
        }
    }

    private var matureSection: some View {
        SettingsCard(title: "Mature Content",
                     footer: "Off by default — the Archive includes adult-leaning collections. Leave off on a shared TV.") {
            SettingsToggleRow(title: "Show Mature Collections", accent: .orange, isOn: showMatureBinding)
                .focused($focused, equals: "mature")
        }
    }

    private var attributionSection: some View {
        SettingsCard(title: "Sources & Attribution", footer: nil) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    Text("TMDB")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(
                            LinearGradient(colors: [Color(hex: "#0d253f") ?? .blue,
                                                    Color(hex: "#01b4e4") ?? .cyan],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 8))
                    Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Posters, backdrops, cast, and synopses come from The Movie Database (TMDb), with Wikidata, Wikimedia Commons, and the Library of Congress as fallbacks. Films, television, and ephemera are served by the Internet Archive. Every title is public domain or otherwise free to share.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var donateSection: some View {
        SettingsCard(title: "Support the Internet Archive", footer: nil) {
            HStack(alignment: .center, spacing: 28) {
                QRCode(string: "https://archive.org/donate")
                    .frame(width: 160, height: 160)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 10) {
                    Text("Archive Watch is free and takes nothing for itself.")
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("If it's brought you something worth keeping, support the people who keep the films online. Scan to donate, or visit:")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("archive.org/donate")
                        .font(.system(.title3, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color(hex: "#FF5C35") ?? .orange)
                }
            }
        }
    }

    private var aboutSection: some View {
        SettingsCard(title: "About", footer: nil) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Version").foregroundStyle(.white)
                    Spacer()
                    Text(versionString).foregroundStyle(.white.opacity(0.6))
                }
                Text("No account, no sign-in, no tracking. Nothing leaves this device except requests to the public services above.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Bindings

    private var showMatureBinding: Binding<Bool> {
        Binding(get: { !store.hideAdultContent },
                set: { store.hideAdultContent = !$0 })
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

// MARK: - Section card (matches the app's dark surface)

private struct SettingsCard<Content: View>: View {
    let title: String
    let footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.system(size: 17, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.5))
            content
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            if let footer {
                Text(footer)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Focusable toggle row

private struct SettingsToggleRow: View {
    let title: String
    let accent: Color
    @Binding var isOn: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 14) {
                Circle().fill(accent).frame(width: 16, height: 16)
                Text(title)
                    .font(.title3)
                    .foregroundStyle(.white)
            }
        }
        .toggleStyle(.switch)
        .focused($isFocused)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isFocused ? Color.white.opacity(0.12) : Color.clear)
        )
        .animation(Motion.focus, value: isFocused)
    }
}

// MARK: - QR code (CoreImage)

private struct QRCode: View {
    let string: String

    var body: some View {
        if let image = Self.generate(from: string) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(12)
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
