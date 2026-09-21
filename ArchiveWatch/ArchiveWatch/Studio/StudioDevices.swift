import Foundation
import AVFoundation

/// WHICH camera and WHICH microphone — macOS-DESIGN §D2.
///
/// Owner: "You should have a lot of controls on MacOS to determine exactly how
/// the stream looks and which inputs/outputs are being managed."
///
/// Until now every platform took `AVCaptureDevice.default` and never said
/// which device that was. On a Mac that is routinely wrong: a host with a
/// Continuity camera, an external webcam and the built-in FaceTime camera has
/// three, and `default` picks one of them without asking.
///
/// The choice is stored as the device's `uniqueID`, not its index and not its
/// name. An index reorders when a device is unplugged and a name is not
/// unique — two identical webcams share one.
public enum StudioDevices {

    public struct Device: Identifiable, Hashable, Sendable {
        public let id: String          // AVCaptureDevice.uniqueID
        public let name: String        // the device's OWN localised name
        public let isDefault: Bool
    }

    // MARK: Enumeration

    /// Every camera this machine can offer, in the system's own order.
    ///
    /// The type list is explicit rather than `.builtInWideAngleCamera` alone,
    /// because the two that matter most on a Mac are the ones a narrow list
    /// drops: `.external` (a USB webcam) and `.continuityCamera` (the host's
    /// iPhone), which is the whole reason the television feature works.
    public static func cameras() -> [Device] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        #if os(macOS)
        types.append(.external)
        if #available(macOS 14.0, *) { types.append(.continuityCamera) }
        #elseif os(iOS)
        types.append(contentsOf: [.builtInTelephotoCamera, .builtInUltraWideCamera])
        if #available(iOS 17.0, *) { types.append(.continuityCamera) }
        #endif
        let found = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified).devices
        let def = AVCaptureDevice.default(for: .video)?.uniqueID
        return found.map { Device(id: $0.uniqueID, name: $0.localizedName,
                                  isDefault: $0.uniqueID == def) }
    }

    public static func microphones() -> [Device] {
        var types: [AVCaptureDevice.DeviceType] = [.microphone]
        #if os(macOS)
        if #available(macOS 14.0, *) { types.append(.external) }
        #endif
        let found = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .audio, position: .unspecified).devices
        let def = AVCaptureDevice.default(for: .audio)?.uniqueID
        return found.map { Device(id: $0.uniqueID, name: $0.localizedName,
                                  isDefault: $0.uniqueID == def) }
    }

    // MARK: The host's choice

    /// `nil` means "whatever the system calls default"; `noneID` means the
    /// host deliberately wants no camera at all, which is a real choice and
    /// not the same as having none (Rule 8.8: an absent camera is normal).
    public static let noneID = "aw.none"

    private static let cameraKey = "AWStudioCameraID"
    private static let micKey = "AWStudioMicrophoneID"

    public static var chosenCameraID: String? {
        get { UserDefaults.standard.string(forKey: cameraKey) }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: cameraKey) }
            else { UserDefaults.standard.removeObject(forKey: cameraKey) }
        }
    }
    public static var chosenMicrophoneID: String? {
        get { UserDefaults.standard.string(forKey: micKey) }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: micKey) }
            else { UserDefaults.standard.removeObject(forKey: micKey) }
        }
    }

    // MARK: Resolution — the only place a choice becomes a device

    /// What the CAPTURE SESSION should actually open, and why.
    ///
    /// Returns nil when the host chose "None", or when nothing is available.
    /// `fellBack` is true when a chosen device could not be found — §D2's
    /// "a device that vanishes says so in its row": unplugging a webcam
    /// mid-show must not end the broadcast, and must not silently pretend the
    /// host chose the built-in camera.
    public static func resolveCamera() -> (device: AVCaptureDevice?, fellBack: Bool) {
        let chosen = chosenCameraID
        if chosen == noneID { return (nil, false) }
        if let chosen, let found = AVCaptureDevice(uniqueID: chosen) {
            return (found, false)
        }
        let fellBack = chosen != nil
        // THE FRONT CAMERA ON A PHONE. `AVCaptureDevice.default(for: .video)`
        // is the BACK camera on iOS, which points at the wall behind the host
        // — the one thing a watch-along tile must not show.
        #if os(iOS)
        let fallback = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .front)
            .devices.first ?? AVCaptureDevice.default(for: .video)
        #else
        let fallback = AVCaptureDevice.default(for: .video)
        #endif
        return (fallback, fellBack)
    }

    public static func resolveMicrophone() -> (device: AVCaptureDevice?, fellBack: Bool) {
        let chosen = chosenMicrophoneID
        if chosen == noneID { return (nil, false) }
        if let chosen, let found = AVCaptureDevice(uniqueID: chosen) {
            return (found, false)
        }
        return (AVCaptureDevice.default(for: .audio), chosen != nil)
    }

    /// The name to draw in the input row, for a choice that may not be live
    /// yet — so the row can say "MacBook Pro Camera" before anything opens.
    public static func nameForChosenCamera() -> String {
        let chosen = chosenCameraID
        if chosen == noneID { return "None" }
        if let chosen, let d = AVCaptureDevice(uniqueID: chosen) { return d.localizedName }
        if chosen != nil { return "Chosen camera not found" }
        return AVCaptureDevice.default(for: .video)?.localizedName ?? "None"
    }

    public static func nameForChosenMicrophone() -> String {
        let chosen = chosenMicrophoneID
        if chosen == noneID { return "None" }
        if let chosen, let d = AVCaptureDevice(uniqueID: chosen) { return d.localizedName }
        if chosen != nil { return "Chosen microphone not found" }
        return AVCaptureDevice.default(for: .audio)?.localizedName ?? "None"
    }
}
