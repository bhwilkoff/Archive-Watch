// §8.27 — keeping the film in sync without SharePlay (SHAREPLAY §11).
//
// The arithmetic here is the part most likely to be quietly wrong, and unlike
// a broadcast it can be exercised with controls on any machine. Three claims
// carry the design, and each is asserted against something that should fail:
//
//  • a host never sends the playhead, so extrapolation must be exact — and a
//    PAUSED film must not advance, which an elapsed-time formula gets wrong
//    the moment it forgets to ask;
//  • the clock offset must come from the FASTEST sample, never the average,
//    because the error bound is RTT/2 — the control is an averaging estimator
//    that one slow sample drags off by hundreds of milliseconds;
//  • drift is closed by RATE, not by seeking (Decision 081), so the
//    thresholds must be ordered and the nudge must point the right way. A
//    nudge with the sign inverted would drive a guest further out and is the
//    single easiest mistake to make here.
import Foundation

@main
struct StudioSyncTest {
    static var failures = 0
    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "PASS" : "FAIL") \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures += 1 }
    }
    static func near(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }

    static func main() {
        print("=== §8.27 cross-platform film sync ===")

        // ---- §11.1 extrapolation
        let playing = StudioSync.State(filmID: "caligari", position: 100,
                                       atServerTime: 1000, rate: 1.0, paused: false)
        check("a playing film advances with server time",
              near(playing.expectedPosition(atServerTime: 1030), 130),
              "\(playing.expectedPosition(atServerTime: 1030))")
        check("at the instant it was published it is exactly the published position",
              near(playing.expectedPosition(atServerTime: 1000), 100))

        let paused = StudioSync.State(filmID: "caligari", position: 100,
                                      atServerTime: 1000, rate: 1.0, paused: true)
        check("A PAUSED FILM DOES NOT ADVANCE",
              near(paused.expectedPosition(atServerTime: 1030), 100),
              "\(paused.expectedPosition(atServerTime: 1030)) — an elapsed-time formula that forgets to ask returns 130")

        // A clock that has gone backwards must not rewind the film.
        check("a server time BEFORE the record does not rewind the film",
              near(playing.expectedPosition(atServerTime: 990), 100))

        // ---- §11.2 the clock, and why the minimum
        // The server is 5.000 s ahead of this client. One clean exchange and
        // two congested ones.
        //
        // THE DELAYS MUST BE ASYMMETRIC, and that is the whole point rather
        // than a detail of the fixture. Under SYMMETRIC delay Cristian's
        // algorithm is EXACT at any round trip — the first version of this
        // test used symmetric slow samples, every estimate came out at exactly
        // 5.000, and the control correctly refused to pass. A fast sample is
        // not better because it is fast; it is better because the asymmetry it
        // can hide is bounded by RTT/2.
        //
        //  A: out 10 ms, back 10 ms   → exact
        //  B: out 700 ms, back 100 ms → reads 300 ms late
        //  C: out 800 ms, back 200 ms → reads 300 ms late
        // B and C lean the same way, as a congested uplink really does.
        let samples = [
            StudioSync.ClockSample(sentAt: 0.00, serverTime: 5.010, receivedAt: 0.020),
            StudioSync.ClockSample(sentAt: 1.00, serverTime: 6.700, receivedAt: 1.800),
            StudioSync.ClockSample(sentAt: 2.00, serverTime: 7.800, receivedAt: 3.000),
        ]
        guard let best = StudioSync.bestOffset(from: samples) else {
            check("bestOffset returned something", false); exit(1)
        }
        check("the chosen sample is the FASTEST round trip",
              near(best.roundTrip, 0.020, 1e-9), String(format: "%.3f s", best.roundTrip))
        check("its offset is within its own error bound of the truth",
              abs(best.offset - 5.0) <= best.error,
              String(format: "offset %.4f, bound ±%.4f", best.offset, best.error))
        check("and that bound is tight", best.error <= 0.010,
              String(format: "±%.4f s", best.error))

        // THE CONTROL: averaging every sample, which is the obvious thing to
        // write and is wrong. It must be materially further from the truth.
        let averaged = samples.map(\.offset).reduce(0, +) / Double(samples.count)
        let bestErr = abs(best.offset - 5.0), avgErr = abs(averaged - 5.0)
        check("CONTROL: averaging is worse, and by enough to matter",
              avgErr > bestErr && avgErr > 0.100,
              String(format: "min-RTT off by %.4f s, average off by %.4f s", bestErr, avgErr))

        check("server time converts from a client clock",
              near(StudioSync.serverTime(clientNow: 10, offset: 5), 15))

        // ---- §11.3 corrections
        func corr(local: Double, paused: Bool = false, now: Double) -> StudioSync.Correction {
            StudioSync.correction(localPosition: local, localPaused: paused,
                                  state: playing, serverNow: now)
        }
        // At server 1030 the film should be at 130.
        check("inside tolerance, do nothing", corr(local: 130.05, now: 1030) == .none)
        check("a guest BEHIND speeds up",
              corr(local: 129.0, now: 1030) == .nudge(rate: StudioSync.nudgeFast),
              "\(corr(local: 129.0, now: 1030))")
        check("a guest AHEAD slows down",
              corr(local: 131.0, now: 1030) == .nudge(rate: StudioSync.nudgeSlow),
              "\(corr(local: 131.0, now: 1030))")
        check("far behind, seek rather than nudge",
              corr(local: 120.0, now: 1030) == .seek(to: 130),
              "\(corr(local: 120.0, now: 1030))")
        check("far ahead, seek too",
              corr(local: 140.0, now: 1030) == .seek(to: 130))

        // THE CONTROL for the nudge direction: the two cases must DIFFER, or a
        // sign error would pass both of the assertions above.
        check("CONTROL: behind and ahead produce different corrections",
              corr(local: 129.0, now: 1030) != corr(local: 131.0, now: 1030))
        check("CONTROL: the fast nudge really is faster than the slow one",
              StudioSync.nudgeFast > 1.0 && StudioSync.nudgeSlow < 1.0)

        // Run state is applied at once and never eased.
        check("a host's pause reaches a playing guest immediately",
              StudioSync.correction(localPosition: 130, localPaused: false,
                                    state: paused, serverNow: 1030) == .setPaused(true))
        check("a paused film in step needs no correction",
              StudioSync.correction(localPosition: 100, localPaused: true,
                                    state: paused, serverNow: 1030) == .none)
        // A paused film cannot DRIFT, but it can be on the wrong FRAME: a host
        // pauses to talk about a shot, and the guests must see that shot.
        // (This asserted the opposite until 2026-09-23, when a Mac guest was
        // measured paused 4.7 s past the host's frame.)
        check("a paused guest on the WRONG FRAME is moved to the host's",
              StudioSync.correction(localPosition: 104.7, localPaused: true,
                                    state: paused, serverNow: 1030) == .seek(to: 100),
              "\(StudioSync.correction(localPosition: 104.7, localPaused: true, state: paused, serverNow: 1030))")
        check("and one within tolerance of it is left alone",
              StudioSync.correction(localPosition: 100.1, localPaused: true,
                                    state: paused, serverNow: 1030) == .none)
        check("the frame is the paused POSITION, not an elapsed-time guess",
              StudioSync.correction(localPosition: 10, localPaused: true,
                                    state: paused, serverNow: 5000) == .seek(to: 100))

        // Thresholds must be ordered, or a band disappears silently.
        check("tolerance is below the seek threshold",
              StudioSync.toleranceSeconds < StudioSync.seekThresholdSeconds)

        // ---- §11.6 backoff
        check("a busy room polls fast",
              near(StudioSync.pollInterval(secondsSinceGenerationChanged: 5),
                   StudioSync.pollFastSeconds))
        check("a quiet room backs off",
              near(StudioSync.pollInterval(secondsSinceGenerationChanged: 120),
                   StudioSync.pollIdleSeconds))
        check("CONTROL: the two intervals differ, or backoff saves nothing",
              StudioSync.pollIdleSeconds > StudioSync.pollFastSeconds)

        // The free tier is the constraint that chose this transport, so assert
        // the arithmetic rather than trusting the estimate in the doc.
        let guests = 4.0, hours = 2.0
        let reads = guests * (hours * 3600 / StudioSync.pollFastSeconds)
        check("four guests for two hours stays well inside a free daily read budget",
              reads < 100_000, String(format: "%.0f reads", reads))

        // THE HOST'S SIDE: when must it republish? Against the ROOM's clock.
        check("a host playing on schedule does not republish",
              !StudioSync.hostShouldRepublish(position: 130, lastPosition: 100, lastPaused: false,
                                              lastRate: 1, secondsSincePublish: 30))
        check("a host a stall left 5 s behind DOES republish",
              StudioSync.hostShouldRepublish(position: 125, lastPosition: 100, lastPaused: false,
                                             lastRate: 1, secondsSincePublish: 30))
        // CONTROL: the old rule compared each half-second sample with the one
        // before (baseline reset every tick), so a 0.5 s tick that saw no
        // progress read as within tolerance and the stall was never said.
        check("control: the per-tick comparison misses that stall",
              !StudioSync.hostShouldRepublish(position: 110, lastPosition: 110, lastPaused: false,
                                              lastRate: 1, secondsSincePublish: 0.5))
        check("a paused host that has not moved does not republish",
              !StudioSync.hostShouldRepublish(position: 100, lastPosition: 100, lastPaused: true,
                                              lastRate: 1, secondsSincePublish: 600))
        check("a paused host that seeks does",
              StudioSync.hostShouldRepublish(position: 40, lastPosition: 100, lastPaused: true,
                                             lastRate: 1, secondsSincePublish: 5))
        check("a 1.25x host on schedule does not",
              !StudioSync.hostShouldRepublish(position: 125, lastPosition: 100, lastPaused: false,
                                              lastRate: 1.25, secondsSincePublish: 20))

        // THE HOST'S COPY (2026-09-26): the same table as the Worker's
        // normalizeCopy and the web's copyURL, so no client can be sent to a
        // file the others would refuse, or anywhere but archive.org.
        let good = URL(string: "https://archive.org/download/the-scarecrow/The%20Scarecrow.mp4")!
        check("a download URL becomes item/file",
              StudioRoomCopy.path(from: good) == "the-scarecrow/The Scarecrow.mp4")
        check("and back, exactly",
              StudioRoomCopy.url(fromPath: "the-scarecrow/The Scarecrow.mp4") == good)
        check("a file in a folder survives",
              StudioRoomCopy.url(fromPath: "reels/r/reel1.mov")?.absoluteString
                == "https://archive.org/download/reels/r/reel1.mov")
        check("another host is not a copy",
              StudioRoomCopy.path(from: URL(string: "https://evil.example/download/a/b.mp4")) == nil)
        for bad in ["https://evil.example/x.mp4", "//evil.example/x.mp4", "a/../b.mp4",
                    "the-scarecrow", "the-scarecrow/", "bad item!/x.mp4", "a/b\u{0}.mp4"] {
            check("refused: \(bad.debugDescription)", StudioRoomCopy.url(fromPath: bad) == nil)
        }
        // In a room the HOST's file wins; outside one, nothing is overridden.
        let fallback = URL(string: "https://archive.org/download/TheScarecrow1920/default.mp4")!
        StudioRoomCopy.clear()
        check("no room: no override", StudioRoomCopy.url(for: "TheScarecrow1920", default: fallback) == nil)
        StudioRoomCopy.set(film: "TheScarecrow1920", copy: "the-scarecrow/The Scarecrow.mp4")
        check("in a room: the host's copy",
              StudioRoomCopy.url(for: "TheScarecrow1920", default: fallback) == good)
        check("another film is untouched",
              StudioRoomCopy.url(for: "Metropolis", default: fallback) == nil)
        StudioRoomCopy.set(film: "TheScarecrow1920", copy: nil)
        check("an older host: the DEFAULT copy, not the viewer's",
              StudioRoomCopy.url(for: "TheScarecrow1920", default: fallback) == fallback)
        StudioRoomCopy.clear()

        print(failures == 0 ? "=== §8.27 OK ===" : "=== §8.27 \(failures) FAILURES ===")
        exit(failures == 0 ? 0 : 1)
    }
}
