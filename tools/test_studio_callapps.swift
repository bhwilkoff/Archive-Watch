// §8.26 — WHICH app's audio (macOS-DESIGN §D2's fourth input, Decision 131).
//
// §8.21 already proved the MECHANISM: a tap on a named process captures that
// process and excludes every other at 82 dB. What this asserts is the LIST the
// host picks from, and the one rule on it that is not cosmetic:
//
//   ARCHIVE WATCH MUST NEVER APPEAR IN ITS OWN LIST.
//
// A host who tapped this app would capture the film a second time and mix it
// into the broadcast on top of itself — the exact feedback §8.21's isolation
// control exists to rule out, arrived at from the other direction. It is the
// kind of option that looks harmless in a picker and is unrecoverable on air.
import Foundation
import CoreAudio
import AudioToolbox
import AppKit

@main
struct StudioCallAppsTest {
    static var failures = 0
    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "PASS" : "FAIL") \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures += 1 }
    }

    static func main() {
        print("=== §8.26 call-audio app list ===")
        guard #available(macOS 14.2, *) else {
            print("SKIP — process taps need macOS 14.2")
            exit(2)
        }

        let apps = StudioAudioProcesses.all()
        print("  \(apps.count) tappable app(s): \(apps.prefix(12).map(\.name))")

        // The machine's process list is whatever happens to be running, so a
        // COUNT is not a test. These three properties are.
        check("no app is listed twice — a host cannot choose between two identical rows",
              Set(apps.map(\.name)).count == apps.count,
              "\(apps.count) rows, \(Set(apps.map(\.name)).count) names")
        check("every row taps at least one audio object",
              apps.allSatisfy { !$0.objectIDs.isEmpty })
        check("every row has a real pid", apps.allSatisfy { $0.pid > 0 })
        check("every row has a name a host could recognise",
              apps.allSatisfy { !$0.name.isEmpty })

        // THE RULE. Our own pid and our own bundle id, both excluded.
        let mypid = ProcessInfo.processInfo.processIdentifier
        check("this process is not offered as a capture source",
              !apps.contains { $0.pid == mypid },
              "pid \(mypid)")
        if let mine = Bundle.main.bundleIdentifier {
            check("this bundle id is not offered either",
                  !apps.contains { $0.bundleID == mine }, mine)
        } else {
            print("SKIP bundle-id exclusion — a command-line tool has no bundle id")
        }

        // THE CONTROL that gives the exclusion meaning: CoreAudio must
        // actually be reporting processes at all. If the raw list were empty
        // for an unrelated reason, "we are not in it" would be true and prove
        // nothing.
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let sizeOK = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr
        let rawCount = Int(size) / MemoryLayout<AudioObjectID>.size
        check("CoreAudio reports a non-empty process list (the control)",
              sizeOK && rawCount > 0,
              "\(rawCount) raw audio objects")

        print(failures == 0 ? "=== §8.26 OK ===" : "=== §8.26 \(failures) FAILURES ===")
        exit(failures == 0 ? 0 : 1)
    }
}
