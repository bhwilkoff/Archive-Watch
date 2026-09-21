// §8.21 — can a macOS host capture ANOTHER APP's audio, and ONLY that app's?
//
// The owner's question: let people use the calling service they already have
// (Zoom, Google Meet in a browser, FaceTime) and have the Studio mix that
// conversation into the broadcast, so the app never carries voice at all.
// That is only possible if a host can tap a NAMED process — and it is only
// SAFE if the tap excludes every other process, or the film would be captured
// a second time and fed back into its own broadcast.
//
// Controls: an object that is not a process must yield no usable tap, and a
// second process playing a different tone at the same time must NOT appear.
import Foundation
import CoreAudio
import AudioToolbox

var failures = 0
func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print("\(ok ? "PASS" : "FAIL") \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !ok { failures += 1 }
}

/// Exit 2, which `tools/test_studio_all.sh` reads as SKIP.
///
/// Used when a PRECONDITION of the measurement is absent rather than when the
/// measurement fails — the difference matters because a red line that really
/// means "somebody is using this Mac" teaches a reader to discount red lines.
func skip(_ label: String, _ why: String) -> Never {
    print("SKIP \(label) — \(why)")
    print("\n8.21 SKIPPED (a skip is not a pass)")
    exit(2)
}

// MARK: - Core Audio process objects

func processObjects() -> [AudioObjectID] {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                         &addr, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                     &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

func objectPID(_ o: AudioObjectID) -> pid_t {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyPID,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<pid_t>.size); var p: pid_t = -1
    AudioObjectGetPropertyData(o, &addr, 0, nil, &size, &p)
    return p
}

func objectBundleID(_ o: AudioObjectID) -> String? {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyBundleID,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var out: Unmanaged<CFString>?
    guard AudioObjectGetPropertyData(o, &addr, 0, nil, &size, &out) == noErr,
          let s = out?.takeUnretainedValue() as String?, !s.isEmpty else { return nil }
    return s
}

// MARK: - A tone file, written without depending on ffmpeg

func writeTone(_ path: String, hz: Double, seconds: Double) {
    let rate = 48000.0, n = Int(rate * seconds)
    var d = Data()
    func le32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    func le16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    let dataBytes = UInt32(n * 2 * 2)
    d.append(contentsOf: Array("RIFF".utf8)); le32(36 + dataBytes)
    d.append(contentsOf: Array("WAVEfmt ".utf8)); le32(16); le16(1); le16(2)
    le32(48000); le32(48000 * 4); le16(4); le16(16)
    d.append(contentsOf: Array("data".utf8)); le32(dataBytes)
    for i in 0..<n {
        let s = Int16(sin(2 * .pi * hz * Double(i) / rate) * 12000)
        le16(UInt16(bitPattern: s)); le16(UInt16(bitPattern: s))
    }
    try? d.write(to: URL(fileURLWithPath: path))
}

// MARK: - Capture a process through a tap in an aggregate device

final class Capture: @unchecked Sendable {
    var frames = 0, n = 0
    var peak: Float = 0
    private var s1a = 0.0, s2a = 0.0, s1b = 0.0, s2b = 0.0
    private let ca: Double, cb: Double
    init(a: Double, b: Double) {
        ca = 2 * cos(2 * .pi * a / 48000); cb = 2 * cos(2 * .pi * b / 48000)
    }
    func feed(_ v: Double) {
        let x = v + ca * s1a - s2a; s2a = s1a; s1a = x
        let y = v + cb * s1b - s2b; s2b = s1b; s1b = y
        n += 1
    }
    var magA: Double { sqrt(max(0, s1a*s1a + s2a*s2a - ca*s1a*s2a)) / Double(max(1, n)) }
    var magB: Double { sqrt(max(0, s1b*s1b + s2b*s2b - cb*s1b*s2b)) / Double(max(1, n)) }
}

