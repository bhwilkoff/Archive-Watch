#if os(macOS)
import SwiftUI

// Env-gated screenshot/test hooks so the Mac app can be driven into a specific Creation Studio
// surface from the command line for visual verification (the macOS analogue of the tvOS/iOS
// AW_START_ITEM hooks). SwiftUI's accessibility tree isn't reliably traversable from shell
// AppleScript, so instead of navigating the live UI we populate the editor document that the
// DocumentGroup reliably opens on launch. ProjectEditorView consults these in its .task.
//
//   AW_CS_TEST=editor    → the opened project gets 2 real clips (timeline + archive.org-
//                          thumbnail filmstrips + program monitor) so the editor is non-empty.
//   AW_CS_TEST=markclip  → the editor immediately presents the Add-Clip interface (thumbnail
//                          scrubber) for a real clippable item.
@MainActor
enum CreationStudioTest {
    static var mode: String? { ProcessInfo.processInfo.environment["AW_CS_TEST"] }

    /// A real, currently-clippable catalog item (playable + rights-clear) with a video URL.
    static func clippable(_ store: AppStore) -> Catalog.Item? {
        for _ in 0..<400 {
            if let it = store.randomPlayable(), it.isClippable, it.videoURLParsed != nil { return it }
        }
        return nil
    }

    /// Add two real clips to the editor (exercising the live addClip → filmstrip → cache path).
    static func populate(_ model: EditorModel, _ store: AppStore) {
        var added = 0, tries = 0
        while added < 2 && tries < 800 {
            tries += 1
            guard let it = clippable(store), let url = it.videoURLParsed else { continue }
            model.addClip(catalogItemID: it.archiveID, sourceURL: url, title: it.title,
                          inSeconds: 30, durationSeconds: 8)
            added += 1
        }
    }
}
#endif
