// Can SharePlay's messenger carry a VOICE? (§9.wwwww's one measurement)
//
// Owner, 2026-09-20: "if we can allow multiple people running Archive Watch
// to hear one another as they watch a live stream and get all of the audio to
// mix together, then that reaches the same goal ... I'd like to watch the
// movie together and be able to talk with my friends and family while I'm
// doing it, and have that all streamed to YouTube or twitch."
//
// `GroupSessionMessenger` sends raw `Data` to every participant and can be
// constructed with `DeliveryMode.unreliable`, so the SHAPE is right. What is
// not known is whether it behaves like a media transport, because Apple
// documents it for application state and says nothing about rate or latency.
// That single unknown decides the whole feature: if the messenger carries it,
// guest voice is assembled from parts this project already has — an AAC
// encoder on every Apple target, and a mixer with 0-10 faders and a duck on
// four platforms. If it does not, the guest transport becomes our own
// networking, at a completely different cost.
//
// So this measures it rather than assuming it, BEFORE anything is built on
// top. Decision 130: prove the rule on the path the product would take.
//
// WHY ROUND-TRIP AND NOT ONE-WAY. Two devices do not share a clock, and a
// one-way number computed across two clocks measures the offset between them
// as much as the network — which is exactly the error that put half a marker
// of bias into the A/V tool (§9) and 19.6 seconds between Android's tracks
// (§9.qq). An echo needs no shared clock: the sender stamps, the peer bounces
// the bytes back untouched, and the sender subtracts. One-way is reported as
// half of it, labelled as the estimate it is.
//
// It is a DEBUG door and no part of the product. `AW_VOICE_PROBE=1`.

#if canImport(GroupActivities)
import Foundation
import GroupActivities
import os

/// The probe's wire format, extracted so it can be TESTED.
///
/// It lived inside `StudioVoiceProbe.handle`, which needs a live
/// `GroupSessionMessenger` and therefore two people in a SharePlay call — so
/// the one piece with an off-by-one in it was the one piece no test could
/// reach. It shipped a crash on every inbound frame (see `decode`).
///
/// Pulling it out costs nothing and makes the hazard assertable: §8.18 feeds
/// `decode` a Data SLICE, which is the shape that trapped.
enum VoiceFrame {
    static let tagProbe: UInt8 = 1
    static let tagEcho: UInt8 = 2

    /// `[0]` tag, `[1..<5]` little-endian sequence, then padding to `size`.
    static func encode(tag: UInt8, seq: UInt32, size: Int) -> Data {
        var payload = Data(count: max(size, 5))
        payload.withUnsafeMutableBytes { dst in
            dst[0] = tag
            withUnsafeBytes(of: seq.littleEndian) { raw in
                for i in 0..<4 { dst[1 + i] = raw[i] }
            }
        }
        return payload
    }

    /// NEVER SUBSCRIPT A `Data` YOU DID NOT CREATE.
    ///
    /// This was `data[0]` and `data[1 + i]`, and **`Data`'s subscript takes an
    /// ABSOLUTE INDEX, not an offset**. A `Data` handed back by a framework is
    /// routinely a SLICE whose `startIndex` is not zero, and `data[0]` on one
    /// of those traps with "Index out of range" — on EVERY frame. `count`
    /// reads correctly on a slice, so the `>= 5` guard passed cleanly and the
    /// next line crashed; the guard looked like it was protecting the thing it
    /// was not. Owner, 2026-09-20: *"Lots of crashing."*
    ///
    /// `withUnsafeBytes` is offset-based over the slice's OWN bytes, which is
    /// what this always meant.
    static func decode(_ data: Data) -> (tag: UInt8, seq: UInt32)? {
        guard data.count >= 5 else { return nil }
        return data.withUnsafeBytes { raw in
            var v: UInt32 = 0
            withUnsafeMutableBytes(of: &v) { out in
                for i in 0..<4 { out[i] = raw[1 + i] }
            }
            return (raw[0], UInt32(littleEndian: v))
        }
    }

