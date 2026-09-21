// §8.28 — the room code people say out loud (SHAREPLAY §11.6 / §11.8).
//
// Owner: "how would it work if they join the call from one location but want
// to use a different device to 'join' the movie."
//
// The code arrives BY EAR — somebody hears it over a call and types it with a
// remote control. That is what every assertion here is really about: the
// failure mode is not a wrong code, it is a correct code typed the way a
// listener would type it and rejected anyway.
import Foundation

@main
struct StudioRoomTest {
    static var failures = 0
    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "PASS" : "FAIL") \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures += 1 }
    }

    static func main() {
        print("=== §8.28 room codes ===")

        // ---- the alphabet keeps its promises
        let alpha = String(StudioRoom.alphabet)
        for bad in ["I", "L", "O", "U"] {
            check("the alphabet excludes \(bad)", !alpha.contains(bad), alpha)
        }
        check("but KEEPS 0 and 1, which is what makes mapping possible",
              alpha.contains("0") && alpha.contains("1"))
        check("the alphabet is 32 characters", StudioRoom.alphabet.count == 32,
              "\(StudioRoom.alphabet.count)")

        // ---- generation
        var seen = Set<String>()
        for _ in 0..<500 {
            let c = StudioRoom.newCode()
            guard c.count == StudioRoom.codeLength else {
                check("every generated code is \(StudioRoom.codeLength) characters", false, c)
                break
            }
            guard c.allSatisfy({ StudioRoom.alphabet.contains($0) }) else {
                check("every generated code uses only the alphabet", false, c)
                break
            }
            seen.insert(c)
        }
        check("every generated code is the right length and alphabet", true)
        // Not a randomness test — a check that it is not returning a constant,
        // which is the way this fails in practice.
        check("500 codes are not all the same", seen.count > 450, "\(seen.count) distinct")
        check("every generated code normalizes to ITSELF",
              seen.allSatisfy { StudioRoom.normalize($0) == $0 })

        // ---- the part that actually matters: how a listener types it
        // The real code here is CA11. A GENERATED code can never contain I,
        // L, O or U — they are not in the alphabet — so those characters only
        // ever appear as a MISHEARING, which is exactly what normalize is
        // for. "CALI" carries both an L and an I and both are ones.
        check("lower case is accepted", StudioRoom.normalize("ca11") == "CA11",
              StudioRoom.normalize("ca11") ?? "nil")
        check("spaces are ignored — people group what they read aloud",
              StudioRoom.normalize("CA 11") == "CA11")
        check("dashes are ignored", StudioRoom.normalize("CA-11") == "CA11")
        // THE POINT. Someone hears "see-ay-one-one" and may type an
        // L or an I for either 1. Every spelling must reach the same room.
        check("a typed L becomes 1", StudioRoom.normalize("CAL1") == "CA11",
              StudioRoom.normalize("CAL1") ?? "nil")
        check("a typed I becomes 1 too", StudioRoom.normalize("CAI1") == "CA11")
        check("AND ALL THREE SPELLINGS REACH THE SAME ROOM",
              StudioRoom.normalize("CALI") == StudioRoom.normalize("CA11")
              && StudioRoom.normalize("CAI1") == StudioRoom.normalize("CA11"),
              StudioRoom.normalize("CALI") ?? "nil")
        check("a typed O becomes 0", StudioRoom.normalize("C0DE") == "C0DE")
        check("a typed capital O in place of zero still works",
              StudioRoom.normalize("CODE") == "C0DE",
              StudioRoom.normalize("CODE") ?? "nil")

        // ---- and it still refuses what it should
        check("a short code is refused", StudioRoom.normalize("AB") == nil)
        check("a long code is refused", StudioRoom.normalize("ABCDE") == nil)
        check("punctuation is refused", StudioRoom.normalize("AB!E") == nil)
        check("U is refused rather than mapped", StudioRoom.normalize("ABUE") == nil)
        // CONTROL: a valid code of the same shape must pass, or "refused"
        // above would prove only that the function refuses everything.
        check("CONTROL: a well-formed code of the same length is accepted",
              StudioRoom.normalize("ABCD") == "ABCD")

        // ---- links, and the id shape this catalogue actually has
        let film = "DasKabinettdesDoktorCaligariTheCabinetofDrCaligari"
        guard let url = StudioRoom.link(code: "ca11", filmID: film) else {
            check("a link is built", false); exit(1)
        }
        check("the link is built", url.absoluteString.hasPrefix("https://archivewatch.org/together/"),
              url.absoluteString)
        check("the room travels in the FRAGMENT, so no server is told about it",
              url.fragment?.hasPrefix("CA11") == true && url.query == nil,
              url.fragment ?? "nil")
        guard let back = StudioRoom.parse(link: url) else {
            check("the link parses back", false); exit(1)
        }
        check("a link round-trips", back.code == "CA11" && back.filmID == film,
              "\(back)")

        // THE ID SHAPE THAT BREAKS THE OBVIOUS IMPLEMENTATION. Archive ids
        // routinely contain dashes; splitting on every dash truncates most of
        // this catalogue.
        let dashy = "ptp_the-love-nest_buster-keaton_blu-ray_h264_1080p_430833"
        guard let u2 = StudioRoom.link(code: "ABCD", filmID: dashy),
              let p2 = StudioRoom.parse(link: u2) else {
            check("a dashed archive id round-trips", false); exit(1)
        }
        check("AN ARCHIVE ID FULL OF DASHES SURVIVES THE ROUND TRIP",
              p2.filmID == dashy && p2.code == "ABCD", p2.filmID)

        check("a link with no fragment is refused",
              StudioRoom.parse(link: URL(string: "https://archivewatch.org/together/")!) == nil)
        check("an unrelated link is refused",
              StudioRoom.parse(link: URL(string: "https://archivewatch.org/item/x#ABCDEF-y")!) == nil)

        print(failures == 0 ? "=== §8.28 OK ===" : "=== §8.28 \(failures) FAILURES ===")
        exit(failures == 0 ? 0 : 1)
    }
}
