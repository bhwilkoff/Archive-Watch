// §8.76 — the CALL's audio arrives at its own pitch and its own speed.
//
// Owner, 2026-10-02, after the first full show: "The audio from the other
// participant on 'the call' sounded like a chipmunk and was highly digitally
// processed." This drives the product's `StudioCallAudioTap` against a helper
// app playing a known sine, reads the ring the way the mixer does (1024
// frames every 1024/44100 s) and measures the frequency and the rate that
// come out. The tapped process is MUTED at its device, so nothing is heard.
//
// The control: the same tone read back with the resampler told the wrong
// source rate must come out at the wrong pitch, or the measurement cannot
// see the defect it exists for.
//
// Usage: test_studio_calltap_rate <path to ToneTest.app> [--switch-rate | --control]
//   --switch-rate changes the default output device's nominal rate mid-run
//   (and restores it), which is what a Bluetooth headset does when a call
//   opens its microphone.
import Foundation
import CoreAudio
import AVFoundation

enum StudioSession { static func browserFamily(_ b: String) -> String { b } }

@main struct CallTapRateTest {
    static var failures = 0
    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "  ok  " : "  FAIL") \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures += 1 }
    }

    static func processObject(pid: pid_t) -> AudioObjectID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var p = pid
        var obj = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                            UInt32(MemoryLayout<pid_t>.size), &p, &size, &obj)
        return st == noErr && obj != 0 ? obj : nil
    }

    static func defaultOutput() -> AudioObjectID {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var dev = AudioObjectID(0); var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
        return dev
    }
    static func nominalRate(_ dev: AudioObjectID) -> Double {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var r = 0.0; var size = UInt32(MemoryLayout<Double>.size)
        AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &r)
        return r
    }
    static func setNominalRate(_ dev: AudioObjectID, _ rate: Double) -> OSStatus {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var r = rate
        return AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Double>.size), &r)
    }

    /// Zero-crossing frequency of the left channel of interleaved stereo.
    static func frequency(_ s: [Float], rate: Double) -> Double {
        var crossings = 0
        var i = 2
        while i < s.count { if (s[i - 2] < 0) != (s[i] < 0) { crossings += 1 }; i += 2 }
        let seconds = Double(s.count / 2) / rate
        return seconds > 0 ? Double(crossings) / 2 / seconds : 0
    }

    /// Read the ring as the mixer does for `seconds`, returning what it gave.
    static func drain(_ ring: AudioRing, seconds: Double) -> (samples: [Float], padded: Int) {
        var out: [Float] = []
        var buf = [Float](repeating: 0, count: 2048)
        let ticks = Int(seconds * 44100 / 1024)
        let start = Date()
        for t in 0..<ticks {
            let due = start.addingTimeInterval(Double(t + 1) * 1024 / 44100)
            Thread.sleep(until: due)
            let got = buf.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, count: 2048) }
            out.append(contentsOf: buf[0..<2048])
            _ = got
        }
        return (out, ring.framesPadded)
    }

    static func main() {
        let args = CommandLine.arguments
        guard args.count > 1 else { print("usage: \(args[0]) ToneTest.app [--switch-rate]"); exit(2) }
        let control = args.contains("--control")
        let switchRate = args.contains("--switch-rate") || control
        let exe = args[1] + "/Contents/MacOS/ToneTest"
        let tone = Process()
        tone.executableURL = URL(fileURLWithPath: exe)
        tone.arguments = ["1000", switchRate ? "30" : "16"]
        tone.standardOutput = FileHandle.nullDevice
        try! tone.run()
        defer { tone.terminate() }
        Thread.sleep(forTimeInterval: 1.0)
        guard let obj = processObject(pid: tone.processIdentifier) else {
            print("  FAIL no CoreAudio process object for the tone app"); exit(1)
        }
        let dev = defaultOutput()
        let originalRate = nominalRate(dev)
        print("output device rate \(originalRate)")

        let proc = StudioAudioProcesses.Process(objectIDs: [obj], pid: tone.processIdentifier,
                                                bundleID: "app.archivewatch.tonetest", name: "ToneTest")
        let tap = StudioCallAudioTap(programRate: 44100)
        tap.muteTappedProcess = true
        tap.followsRateChanges = !control
        if let why = tap.start(process: proc) { print("  FAIL tap: \(why)"); exit(1) }
        Thread.sleep(forTimeInterval: 0.5)
        _ = drain(tap.ring, seconds: 0.5)          // settle
        let s0 = tap.samplesReceived
        let t0 = Date()
        let (a, padA) = drain(tap.ring, seconds: 4)
        let rateIn = Double(tap.samplesReceived - s0) / Date().timeIntervalSince(t0)
        let fA = frequency(Array(a.dropFirst(4096)), rate: 44100)
        print("shape \(tap.lastBufferShape) sourceRate \(tap.sourceRate) delivered \(Int(rateIn))/s padded \(padA) dropped \(tap.ring.framesDroppedForLatency)")
        check("the tone comes out at its own pitch", abs(fA - 1000) < 15, String(format: "%.1f Hz", fA))
        check("the tap delivers at the rate it was configured for",
              abs(rateIn - tap.sourceRate) / tap.sourceRate < 0.03,
              "\(Int(rateIn))/s vs \(Int(tap.sourceRate))")

        if switchRate {
            let other = originalRate == 48000 ? 44100.0 : 48000.0
            let st = setNominalRate(dev, other)
            print("switched output device to \(other) (status \(st)); now \(nominalRate(dev))")
            Thread.sleep(forTimeInterval: 1.5)
            _ = drain(tap.ring, seconds: 0.5)
            let s1 = tap.samplesReceived, t1 = Date()
            let (b, _) = drain(tap.ring, seconds: 4)
            let rate2 = Double(tap.samplesReceived - s1) / Date().timeIntervalSince(t1)
            let fB = frequency(Array(b.dropFirst(4096)), rate: 44100)
            print("after switch: sourceRate \(tap.sourceRate) delivered \(Int(rate2))/s")
            if control {
                check("CONTROL: a tap that ignores the change loses the pitch", abs(fB - 1000) > 15,
                      String(format: "%.1f Hz", fB))
            } else {
                check("after the device changes rate, the tone keeps its pitch", abs(fB - 1000) < 15,
                      String(format: "%.1f Hz", fB))
            }
            let back = setNominalRate(dev, originalRate)
            print("restored output device to \(nominalRate(dev)) (status \(back))")
        }
        tap.stop()
        print(failures == 0 ? "PASS" : "FAILED \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
