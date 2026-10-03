#if os(macOS)
import AVFoundation
import Foundation

// THE SHOW'S SOURCES on the Mac — macOS-DESIGN §D40.
//
// Owner, 2026-09-30: "You should be able to have full control over which
// camera and call are on each scene, just as you can do in OBS." The list the
// host builds here is what every scene chooses from; the rules for how a
// scene composes it are in `StudioComposition` (shared, tested by §8.74).

/// The Sources list: every camera and every call the host added, in the order
/// they added them. That order decides which camera takes a placement's host
/// seat and which call takes its call seat (`StudioComposition.tiles`).
@MainActor
@Observable
final class StudioSources {
    static let shared = StudioSources()

    private(set) var list: [StudioSourceRef]
    private static let key = "StudioSources.v1"

    /// NOTHING HERE MAY TOUCH `StudioControls` OR `StudioScenes`: both read
    /// this list while they are being built, and a `static let` that re-enters
    /// its own initializer traps.
    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([StudioSourceRef].self, from: data) {
            list = saved
        } else {
            // A STUDIO FROM BEFORE §D40 becomes one camera — the one its
            // Camera row had chosen, unless that was None — and one call
            // with no window yet, which is what its "Your call" row was. The
            // scenes it saved migrate onto exactly these two (StudioScenes).
            var seed: [StudioSourceRef] = []
            let chosen = StudioDevices.chosenCameraID
            if chosen != StudioDevices.noneID { seed.append(.newCamera(deviceID: chosen)) }
            seed.append(.newCall())
            list = seed
            save()
        }
    }

    var cameras: [StudioSourceRef] { list.filter { $0.kind == .camera } }
    var calls: [StudioSourceRef] { list.filter { $0.kind == .call } }
    var windows: [StudioSourceRef] { list.filter { $0.kind == .window } }
    var primaryCameraID: String? { cameras.first?.id }
    var primaryCallID: String? { calls.first?.id }
    func source(_ id: String) -> StudioSourceRef? { list.first { $0.id == id } }

    // MARK: Editing the list

    @discardableResult
    func addCamera(deviceID: String?) -> String {
        let ref = StudioSourceRef.newCamera(deviceID: deviceID)
        list.append(ref)
        changed()
        return ref.id
    }

    @discardableResult
    func addWindow() -> String {
        let ref = StudioSourceRef.newWindow()
        list.append(ref)
        changed()
        return ref.id
    }

    @discardableResult
    func addCall() -> String {
        let ref = StudioSourceRef.newCall()
        list.append(ref)
        changed()
        return ref.id
    }

    /// Removing a source stops it, drops it from every scene that showed it,
    /// and forgets its framing. A scene that showed nothing else simply shows
    /// the film.
    func remove(_ id: String) {
        guard let ref = source(id) else { return }
        list.removeAll { $0.id == id }
        let session = StudioSession.shared
        switch ref.kind {
        case .call, .window: session.stopCall(id)
        case .camera: Task { await session.rebuildCamera(id) }   // gone from the list: stops it
        }
        StudioScenes.shared.forget(id)
        StudioControls.shared.forget(id)
        changed()
    }

    /// §D11 — which device a camera source is. Takes effect NOW.
    func setDevice(_ id: String, _ deviceID: String?) {
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].deviceID = deviceID
        changed()
        Task { await StudioSession.shared.rebuildCamera(id) }
    }

    /// §D41 — a call's app, remembered from the window chosen for it.
    func setAppName(_ id: String, _ name: String?) {
        guard let name, !name.isEmpty, let i = list.firstIndex(where: { $0.id == id }),
              list[i].appName != name else { return }
        list[i].appName = name
        save()
    }

    /// §D41 — A LOADED SETUP'S SOURCES REPLACE THE LIST. A source the setup
    /// does not hold is removed exactly as Remove does (it stops, and leaves
    /// every scene); one it keeps by id keeps running — a call keeps the
    /// window already chosen for it this session; a camera whose device
    /// changed, or that is new, restarts if a show is running.
    func replace(with refs: [StudioSourceRef]) {
        var seen = Set<String>()
        let incoming = refs.filter { seen.insert($0.id).inserted }
        let keep = Set(incoming.map(\.id))
        for old in list where !keep.contains(old.id) { remove(old.id) }
        let before = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        list = incoming
        changed()
        for ref in incoming where ref.kind == .camera {
            if before[ref.id]?.deviceID != ref.deviceID || before[ref.id] == nil {
                let id = ref.id
                Task { await StudioSession.shared.rebuildCamera(id) }
            }
        }
    }

    private func changed() {
        save()
        // THE FIRST CAMERA IS "THE CAMERA" wherever the app still asks for
        // one: `hostAbsentReason` (Decision 138 — going live needs a camera)
        // and the rows written before §D40. No camera at all reads as None.
        StudioDevices.chosenCameraID = cameras.first.map { $0.deviceID } ?? StudioDevices.noneID
        StudioControls.shared.pushTiles()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    // MARK: Names — the device's or the app's own, never abbreviated

    /// A camera source's name: its device's, or the system default's.
    func cameraName(_ ref: StudioSourceRef) -> String {
        if let id = ref.deviceID {
            return AVCaptureDevice(uniqueID: id)?.localizedName ?? "Camera not connected"
        }
        return AVCaptureDevice.default(for: .video)?.localizedName ?? "System default camera"
    }

    /// What a source is called in a scene's list and on the preview.
    func name(_ id: String) -> String {
        guard let ref = source(id) else { return "Removed source" }
        switch ref.kind {
        case .camera: return cameraName(ref)
        case .call:
            if let label = StudioSession.shared.callLabel(id) { return label }
            if let app = ref.appName { return "\(app) — choose its window" }
            let n = (calls.firstIndex { $0.id == id } ?? 0) + 1
            return calls.count > 1 ? "Call \(n) — no window chosen" : "Call — no window chosen"
        case .window:
            if let label = StudioSession.shared.callLabel(id) { return label }
            if let app = ref.appName { return "\(app) — choose its window" }
            return "Window — not chosen"
        }
    }

    /// WHY A SOURCE THE SCENE SHOWS HAS NO PICTURE, in one line — or nil when
    /// it has one (or no show is running, when nothing has a picture yet).
    func missingPicture(_ id: String) -> String? {
        let session = StudioSession.shared
        guard session.isLive, let ref = source(id) else { return nil }
        switch ref.kind {
        case .camera:
            if session.cameraIsRunning(id) { return session.cameraStalls[id] }
            return session.cameraProblem(id)
        case .call, .window:
            // A call with no window says so in its NAME; only a fault needs
            // a line of its own.
            if session.callIsRunning(id) { return session.callStalls[id] }
            return session.callProblem(id)
        }
    }
}

