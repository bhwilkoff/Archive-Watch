#if os(macOS)
import Foundation
import CoreAudio
import AudioToolbox
import AppKit

// WHICH APP's audio (macOS-DESIGN §D2's fourth input).
//
// Split out of `StudioProcessTap.swift` so it compiles with no audio pipeline
// behind it and the §8 suite can test it — the same reason
// `StudioOutputSettings` has its own file. The TAP needs `AudioRing` and the
// resampler; enumerating processes needs neither.

@available(macOS 14.2, *)
public enum StudioAudioProcesses {

    /// ONE ROW PER APP, not per process.
    ///
    /// A browser plays audio from a HELPER process, so Chrome appeared twice
    /// — `com.google.Chrome` and `com.google.Chrome.helper`, both rendering
    /// as "Google Chrome", and a host cannot choose between two identical
    /// rows. `CATapDescription(stereoMixdownOfProcesses:)` takes an ARRAY, so
    /// the honest model is to let the host pick the APP and tap every audio
    /// object it owns.
    public struct Process: Identifiable, Hashable, Sendable {
        /// Every CoreAudio process object this app owns.
        public let objectIDs: [AudioObjectID]
        public let pid: pid_t
        public let bundleID: String
        /// The app's own display name where we can get it — a host picks
        /// "Google Chrome", not a bundle id and not a number.
        public let name: String
        public var id: String { name }
    }

    /// Every process CoreAudio currently knows how to tap.
    ///
    /// OUR OWN PROCESS IS EXCLUDED, deliberately and not as tidying: Archive
    /// Watch is playing the film, so tapping ourselves would capture the film
    /// a second time and mix it into the broadcast on top of the film — the
    /// exact feedback §8.21's isolation control exists to rule out.
    public static func all() -> [Process] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0,
                                  count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &addr, 0, nil, &size, &ids) == noErr else { return [] }

        let me = ProcessInfo.processInfo.processIdentifier
        let mine = Bundle.main.bundleIdentifier
        var out: [Process] = []
        for o in ids {
            let pid = objectPID(o)
            guard pid > 0, pid != me else { continue }
            guard let bundle = objectBundleID(o), bundle != mine else { continue }
            guard isWorthOffering(bundleID: bundle, pid: pid) else { continue }
            out.append(Process(objectIDs: [o], pid: pid, bundleID: bundle,
                               name: displayName(bundleID: bundle, pid: pid)))
        }
        // GROUP BY THE NAME THE HOST SEES. Every audio object belonging to
        // "Google Chrome" — the browser and its helpers — becomes one row
        // that taps all of them.
        var byName: [String: (pid: pid_t, bundle: String, ids: [AudioObjectID])] = [:]
        for p in out.sorted(by: { $0.pid < $1.pid }) {
            if var e = byName[p.name] {
                e.ids.append(contentsOf: p.objectIDs)
                byName[p.name] = e
            } else {
                byName[p.name] = (p.pid, p.bundleID, p.objectIDs)
            }
        }
        return byName.map { name, e in
            Process(objectIDs: e.ids, pid: e.pid, bundleID: e.bundle, name: name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func objectPID(_ o: AudioObjectID) -> pid_t {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<pid_t>.size)
        var p: pid_t = -1
        AudioObjectGetPropertyData(o, &addr, 0, nil, &size, &p)
        return p
    }

    static func objectBundleID(_ o: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var out: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(o, &addr, 0, nil, &size, &out) == noErr,
              let s = out?.takeUnretainedValue() as String?, !s.isEmpty else { return nil }
        return s
    }

    /// A HOST PICKS AN APP, NOT A DAEMON.
    ///
    /// The raw CoreAudio list is every process that can produce audio, which
    /// on this Mac was 24 entries and mostly `callservicesd`, `audiomxd`,
    /// `assistantd` and the Core Audio driver service — none of which a person
    /// could recognise, and none of which is a conversation.
    ///
    /// Two ways in, because either alone is wrong:
    ///  • a process with a real app in the Dock (`.regular`) — Zoom,
    ///    FaceTime, Safari;
    ///  • ANY non-Apple process, which keeps the helper processes browsers
    ///    actually play audio from. `com.google.Chrome.helper` has no
    ///    `NSRunningApplication` at all, and dropping it would remove Google
    ///    Meet — the single most likely thing a host is on.
    private static func isWorthOffering(bundleID: String, pid: pid_t) -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid),
           app.activationPolicy == .regular { return true }
        return !bundleID.hasPrefix("com.apple.")
    }

    /// A helper process has its OWN localized name — "Google Chrome Helper",
    /// "Slack Helper (Renderer)" — so taking it at face value split one app
    /// into two rows the host has to guess between. The app is the thing
    /// being captured; the helper is an implementation detail of it.
    private static func canonical(_ name: String) -> String {
        var n = name
        // "Google Chrome Helper (Renderer)" -> "Google Chrome Helper"
        if let open = n.firstIndex(of: "("), n.hasSuffix(")") {
            n = String(n[n.startIndex..<open]).trimmingCharacters(in: .whitespaces)
        }
        for suffix in [" Helper", " Web Content", " Networking", " GPU"] where n.hasSuffix(suffix) {
            n = String(n.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        return n.isEmpty ? name : n
    }

    private static func displayName(bundleID: String, pid: pid_t) -> String {
        if let app = NSRunningApplication(processIdentifier: pid),
           let n = app.localizedName, !n.isEmpty { return canonical(n) }
        // A browser's audio comes from a HELPER process with no running
        // application of its own, so borrow the parent's name: "Google Chrome"
        // is something a host can find in a list and "com.google.Chrome.helper"
        // is not.
        var base = bundleID
        for suffix in [".helper", ".Helper"] where base.hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count))
        }
        if base != bundleID,
           let parent = NSRunningApplication.runningApplications(withBundleIdentifier: base).first,
           let n = parent.localizedName, !n.isEmpty { return canonical(n) }
        return base
    }
}
#endif
