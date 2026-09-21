#if os(macOS)
import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation
import AppKit

/// THE CALL'S AUDIO — macOS-DESIGN §D2's fourth input, and the piece that
/// makes "With Friends and the World" real (Decision 131, SHAREPLAY §10).
///
/// The owner's own proposal: people use the calling service they already have
/// — Zoom, Meet, FaceTime, a phone call — and the app captures the host's
/// machine playing it. That removes the guest-voice TRANSPORT entirely, and
/// with it the relay, the NAT traversal and the running cost that made every
/// previous design fail the $0 constraint.
///
/// `AudioHardwareCreateProcessTap` is `API_UNAVAILABLE(ios, watchos, tvos)`,
/// which is why only a Mac can host this mode.
///
/// §8.21 proved the mechanism before any of it was built: a tap on a named
/// process captures that process and EXCLUDES every other one at 82 dB. That
/// isolation is not a nicety — it is what stops the film being captured a
/// second time and fed back into its own broadcast.
///
/// The process LIST lives in `StudioAudioProcesses.swift`.
/// A live tap on ONE process, delivering interleaved stereo Float at the
/// program rate — the same contract `MicAudioTap` meets, so the mixer cannot
/// tell the sources apart.
@available(macOS 14.2, *)
public final class StudioCallAudioTap: NSObject, @unchecked Sendable {

    /// 120 ms, matching the microphone. A conversation that arrives late is
    /// worse than one with a gap.
    let ring = AudioRing(capacity: 44100 * 2,
                         maxBacklog: MicAudioTap.backlogSamples)

    private let programRate: Double
    private let resampler = PolyphaseResampler()
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let lock = NSLock()
    private var running = false
    /// Counted for the same reason the camera's frames are: without it,
    /// "no conversation is being captured" and "this app is silent" are the
    /// same observation.
    public private(set) var samplesReceived: Int = 0

    /// Source-rate interleaved stereo, before resampling.
    private var srcScratch = [Float](repeating: 0, count: 16384 * 2)
    private var dstScratch = [Float](repeating: 0, count: 16384 * 2)

    public init(programRate: Double = 44100) {
        self.programRate = programRate
        super.init()
    }

    deinit { stop() }

    /// Begin capturing `process`. Returns a sentence naming the failure, or
    /// nil on success — §D2: a device that cannot be opened says so in its row
    /// rather than leaving a silent channel that looks fine.
    @discardableResult
    public func start(process: StudioAudioProcesses.Process) -> String? {
        stop()
        // EVERY object the app owns — a browser's audio comes from its
        // helper, so tapping only the parent would capture silence.
        let desc = CATapDescription(stereoMixdownOfProcesses: process.objectIDs)
        // PRIVATE and UNMUTED: private so the tap does not appear as a device
        // to anything else on the machine, unmuted so the HOST still hears the
        // call they are in. Muting it would capture the conversation and
        // deafen the person having it.
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(desc, &tap) == noErr,
              tap != kAudioObjectUnknown else {
            return "macOS would not let the Studio listen to \(process.name)."
        }

        guard let uid = defaultOutputUID() else {
            stop(); return "This Mac reported no audio output to attach the tap to."
        }
        let cfg: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Archive Watch Call Tap",
            kAudioAggregateDeviceUIDKey as String: "app.archivewatch.calltap",
            kAudioAggregateDeviceMainSubDeviceKey as String: uid,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            kAudioAggregateDeviceSubDeviceListKey as String: [[kAudioSubDeviceUIDKey as String: uid]],
            kAudioAggregateDeviceTapListKey as String: [[
                kAudioSubTapUIDKey as String: desc.uuid.uuidString,
                kAudioSubTapDriftCompensationKey as String: true]],
        ]
        guard AudioHardwareCreateAggregateDevice(cfg as CFDictionary, &aggregate) == noErr,
              aggregate != kAudioObjectUnknown else {
            stop(); return "This Mac would not create the audio device the tap needs."
        }