/// Every camera source's capture session. One session per camera — see
/// `StudioSession.cameraRig` for the AVCaptureSession.h reason.
@MainActor
final class StudioCameraRig {
    struct Running {
        let session: AVCaptureSession
        let tap: CameraFrameTap
        let deviceName: String
    }
    private(set) var running: [String: Running] = [:]
    /// Why a source has no session, in the host's words.
    private(set) var problems: [String: String] = [:]

    func start(_ ref: StudioSourceRef, engine: StudioEngine) async {
        stop(ref.id)
        // A CHOSEN DEVICE THAT IS GONE IS SAID, NOT REPLACED. With one camera
        // the old path fell back to the system default; with several, that
        // would quietly open a camera some other source already shows.
        let device: AVCaptureDevice?
        if let id = ref.deviceID {
            device = AVCaptureDevice(uniqueID: id)
            if device == nil {
                problems[ref.id] = "That camera is not connected."
                awdiag("AWCAM source %@ — its device is not connected", String(ref.id.prefix(15)))
                return
            }
        } else {
            device = AVCaptureDevice.default(for: .video)
        }
        guard let cam = device, let input = try? AVCaptureDeviceInput(device: cam) else {
            problems[ref.id] = "macOS would not open that camera."
            return
        }
        let session = AVCaptureSession()
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        // THE PRESET GOES AFTER THE INPUT, AND A BORROWED PHONE GETS NONE —
        // the rule `attachCameraIfAvailable` carries in full: forcing a preset
        // on a Continuity camera threw an ObjC exception no Swift `try` can
        // catch (2026-09-19). `.high`, the default, negotiates instead.
        let borrowedPhone = cam.deviceType == .continuityCamera || cam.deviceType == .external
        if !borrowedPhone, session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }
        session.commitConfiguration()
        let tap = CameraFrameTap()
        tap.attach(to: session)
        await engine.attachSource(ref.id, tap, call: false)
        session.startRunning()
        running[ref.id] = Running(session: session, tap: tap, deviceName: cam.localizedName)
        problems[ref.id] = nil
        awdiag("AWCAM source attached camera=%@ preset=%@ (%d running)", cam.localizedName,
               borrowedPhone ? "negotiated" : "hd1280x720", running.count)
    }

    func stop(_ id: String) {
        if let r = running.removeValue(forKey: id) { r.session.stopRunning() }
        problems[id] = nil
    }

    func stopAll() {
        for id in Array(running.keys) { stop(id) }
        problems = [:]
    }
}
#endif
