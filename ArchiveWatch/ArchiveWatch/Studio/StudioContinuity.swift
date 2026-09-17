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
        let port = microphonePort()
        state = .connected(name: cam.localizedName, hasMicrophone: port != nil)
        note = port == nil
            ? "\(cam.localizedName) is the camera. Its microphone is not available, so your voice will not be in the stream."
            : "\(cam.localizedName) is the camera and the microphone."
        if let port { raiseAudioSession(preferring: port) }
    }

    // MARK: What the engine needs

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
        if let d = device, d.isConnected, let p = d.audioSessionInputs.first { return p }
        // Without a picker hand-off, ask the session what inputs exist.
        return AVAudioSession.sharedInstance().availableInputs?
            .first { $0.portType == .continuityMicrophone }
    }

    /// A capture session carrying the continuity camera, and the microphone
    /// when there is one. The caller builds the taps against it (they cannot
    /// cross into the engine actor — an `AVCaptureSession` is not `Sendable`).
    public func makeSession() -> AVCaptureSession? {
        guard let cam = camera(), let input = try? AVCaptureDeviceInput(device: cam) else { return nil }
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720      // the camera tile is never full-frame
        if session.canAddInput(input) { session.addInput(input) }
        // The microphone device is generic on tvOS; the ROUTE decides which
        // physical mic it is, and `raiseAudioSession` set that route.
        if microphonePort() != nil,
           let micDevice = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: micDevice),
           session.canAddInput(micInput) {
            session.addInput(micInput)
        }
        session.commitConfiguration()
        return session
    }

    // MARK: The audio session

    /// `.playAndRecord` is legitimate on tvOS ONLY once there is something to
    /// record from. Raising it before that fails ("Session activation failed")
    /// and a failed activation stops AVPlayer dead (§9).
    private func raiseAudioSession(preferring port: AVAudioSessionPortDescription) {
        let s = AVAudioSession.sharedInstance()
        if previousCategory == nil { previousCategory = s.category }
        do {
            try s.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetooth])
            try s.setActive(true)
            try s.setPreferredInput(port)
        } catch {
            // Report and fall back to playback, rather than leaving the
            // session in a state that silently prevents the film playing.
            note = "Could not use \(port.portName) as the microphone (\(error.localizedDescription)). The film will play; your voice will not be in the stream."
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