    /// The same frame with only the tag changed, as a FRESH buffer — never by
    /// mutating a slice somebody else owns.
    static func bounce(_ data: Data, tag: UInt8) -> Data {
        var back = Data(count: data.count)
        data.withUnsafeBytes { src in
            back.withUnsafeMutableBytes { dst in
                for i in 0..<data.count { dst[i] = src[i] }
                dst[0] = tag
            }
        }
        return back
    }
}

@MainActor
@Observable
public final class StudioVoiceProbe {

    /// ON BY DEFAULT IN DEBUG, off with `AW_VOICE_PROBE=0`.
    ///
    /// It was an opt-in environment variable, which only works when the app is
    /// LAUNCHED BY devicectl — and the person taking this measurement needs to
    /// tap the app, start a session, and move around the UI. An env var would
    /// have silently not been set on exactly the run that mattered, and the
    /// probe would have reported nothing while looking fine.
    ///
    /// It is harmless where it is on: DEBUG only, dormant until a
    /// `GroupSession` actually exists, and 4 kB/s of 80-byte frames while one
    /// does. It never ships — `#if DEBUG` is the gate, not a flag someone has
    /// to remember to clear.
    /// OPT-IN. `AW_VOICE_PROBE=1`, DEBUG only.
    ///
    /// It was briefly ON by default in DEBUG, so that the person taking the
    /// measurement could tap the app rather than have it launched for them.
    /// That was wrong in the way this project keeps finding: **the instrument
    /// must be invisible to its own test.** Owner, minutes later: *"The
    /// SharePlay session keeps quitting out."* A probe that begins firing
    /// fifty messages a second the instant a session is adopted is the prime
    /// suspect for a session that will not stay up, and while it is on by
    /// default there is no way to tell a transport that cannot carry voice
    /// from a transport being knocked over by the thing measuring it.
    ///
    /// Default OFF restores the control: get a session to stay up with the
    /// probe off, THEN turn it on and see what changes. That comparison is
    /// the measurement; the flood on its own never was.
    /// ON in DEBUG, and it STOPS BY ITSELF after one ramp.
    ///
    /// Two failed shapes got here. Opt-in by environment variable only works
    /// when devicectl launches the app — and a devicectl-launched app is
    /// killed the moment it is backgrounded to start a SharePlay call, which
    /// is exactly what the person taking this measurement has to do. On by
    /// default with an unbounded 50/s flood is an instrument that can knock
    /// over the thing it measures.
    ///
    /// CORRECTION OWED: when the owner reported "the SharePlay session keeps
    /// quitting out" I blamed the flood and made it opt-in. That may have been
    /// wrong. Both apps were devicectl-launched at the time, and a
    /// debug-launched app dying on backgrounding looks identical from the
    /// outside. The diagnosis was plausible and unproven, and it is recorded
    /// here rather than quietly dropped.
    ///
    /// So: on by default (a tap works), gentle (5/s rising), and BOUNDED —
    /// about twenty-five seconds and then it stops for good. If a session
    /// still fails with that, the probe is not what is failing, which is the
    /// one thing neither earlier shape could tell us.
    public static let enabled: Bool = {
        #if DEBUG
        // BACK ON BY DEFAULT, now that the crash it was disabled for is
        // fixed and covered. `Data`'s absolute-index subscript trapped on
        // every inbound frame (see `VoiceFrame.decode`); that is gone and the
        // wire format is a separate, testable type.
        //
        // On by default because it is the ONLY shape that works: a
        // devicectl-launched app is killed both when it is backgrounded to
        // start a call AND when SharePlay's own UI takes over on activation
        // (measured twice, 2026-09-20). A tap is the only launch that
        // survives, and a tap carries no environment variables.
        //
        // Safe to leave on: dormant until a session exists, 5/s rising to 50
        // over ten seconds, and it STOPS ITSELF after about twenty-five.
        return ProcessInfo.processInfo.environment["AW_VOICE_PROBE"] != "0"
        #else
        return false
        #endif
    }()