func capture(pid target: pid_t, seconds: Double, toneA: Double, toneB: Double) -> Capture? {
    guard let obj = processObjects().first(where: { objectPID($0) == target }) else { return nil }
    let desc = CATapDescription(stereoMixdownOfProcesses: [obj])
    desc.isPrivate = true
    desc.muteBehavior = .unmuted
    var tap = AudioObjectID(kAudioObjectUnknown)
    guard AudioHardwareCreateProcessTap(desc, &tap) == noErr, tap != kAudioObjectUnknown else { return nil }
    defer { AudioHardwareDestroyProcessTap(tap) }

    var outAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var outDev = AudioObjectID(0); var ods = UInt32(MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &outAddr, 0, nil, &ods, &outDev)
    var uidAddr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var uid: CFString = "" as CFString; var us = UInt32(MemoryLayout<CFString>.size)
    withUnsafeMutablePointer(to: &uid) { AudioObjectGetPropertyData(outDev, &uidAddr, 0, nil, &us, $0) }

    let cfg: [String: Any] = [
        kAudioAggregateDeviceNameKey as String: "AW Tap Probe",
        kAudioAggregateDeviceUIDKey as String: "app.archivewatch.tapprobe",
        kAudioAggregateDeviceMainSubDeviceKey as String: uid as String,
        kAudioAggregateDeviceIsPrivateKey as String: true,
        kAudioAggregateDeviceIsStackedKey as String: false,
        kAudioAggregateDeviceSubDeviceListKey as String: [[kAudioSubDeviceUIDKey as String: uid as String]],
        kAudioAggregateDeviceTapListKey as String: [[
            kAudioSubTapUIDKey as String: desc.uuid.uuidString,
            kAudioSubTapDriftCompensationKey as String: true]],
    ]
    var agg = AudioObjectID(kAudioObjectUnknown)
    guard AudioHardwareCreateAggregateDevice(cfg as CFDictionary, &agg) == noErr else { return nil }
    defer { AudioHardwareDestroyAggregateDevice(agg) }

    let cap = Capture(a: toneA, b: toneB)
    var proc: AudioDeviceIOProcID?
    let st = AudioDeviceCreateIOProcIDWithBlock(&proc, agg, nil) { _, inData, _, _, _ in
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
        for b in abl {
            guard let d = b.mData else { continue }
            let total = Int(b.mDataByteSize) / MemoryLayout<Float>.size
            let ch = max(1, Int(b.mNumberChannels))
            let p = d.assumingMemoryBound(to: Float.self)
            for i in stride(from: 0, to: total, by: ch) {
                let v = p[i]
                if abs(v) > cap.peak { cap.peak = abs(v) }
                cap.feed(Double(v))
            }
            cap.frames += total / ch
        }
    }
    guard st == noErr, let proc else { return nil }
    AudioDeviceStart(agg, proc)
    Thread.sleep(forTimeInterval: seconds)
    AudioDeviceStop(agg, proc)
    AudioDeviceDestroyIOProcID(agg, proc)
    return cap
}

// MARK: - The suite

@main
struct ProcessTapTest {
    static func main() {
        print("=== 8.21 per-process audio tap: the call app is tappable, and ONLY it ===")

        if #unavailable(macOS 14.2) {
            print("SKIP 8.21 requires macOS 14.2+"); exit(0)
        }

        let procs = processObjects()
        check("8.21.1 process object list is readable", !procs.isEmpty, "\(procs.count) audio processes")

        var named: [String: AudioObjectID] = [:]
        for p in procs { if let b = objectBundleID(p) { named[b] = p } }
        check("8.21.2 processes are identified by bundle id", !named.isEmpty, "\(named.count) named")

        // The specific claim being made: the services people already have are here.
        let callApps = ["us.zoom.xos": "Zoom", "com.google.Chrome": "Google Meet in Chrome",
                        "com.apple.avconferenced": "FaceTime", "com.microsoft.teams2": "Teams",
                        "com.tinyspeck.slackmacgap": "Slack huddles"]
        let present = callApps.filter { named[$0.key] != nil }
        print("        call-capable processes running now: " +
              (present.isEmpty ? "(none)" : present.values.sorted().joined(separator: ", ")))

