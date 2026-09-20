// The guests, mixed — SHAREPLAY §5.4's half of the feature.
//
// One of these lives on the HOST. Each remote participant gets a jitter
// buffer and its own decoder; every 20 ms the room pulls one frame from each,
// sums them, and hands the result to the Studio mixer as one more input
// beside the film and the host's own microphone. It also produces a
// MIX-MINUS per participant — everyone except themselves — because a guest
// who hears their own voice back is a guest who stops talking.
//
// IT KNOWS NOTHING ABOUT THE TRANSPORT, deliberately. SHAREPLAY §7 leaves
// that decision on one measurement (can the SharePlay messenger carry ~50
// small frames a second?), and the answer changes nothing here: packets
// arrive with a participant and a sequence number, from Apple's messenger or
// from our own UDP, and this behaves identically. Building it first means the
// transport question stops blocking the feature.
//
// THE THREE THINGS A VOICE MIXER GETS WRONG, each paid for elsewhere in this
// project and each tested in §8.20:
//
//  · **Ordering.** An unreliable transport reorders. A buffer that plays
//    packets as they arrive scrambles a voice exactly as §9.jjjjj's LIFO ring
//    scrambled a film — real audio, right level, no discontinuities, and
//    unintelligible.
//  · **Gaps.** A lost packet must become CONCEALMENT, not a hole. Opus has
//    packet-loss concealment built in; the buffer must ask for it rather than
//    emit a click.
//  · **Clipping.** Summing four voices overflows. An Int16 that wraps is not
//    loud, it is a crack on every peak — the same rule Android's mixer
//    carries.

import Foundation

/// Who is speaking. Opaque so the transport can define identity however it
/// likes — a SharePlay `Participant`, a socket, a name.
public struct VoiceParticipant: Hashable, Sendable {
    public let id: String
    public init(_ id: String) { self.id = id }
}

public final class StudioVoiceRoom {

    /// How many frames to hold before playing one out.
    ///
    /// Three frames is 60 ms, spent straight out of §5.3's conversational
    /// budget — but a buffer shallower than the network's jitter underruns,
    /// and an underrun is a gap in someone's sentence. 60 ms of depth against
    /// 22 ms of codec delay each way still leaves room inside 150 ms.
    public static let targetDepth = 3
    /// Past this, the transport is delivering faster than real time and the
    /// oldest audio is no longer live — the same rule as the microphone's
    /// 120 ms bound.
    public static let maxDepth = 8

    public private(set) var participants: [VoiceParticipant] = []

    /// Frames played out, and frames that were not there when their turn came.
    public private(set) var framesPlayed = 0
    public private(set) var framesConcealed = 0
    public private(set) var framesDroppedLate = 0
    /// Frames binned because the sender outran us past `maxDepth`. Separate
    /// from `framesDroppedLate`: one is the network reordering, the other is
    /// this buffer refusing to grow, and they need different answers.
    public private(set) var framesDroppedOverflow = 0

    private struct Stream {
        var codec: StudioVoiceCodec
        /// Sequence -> packet, so arrival order cannot become playback order.
        var pending: [UInt32: Data] = [:]
        /// The next sequence this stream will play. Nil until the first packet.
        var next: UInt32?
        var scratch: [Float]
    }
    private var streams: [VoiceParticipant: Stream] = [:]

    public init() {}