    /// A frame the size of 20 ms of AAC-LC voice at 32 kbps — which is what
    /// the real thing would send, 50 times a second per speaker. Measuring
    /// with a token-sized message would measure something we would never do.
    public static let frameBytes = 80
    /// START GENTLE. Fifty a second is what a voice needs, but opening at
    /// that rate tells us nothing if the session dies — we would not know
    /// whether the transport failed at 50/s or at 5/s. The rate climbs, so a
    /// failure has a NUMBER attached to it.
    public static let framesPerSecond = 50
    private var currentRate = 5

    public private(set) var sent = 0
    public private(set) var echoed = 0
    /// Frames the peer sent us that we bounced back.
    public private(set) var bounced = 0
    public private(set) var lastRoundTripMs: Double = 0
    public private(set) var worstRoundTripMs: Double = 0
    public private(set) var meanRoundTripMs: Double = 0
    public private(set) var note: String = "not started"
    /// Sends the messenger REFUSED, and the last reason. A transport that is
    /// rejecting frames must not read as one that is merely quiet.
    public private(set) var sendErrors = 0
    public private(set) var lastSendError: String?

    private var messenger: GroupSessionMessenger?
    private var pump: Task<Void, Never>?
    private var receive: Task<Void, Never>?
    private var sendTimes: [UInt32: CFAbsoluteTime] = [:]
    private var rtts: [Double] = []
    private var seq: UInt32 = 0

    public init() {}

    /// Starts against a live session. The messenger is built UNRELIABLE, which
    /// is the mode a voice wants: a frame that arrives late is worthless, and
    /// retransmitting it ahead of the next one makes the conversation worse.
    public func start<A: GroupActivity>(session: GroupSession<A>) {
        stop()
        let m = GroupSessionMessenger(session: session, deliveryMode: .unreliable)
        messenger = m
        note = "running"

        receive = Task { [weak self] in
            for await (data, _) in m.messages(of: Data.self) {
                await self?.handle(data, via: m)
            }
        }

        pump = Task { [weak self] in
            // RAMP: 5/s for three seconds, then 15, then 30, then 50. If the
            // session dies, it died at a rate we can name.
            let ladder = [(5, 3.0), (15, 3.0), (30, 3.0), (Self.framesPerSecond, 60.0)]
            for (rate, seconds) in ladder {
                if Task.isCancelled { return }
                await MainActor.run { self?.currentRate = rate }
                let period = UInt64(1_000_000_000 / UInt64(rate))
                let deadline = Date().addingTimeInterval(seconds)
                while !Task.isCancelled && Date() < deadline {
                    await self?.emit(via: m)
                    try? await Task.sleep(nanoseconds: period)
                }
            }
            // AND THEN IT STOPS. A measurement that runs for the life of the
            // call is not a measurement, it is a load test nobody asked for.
            await MainActor.run { self?.note = "finished"; self?.stopPumpOnly(); self?.persist() }
        }
    }

    /// Frame layout: [0] tag, [1..4] sequence, rest padding to `frameBytes`.
    /// Tag 1 is an outbound probe, tag 2 is that probe coming back.
    private func emit(via m: GroupSessionMessenger) async {
        seq &+= 1
        let payload = VoiceFrame.encode(tag: VoiceFrame.tagProbe, seq: seq,
                                        size: Self.frameBytes)
        sendTimes[seq] = CFAbsoluteTimeGetCurrent()
        // Do not let the table grow without bound on a link that eats frames.
        if sendTimes.count > 400 {
            let cutoff = CFAbsoluteTimeGetCurrent() - 5
            sendTimes = sendTimes.filter { $0.value > cutoff }
        }
        sent += 1
        m.send(payload, to: .all) { [weak self] error in
            guard let error else { return }
            // NEVER SWALLOWED. An ignored error here is how a transport that
            // is refusing everything reads as a transport that is merely
            // quiet — the same shape as the OSStatus the Apple encoder threw
            // away for five minutes (§9).
            Task { @MainActor in
                self?.sendErrors += 1
                self?.lastSendError = "\(error)"
            }
        }
    }

