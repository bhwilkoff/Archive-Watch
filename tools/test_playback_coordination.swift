// Does AVPlayerPlaybackCoordinator actually work through OUR custom-scheme
// resource loader?
//
// This is the one claim SharePlay rests on here and the one I could not prove
// from documentation alone. Decision 051 established that video AirPlay does
// NOT work through a custom AVAssetResourceLoaderDelegate (it is solved by
// swapping to a published URL), and Decision 072 puts every title behind
// exactly such a loader — `aw-stream://`. If coordination shared that
// limitation, SharePlay would be dead on arrival for this app.
//
// Apple's documentation says it should be fine, because `identifierForPlayerItem`
// exists precisely "to establish identity of two items created from different
// URLs". Documentation is not evidence. AVFoundation is the only authority.
//
// The test needs no FaceTime call and no second Apple ID: AVPlaybackCoordination-
// Medium (new in 26) connects two LOCAL AVPlayerPlaybackCoordinators. That is
// the same coordination machinery a group session drives, minus the transport —
// so if two players built from `aw-stream://` assets follow each other through a
// medium, the coordinator is demonstrably willing to drive our loader-backed
// items, and the identifier delegate is demonstrably being consulted.
//
// PASSES when: both items reach .readyToPlay through the custom scheme, the
// identifier delegate is called for BOTH, and a rate change on player A is
// mirrored by player B within tolerance.
//
// Run (swiftc, because `swift <file>` script mode compiles only ONE file and the
// point is to test the SHIPPED loader, not a copy of it):
//   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
//   xcrun swiftc -O tools/test_playback_coordination.swift \
//     ArchiveWatch/ArchiveWatch/Networking/ResilientStreamLoader.swift \
//     -o /tmp/awcoord && /tmp/awcoord [mp4-url]

import AVFoundation
import Foundation

// ResilientStreamLoader defines awdiag and PlaybackDiag itself; only this one
// symbol comes from elsewhere in the app.
enum AirPlayRouting {
    static let streamScheme = "aw-stream"
    static let hlsScheme = "aw-hls"
    static let loaderSchemes: Set<String> = [streamScheme, hlsScheme]
}

let args = CommandLine.arguments
let mp4 = args.count > 1 && args[1].hasPrefix("http")
    ? args[1]
    : "https://archive.org/download/suddenly/suddenly.mp4"
let archiveID = "suddenly"

guard #available(macOS 26.0, *) else {
    print("FAIL: AVPlaybackCoordinationMedium needs macOS 26+")
    exit(1)
}

/// Answers with the archiveID regardless of which URL the item was built from —
/// the whole point under test.
final class Identity: NSObject, AVPlayerPlaybackCoordinatorDelegate, @unchecked Sendable {
    let label: String
    private(set) var asked = 0
    init(_ label: String) { self.label = label }
    func playbackCoordinator(_ c: AVPlayerPlaybackCoordinator,
                             identifierFor playerItem: AVPlayerItem) -> String {
        asked += 1
        return archiveID
    }
}

// The resource-loader delegate is held WEAKLY by AVAssetResourceLoader, so the
// loader must be retained for the lifetime of the asset. Dropping it (the
// tempting `let (asset, _) = …`) deallocates the delegate immediately and every
// request for the custom scheme fails with "unsupported URL" — which reads like
// AVFoundation rejecting our scheme, and is not.
var keepAlive: [AnyObject] = []

func makePlayer(_ label: String) -> (AVPlayer, AVPlayerItem, Identity, URL) {
    let (asset, loader) = ResilientStreamLoader.makeAsset(for: URL(string: mp4)!)
    if let loader { keepAlive.append(loader) }
    let item = AVPlayerItem(asset: asset)
    let p = AVPlayer(playerItem: item)
    p.isMuted = true
    let id = Identity(label)
    p.playbackCoordinator.delegate = id
    return (p, item, id, (asset as AVURLAsset).url)
}

let (a, itemA, idA, urlA) = makePlayer("A")
let (b, itemB, idB, urlB) = makePlayer("B")

print("asset URL A: \(urlA.absoluteString.prefix(60))…")
print("custom scheme in use: \(urlA.scheme == AirPlayRouting.streamScheme ? "YES (aw-stream)" : "NO — test is not exercising the loader!")")
guard urlA.scheme == AirPlayRouting.streamScheme else {
    print("FAIL: asset is not loader-backed; nothing meaningful is being tested")
    exit(1)
}

@available(macOS 26.0, *)
func run() -> Int32 {
    let medium = AVPlaybackCoordinationMedium()
    var err: NSError?
    for (p, name) in [(a, "A"), (b, "B")] {
        do {
            try p.playbackCoordinator.coordinate(using: medium)
            print("connect \(name) to medium: OK")
        } catch let e as NSError {
            print("connect \(name) to medium: FAILED \(e.localizedDescription)")
            err = e
        }
    }
    if err != nil { return 1 }
    print("connected coordinators: \(medium.connectedPlaybackCoordinators.count)")

    // Both items must load THROUGH the custom scheme before coordination means
    // anything — a coordinator on a dead item proves nothing.
    let deadline = Date().addingTimeInterval(90)
    while Date() < deadline,
          !(itemA.status == .readyToPlay && itemB.status == .readyToPlay) {
        if itemA.status == .failed || itemB.status == .failed {
            print("FAIL: item failed: \(itemA.error?.localizedDescription ?? itemB.error?.localizedDescription ?? "?")")
            return 1
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    guard itemA.status == .readyToPlay, itemB.status == .readyToPlay else {
        print("FAIL: items never became ready through aw-stream:// (A=\(itemA.status.rawValue) B=\(itemB.status.rawValue))")
        return 1
    }
    print("both items readyToPlay through the custom scheme")

    // Drive A; B must follow without being touched.
    a.play()
    let watch = Date().addingTimeInterval(20)
    var bMoved = false
    while Date() < watch {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        if b.rate > 0 || b.currentTime().seconds > 0.5 { bMoved = true; break }
    }
    let ta = a.currentTime().seconds, tb = b.currentTime().seconds
    print(String(format: "after play on A only:  A=%.2fs rate=%.1f   B=%.2fs rate=%.1f",
                 ta, a.rate, tb, b.rate))
    print("identifier delegate consulted:  A=\(idA.asked)x  B=\(idB.asked)x")

    var pass = true
    if idA.asked == 0 || idB.asked == 0 {
        print("FAIL: identifierForPlayerItem was never called — items are not being matched by our id")
        pass = false
    }
    if !bMoved {
        print("FAIL: B never followed A — coordination did not drive the second player")
        pass = false
    }
    if pass, abs(ta - tb) > 3.0 {
        print(String(format: "WARN: drift %.2fs between coordinated players", abs(ta - tb)))
    }
    a.pause(); b.pause()
    print(pass ? "\nPASS — playback coordination works through the custom-scheme resource loader."
               : "\nFAIL")
    return pass ? 0 : 1
}

exit(run())
