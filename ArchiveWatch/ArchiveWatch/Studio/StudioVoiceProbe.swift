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
    public static let enabled: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["AW_VOICE_PROBE"] == "1"
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
            while !Task.isCancelled {
                await self?.emit(via: m)
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 / UInt64(Self.framesPerSecond)))
            }
        }
    }

    /// Frame layout: [0] tag, [1..4] sequence, rest padding to `frameBytes`.
    /// Tag 1 is an outbound probe, tag 2 is that probe coming back.
    private func emit(via m: GroupSessionMessenger) async {
        seq &+= 1
        var payload = Data(count: Self.frameBytes)
        payload[0] = 1
        withUnsafeBytes(of: seq.littleEndian) { raw in
            for i in 0..<4 { payload[1 + i] = raw[i] }
        }
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

    private func handle(_ data: Data, via m: GroupSessionMessenger) async {
        guard data.count >= 5 else { return }
        let tag = data[0]
        let n = data.withUnsafeBytes { raw -> UInt32 in
            var v: UInt32 = 0
            withUnsafeMutableBytes(of: &v) { out in
                for i in 0..<4 { out[i] = raw[1 + i] }
            }
            return UInt32(littleEndian: v)
        }
        if tag == 1 {
            // A peer's probe. Bounce the SAME bytes back, changing only the
            // tag, so the round trip carries a real frame in both directions.
            var back = data
            back[0] = 2
            bounced += 1
            m.send(back, to: .all) { _ in }
            return
        }
        guard tag == 2, let t0 = sendTimes.removeValue(forKey: n) else { return }
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

    public func stop() {
        pump?.cancel(); pump = nil
        receive?.cancel(); receive = nil
        messenger = nil
        sendTimes.removeAll()
        note = "stopped"
    }
}
#endif
