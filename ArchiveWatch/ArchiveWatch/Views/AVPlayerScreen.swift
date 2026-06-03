import SwiftUI
import AVKit
import AVFoundation

// Native tvOS playback surface.
//
// Per docs/tvos-playbook.md "Playback": AVPlayerViewController is the
// baseline, not SwiftUI's VideoPlayer — it gives the full tvOS transport
// (scrubbing thumbnails, the Info tab with title/description/genre, audio
// + subtitle menus, Now Playing on the remote) for free. We feed it
// `externalMetadata` so that Info tab shows the real film details instead
// of a bare scrubber.

struct AVPlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}

// Builds the AVKit Info-panel metadata from a catalog item. Title +
// description + genre are what the tvOS player surfaces; artwork would
// require fetching poster bytes synchronously, so it's left to the
// poster art on the Detail screen instead.
func makeExternalMetadata(for item: Catalog.Item) -> [AVMetadataItem] {
    func entry(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem? {
        guard !value.isEmpty else { return nil }
        let m = AVMutableMetadataItem()
        m.identifier = identifier
        m.value = value as NSString
        m.extendedLanguageTag = "und"
        return m
    }

    var meta: [AVMetadataItem?] = [
        entry(.commonIdentifierTitle, item.title)
    ]
    if let synopsis = item.displaySynopsis {
        meta.append(entry(.commonIdentifierDescription, synopsis))
    }
    if !item.genres.isEmpty {
        meta.append(entry(.quickTimeMetadataGenre,
                          item.genres.prefix(3).joined(separator: ", ")))
    }
    // NOTE: we deliberately DON'T emit .commonIdentifierCreationDate. AVKit
    // renders that field as a date string above the transport scrubber, but a
    // bare 4-digit year ("1952") is not a valid date — tvOS reinterprets it and
    // surfaced wrong, often future years (2035/2045) on nearly every title (#5).
    // The correct year already shows on the Detail screen + hero; keeping it out
    // of the player metadata removes the spurious year entirely.
    return meta.compactMap { $0 }
}
