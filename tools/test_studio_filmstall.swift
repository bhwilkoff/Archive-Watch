// §8.40 — the film's stall names its own cause, and names the RIGHT one.
//
// The sentence a host reads when the programme goes quiet. Every branch is
// checked, and so is the ORDER, because the branches overlap: a player whose
// item has been nilled also reports rate 0, so an implementation that asked
// "is it paused" first would tell the host they pressed pause when in fact the
// window was rebuilt underneath them. Both sentences are true of the facts;
// only one sends somebody to the right place.
//
//   DEVELOPER_DIR=... xcrun swiftc -parse-as-library -O \
//     ArchiveWatch/ArchiveWatch/Studio/StudioFilmStall.swift \
//     tools/test_studio_filmstall.swift -o /tmp/awfs && /tmp/awfs
import Foundation

@main
struct FilmStallTest {
    static var failures = 0

    static func check(_ what: String, _ facts: StudioFilmStall.Facts, contains: String) {
        let got = StudioFilmStall.reason(facts)
        if got.contains(contains) {
            print("  ok   \(what) -> \"\(got)\"")
        } else {
            print("  FAIL \(what): expected a sentence containing \"\(contains)\", got \"\(got)\"")
            failures += 1
        }
    }

    static func main() {
        print("§8.40 film-stall reasons")

        // Playing normally is not a fact this function ever sees — it is only
        // called after three silent seconds — so the healthy-looking facts must
        // still produce the honest fallback rather than a reassurance.
        check("no player at all",
              .init(hasPlayer: false, hasItem: false, rate: 0, likelyToKeepUp: false),
              contains: "not holding a player")
        check("player, no item (the window was rebuilt)",
              .init(hasPlayer: true, hasItem: false, rate: 0, likelyToKeepUp: false),
              contains: "no item")
        check("paused",
              .init(hasPlayer: true, hasItem: true, rate: 0, likelyToKeepUp: true),
              contains: "paused")
        check("buffering",
              .init(hasPlayer: true, hasItem: true, rate: 1, likelyToKeepUp: false),
              contains: "buffering")
        check("the item carries an error",
              .init(hasPlayer: true, hasItem: true, rate: 1, likelyToKeepUp: true,
                    errorDescription: "The operation could not be completed"),
              contains: "The operation could not be completed")
        check("everything looks healthy and nothing arrives",
              .init(hasPlayer: true, hasItem: true, rate: 1, likelyToKeepUp: true),
              contains: "no frames are reaching the programme")

        // THE ORDER. These two facts are BOTH true of a rebuilt window, and an
        // implementation that reordered the branches would still pass every
        // check above — each one only asserts its own row.
        let rebuilt = StudioFilmStall.Facts(hasPlayer: true, hasItem: false,
                                            rate: 0, likelyToKeepUp: false)
        if StudioFilmStall.reason(rebuilt).contains("paused") {
            print("  FAIL a rebuilt window is reported as a host who pressed pause")
            failures += 1
        } else {
            print("  ok   a rebuilt window outranks \"paused\", which is also true of it")
        }

        // NEGATIVE CONTROL. Every check above asks `contains`, and a function
        // that returned one long sentence naming all six causes would pass all
        // of them. The reasons must be DISTINCT.
        let all = [
            StudioFilmStall.Facts(hasPlayer: false, hasItem: false, rate: 0, likelyToKeepUp: false),
            .init(hasPlayer: true, hasItem: false, rate: 0, likelyToKeepUp: false),
            .init(hasPlayer: true, hasItem: true, rate: 0, likelyToKeepUp: true),
            .init(hasPlayer: true, hasItem: true, rate: 1, likelyToKeepUp: false),
            .init(hasPlayer: true, hasItem: true, rate: 1, likelyToKeepUp: true, errorDescription: "x"),
            .init(hasPlayer: true, hasItem: true, rate: 1, likelyToKeepUp: true),
        ].map(StudioFilmStall.reason)
        if Set(all).count == all.count {
            print("  ok   control — all \(all.count) reasons are distinct sentences")
        } else {
            print("  FAIL control — two sets of facts produce the same sentence")
            failures += 1
        }

        print(failures == 0 ? "PASS" : "FAIL: \(failures) check(s)")
        exit(failures == 0 ? 0 : 1)
    }
}