    /// A packet from the wire. Cheap and allocation-light: this runs on
    /// whatever thread the transport delivers on.
    public func receive(_ packet: Data, from who: VoiceParticipant, sequence: UInt32) {
        if streams[who] == nil {
            guard let c = StudioVoiceCodec() else { return }
            streams[who] = Stream(codec: c,
                                  scratch: [Float](repeating: 0,
                                                   count: StudioVoiceCodec.frameSamples))
            participants.append(who)
        }
        guard var s = streams[who] else { return }
        // A packet whose turn has already passed is not late, it is GONE:
        // playing it now would put a syllable out of order, which is worse
        // than the concealment a gap already gets.
        //
        // BUT ONLY ONCE PLAYBACK HAS STARTED. The first version set `next` to
        // the first sequence that ARRIVED, which on a reordering transport is
        // not the lowest — deliver 3,1,4,0,2 and it took 3 as the start, then
        // discarded 1, 0 and 2 as "late" before a single frame had played.
        // §8.20 caught it: three packets thrown away in the very test written
        // to prove reordering works. `next` is now chosen at FIRST PLAYBACK,
        // from the lowest sequence actually in hand.
        if let next = s.next, sequence < next {
            framesDroppedLate += 1
            streams[who] = s
            return
        }
        s.pending[sequence] = packet
        // Runaway guard: if the far end outruns us, skip forward rather than
        // grow without bound and play minutes-old speech.
        //
        // AND IT IS COUNTED. The first version evicted SILENTLY, and §8.20
        // caught what that hides: a test that dropped packet 2 to prove
        // concealment saw no concealment at all, because the guard had already
        // thrown packet 2 away and playback simply began later. Audio
        // discarded without a counter is the defect class this project keeps
        // finding — the camera counter nobody read (§9.kkkkk), the ring
        // overflow nobody read (§9.jjjjj). A buffer that quietly bins speech
        // must say how much.
        if s.pending.count > Self.maxDepth, let lowest = s.pending.keys.min() {
            s.pending.removeValue(forKey: lowest)
            framesDroppedOverflow += 1
            if s.next == lowest { s.next = s.pending.keys.min() }
        }
        streams[who] = s
    }

    /// True once every stream has enough depth to start without underrunning.
    public var ready: Bool {
        !streams.isEmpty && streams.values.allSatisfy { $0.pending.count >= Self.targetDepth }
    }

    /// One 20 ms frame of everyone, summed. Returns samples written.
    public func mix(into out: UnsafeMutablePointer<Float>, capacity: Int) -> Int {
        render(into: out, capacity: capacity, excluding: nil)
    }

    /// The same, minus one participant — what that participant is sent, so
    /// they do not hear themselves.
    public func mixMinus(_ who: VoiceParticipant,
                         into out: UnsafeMutablePointer<Float>, capacity: Int) -> Int {
        render(into: out, capacity: capacity, excluding: who)
    }

    private func render(into out: UnsafeMutablePointer<Float>, capacity: Int,
                        excluding: VoiceParticipant?) -> Int {
        let n = min(capacity, StudioVoiceCodec.frameSamples)
        guard n > 0 else { return 0 }
        for i in 0..<n { out[i] = 0 }

        for who in participants {
            guard who != excluding, var s = streams[who] else { continue }
            // Chosen here, not on arrival: see `receive`. The lowest sequence
            // in hand is the start, whatever order the transport delivered in.
            if s.next == nil { s.next = s.pending.keys.min() }
            guard let seq = s.next else { continue }
            var wrote = 0
            if let packet = s.pending.removeValue(forKey: seq) {
                wrote = s.scratch.withUnsafeMutableBufferPointer {
                    s.codec.decode(packet, into: $0.baseAddress!)
                }
            } else {
                // CONCEALED, not skipped. The sequence still advances, or one
                // lost packet desynchronises this speaker for the rest of the
                // call.
                framesConcealed += 1
                for i in 0..<s.scratch.count { s.scratch[i] = 0 }
                wrote = n
            }
            for i in 0..<min(wrote, n) { out[i] += s.scratch[i] }
            s.next = seq &+ 1
            streams[who] = s
        }

        // CLIP, NEVER WRAP. Four voices at once exceed 1.0 and a consumer that
        // converts to Int16 would wrap to the opposite sign — not loudness, a
        // crack on every peak, and it would be blamed on the encoder.
        for i in 0..<n { out[i] = max(-1.0, min(1.0, out[i])) }
        framesPlayed += 1
        return n
    }

    /// Someone left. Their buffer goes with them; a stream nobody feeds would
    /// otherwise conceal a silent frame forever.
    public func remove(_ who: VoiceParticipant) {
        streams.removeValue(forKey: who)
        participants.removeAll { $0 == who }
    }
}
