// §8.55 — ending a show survives the CALLER's cancellation (audit A12).
//
// tvOS ends a show by setting `studioFilm` nil, which cancels the
// `.task(id:)` whose teardown then completes the YouTube broadcast. In a
// cancelled task URLSession throws at once, so the broadcast was never
// completed or deleted. `StudioSession.completeArmedBroadcast` now runs its
// body in an unstructured Task. This proves the mechanism with a REAL request
// against a local server, and runs the bare call as the control that must fail:
//   ok   — a cancelled parent awaiting `Task { request }.value` gets through
//   ctrl — the same request made directly in the cancelled parent is refused
// And the source half: completeArmedBroadcast still wraps its body.
import Foundation

let port = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "18765"
let url = URL(string: "http://127.0.0.1:\(port)/")!

@MainActor func request() async -> String {
    do { _ = try await URLSession.shared.data(from: url); return "reached" }
    catch { return "refused (\((error as NSError).code))" }
}

@MainActor func run() async -> (wrapped: String, bare: String) {
    let parent = Task { @MainActor () -> (String, String) in
        while !Task.isCancelled { try? await Task.sleep(nanoseconds: 1_000_000) }
        let wrapped = await Task { await request() }.value
        let bare = await request()
        return (wrapped, bare)
    }
    parent.cancel()
    return await parent.value
}

let src = (try? String(contentsOfFile: "ArchiveWatch/ArchiveWatch/Studio/StudioSession.swift", encoding: .utf8)) ?? ""
let wrapsBody = src.range(of: #"public func completeArmedBroadcast\(\) async \{[^}]*await Task \{ await self\.completeArmedBroadcastNow\(\) \}\.value"#,
                          options: .regularExpression) != nil

Task { @MainActor in
    let r = await run()
    print("  wrapped in a cancelled parent: \(r.wrapped)")
    print("  bare in a cancelled parent:    \(r.bare)   (control)")
    print("  completeArmedBroadcast wraps its body: \(wrapsBody)")
    let pass = r.wrapped == "reached" && r.bare != "reached" && wrapsBody
    print(pass ? "PASS" : "FAIL")
    exit(pass ? 0 : 1)
}
RunLoop.main.run()
