import SwiftUI
import CoreImage.CIFilterBuiltins

// Settings / About.
//
// Built on the native tvOS `Form` (grouped list) rather than hand-rolled
// cards — it gives correct focus traversal, the system grouped style, and
// a native large navigation title for free. Earns its place against three
// binding decisions:
//   • Decision 007 — TMDb attribution is REQUIRED ("This product uses the
//     TMDB API but is not endorsed or certified by TMDB"). This is that
//     surface; without it the app can't ship.
//   • Decision 012 — the adult-content filter is user-toggleable
//     (default on). The native Toggle binds to AppStore.hideAdultContent,
//     the single chokepoint that re-derives every shelf/grid.
//   • Decision 010 — surface a donate-to-the-Archive link (never to the
//     app itself). tvOS has no browser, so we render a QR the viewer
//     scans with a phone.
//
// Learning-orientation check: deepens understanding (tells the viewer
// exactly where each poster/synopsis/film comes from rather than passing
// archival content off as ours) and supports agency (the mature-content
// choice is theirs). No passivity introduced.

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Form {
            Section {
                Toggle(isOn: showMatureBinding) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Show Mature Collections")
                        Text("Off by default. The Archive's catalog includes adult-leaning collections; leave this off on a shared TV.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Preferences")
            }

            Section {
                HStack(spacing: 16) {
                    Text("TMDB")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            LinearGradient(colors: [Color(hex: "#0d253f") ?? .blue,
                                                    Color(hex: "#01b4e4") ?? .cyan],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Posters, backdrops, cast, and synopses come from The Movie Database (TMDb), with Wikidata, Wikimedia Commons, and the Library of Congress as fallbacks. Films, television, and ephemera are served by the Internet Archive. Every title is public domain or otherwise free to share.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Sources & Attribution")
            }

            Section {
                HStack(alignment: .center, spacing: 28) {
                    QRCode(string: "https://archive.org/donate")
                        .frame(width: 160, height: 160)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Archive Watch is free and takes nothing for itself.")
                            .fixedSize(horizontal: false, vertical: true)
                        Text("If it's brought you something worth keeping, support the people who keep the films online. Scan to donate, or visit:")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("archive.org/donate")
                            .font(.system(.title3, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color(hex: "#FF5C35") ?? .orange)
                    }
                }
            } header: {
                Text("Support the Internet Archive")
            }

            Section {
                LabeledContent("Version", value: versionString)
                Text("No account, no sign-in, no tracking. Nothing leaves this device except requests to the public services above.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
    }

    /// Decision 012 phrasing: the user-facing control is "Show Mature
    /// Collections" (off by default), the inverse of the stored
    /// hideAdultContent flag.
    private var showMatureBinding: Binding<Bool> {
        Binding(
            get: { !store.hideAdultContent },
            set: { store.hideAdultContent = !$0 }
        )
    }

    private var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
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
