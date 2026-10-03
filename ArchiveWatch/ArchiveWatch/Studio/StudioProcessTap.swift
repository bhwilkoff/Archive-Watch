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
    /// Replaced, never reconfigured in place, when the device changes rate:
    /// the render callback holds `rateLock` only to read this reference.
    private var resampler = PolyphaseResampler()
    private let rateLock = NSLock()
    private var rateListener: AudioObjectPropertyListenerBlock?
    private let listenerQueue = DispatchQueue(label: "studio.calltap.rate")
    /// The tap's own stream: how many channels, and whether they arrive as
    /// one interleaved buffer or one buffer each.
    private var tapChannels = 2
    private var tapInterleaved = true
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let lock = NSLock()
    private var running = false
    /// Counted for the same reason the camera's frames are: without it,
    /// "no conversation is being captured" and "this app is silent" are the
    /// same observation.
    public private(set) var samplesReceived: Int = 0
    /// The SHAPE of what the aggregate hands the callback — buffers per
    /// call and channels in each — so a harness (and a log line) can see a
    /// headset's own input stream or a non-interleaved tap instead of
    /// inferring it from how the voice sounds.
    public private(set) var lastBufferShape: [Int] = []
    /// The rate the resampler is converting FROM.
    public private(set) var sourceRate: Double = 0
    /// Harness only: mute the tapped process at its device, so a test tone
    /// is captured without being played into the room.
    public var muteTappedProcess = false
    /// Harness only: the §8.76 control turns this off and must hear the
    /// pitch move.
    public var followsRateChanges = true

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
        // AND BY BUNDLE ID, FOLLOWED ACROSS RESTARTS (macOS 26). A browser
        // renders a call's sound in a helper that can start AFTER the host
        // picked the window — a tap bound only to the audio objects that
        // existed at that moment hears nothing from the new one. Measured
        // 2026-09-25 on the owner's Meet call: the tap ran, 13.9 million
        // samples, every level 0.0000. The browser itself and its helper are
        // both named so either one's audio is followed.
        let family = StudioSession.browserFamily(process.bundleID)
        desc.bundleIDs = Array(Set([process.bundleID, family, family + ".helper"]))
        desc.isProcessRestoreEnabled = true
        // PRIVATE and UNMUTED: private so the tap does not appear as a device
        // to anything else on the machine, unmuted so the HOST still hears the
        // call they are in. Muting it would capture the conversation and
        // deafen the person having it.
        desc.isPrivate = true
        desc.muteBehavior = muteTappedProcess ? .muted : .unmuted
        guard AudioHardwareCreateProcessTap(desc, &tap) == noErr,
              tap != kAudioObjectUnknown else {
            return "macOS would not let the Studio listen to \(process.name)."
        }

        guard let uid = defaultOutputUID() else {
            stop(); return "This Mac reported no audio output to attach the tap to."
        }
        let cfg: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Archive Watch Call Tap",
            // ONE UID PER TAP: §D40 runs a tap per calling app at once, and two
            // aggregate devices may not share a UID.
            kAudioAggregateDeviceUIDKey as String: "app.archivewatch.calltap." + UUID().uuidString,
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
        sourceRate = srcRate
        if let f = tapFormat() {
            tapChannels = max(1, Int(f.mChannelsPerFrame))
            tapInterleaved = f.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        }
        // AND FOLLOWED WHEN IT CHANGES. Owner, 2026-10-02, after the first
        // full show: *"The audio from the other participant on 'the call'
        // sounded like a chipmunk and was highly digitally processed."* The
        // rate was read ONCE, when the host picked the call — and the
        // aggregate runs at its output device's rate, which a Bluetooth
        // headset drops from 48 kHz to 16 or 24 kHz the moment a call (or this
        // Studio) opens its microphone. A 24 kHz stream converted as if it
        // were 48 kHz comes out at twice the speed and an octave up, with the
        // ring running dry between chunks: exactly that sound. §8.76 changes
        // the device's rate mid-run and requires the tone's pitch to hold.
        if followsRateChanges { listenForRateChanges() }

        let st = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, nil) {
            [weak self] _, inData, inTime, _, _ in
            self?.consume(inData, at: inTime)
        }
        guard st == noErr, let procID else {
            stop(); return "This Mac would not start the tap's audio callback."
        }
        // THE STATUS IS READ (§D18). This was `AudioDeviceStart(aggregate, procID)`
        // with its result discarded, so a tap macOS refused to start reported
        // SUCCESS — and the Studio drew a mixer channel that could never carry
        // anything. That is exactly the silent channel §D2 forbids, in the one
        // input whose TCC behaviour has been listed as unmeasured since it was
        // written: a process tap has its own privacy service, which neither the
        // microphone entitlement nor the sandbox's audio-input covers.
        let runStatus = AudioDeviceStart(aggregate, procID)
        guard runStatus == noErr else {
            stop()
            return "macOS refused to start capturing \(process.name) "
                 + "(OSStatus \(runStatus)). Check Privacy & Security ▸ "
                 + "Audio Recording for Archive Watch."
        }
        lock.lock(); running = true; lock.unlock()
        return nil
    }

    public func stop() {
        stopListeningForRateChanges()
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

    private func consume(_ inData: UnsafePointer<AudioBufferList>,
                         at time: UnsafePointer<AudioTimeStamp>) {
        let abl = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inData))
        let shape = abl.map { Int($0.mNumberChannels) }
        if shape != lastBufferShape { lastBufferShape = shape }
        // ONLY THE TAP'S OWN BUFFERS. The aggregate's sub-device is the output
        // device, and when that device has a microphone of its own — a
        // headset, AirPods, a display with a mic — its input stream arrives in
        // the same list, AHEAD of the tap's. Every buffer used to be appended
        // one after another as if it were one timeline: the headset's mic,
        // then the call, then the headset again, at twice real time, with the
        // ring's latency cap throwing the surplus away. The tap's streams are
        // the LAST ones in the list: one interleaved buffer, or one buffer per
        // channel when the tap is non-interleaved.
        let need = tapInterleaved ? 1 : tapChannels
        guard abl.count >= need else { return }
        let first = abl.count - need
        var frames = 0
        srcScratch.withUnsafeMutableBufferPointer { src in
            guard let s = src.baseAddress else { return }
            let capacityFrames = src.count / 2
            if tapInterleaved {
                let b = abl[first]
                guard let d = b.mData else { return }
                let ch = max(1, Int(b.mNumberChannels))
                let n = Int(b.mDataByteSize) / MemoryLayout<Float>.size / ch
                let p = d.assumingMemoryBound(to: Float.self)
                // De-shape to interleaved STEREO whatever arrives: a mono tap
                // written straight through plays at half speed in a stereo
                // program, and a 6-channel one plays at a third.
                for i in 0..<min(n, capacityFrames) {
                    let l = p[i * ch]
                    s[i * 2] = l
                    s[i * 2 + 1] = ch > 1 ? p[i * ch + 1] : l
                }
                frames = min(n, capacityFrames)
            } else {
                guard let dl = abl[first].mData else { return }
                let pl = dl.assumingMemoryBound(to: Float.self)
                let pr = need > 1 ? abl[first + 1].mData?.assumingMemoryBound(to: Float.self) : nil
                let n = Int(abl[first].mDataByteSize) / MemoryLayout<Float>.size
                for i in 0..<min(n, capacityFrames) {
                    s[i * 2] = pl[i]
                    s[i * 2 + 1] = pr?[i] ?? pl[i]
                }
                frames = min(n, capacityFrames)
            }
        }
        guard frames > 0 else { return }
        rateLock.lock()
        let rs = resampler
        rateLock.unlock()
        // FRAMES, not samples, on both sides: `PolyphaseResampler` counts
        // interleaved-stereo frames in and out (passing a sample count asks it
        // to read twice the audio that exists and write it at double speed).
        let cap = rs.capacityNeeded(forInputFrames: frames)
        if dstScratch.count < cap * 2 { dstScratch = [Float](repeating: 0, count: cap * 2) }
        srcScratch.withUnsafeBufferPointer { src in
            dstScratch.withUnsafeMutableBufferPointer { dst in
                guard let sp = src.baseAddress, let dp = dst.baseAddress else { return }
                let outFrames = rs.process(sp, inFrames: frames, out: dp, outCapacity: cap)
                // When the call's last sample was played, so the mixer can
                // hold it to the age of the call's window (§D42).
                let ts = time.pointee
                let end = ts.mFlags.contains(.hostTimeValid) && ts.mHostTime > 0
                    ? StudioCaptureClock.hostSeconds(machTime: ts.mHostTime)
                        + Double(frames) / max(rs.sourceRate, 1)
                    : nil
                if outFrames > 0 { ring.write(dp, count: outFrames * 2, capturedAt: end) }
            }
        }
        lock.lock(); samplesReceived += frames; lock.unlock()
    }

    private func listenForRateChanges() {
        guard aggregate != kAudioObjectUnknown else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.rateChanged()
        }
        if AudioObjectAddPropertyListenerBlock(aggregate, &addr, listenerQueue, block) == noErr {
            rateListener = block
        }
    }

    private func stopListeningForRateChanges() {
        guard let block = rateListener, aggregate != kAudioObjectUnknown else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(aggregate, &addr, listenerQueue, block)
        rateListener = nil
    }

    /// Off the render thread: building a kernel allocates.
    private func rateChanged() {
        guard let rate = aggregateSampleRate(), rate != sourceRate else { return }
        let fresh = PolyphaseResampler()
        fresh.configure(sourceRate: rate, programRate: programRate)
        rateLock.lock()
        resampler = fresh
        rateLock.unlock()
        sourceRate = rate
        awdiag("AWCALL tap rate changed to %.0f Hz", rate)
    }

    private func tapFormat() -> AudioStreamBasicDescription? {
        guard tap != kAudioObjectUnknown else { return nil }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var f = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tap, &addr, 0, nil, &size, &f) == noErr else { return nil }
        return f
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
