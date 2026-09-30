// THE SHOW'S SOURCES, and how a scene composes them — macOS-DESIGN §D40.
//
// Owner, 2026-09-30: "You should be able to have full control over which
// camera and call are on each scene, just as you can do in OBS." Asked how
// far, the owner chose: any number of cameras and calls, each its own tile;
// every added camera kept running so a cut is instant; and hiding a call's
// picture never mutes its voice.
//
// PURE VALUE LOGIC, no capture and no UI, so the rules — which tile holds a
// preset seat, how a scene saved before §D40 becomes tiles, what removing a
// source does to a scene — are tested without a camera (§8.74). It compiles
// beside the engine in every harness that needs it and on every platform;
// only the Mac has a Sources list that calls it.

import Foundation
import CoreGraphics

/// One source the host added to the show.
public struct StudioSourceRef: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case camera, call }
    /// Stable for the life of the source, so every scene that shows it keeps
    /// showing it when the host changes which device it is.
    public var id: String
    public var kind: Kind
    /// A camera's `AVCaptureDevice.uniqueID`; nil is the system default.
    /// Always nil for a call: the window is chosen by the host every time and
    /// never remembered (§D23).
    public var deviceID: String?

    public init(id: String, kind: Kind, deviceID: String? = nil) {
        self.id = id; self.kind = kind; self.deviceID = deviceID
    }

    public static func newCamera(deviceID: String?) -> StudioSourceRef {
        StudioSourceRef(id: "camera-" + UUID().uuidString, kind: .camera, deviceID: deviceID)
    }
    public static func newCall() -> StudioSourceRef {
        StudioSourceRef(id: "call-" + UUID().uuidString, kind: .call)
    }
}

/// A scene's framing of its tiles (§D31's "Tiles" part). `camera` and
/// `guests` are the two framings a scene carried before §D40 and are still
/// written, so a scene set saved by this version is still read by the last.
public struct StudioSceneTiles: Codable, Equatable, Sendable {
    public var camera = StudioCameraFraming()
    public var guests = StudioCameraFraming()
    /// §D40 — every source's framing, by source id. OPTIONAL in storage, or
    /// every scene saved before it existed would fail to decode and be
    /// replaced by the starters — the one thing a host may never lose.
    public var bySource: [String: StudioCameraFraming]?

    public init(camera: StudioCameraFraming = StudioCameraFraming(),
                guests: StudioCameraFraming = StudioCameraFraming(),
                bySource: [String: StudioCameraFraming]? = nil) {
        self.camera = camera; self.guests = guests; self.bySource = bySource
    }
}

public enum StudioComposition {

    /// The engine's tile list for a scene: the sources it shows, in its layer
    /// order (first = back), each with its framing.
    ///
    /// THE PRESET SEATS GO BY THE SOURCES LIST, NEVER BY LAYER ORDER. The
    /// first camera in the host's Sources list that the scene shows takes the
    /// placement's host seat, the first call the call's seat; the rest start
    /// in a column of their own. Were it by layer order, bringing a tile to the
    /// front would move every other tile to a different seat.
    ///
    /// A source that is no longer in the list is dropped: nothing to draw.
    public static func tiles(shown: [String], framings: [String: StudioCameraFraming],
                             sources: [StudioSourceRef]) -> [StudioTile] {
        let known = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        let visible = Set(shown)
        let seatCamera = sources.first { $0.kind == .camera && visible.contains($0.id) }?.id
        let seatCall = sources.first { $0.kind == .call && visible.contains($0.id) }?.id
        var seen = Set<String>()
        return shown.compactMap { id in
            guard known[id] != nil, !seen.contains(id) else { return nil }
            seen.insert(id)
            let slot: StudioTileSlot = id == seatCamera ? .camera : (id == seatCall ? .call : .free)
            return StudioTile(source: id, slot: slot, framing: framings[id] ?? StudioCameraFraming())
        }
    }

    /// A SCENE SAVED BEFORE §D40, as sources. Nothing a host built may be
    /// lost: its Camera and Call switches become which of the first camera
    /// and the first call it shows, and its two framings become theirs. The
    /// call goes BEHIND the host, which is the order the one-camera path drew
    /// them in — so the migrated scene composites pixel for pixel as it did
    /// (§8.74 compares the two).
    public static func migrate(cameraOn: Bool, callOn: Bool,
                               tiles: StudioSceneTiles,
                               primaryCamera: String?, primaryCall: String?)
        -> (shown: [String], framings: [String: StudioCameraFraming]) {
        var shown: [String] = []
        if callOn, let primaryCall { shown.append(primaryCall) }
        if cameraOn, let primaryCamera { shown.append(primaryCamera) }
        return (shown, framings(from: tiles, primaryCamera: primaryCamera, primaryCall: primaryCall))
    }

    /// A tile set's per-source framings, reading a pre-§D40 set's two.
    public static func framings(from tiles: StudioSceneTiles, primaryCamera: String?,
                                primaryCall: String?) -> [String: StudioCameraFraming] {
        if let by = tiles.bySource { return by }
        var out: [String: StudioCameraFraming] = [:]
        if let primaryCamera, !tiles.camera.isDefault { out[primaryCamera] = tiles.camera }
        if let primaryCall, !tiles.guests.isDefault { out[primaryCall] = tiles.guests }
        return out
    }

    // MARK: Layer order — "the host can change it"

    public enum LayerMove: Sendable { case forward, backward, front, back }

    /// `shown` with `id` moved one step or all the way. Front is the END of
    /// the array (drawn last).
    public static func moving(_ id: String, _ move: LayerMove, in shown: [String]) -> [String] {
        guard let i = shown.firstIndex(of: id) else { return shown }
        var s = shown
        s.remove(at: i)
        let to: Int
        switch move {
        case .forward: to = min(i + 1, s.count)
        case .backward: to = max(i - 1, 0)
        case .front: to = s.count
        case .back: to = 0
        }
        s.insert(id, at: to)
        return s
    }

    /// Turn a source on or off in a scene. Turned on, it comes in FRONT —
    /// what the host just asked to see is never hidden behind what was there.
    public static func setting(_ id: String, shown on: Bool, in shown: [String]) -> [String] {
        var s = shown.filter { $0 != id }
        if on { s.append(id) }
        return s
    }
}
