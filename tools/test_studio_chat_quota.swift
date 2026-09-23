// §8.56 — the YouTube chat reader respects a quota SHARED by every host
// (Decision 136).
//   floor   — YouTube asking for 100 ms still gets ONE read in 3 s (10 s floor)
//   quota   — a `quotaExceeded` 403 stops reading after ONE call and says so
//   control — a `rateLimitExceeded` 403 keeps the reader alive (backoff only)
import Foundation

struct Refusal: Error, CustomStringConvertible { let description: String }
final class Counter: @unchecked Sendable {
    private let q = DispatchQueue(label: "c"); private var n = 0
    func bump() { q.sync { n += 1 } }
    var value: Int { q.sync { n } }
}

func run() async -> Bool {
    var ok = true

    let a = Counter()
    let fast = StudioChatYouTube()
    await fast.start(liveChatID: "x") { _, _ in a.bump(); return ([], "p", 100) }
    try? await Task.sleep(nanoseconds: 3_000_000_000)
    await fast.stop()
    print("  floor: \(a.value) read(s) in 3 s with YouTube asking for 100 ms")
    ok = ok && a.value == 1

    let b = Counter()
    let spent = StudioChatYouTube()
    await spent.start(liveChatID: "x") { _, _ in
        b.bump(); throw Refusal(description: "the platform answered 403: {\"reason\": \"quotaExceeded\"}")
    }
    try? await Task.sleep(nanoseconds: 1_000_000_000)
    let h = await spent.health
    print("  quota: \(b.value) call(s), polling=\(h.polling), says=\(h.lastError ?? "nothing")")
    ok = ok && b.value == 1 && !h.polling && (h.lastError ?? "").contains("daily limit")

    let c = Counter()
    let busy = StudioChatYouTube()
    await busy.start(liveChatID: "x") { _, _ in
        c.bump(); throw Refusal(description: "the platform answered 403: {\"reason\": \"rateLimitExceeded\"}")
    }
    try? await Task.sleep(nanoseconds: 1_000_000_000)
    let hc = await busy.health
    await busy.stop()
    print("  control: rateLimitExceeded leaves polling=\(hc.polling)")
    ok = ok && hc.polling

    return ok
}

@main struct ChatQuotaTest {
    static func main() async {
        let passed = await run()
        print(passed ? "PASS" : "FAIL")
        exit(passed ? 0 : 1)
    }
}
