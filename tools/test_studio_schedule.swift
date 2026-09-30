// §8.73 — a watch-along scheduled ahead of time (macOS-DESIGN §D39).
//
// Every request the schedule feature makes is sent to a LOCAL mock of the
// YouTube live endpoints (tools/mock_youtube_live.py) and read back from the
// mock's own log — never from our own belief about what we sent (Decision 133).
// No account, no token, no network: the base URLs point at 127.0.0.1.
//
// It compiles the REAL sources (Decision 119), including the overlay renderer,
// so the thumbnail the mock receives is the Starting-soon card itself:
//
//   bash tools/test_studio_all.sh   (case "8.73 scheduled watch-along")
//
// THE CONTROL: the "no liveBroadcasts.insert" check is run against `prepare`,
// which DOES insert, and must report the insert. A detector that cannot see an
// insert would pass `credentials(forScheduled:)` for the wrong reason.

import CoreGraphics
import Foundation
import ImageIO

@main
struct ScheduleTest {
    nonisolated(unsafe) static var pass = 0
    nonisolated(unsafe) static var fail = 0
    nonisolated(unsafe) static var port = 0

    static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if ok { pass += 1; print("  PASS  \(name)") }
        else  { fail += 1; print("  FAIL  \(name)\(detail.isEmpty ? "" : " — \(detail)")") }
    }

    typealias Req = [String: Any]

    static var yt: YouTubeLive {
        YouTubeLive(token: "mock-token-not-a-credential",
                    base: "http://127.0.0.1:\(port)/youtube/v3",
                    uploadBase: "http://127.0.0.1:\(port)/upload/youtube/v3")
    }

    static func control(_ path: String, method: String = "GET") async -> Data? {
        var r = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        r.httpMethod = method
        return try? await URLSession.shared.data(for: r).0
    }

    static func reset(_ scenario: String) async { _ = await control("/__reset?scenario=\(scenario)", method: "POST") }

    static func log() async -> [Req] {
        guard let d = await control("/__log"),
              let a = try? JSONSerialization.jsonObject(with: d) as? [Req] else { return [] }
        return a
    }

    static func calls(_ log: [Req], _ method: String, _ path: String) -> [Req] {
        log.filter { ($0["method"] as? String) == method && ($0["path"] as? String) == path }
    }

    static func summary(_ log: [Req]) -> String {
        log.map { "\($0["method"] ?? "?") \($0["path"] ?? "?")" }.joined(separator: ", ")
    }

    /// The insert detector — the thing the control proves can fail.
    static func insertedBroadcast(_ log: [Req]) -> Bool {
        !calls(log, "POST", "/youtube/v3/liveBroadcasts").isEmpty
    }

    static func main() async {
        print("=== §8.73 scheduled watch-along, against a local mock ===\n")
        let mock = Process()
        mock.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        mock.arguments = ["python3", "tools/mock_youtube_live.py"]
        let out = Pipe()
        mock.standardOutput = out
        do { try mock.run() } catch { print("SKIP no python3 — \(error)"); exit(2) }
        let first = String(decoding: out.fileHandleForReading.availableData, as: UTF8.self)
        guard let p = first.split(separator: " ").last.flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) })
        else { print("FAIL the mock did not report a port: \(first)"); mock.terminate(); exit(1) }
        port = p
        print("mock on 127.0.0.1:\(port)\n")

        let jpeg = StudioOverlayRenderer(size: CGSize(width: 1280, height: 720))
            .scheduledCardJPEG(film: "The General", detail: "1926 \u{00B7} Buster Keaton")
        await thumbnailIsTheCard(jpeg)
        await scheduleShape(jpeg)
        await bindFailureDeletes(jpeg)
        await thumbnailRefusalKeepsBroadcast(jpeg)
        await rescheduleSendsWholeSnippet()
        await goLiveOnScheduledInsertsNothing()
        await goneIsSaid()
        await controlDetectorSeesAnInsert()
        storeRules()

        mock.terminate()
        print("\npass=\(pass) fail=\(fail)")
        exit(fail == 0 ? 0 : 1)
    }

    static func thumbnailIsTheCard(_ jpeg: Data?) async {
        print("-- the thumbnail is the Starting-soon card, 1280x720 JPEG")
        guard let jpeg, let src = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            check("the renderer produced a JPEG", false); return
        }
        check("the renderer produced a JPEG", jpeg.prefix(2) == Data([0xFF, 0xD8]))
        check("it is 1280x720", img.width == 1280 && img.height == 720, "\(img.width)x\(img.height)")
    }

    static func scheduleShape(_ jpeg: Data?) async {
        print("\n-- schedule: stream, broadcast in the FUTURE, bind, thumbnail")
        await reset("ok")
        let start = Date().addingTimeInterval(3 * 24 * 3600)
        do {
            let s = try await yt.schedule(title: "The General", description: "d",
                                          privacy: "unlisted", start: start, thumbnail: jpeg)
            check("schedule returns the broadcast and stream ids",
                  s.broadcastID == "bc-1" && s.streamID == "stream-1")
            check("a card that was accepted leaves no refusal", s.thumbnailRefusal == nil)
        } catch { check("schedule succeeds", false, "\(error)") }
        let l = await log()
        let order = l.map { "\($0["method"] ?? "") \($0["path"] ?? "")" }
        check("the calls are insert stream, insert broadcast, bind, thumbnail — in that order",
              order == ["POST /youtube/v3/liveStreams", "POST /youtube/v3/liveBroadcasts",
                        "POST /youtube/v3/liveBroadcasts/bind", "POST /upload/youtube/v3/thumbnails/set"],
              summary(l))
        let bc = calls(l, "POST", "/youtube/v3/liveBroadcasts").first
        let snippet = (bc?["json"] as? Req)?["snippet"] as? Req
        let sent = (snippet?["scheduledStartTime"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        check("scheduledStartTime is the host's future time",
              sent.map { abs($0.timeIntervalSince(start)) < 1.5 && $0 > Date() } ?? false,
              "\(snippet?["scheduledStartTime"] ?? "none")")
        let cd = (bc?["json"] as? Req)?["contentDetails"] as? NSDictionary
        check("contentDetails are EXACTLY the go-live ones",
              cd == (YouTubeLive.broadcastContentDetails as NSDictionary), "\(cd ?? [:])")
        check("privacy is the host's", ((bc?["json"] as? Req)?["status"] as? Req)?["privacyStatus"] as? String == "unlisted")
        let bind = calls(l, "POST", "/youtube/v3/liveBroadcasts/bind").first?["query"] as? Req
        check("bind joins THIS broadcast to THIS stream",
              bind?["id"] as? String == "bc-1" && bind?["streamId"] as? String == "stream-1")
        let th = calls(l, "POST", "/upload/youtube/v3/thumbnails/set").first
        check("thumbnails.set names the broadcast", (th?["query"] as? Req)?["videoId"] as? String == "bc-1")
        check("and carries the card as image/jpeg",
              th?["contentType"] as? String == "image/jpeg"
              && (th?["bodyHead"] as? String)?.hasPrefix("ffd8") == true
              && th?["bodyLength"] as? Int == jpeg?.count,
              "\(th?["contentType"] ?? "") \(th?["bodyLength"] ?? 0) bytes")

        // The same comparison against go-live's own request, not the constant.
        await reset("ok")
        _ = try? await yt.prepare(title: "t", description: "d", privacy: "unlisted")
        let live = calls(await log(), "POST", "/youtube/v3/liveBroadcasts").first
        check("a scheduled show and a live one send the same contentDetails",
              ((live?["json"] as? Req)?["contentDetails"] as? NSDictionary) == cd)
    }

    static func bindFailureDeletes(_ jpeg: Data?) async {
        print("\n-- a failed bind deletes the broadcast it made")
        await reset("bindfail")
        do {
            _ = try await yt.schedule(title: "t", description: "d", privacy: "public",
                                      start: Date().addingTimeInterval(7200), thumbnail: jpeg)
            check("the failure reaches the host", false, "schedule SUCCEEDED")
        } catch { check("the failure reaches the host", true) }
        let l = await log()
        let del = calls(l, "DELETE", "/youtube/v3/liveBroadcasts")
        check("the new broadcast is deleted", del.count == 1 && (del[0]["query"] as? Req)?["id"] as? String == "bc-1",
              summary(l))
        check("no thumbnail is uploaded for a broadcast that was deleted",
              calls(l, "POST", "/upload/youtube/v3/thumbnails/set").isEmpty)
    }

    static func thumbnailRefusalKeepsBroadcast(_ jpeg: Data?) async {
        print("\n-- a refused thumbnail keeps the broadcast")
        await reset("thumbfail")
        do {
            let s = try await yt.schedule(title: "t", description: "d", privacy: "public",
                                          start: Date().addingTimeInterval(7200), thumbnail: jpeg)
            check("the schedule succeeds", s.broadcastID == "bc-1")
            check("and carries YouTube's refusal as one line",
                  s.thumbnailRefusal?.contains("not allowed custom thumbnails") == true,
                  s.thumbnailRefusal ?? "nil")
        } catch { check("the schedule succeeds", false, "\(error)") }
        check("nothing is deleted", calls(await log(), "DELETE", "/youtube/v3/liveBroadcasts").isEmpty)
    }

    static func rescheduleSendsWholeSnippet() async {
        print("\n-- reschedule sends the whole snippet")
        await reset("ok")
        let start = Date().addingTimeInterval(10 * 24 * 3600)
        do {
            try await yt.reschedule(broadcastID: "bc-1", title: "Moved title",
                                    description: "the description", start: start)
        } catch { check("reschedule succeeds", false, "\(error)") }
        let put = calls(await log(), "PUT", "/youtube/v3/liveBroadcasts").first
        let body = put?["json"] as? Req
        let sn = body?["snippet"] as? Req
        check("it is liveBroadcasts.update with part=snippet",
              (put?["query"] as? Req)?["part"] as? String == "snippet")
        check("it names the broadcast", body?["id"] as? String == "bc-1")
        check("title, description and the NEW start all go",
              sn?["title"] as? String == "Moved title"
              && sn?["description"] as? String == "the description"
              && (sn?["scheduledStartTime"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
                    .map { abs($0.timeIntervalSince(start)) < 1.5 } == true,
              "\(sn ?? [:])")
    }

    static func goLiveOnScheduledInsertsNothing() async {
        print("\n-- going live on a scheduled show inserts NOTHING")
        await reset("ok")
        do {
            let c = try await yt.credentials(forScheduled: "bc-1", streamID: "stream-1")
            check("the ingest is recovered from the stream, RTMPS preferred",
                  c.server.scheme == "rtmps" && c.key == "MOCK-KEY", c.server.absoluteString)
            check("the broadcast is the scheduled one, with its chat",
                  c.broadcastID == "bc-1" && c.liveChatID == "chat-1")
        } catch { check("credentials(forScheduled:) succeeds", false, "\(error)") }
        let l = await log()
        check("no liveBroadcasts.insert", !insertedBroadcast(l), summary(l))
        check("no liveStreams.insert, no bind, no thumbnail",
              calls(l, "POST", "/youtube/v3/liveStreams").isEmpty
              && calls(l, "POST", "/youtube/v3/liveBroadcasts/bind").isEmpty
              && calls(l, "POST", "/upload/youtube/v3/thumbnails/set").isEmpty, summary(l))
        check("exactly two reads (2 units)", l.count == 2
              && l.allSatisfy { ($0["method"] as? String) == "GET" }, summary(l))
        // The product path: StudioGoLive.destination takes this branch for a
        // scheduled request. A source check, because destination() needs the app.
        let src = (try? String(contentsOfFile: "ArchiveWatch/ArchiveWatch/Studio/StudioGoLive.swift",
                               encoding: .utf8)) ?? ""
        check("StudioGoLive routes a scheduled request to credentials(forScheduled:)",
              src.contains("if let show = request.scheduled")
              && src.contains("yt.credentials(forScheduled: show.broadcastID"))
    }

    static func goneIsSaid() async {
        print("\n-- a scheduled show deleted or ended on YouTube is SAID, not recreated")
        for sc in ["gone", "ended", "streamgone"] {
            await reset(sc)
            do {
                _ = try await yt.credentials(forScheduled: "bc-1", streamID: "stream-1")
                check("\(sc): refused", false, "it returned credentials")
            } catch StudioPlatformError.scheduledGone(let why) {
                check("\(sc): scheduledGone — \(why)", true)
            } catch { check("\(sc): scheduledGone", false, "\(error)") }
            check("\(sc): and nothing was inserted", !insertedBroadcast(await log()))
        }
    }

    static func controlDetectorSeesAnInsert() async {
        print("\n-- CONTROL: the insert detector must fire on a path that inserts")
        await reset("ok")
        _ = try? await yt.prepare(title: "t", description: "d", privacy: "private")
        check("prepare() is seen inserting a broadcast (so the detector can fail)",
              insertedBroadcast(await log()))
    }

    static func storeRules() {
        print("\n-- the local list: never a key, pruned 12 h past start, matched by film")
        let d = UserDefaults(suiteName: "aw.test.schedule.\(UUID().uuidString)")!
        let now = Date()
        func show(_ id: String, _ film: String, _ h: Double) -> StudioScheduledShow {
            StudioScheduledShow(broadcastID: id, streamID: "s-\(id)", archiveID: film,
                                copy: "\(film)/\(film).mp4", title: id, description: "d",
                                start: now.addingTimeInterval(h * 3600), privacy: "unlisted")
        }
        StudioSchedule.save([show("future", "a", 48), show("late", "a", -11), show("stale", "a", -13),
                             show("other", "b", 5)], to: d)
        let kept = StudioSchedule.prune(now: now, defaults: d).map(\.broadcastID)
        check("a show 13 h past its start is dropped; 11 h is kept",
              Set(kept) == ["future", "late", "other"], "\(kept)")
        let m = StudioSchedule.matching(archiveID: "a", in: StudioSchedule.load(from: d), now: now)
        check("matching is by film, soonest first", m.map(\.broadcastID) == ["late", "future"])
        let raw = String(decoding: d.data(forKey: StudioSchedule.defaultsKey) ?? Data(), as: UTF8.self)
        check("the stored record carries no key", !raw.contains("MOCK-KEY") && !raw.lowercased().contains("streamname"))
        check("and does carry the copy", raw.contains("a\\/a.mp4") || raw.contains("a/a.mp4"))
    }
}
