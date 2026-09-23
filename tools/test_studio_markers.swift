// §8.51 — which card changes become chapter markers on the replay (§D30).
//
// The mapping is PURE and tested here without a network. The one assertion
// that matters most is the countdown: "Starting soon" carries a value that
// changes every second, and comparing values instead of kinds would place a
// marker per second — the control below proves the test would see that.
import Foundation

@main struct MarkersTest {
    static func main() {
        typealias C = StudioOverlay.Card
        var fail = 0
        func check(_ name: String, _ got: String?, _ want: String?) {
            if got == want { print("  ok   \(name)") }
            else { print("  FAIL \(name): got \(got ?? "nil"), want \(want ?? "nil")"); fail += 1 }
        }
        let M = StudioMarkers.moment
        check("starting soon goes up", M(nil, .startingSoon(secondsRemaining: 60)), "Starting soon")
        check("a countdown tick is not a moment",
              M(.startingSoon(secondsRemaining: 60), .startingSoon(secondsRemaining: 59)), nil)
        check("starting soon comes down", M(.startingSoon(secondsRemaining: 3), nil), "The film begins")
        check("intermission goes up", M(nil, .intermission), "Intermission")
        check("intermission comes down", M(.intermission, nil), "Back from intermission")
        check("ending goes up", M(nil, .ending), "Thanks for watching")
        check("ending comes down is not a chapter", M(.ending, nil), nil)
        check("no card to no card", M(nil, nil), nil)
        let line = StudioOverlay.CardLine(id: 0, text: "Q&A with the audience", rank: .display)
        check("a custom card is named by its first line", M(nil, .custom(lines: [line])), "Q&A with the audience")
        let long = StudioOverlay.CardLine(id: 0, text: String(repeating: "x", count: 300), rank: .display)
        check("and capped at Twitch's 140", M(nil, .custom(lines: [long]))?.count.description, "140")
        // CONTROL: the countdown test must be able to fail. Two different
        // kinds DO produce a moment, so "nil for a tick" is not a mapping
        // that returns nil for everything.
        check("control: a different card is a moment", M(.startingSoon(secondsRemaining: 5), .intermission), "Intermission")
        print(fail == 0 ? "RESULT: PASS" : "RESULT: FAIL")
        exit(fail == 0 ? 0 : 1)
    }
}
