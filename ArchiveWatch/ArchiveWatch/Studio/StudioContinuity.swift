// The Apple TV as the Studio — Continuity Camera (docs/WATCH-TOGETHER.md §3.5).
//
// This is the configuration the owner actually watches in: the film on the
// television, an iPhone propped on the coffee table as the camera, and the box
// that plays the film also encoding the show. tvOS 17+ on an Apple TV 4K
// (2nd generation or later).
//
// WHAT THE SDK ACTUALLY SAYS, read from the tvOS 27 headers rather than
// remembered — and it corrects the research note this file replaces:
//
//   · `AVContinuityDevicePickerViewController` (tvOS 17+) pairs a phone.
//     `isSupported` is a CLASS property, the delegate hands back an
//     `AVContinuityDevice`, and Apple's own guidance is "always display the
//     device picker as a full-screen, modal view".
//   · An `AVContinuityDevice` exposes `videoDevices: [AVCaptureDevice]` AND
//     `audioSessionInputs: [AVAudioSessionPortDescription]`.
//   · THE MICROPHONE IS AN AUDIO-SESSION PORT, NOT A CAPTURE DEVICE. The
//     research doc said "the audio port `.continuityMicrophone`"; there is no
//     such device type. You select the port with
//     `AVAudioSession.setPreferredInput(_:)`, and then a capture device of
//     type `.microphone` records from whatever the routing subsystem chose —
//     the header is explicit that tvOS exposes exactly one microphone device
//     and "the audio routing subsystem decides which physical microphone to
//     use".
//   · `AVCaptureDeviceTypeContinuityCamera` IS available on tvOS 17, so the
//     camera can also be found by a discovery session without the picker once
//     a phone has been paired.
//
// AND THIS IS WHAT UNLOCKS `.playAndRecord` ON tvOS. §9 records that the
// category fails there outright and that a failed activation stops AVPlayer
// dead. It fails because there is nothing to record FROM. Once a continuity
// microphone port exists, the category is legitimate — so the session is
// raised only then, and lowered again when the phone walks away.

import AVFoundation
import Foundation

#if os(tvOS)
import AVKit
import UIKit

// @Observable, not ObservableObject — the project's model layer is Swift
// Observation throughout (CLAUDE.md), and Combine is not imported anywhere.
@MainActor
@Observable
public final class StudioContinuity: NSObject {

    public enum State: Equatable {
        case unsupported                 // not an Apple TV 4K 2nd gen+, or below tvOS 17
        case none                        // supported, nothing paired
        case connected(name: String, hasMicrophone: Bool)

        public var isConnected: Bool { if case .connected = self { return true }; return false }
    }

    public private(set) var state: State = .none
    /// Said out loud rather than inferred from an empty camera tile.
    public private(set) var note: String = ""

    private var discovery: AVCaptureDevice.DiscoverySession?
    private var observation: NSKeyValueObservation?
    private var device: AVContinuityDevice?

    /// The device the PICKER handed back, kept across instances.
    ///
    /// The microphone is reachable only through `AVContinuityDevice`
    /// (`audioSessionInputs`) — there is no `.continuityMicrophone` device to
    /// discover, as this file's header says. A show builds a fresh
    /// `StudioContinuity`, so a device picked on the go-live sheet would be
    /// thrown away before the engine ever asked: paired camera, no microphone,
    /// which is exactly what the owner measured twice.
    @MainActor public static var lastPicked: AVContinuityDevice?
    private var previousCategory: AVAudioSession.Category?

    public override init() {
        super.init()
        guard AVContinuityDevicePickerViewController.isSupported else {
            state = .unsupported
            note = "This Apple TV cannot use an iPhone as a camera. Continuity Camera needs an Apple TV 4K (2nd generation or later) on tvOS 17 or newer."
            return
        }
        beginDiscovery()
    }

