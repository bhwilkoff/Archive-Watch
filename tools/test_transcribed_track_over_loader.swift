// Does the system's automatic "English (US) Transcribed" subtitle survive our
// custom resource loader?
//
// THE REPORT: a film the catalog knows has NO captions still shows English
// subtitles in the player, and selecting them renders nothing.
//
// THE FINDING BEHIND IT: on a raw https URL, an archive.org MP4 with only video
// and audio tracks still advertises ONE legible option — "English (US)
// Transcribed" — which is AVFoundation's own on-device transcription, not
// anything this app supplies. AVPlayerViewController lists whatever the asset
// advertises, so the app "says it has English subtitles" without ever claiming
// so itself.
//
// THE QUESTION THIS ANSWERS: every playback path here is loader-backed
// (`aw-stream://`, Decisions 021/031/034). Apple has already told us that video
// AirPlay is unsupported with a custom resource loader (Decision 051); if the
// transcription feature is likewise unavailable, the CC menu is advertising
// something that structurally cannot render — which is exactly what a viewer
// sees. Comparing the two assets side by side is the only way to know.
//
// Compile against the SHIPPED loader:
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
//     -parse-as-library ArchiveWatch/ArchiveWatch/Networking/AirPlayRouting.swift \
//     ArchiveWatch/ArchiveWatch/Networking/ResilientStreamLoader.swift \
//     tools/test_transcribed_track_over_loader.swift -o /tmp/awtrans && /tmp/awtrans <mp4-url>

import AVFoundation
import Foundation

@main
struct Harness {
    static func options(_ asset: AVURLAsset, _ label: String) async -> [String] {
        do {
            _ = try await asset.load(.duration)
        } catch {
            print("  \(label): FAILED to load — \(error)")
            return []
        }
        guard let group = try? await asset.loadMediaSelectionGroup(for: .legible) else {
            print("  \(label): no legible group")
            return []
        }
        let names = group.options.map(\.displayName)
        print("  \(label): \(names.isEmpty ? "(none)" : names.joined(separator: ", "))")
        return names
    }

    static func main() async {
        let raw = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "https://archive.org/download/mantheincrediblemachine/mantheincrediblemachine.mp4"
        guard let url = URL(string: raw) else { print("bad url"); exit(2) }

        print("legible options for \(url.lastPathComponent)\n")

        let direct = await options(AVURLAsset(url: url), "direct https        ")

        let (asset, loader) = ResilientStreamLoader.makeAsset(for: url)
        _ = loader          // the delegate is held weakly; keep it alive
        let viaLoader = await options(asset, "via ResilientStream ")

        print("")
        let directHas = direct.contains { $0.localizedCaseInsensitiveContains("transcrib") }
        let loaderHas = viaLoader.contains { $0.localizedCaseInsensitiveContains("transcrib") }

        if directHas && !loaderHas {
            print("RESULT: the system transcription is LOST through the custom loader.")
            print("        The player would offer it on a direct URL and not on ours.")
        } else if directHas && loaderHas {
            print("RESULT: the transcribed option survives the loader — the CC menu entry")
            print("        is real, so an empty render is a different fault (assets/entitlement).")
        } else if !directHas {
            print("RESULT: no transcribed option even on the direct URL — this file is not")
            print("        the case under investigation.")
        }
        exit(0)
    }
}
