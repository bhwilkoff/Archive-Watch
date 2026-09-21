// §8.24 — WHICH camera and WHICH microphone (macOS-DESIGN §D2).
//
// The owner: "you should have a lot of controls on MacOS to determine exactly
// how the stream looks and which inputs/outputs are being managed." Until now
// every platform took `AVCaptureDevice.default` and never said which device
// that was.
//
// What this asserts is the RESOLUTION, not the list: a machine's device set is
// whatever is plugged in, so a count is not a test. What IS testable, and what
// actually breaks, is what a stored choice turns into —
//   • a choice of None must open NOTHING (not "fall back to the default",
//     which would put a camera in a show the host switched off);
//   • a choice that no longer exists must fall back AND SAY SO, because §D2
//     requires a vanished device to be visible in its row rather than
//     silently replaced;
//   • no choice at all must be the system default, which is the behaviour
//     every platform had before this existed.
//
// The control that gives the third one meaning: a bogus id must NOT resolve
// to a device and report `fellBack == false`, or "I chose this" and "I chose
// nothing" would be indistinguishable.
import Foundation
import AVFoundation

@main
struct StudioDevicesTest {
    static var failures = 0

    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "PASS" : "FAIL") \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures += 1 }
    }

    static func main() {
        print("=== §8.24 Studio device selection ===")

        let cams = StudioDevices.cameras()
        let mics = StudioDevices.microphones()
        print("  cameras:     \(cams.map { "\($0.name)\($0.isDefault ? " [default]" : "")" })")
        print("  microphones: \(mics.map { "\($0.name)\($0.isDefault ? " [default]" : "")" })")

        // Identity, not order: a name is not unique (two identical webcams) and
        // an index reorders when something is unplugged.
        check("camera ids are unique",
              Set(cams.map(\.id)).count == cams.count,
              "\(cams.count) devices, \(Set(cams.map(\.id)).count) ids")
        check("microphone ids are unique",
              Set(mics.map(\.id)).count == mics.count)
        check("at most one camera is the default",
              cams.filter(\.isDefault).count <= 1)

        let originalCam = StudioDevices.chosenCameraID
        let originalMic = StudioDevices.chosenMicrophoneID
        defer {
            StudioDevices.chosenCameraID = originalCam
            StudioDevices.chosenMicrophoneID = originalMic
        }

        // 1. No choice == the system default, i.e. the old behaviour.
        StudioDevices.chosenCameraID = nil
        let (d0, fell0) = StudioDevices.resolveCamera()
        check("no choice resolves to the system default",
              d0?.uniqueID == AVCaptureDevice.default(for: .video)?.uniqueID && !fell0,
              "got \(d0?.localizedName ?? "nil"), fellBack=\(fell0)")

        // 2. None means NONE. A fallback here would broadcast a camera the
        //    host switched off, which is worse than any missing feature.
        StudioDevices.chosenCameraID = StudioDevices.noneID
        let (d1, fell1) = StudioDevices.resolveCamera()
        check("None opens no camera at all", d1 == nil && !fell1,
              "got \(d1?.localizedName ?? "nil")")
        check("None reads as None in the row",
              StudioDevices.nameForChosenCamera() == "None")

        // 3. A vanished device falls back AND SAYS SO (§D2).
        StudioDevices.chosenCameraID = "aw.no.such.device.\(UUID().uuidString)"
        let (d2, fell2) = StudioDevices.resolveCamera()
        check("a vanished camera falls back", d2?.uniqueID == AVCaptureDevice.default(for: .video)?.uniqueID)
        check("a vanished camera REPORTS the fallback", fell2,
              "fellBack must be true or the row cannot say the device is gone")
        check("a vanished camera is named as missing",
              StudioDevices.nameForChosenCamera() == "Chosen camera not found",
              StudioDevices.nameForChosenCamera())

        // 4. THE CONTROL: a real choice must NOT report a fallback, or the
        //    flag means nothing.
        if let first = cams.first {
            StudioDevices.chosenCameraID = first.id
            let (d3, fell3) = StudioDevices.resolveCamera()
            check("a real choice resolves to THAT device and reports no fallback",
                  d3?.uniqueID == first.id && !fell3,
                  "got \(d3?.localizedName ?? "nil"), fellBack=\(fell3)")
            check("a real choice is named by the DEVICE's own name",
                  StudioDevices.nameForChosenCamera() == first.name,
                  StudioDevices.nameForChosenCamera())
        } else {
            print("SKIP a real choice — this machine reports no camera")
        }

        // 5. The microphone obeys the same three rules.
        StudioDevices.chosenMicrophoneID = StudioDevices.noneID
        let (m1, mf1) = StudioDevices.resolveMicrophone()
        check("microphone None opens nothing", m1 == nil && !mf1)
        StudioDevices.chosenMicrophoneID = "aw.no.such.mic"
        let (_, mf2) = StudioDevices.resolveMicrophone()
        check("a vanished microphone REPORTS the fallback", mf2)

        print(failures == 0 ? "=== §8.24 OK ===" : "=== §8.24 \(failures) FAILURES ===")
        exit(failures == 0 ? 0 : 1)
    }
}