    /// NEVER SUBSCRIPT A `Data` YOU DID NOT CREATE.
    ///
    /// This read `data[0]` and wrote `back[0] = 2`, and **`Data`'s subscript
    /// takes an ABSOLUTE INDEX, not an offset.** A `Data` handed back by a
    /// framework is routinely a SLICE whose `startIndex` is not zero, and
    /// `data[0]` on one of those traps — "Index out of range" — on every
    /// inbound frame. With the probe enabled by default that crashed both
    /// phones the instant a session carried anything. Owner: *"Lots of
    /// crashing."*
    ///
    /// `count` reads correctly on a slice, which is why the `>= 5` guard gave
    /// no warning: every check passed and the very next line trapped.
    ///
    /// Everything now goes through `withUnsafeBytes`, which is offset-based
    /// over the slice's own bytes, and the bounce is built as a FRESH `Data`
    /// rather than by mutating someone else's.
    private func handle(_ data: Data, via m: GroupSessionMessenger) async {
        guard let parsed = VoiceFrame.decode(data) else { return }

        if parsed.tag == VoiceFrame.tagProbe {
            bounced += 1
            m.send(VoiceFrame.bounce(data, tag: VoiceFrame.tagEcho), to: .all) { _ in }
            return
        }
        guard parsed.tag == VoiceFrame.tagEcho, let t0 = sendTimes.removeValue(forKey: parsed.seq) else { return }
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        echoed += 1
        lastRoundTripMs = ms
        worstRoundTripMs = max(worstRoundTripMs, ms)
        rtts.append(ms)
        if rtts.count > 500 { rtts.removeFirst(rtts.count - 500) }
        meanRoundTripMs = rtts.reduce(0, +) / Double(rtts.count)
    }

    /// What the measurement says, in the terms the decision needs.
    public var verdict: String {
        guard echoed > 0 else { return "no frames have come back yet" }
        let delivered = Double(echoed) / Double(max(sent, 1)) * 100
        let oneWay = meanRoundTripMs / 2
        return String(format:
            "rate %d/s, sent %d, echoed %d (%.0f%%), refused %d, "
            + "round trip mean %.0f ms / worst %.0f ms, one-way ~%.0f ms — %@",
            currentRate, sent, echoed, delivered, sendErrors,
            meanRoundTripMs, worstRoundTripMs, oneWay,
            // 150 ms one-way is the usual ceiling for a conversation feeling
            // live; past ~250 ms people start talking over each other.
            (oneWay < 150 && delivered > 90)
                ? "GOOD ENOUGH for a conversation"
                : "NOT good enough — the guest transport must be ours")
    }

    /// Stops SENDING but keeps listening, so frames still in flight are
    /// still counted and still bounced for the peer.
    func stopPumpOnly() {
        pump?.cancel(); pump = nil
    }

    /// THE VERDICT GOES TO ITS OWN FILE, unconditionally in DEBUG.
    ///
    /// `awdiag` writes to disk only when `AW_DIAG_FILE=1`, which a
    /// devicectl launch sets and a TAP does not. This probe must be tapped —
    /// a devicectl-launched app is killed the moment it is backgrounded to
    /// start the call — so routing its answer through `DiagFile` meant the one
    /// launch method that works is the one that records nothing. The
    /// measurement would have been taken and then thrown away.
    ///
    /// Its own file, its own rule: if the probe ran, the number is readable.
    func persist() {
        #if DEBUG
        let line = ISO8601DateFormatter().string(from: Date()) + "  " + verdict + "\n"
        guard let dir = FileManager.default.urls(for: .cachesDirectory,
                                                 in: .userDomainMask).first else { return }
        let url = dir.appendingPathComponent("awvoice.log")
        if let data = line.data(using: .utf8) {
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: url)
            }
        }
        #endif
    }

    public func stop() {
        pump?.cancel(); pump = nil
        receive?.cancel(); receive = nil
        messenger = nil
        sendTimes.removeAll()
        note = "stopped"
    }
}
#endif
