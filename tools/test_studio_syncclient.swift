// §8.31 — the sync CLIENT against a running Worker (SHAREPLAY §11).
//
// §8.27 proves the arithmetic and §8.30 proves the routes. Neither says the
// two are wired together correctly, which is Decision 133's whole point: a
// control is proved where its value LANDS. So this runs a real host and a real
// guest against `wrangler dev`, and asserts that what the host publishes is
// what the guest's player would be told to do.
//
//   AW_TOGETHER_BASE=http://127.0.0.1:8799 ./t831
import Foundation

@main
struct SyncClientTest {
    static var failures = 0
    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "PASS" : "FAIL") \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures += 1 }
    }

    static func main() async {
        let raw = ProcessInfo.processInfo.environment["AW_TOGETHER_BASE"]
            ?? "http://127.0.0.1:8799"
        guard let base = URL(string: raw) else { print("bad base"); exit(2) }
        print("=== §8.31 sync client, live (\(raw)) ===")

        let cfg = StudioSyncClient.Config(base: base)
        let host = StudioSyncClient(config: cfg)
        let guest = StudioSyncClient(config: cfg)
        let film = "ptp_the-love-nest_buster-keaton_blu-ray_h264_1080p_430833"

        // ---- the host opens a room
        guard let code = try? await host.createRoom(filmID: film, position: 60) else {
            check("the host creates a room", false, "could not reach \(raw)")
            print("=== §8.31 cannot continue (is `wrangler dev` running?) ===")
            exit(2)
        }
        check("the host creates a room", code.count == StudioRoom.codeLength, code)

        // ---- a guest joins BY THE CODE AS HEARD, not as generated
        let heard = code.replacingOccurrences(of: "1", with: "I")
                        .replacingOccurrences(of: "0", with: "O")
                        .lowercased()
        guard let joined = try? await guest.join(code: heard) else {
            check("a guest joins with the code as HEARD", false, heard)
            await host.endRoom(); exit(1)
        }
        check("a guest joins with the code as HEARD", joined.filmID == film,
              "typed \"\(heard)\" for \(code)")
        check("the guest sees the host's position", joined.position == 60,
              "\(joined.position)")

        // ---- the clock estimate exists and is bounded
        let off = await guest.clockOffset
        check("the guest has a clock offset with an error bound", off != nil,
              off.map { String(format: "%.4f ± %.4f s", $0.offset, $0.error) } ?? "nil")
        check("against a local Worker the bound is tight", (off?.error ?? 99) < 0.5,
              String(format: "±%.4f s", off?.error ?? 99))

        // ---- a guest who is exactly right is left alone
        let now = await guest.serverNow
        let expected = joined.expectedPosition(atServerTime: now)
        let c0 = await guest.correction(localPosition: expected, localPaused: false)
        check("a guest in step is not corrected", c0 == StudioSync.Correction.none, "\(c0!)")

        // ---- a guest who has fallen behind is told to catch up
        let c1 = await guest.correction(localPosition: expected - 1.0, localPaused: false)
        check("a guest 1 s BEHIND is nudged faster",
              c1 == .nudge(rate: StudioSync.nudgeFast), "\(c1!)")
        let c2 = await guest.correction(localPosition: expected - 30, localPaused: false)
        if case .seek = c2! { check("a guest 30 s behind is SEEKED", true) }
        else { check("a guest 30 s behind is SEEKED", false, "\(c2!)") }

        // ---- THE END TO END CLAIM: the host pauses, and the guest's player
        //      is told to pause. Nothing else in this suite asserts that the
        //      publish, the poll and the arithmetic agree.
        try? await host.publish(filmID: film, position: 75, paused: true)
        _ = try? await guest.poll()
        let c3 = await guest.correction(localPosition: expected, localPaused: false)
        check("THE HOST PAUSES AND THE GUEST IS TOLD TO PAUSE",
              c3 == .setPaused(true), "\(c3!)")
        let s = await guest.lastState
        check("and the guest sees the host's new position", s?.position == 75,
              "\(s?.position ?? -1)")

        // CONTROL: resuming must reverse it, or "setPaused" could be a
        // one-way latch that happens to read true.
        try? await host.publish(filmID: film, position: 80, paused: false)
        _ = try? await guest.poll()
        let c4 = await guest.correction(localPosition: 80, localPaused: true)
        check("CONTROL: the host resumes and the guest is told to resume",
              c4 == .setPaused(false), "\(c4!)")

        // ---- the generation moved, so the guest polls fast
        let delay = await guest.nextPollDelay
        check("a room that just changed is polled fast",
              delay == StudioSync.pollFastSeconds, "\(delay)s")

        // ---- ending really ends
        await host.endRoom()
        do {
            _ = try await guest.poll()
            check("a guest polling an ENDED room is told so", false, "poll succeeded")
        } catch {
            let isGone = (error as? StudioSyncClient.JoinError).map {
                if case .noSuchRoom = $0 { return true }
                if case .ended = $0 { return true }
                return false
            } ?? false
            check("a guest polling an ENDED room is told so", isGone, "\(error)")
        }

        print(failures == 0 ? "=== §8.31 OK ===" : "=== §8.31 \(failures) FAILURES ===")
        exit(failures == 0 ? 0 : 1)
    }
}