        // CONTROL FIRST: something that is not a process must not give a usable tap.
        var bogus = AudioObjectID(kAudioObjectUnknown)
        let bogusDesc = CATapDescription(stereoMixdownOfProcesses: [AudioObjectID(0x7FFFFFFF)])
        bogusDesc.isPrivate = true
        let bst = AudioHardwareCreateProcessTap(bogusDesc, &bogus)
        var bogusUsable = false
        if bst == noErr && bogus != kAudioObjectUnknown {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioTapPropertyFormat,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var asbd = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            bogusUsable = AudioObjectGetPropertyData(bogus, &addr, 0, nil, &size, &asbd) == noErr && asbd.mSampleRate > 0
            AudioHardwareDestroyProcessTap(bogus)
        }
        check("8.21.3 CONTROL a non-process yields no usable tap", !bogusUsable, "status=\(bst)")

        // Two processes, two tones. Tap one. The other must not appear.
        let dir = NSTemporaryDirectory()
        let aPath = dir + "aw_tap_440.wav", bPath = dir + "aw_tap_1000.wav"
        writeTone(aPath, hz: 440, seconds: 12)
        writeTone(bPath, hz: 1000, seconds: 12)

        func play(_ path: String) -> Process {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            p.arguments = [path]
            try? p.run()
            return p
        }
        let pa = play(aPath), pb = play(bPath)
        Thread.sleep(forTimeInterval: 1.0)

        if let cap = capture(pid: pa.processIdentifier, seconds: 4.0, toneA: 440, toneB: 1000) {
            let rate = Double(cap.frames) / 4.0
            // THIS HARNESS REACHES INTO A LIVE MACHINE, and that is the one
            // thing it must own up to. The tap follows the DEFAULT OUTPUT
            // DEVICE, so its sample rate is whatever the person at the desk is
            // listening through — and a Bluetooth headset in call mode runs at
            // 24 kHz, not 44.1 or 48. At that rate these tones are resampled
            // and attenuated to nothing, and whatever the owner is ACTUALLY
            // listening to dominates the capture.
            //
            // Seen on 2026-09-21: six clean passes during the day, then
            // "peak 0.41, 440 Hz magnitude 0.000060" at 24 kHz — real audio
            // flowing, none of it ours, with the 1000 Hz control LOUDER than
            // the signal. Nothing in the code had changed; the machine had.
            //
            // So this SKIPS rather than fails. A failure that really means
            // "somebody is using this Mac" is worse than a skip: it teaches a
            // reader to discount a red line, which is the one thing a suite
            // cannot afford. `instrument_must_be_invisible` is the standing
            // rule and this is the audio version of it.
            guard rate >= 40_000 else {
                pa.terminate(); pb.terminate()
                pa.waitUntilExit(); pb.waitUntilExit()
                try? FileManager.default.removeItem(atPath: aPath)
                try? FileManager.default.removeItem(atPath: bPath)
                skip("8.21.4-6 the tapped process is heard, and only it",
                     String(format: "the default output device is running at %.0f Hz — "
                            + "a headset in call mode, not a speaker. This harness needs "
                            + "a 44.1/48 kHz output and a quiet machine.", rate))
            }
            check("8.21.4 the tap delivers PCM at the device rate", cap.frames > 40_000,
                  String(format: "%d frames, %.0f Hz", cap.frames, rate))
            check("8.21.5 the tapped process is HEARD", cap.peak > 0.01 && cap.magA > 1e-4,
                  String(format: "peak %.4f, 440 Hz magnitude %.6f", cap.peak, cap.magA))
            // This is the one that makes the design safe rather than merely possible.
            let ratio = cap.magA / max(1e-12, cap.magB)
            check("8.21.6 a SECOND process playing at the same time is EXCLUDED", ratio > 100,
                  String(format: "440 Hz %.6f vs 1000 Hz %.6f = %.0f:1 (%.0f dB)",
                         cap.magA, cap.magB, ratio, 20 * log10(ratio)))
        } else {
            check("8.21.4 the tap delivers PCM at the device rate", false, "capture could not start")
            check("8.21.5 the tapped process is HEARD", false, "capture could not start")
            check("8.21.6 a SECOND process playing at the same time is EXCLUDED", false, "capture could not start")
        }

        pa.terminate(); pb.terminate()
        pa.waitUntilExit(); pb.waitUntilExit()
        try? FileManager.default.removeItem(atPath: aPath)
        try? FileManager.default.removeItem(atPath: bPath)
        check("8.21.7 both tone processes are stopped", !pa.isRunning && !pb.isRunning)

        print(failures == 0 ? "\n8.21 OK" : "\n8.21 \(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