        // THE SOURCE RATE IS READ, NOT ASSUMED. A tap runs at the output
        // device's rate, which is 48 kHz on most Macs while the program is
        // 44.1 — the exact mismatch that sent a whole film out 8.8% fast and
        // drifting for ever (§9, the 48 kHz lesson). The resampler's kernel is
        // built HERE because building it allocates, and the IO block below is
        // a real-time callback.
        let srcRate = aggregateSampleRate() ?? programRate
        resampler.configure(sourceRate: srcRate, programRate: programRate)

        let st = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, nil) {
            [weak self] _, inData, _, _, _ in
            self?.consume(inData)
        }
        guard st == noErr, let procID else {
            stop(); return "This Mac would not start the tap's audio callback."
        }
        AudioDeviceStart(aggregate, procID)
        lock.lock(); running = true; lock.unlock()
        return nil
    }

    public func stop() {
        lock.lock(); let wasRunning = running; running = false; lock.unlock()
        if let procID, aggregate != kAudioObjectUnknown {
            if wasRunning { AudioDeviceStop(aggregate, procID) }
            AudioDeviceDestroyIOProcID(aggregate, procID)
        }
        procID = nil
        if aggregate != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregate)
            aggregate = kAudioObjectUnknown
        }
        if tap != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tap)
            tap = kAudioObjectUnknown
        }
    }

    public var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    // MARK: The real-time path

    private func consume(_ inData: UnsafePointer<AudioBufferList>) {
        let abl = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inData))
        var frames = 0
        srcScratch.withUnsafeMutableBufferPointer { src in
            guard let s = src.baseAddress else { return }
            for b in abl {
                guard let d = b.mData else { continue }
                let ch = max(1, Int(b.mNumberChannels))
                let total = Int(b.mDataByteSize) / MemoryLayout<Float>.size
                let p = d.assumingMemoryBound(to: Float.self)
                let n = total / ch
                // De-shape to interleaved STEREO whatever arrives: a mono tap
                // written straight through plays at half speed in a stereo
                // program, and a 6-channel one plays at a third.
                for i in 0..<min(n, src.count / 2) {
                    let l = p[i * ch]
                    let r = ch > 1 ? p[i * ch + 1] : l
                    s[frames * 2] = l
                    s[frames * 2 + 1] = r
                    frames += 1
                }
            }
        }
        guard frames > 0 else { return }
        // FRAMES, not samples. `PolyphaseResampler` counts interleaved-stereo
        // FRAMES and returns frames, so passing `frames * 2` here would ask it
        // to read twice the audio that exists and write it at double speed —
        // the same class of error as the 48 kHz mismatch this resampler was
        // written to fix.
        srcScratch.withUnsafeBufferPointer { src in
            dstScratch.withUnsafeMutableBufferPointer { dst in
                guard let sp = src.baseAddress, let dp = dst.baseAddress else { return }
                let outFrames = resampler.process(sp, inFrames: frames,
                                                  out: dp, outCapacity: dst.count)
                if outFrames > 0 { ring.write(dp, count: outFrames * 2) }
            }
        }
        lock.lock(); samplesReceived += frames; lock.unlock()
    }

    // MARK: CoreAudio odds and ends

    private func defaultOutputUID() -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dev = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &addr, 0, nil, &size, &dev) == noErr else { return nil }
        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid: CFString = "" as CFString
        var us = UInt32(MemoryLayout<CFString>.size)
        let ok = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(dev, &uidAddr, 0, nil, &us, $0)
        }
        guard ok == noErr else { return nil }
        let s = uid as String
        return s.isEmpty ? nil : s
    }

    private func aggregateSampleRate() -> Double? {
        guard aggregate != kAudioObjectUnknown else { return nil }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var rate: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        guard AudioObjectGetPropertyData(aggregate, &addr, 0, nil, &size, &rate) == noErr,
              rate > 0 else { return nil }
        return rate
    }
}
#endif
