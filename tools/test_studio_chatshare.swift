// §8.52 — the film's chat line fits YouTube's 200 characters and never cuts
// the link (§D32). The control: a naive prefix(200) of the long case DOES cut
// the link, so the assertion is capable of failing.
import Foundation

@main struct ChatShareTest {
    static func main() {
        var fail = 0
        func check(_ name: String, _ ok: Bool) {
            print(ok ? "  ok   \(name)" : "  FAIL \(name)"); if !ok { fail += 1 }
        }
        let id = "the-man-who-laughs-1928-1080p-blu-ray-x-265-ghost"
        let link = "https://archive.org/details/\(id)"
        let normal = StudioChatShare.message(title: "The Man Who Laughs", meta: "1928 · Paul Leni", archiveID: id)
        print("  msg: \(normal)")
        check("a normal film says everything", normal.contains("1928 · Paul Leni") && normal.hasSuffix(link))
        check("and fits", normal.count <= 200)
        for n in [60, 120, 180, 400] {
            let t = String(repeating: "Lengthy Title ", count: n / 14 + 1)
            let m = StudioChatShare.message(title: t, meta: "1920 · Somebody With A Long Name", archiveID: id)
            check("title of \(t.count): fits (\(m.count))", m.count <= 200)
            check("title of \(t.count): the link is whole", m.hasSuffix(link))
        }
        // CONTROL: the obvious implementation would pass "fits" and fail this.
        let long = "Now watching: " + String(repeating: "x", count: 190) + " " + link
        check("control: a naive prefix(200) cuts the link", !String(long.prefix(200)).hasSuffix(link))
        print(fail == 0 ? "RESULT: PASS" : "RESULT: FAIL")
        exit(fail == 0 ? 0 : 1)
    }
}