    /// A phone paired in a previous session is still discoverable, so the
    /// picker is a ONE-TIME human step rather than a per-show one. The session
    /// watches for it instead of demanding it.
    private func beginDiscovery() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.continuityCamera, .external],
            mediaType: .video, position: .unspecified)
        discovery = session
        observation = session.observe(\.devices, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        guard let cam = camera() else {
            if case .unsupported = state { return }
            state = .none
            note = "No iPhone is paired as a camera yet."
            lowerAudioSession()
            return
        }
        // THE DEVICE DECIDES, NOT THE PORT.
        //
        // This asked `microphonePort()`, and on tvOS that is empty even when
        // the microphone is right there. Measured on Ben Bedroom 2026-09-19
        // with a paired iPhone and microphone permission granted:
        //
        //   AWMIC default audio device: Continuity Microphone
        //   AWMIC audio discovery: 1 [Continuity Microphone]
        //   AWMIC after-raise category=PlayAndRecord inputs=0 []
        //   AWMIC continuity microphone port: STILL NONE
        //
        // `AVAudioSession.availableInputs` is empty in `.playback` AND after
        // raising `.playAndRecord`, while `AVCaptureDevice.default(for:
        // .audio)` is the Continuity Microphone itself. So the port was never
        // going to arrive, and gating on it made `hasMicrophone` false, which
        // made `makeSession` skip the input and `attachMicrophone` never run.
        // That is why every broadcast has gone out with no host audio.
        //
        // The header's reasoning was sound and its premise was not: the port
        // exists to CHOOSE among microphones with `setPreferredInput`, and
        // tvOS vends exactly one audio device — this one. With nothing to
        // choose between, the device alone is the answer. A port, when one
        // does appear, is still preferred for routing.
        // RAISE FIRST, THEN LOOK. Both the port AND the capture device are
        // invisible while the session is `.playback`, so asking before raising
        // answers "no microphone" every time and then declines to raise
        // because there is no microphone. Moving the gate from the port to the
        // device (2026-09-19) did not break that loop — it moved it one level
        // up, and the only runs where the microphone appeared were the ones
        // where `AW_STUDIO_MIC_PROBE=1` happened to raise the category first.
        // Measured without the probe: `sessionMade inputs=1`, `micFrames=0`,
        // `micPadded` climbing into the millions.
        //
        // Raising here is safe BECAUSE a camera is connected — that is the
        // guard, and the probe measured `.playAndRecord ACTIVATED` in exactly
        // this state. §6.2's documented failure is the case with NOTHING
        // attached, which is why this sits after the `camera()` guard and
        // nowhere else.
        raiseAudioSession(preferring: nil)
        let port = microphonePort()
        let micDevice = AVCaptureDevice.default(for: .audio)
        state = .connected(name: cam.localizedName, hasMicrophone: micDevice != nil)
        note = micDevice == nil
            ? "\(cam.localizedName) is the camera. Its microphone is not available, so your voice will not be in the stream."
            : "\(cam.localizedName) is the camera and the microphone."
        // Re-apply with the port now that one may exist; the category is
        // already up from the call above.
        // DO NOT LOWER IT AGAIN WHILE A CAMERA IS CONNECTED.
        //
        // The Continuity microphone does NOT appear synchronously when the
        // category goes up: measured 2026-09-19, `refresh` raised
        // `.playAndRecord`, queried immediately, got `micDevice=nil port=nil`,
        // lowered straight back to `.playback` — and half a second later
        // `makeSession` found "Continuity Microphone" and added it as an input
        // to a session whose category had just been taken away. `inputs=2`,
        // and `micFrames=0` for three solid minutes.
        //
        // A camera is attached, so `.playAndRecord` is legitimate (the probe
        // measured ACTIVATED in exactly this state). Leaving it up costs
        // nothing and lets the device arrive in its own time; `makeSession`
        // re-queries and `lowerAudioSession` still runs when the phone leaves.
        if port != nil { raiseAudioSession(preferring: port) }
        awdiag("AWCONT refresh: camera=%@ micDevice=%@ port=%@",
               cam.localizedName, micDevice?.localizedName ?? "nil", port?.portName ?? "nil")
    }

    // MARK: What the engine needs

    /// Is a phone ALREADY paired? Asked before offering to pair one.
    ///
    /// Owner: "it should detect if a continuity camera is already connected
    /// before asking to do it again." A phone paired in an earlier session
    /// stays discoverable, so the picker is a one-time step and the sheet
    /// should say so rather than invite the same work twice.
    @MainActor public static func pairedCameraName() -> String? {
        guard AVContinuityDevicePickerViewController.isSupported else { return nil }
        let s = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.continuityCamera, .external],
            mediaType: .video, position: .unspecified)
        return (s.devices.first(where: { $0.isContinuityCamera }) ?? s.devices.first)?
            .localizedName
    }

    /// The continuity camera, if one is available.
    public func camera() -> AVCaptureDevice? {
        let devices = discovery?.devices ?? []
        // `isContinuityCamera` is the authority: a device may be discovered as
        // `.external` and still be a phone.
        return devices.first(where: { $0.isContinuityCamera }) ?? devices.first
    }

    /// The continuity microphone as an AUDIO SESSION PORT — the only shape
    /// tvOS offers it in.
    public func microphonePort() -> AVAudioSessionPortDescription? {
        if let d = device ?? Self.lastPicked, d.isConnected,
           let p = d.audioSessionInputs.first { return p }
        // Without a picker hand-off, ask the session what inputs exist.
        return AVAudioSession.sharedInstance().availableInputs?
            .first { $0.portType == .continuityMicrophone }
    }

    /// DIAGNOSTIC ONLY — `AW_STUDIO_MIC_PROBE=1`. Answers the one question
    /// blocking the Continuity microphone, and changes nothing.
    ///
    /// The camera is found by DISCOVERY, so it works after any app launch.
    /// The microphone is an `AVAudioSession` input PORT, and the only object
    /// that exposes it is an `AVContinuityDevice`, which the SDK hands over
    /// ONLY through the picker delegate — `AVContinuityDevice.h` on tvOS 27
    /// declares just `connectionID`, `connected`, `videoDevices` and
    /// `audioSessionInputs`, with no way to enumerate a paired device. So
    /// after a relaunch `device`/`lastPicked` are nil and `microphonePort()`
    /// falls through to asking the SESSION, which in `.playback` lists no
    /// inputs at all. Every run on 2026-09-19 read `micPort=none`.
    ///
    /// The untested half: §6.2 says `.playAndRecord` fails on tvOS when there
    /// is nothing to record from, and a failed activation stops AVPlayer dead
    /// (an earlier pre-raise crashed the app and was reverted). But that was
    /// measured with NOTHING connected. With a Continuity camera actually
    /// attached the phone may well offer its microphone, and the category may
    /// be legitimate — in which case the ordering problem dissolves.
    ///
    /// This asks, restores whatever it found, and says what happened. It is
    /// deliberately not a fix: the answer decides the design.
    public func probeMicrophone() {
        let s = AVAudioSession.sharedInstance()
        func inputs(_ when: String) {
            let list = s.availableInputs ?? []
            awdiag("AWMIC %@ category=%@ inputs=%d [%@]", when, s.category.rawValue,
                   list.count, list.map { $0.portType.rawValue }.joined(separator: ","))
        }
        // THE PERMISSION, which nothing on the tvOS product path has ever
        // asked for. `requestAccess(for: .audio)` exists only in StudioLab
        // (the debug harness) and the macOS editor — the same shape as §6.2a,
        // where the audio session was configured in the harness alone. Without
        // audio authorisation a Continuity device offers no microphone at all,
        // which is exactly `audioSessionInputs=0` / `hasMicrophone: false`.
        func name(_ st: AVAuthorizationStatus) -> String {
            switch st {
            case .authorized: "authorized"
            case .denied: "denied"
            case .restricted: "restricted"
            case .notDetermined: "NOT-DETERMINED (never asked)"
            @unknown default: "unknown"
            }
        }
        awdiag("AWMIC permissions camera=%@ microphone=%@",
               name(AVCaptureDevice.authorizationStatus(for: .video)),
               name(AVCaptureDevice.authorizationStatus(for: .audio)))
        awdiag("AWMIC probe: device=%@ lastPicked=%@ state=%@",
               device == nil ? "nil" : "yes", Self.lastPicked == nil ? "nil" : "yes",
               String(describing: state))
        if let d = device ?? Self.lastPicked {
            awdiag("AWMIC continuity device audioSessionInputs=%d", d.audioSessionInputs.count)
        }
        inputs("before")
        // ASK, ONCE, IF IT HAS NEVER BEEN ASKED. Diagnostic still: this only
        // raises the system prompt the product would have to raise anyway, and
        // the answer decides whether the microphone is reachable at all.
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            awdiag("AWMIC requesting microphone access (never asked before)")
            let sema = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                awdiag("AWMIC microphone access granted=%@", granted ? "yes" : "NO")
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 30)
            awdiag("AWMIC permissions now microphone=%@",
                   name(AVCaptureDevice.authorizationStatus(for: .audio)))
            inputs("after-permission")
        }
        // WHAT AUDIO CAPTURE DEVICES EXIST AT ALL. `makeSession` adds the mic
        // input via `AVCaptureDevice.default(for: .audio)`, so if that is nil
        // there is nothing to add regardless of ports or permission. This
        // separates "tvOS vends no audio capture device" from "a device exists
        // but the Continuity link offers no session port".
        let defaultAudio = AVCaptureDevice.default(for: .audio)
        awdiag("AWMIC default audio device: %@", defaultAudio?.localizedName ?? "NIL")
        let found = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone], mediaType: .audio, position: .unspecified).devices
        awdiag("AWMIC audio discovery: %d [%@]", found.count,
               found.map { $0.localizedName }.joined(separator: ", "))
        let previous = s.category
        do {
            try s.setCategory(.playAndRecord, mode: .default,
                              options: [.mixWithOthers, .allowBluetooth])
            try s.setActive(true)
            awdiag("AWMIC .playAndRecord ACTIVATED")
            inputs("after-raise")
            let cm = (s.availableInputs ?? []).first { $0.portType == .continuityMicrophone }
            awdiag("AWMIC continuity microphone port: %@", cm?.portName ?? "STILL NONE")
        } catch {
            awdiag("AWMIC .playAndRecord REFUSED: %@", "\(error)")
        }
        // ALWAYS restore, including after success — this probe must not leave
        // the session in a category the show did not ask for.
        try? s.setCategory(previous, mode: .moviePlayback, options: [.mixWithOthers])
        try? s.setActive(true)
        awdiag("AWMIC restored category=%@", s.category.rawValue)
    }

    /// A capture session carrying the continuity camera, and the microphone
    /// when there is one. The caller builds the taps against it (they cannot
    /// cross into the engine actor — an `AVCaptureSession` is not `Sendable`).
    /// Whether the last `makeSession()` actually put a microphone INPUT in the
    /// session. The caller gates its `MicAudioTap` on this rather than on
    /// `state.hasMicrophone`, which is computed earlier from a query that can
    /// still be `nil` while the device is on its way (see `refresh`). That
    /// mismatch is what produced `inputs=2` with `micFrames=0`: the input was
    /// there and nothing was ever tapped off it.
    public private(set) var sessionHasMicrophone = false

    public func makeSession() -> AVCaptureSession? {
        sessionHasMicrophone = false
        guard let cam = camera(), let input = try? AVCaptureDeviceInput(device: cam) else { return nil }
        let session = AVCaptureSession()
        session.beginConfiguration()
        // THE INPUT FIRST, THEN THE PRESET — and only a preset this session
        // says it can actually set.
        //
        // This crashed every Continuity broadcast (2026-09-19, Ben Bedroom,
        // reproduced twice): the preset was assigned here, before any input
        // existed, so `canSetSessionPreset` was never asked at a moment when
        // it means anything. `.hd1280x720` is not a format an iPhone offers
        // as a Continuity Camera on tvOS, and the failure does not surface
        // until something forces the device to renegotiate — which is the
        // `addOutput` in `CameraFrameTap.attach`, a call away and in another
        // file:
        //
        //   -[AVCaptureDevice _setActiveFormat:…sessionPreset:]
        //   Unsupported format ((null)) - use -formats to discover valid formats
        //
        // An ObjC exception, so no Swift `try` catches it and the app is gone
        // with signal 6. `canAddInput`/`canAddOutput` both answer true: they
        // check whether the port is compatible, never whether the PRESET is
        // reachable for the device behind it.
        if session.canAddInput(input) { session.addInput(input) }
        // WHAT THE DEVICE ACTUALLY OFFERS. Measured, not assumed: the first
        // attempt at this fix chose the preset with `canSetSessionPreset`,
        // which answered TRUE for `.hd1280x720` on a Continuity Camera and
        // then threw `Unsupported format ((null))` anyway when the output was
        // added. So that predicate is optimistic here and cannot be the gate.
        let dims = cam.formats.map {
            let d = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            return "\(d.width)x\(d.height)"
        }
        awdiag("AWCONT camera formats=%d [%@] active=%@", cam.formats.count,
               dims.prefix(8).joined(separator: " "),
               CMVideoFormatDescriptionGetDimensions(cam.activeFormat.formatDescription)
                   .width.description + "x"
               + CMVideoFormatDescriptionGetDimensions(cam.activeFormat.formatDescription)
                   .height.description)
        // `.inputPriority` means the SESSION NEVER SETS THE DEVICE'S FORMAT —
        // it takes whatever the device is already in. For a Continuity Camera
        // that is the only safe choice: the phone decides its own format, the
        // session cannot negotiate one it does not have, and the exception
        // that killed the app three times has nothing left to throw. The tile
        // is scaled to its layout slot downstream anyway, so nothing here
        // needed a specific capture size in the first place.
        session.sessionPreset = .inputPriority
        awdiag("AWCONT preset=inputPriority (device keeps its own format)")
        // The microphone device is generic on tvOS; the ROUTE decides which
        // physical mic it is, and `raiseAudioSession` set that route.
        // LET THE CAPTURE SESSION OWN THE AUDIO SESSION.
        //
        // `AVCaptureSession.h` on tvOS 27: `automaticallyConfiguresApplication
        // AudioSession` defaults to YES and "ensures the application's audio
        // session is set to the PlayAndRecord category, and picks an
        // appropriate microphone and polar pattern TO MATCH THE VIDEO CAMERA
        // BEING USED". With a Continuity camera as the video device, that is
        // exactly the pairing we want, and it is AVFoundation's job — not
        // ours. Configuring the category by hand alongside it is two owners
        // for one session, which is how a microphone that attaches and
        // delivers real-time buffers can still deliver pure silence.
        //
        // Stated explicitly rather than relied on as a default, because the
        // whole point is that this object, and not `StudioContinuity` or
        // `StudioEngine`, decides the routing.
        session.usesApplicationAudioSession = true
        session.automaticallyConfiguresApplicationAudioSession = true

        // AND SAY WHICH STEP FAILED. `inputs=1` could mean no device, a device
        // that would not open, or a session that refused the input — three
        // different faults that logged identically.
        let micDevice = AVCaptureDevice.default(for: .audio)
        if let micDevice {
            do {
                let micInput = try AVCaptureDeviceInput(device: micDevice)
                if session.canAddInput(micInput) {
                    session.addInput(micInput)
                    sessionHasMicrophone = true
                    awdiag("AWCONT mic input added (%@)", micDevice.localizedName)
                } else {
                    awdiag("AWCONT mic input REFUSED by the session (%@)", micDevice.localizedName)
                }
            } catch {
                awdiag("AWCONT mic input could not be opened: %@", "\(error)")
            }
        } else {
            awdiag("AWCONT no audio capture device — category is %@",
                   AVAudioSession.sharedInstance().category.rawValue)
        }
        session.commitConfiguration()
        return session
    }

    // MARK: The audio session

    /// `.playAndRecord` is legitimate on tvOS ONLY once there is something to
    /// record from. Raising it before that fails ("Session activation failed")
    /// and a failed activation stops AVPlayer dead (§9).
    /// `port` is OPTIONAL now: on tvOS the microphone arrives as a capture
    /// DEVICE with no session port at all (measured — see `refresh`), and
    /// there is only ever one, so there is nothing to prefer. When a port does
    /// exist it is still selected, because that is what routing expects.
    ///
    /// Raising the category here is safe in exactly this situation and the
    /// probe proved it: `.playAndRecord ACTIVATED` with a Continuity camera
    /// attached. §6.2's "it fails on tvOS" holds only when nothing is
    /// connected, which is why this is reached solely from the branch that
    /// has a microphone device in hand.
    private func raiseAudioSession(preferring port: AVAudioSessionPortDescription?) {
        let s = AVAudioSession.sharedInstance()
        if previousCategory == nil { previousCategory = s.category }
        do {
            try s.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetooth])
            try s.setActive(true)
            if let port { try s.setPreferredInput(port) }
        } catch {
            // Report and fall back to playback, rather than leaving the
            // session in a state that silently prevents the film playing.
            note = "Could not use \(port?.portName ?? "the phone's microphone") as the microphone (\(error.localizedDescription)). The film will play; your voice will not be in the stream."
            lowerAudioSession()
        }
    }

    /// Back to playback. Called when the phone leaves, and on teardown.
    public func lowerAudioSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(previousCategory ?? .playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? s.setActive(true)
    }

    // MARK: The picker

    /// Presents the system picker full-screen, as Apple's guidance requires.
    /// A one-time step: a paired phone is discoverable in later sessions.
    public func presentPicker(from presenter: UIViewController) {
        guard AVContinuityDevicePickerViewController.isSupported else { return }
        let picker = AVContinuityDevicePickerViewController()
        picker.delegate = self
        picker.modalPresentationStyle = .fullScreen
        presenter.present(picker, animated: true)
    }
}

extension StudioContinuity: AVContinuityDevicePickerViewControllerDelegate {
    public func continuityDevicePicker(_ picker: AVContinuityDevicePickerViewController,
                                       didConnect device: AVContinuityDevice) {
        self.device = device
        refresh()
    }

    public func continuityDevicePickerDidCancel(_ picker: AVContinuityDevicePickerViewController) {
        note = "No phone was paired. The film can still stream without a camera."
    }
}
#endif
