import SwiftUI
import CoreImage.CIFilterBuiltins

// Settings / About.
//
// Earns its place against three binding decisions:
//   • Decision 007 — TMDb attribution is REQUIRED ("This product uses the
//     TMDB API but is not endorsed or certified by TMDB"). Without a
//     surface for it, the app cannot ship. This is that surface.
//   • Decision 012 — the adult-content filter must be user-toggleable
//     (default on). The toggle binds to AppStore.hideAdultContent, the
//     single chokepoint that re-derives every shelf/grid.
//   • Decision 010 — surface a donate-to-the-Archive link (never to the
//     app itself). tvOS has no browser, so we render a QR code the viewer
//     can scan with a phone.
//
// Learning-orientation check: this screen deepens understanding (it tells
// the viewer exactly where each poster, synopsis, and film comes from
// rather than presenting archival content as if it were ours) and
// supports agency (the mature-content choice is theirs, not a locked
// default). No passivity introduced.

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 36) {
                header
                preferencesCard
                attributionCard
                supportCard
                aboutCard
                    .padding(.bottom, 80)
            }
            .frame(maxWidth: 1280, alignment: .leading)
            .padding(.horizontal, 80)
            .padding(.top, 48)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.system(size: 54, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
            Text("Preferences, sources, and how to support the Archive.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Preferences

    private var preferencesCard: some View {
        SettingsCard(title: "Preferences") {
            Toggle(isOn: Binding(
                get: { !store.hideAdultContent },
                set: { store.hideAdultContent = !$0 }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show Mature Collections")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Off by default. The Archive's catalog includes adult-leaning collections; leave this off on a shared TV.")
                        .font(.system(size: 21))
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .tint(Color(hex: "#FF5C35") ?? .orange)
        }
    }

    // MARK: - Attribution (Decision 007 — required)

    private var attributionCard: some View {
        SettingsCard(title: "Sources & Attribution") {
            VStack(alignment: .leading, spacing: 18) {
                // The TMDb wordmark + the exact required notice. The text is
                // the mandatory part of the terms; keep it verbatim.
                HStack(spacing: 14) {
                    Text("TMDB")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(colors: [Color(hex: "#0d253f") ?? .blue,
                                                    Color(hex: "#01b4e4") ?? .cyan],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                        .font(.system(size: 23))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Posters, backdrops, cast, and synopses are sourced from The Movie Database (TMDb), with Wikidata, Wikimedia Commons, and the Library of Congress as fallbacks. Films, television, and ephemera are served by the Internet Archive. All titles are in the public domain or otherwise free to share.")
                    .font(.system(size: 21))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Support (Decision 010)

    private var supportCard: some View {
        SettingsCard(title: "Support the Internet Archive") {
            HStack(alignment: .center, spacing: 28) {
                QRCode(string: "https://archive.org/donate")
                    .frame(width: 180, height: 180)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 10) {
                    Text("Archive Watch is free and takes nothing for itself.")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("If it's brought you something worth keeping, support the people who keep the films online. Scan to donate, or visit:")
                        .font(.system(size: 21))
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("archive.org/donate")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: "#FF5C35") ?? .orange)
                }
            }
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        SettingsCard(title: "About") {
            VStack(alignment: .leading, spacing: 12) {
                Text(versionString)
                    .font(.system(size: 23, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                Text("No account, no sign-in, no tracking. Nothing leaves this device except requests to the public services above.")
                    .font(.system(size: 21))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Archive Watch · Version \(v) (\(b))"
    }
}

// MARK: - Reusable card container

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title.uppercased())
                .font(.system(size: 16, weight: .bold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.45))
            content
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - QR code

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
