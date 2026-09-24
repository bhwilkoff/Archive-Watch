// §8.59 — a single-use refresh token is spent ONCE however many callers race
// for it (launch audit B). The stub below behaves like Twitch: using the
// refresh token a second time is refused.
//   gated   — eight concurrent callers through StudioRefreshGate: one refresh,
//             eight successes, all given the same token
//   control — the same eight calling the refresh directly: seven are refused
import Foundation

actor SingleUseRefreshToken {
    private var spent = false
    private(set) var uses = 0
    func refresh() async throws -> String {
        uses += 1
        try await Task.sleep(nanoseconds: 200_000_000)
        if spent { throw NSError(domain: "twitch", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid refresh token"]) }
        spent = true
        return "access-\(uses)"
    }
}

func race(_ n: Int, _ call: @escaping @Sendable () async throws -> String) async -> (ok: [String], failed: Int) {
    await withTaskGroup(of: String?.self) { g in
        for _ in 0..<n { g.addTask { try? await call() } }
        var ok: [String] = []; var failed = 0
        for await r in g { if let r { ok.append(r) } else { failed += 1 } }
        return (ok, failed)
    }
}

@main struct RefreshGateTest {
    static func main() async {
        let a = SingleUseRefreshToken(); let gate = StudioRefreshGate()
        let gated = await race(8) { try await gate.run("twitch") { try await a.refresh() } }
        let aUses = await a.uses
        print("  gated:   \(gated.ok.count) ok, \(gated.failed) refused, refresh used \(aUses)x, tokens \(Set(gated.ok))")
        let b = SingleUseRefreshToken()
        let direct = await race(8) { try await b.refresh() }
        print("  control: \(direct.ok.count) ok, \(direct.failed) refused (no gate)")
        let pass = gated.ok.count == 8 && aUses == 1 && Set(gated.ok).count == 1 && direct.failed == 7
        print(pass ? "PASS" : "FAIL"); exit(pass ? 0 : 1)
    }
}
