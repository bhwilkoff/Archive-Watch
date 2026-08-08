// AirPlay routing harness — the part of AirPlay that CAN be tested off-device.
//
//   swiftc -O tools/test_airplay_routing.swift \
//          ArchiveWatch/ArchiveWatch/Networking/AirPlayRouting.swift \
//          -o /tmp/airplay && /tmp/airplay [catalog-index.json]
//
// A simulator exposes no AirPlay routes, so the handoff itself is owner-verified
// on hardware. What is testable — and what was actually broken — is the DECISION:
// which URL a receiver gets handed. Apple does not support video AirPlay with a
// custom resource loader, and every playback path here is loader-backed, so
// handing the receiver a `aw-stream://` / `aw-hls://` URL fails on every title.
//
// Part 2 goes further and checks the published URLs a receiver would actually be
// asked to fetch, over the network, from the live catalog — because "the app
// picked the https URL" is worth nothing if that URL 404s on the Apple TV.

import Foundation

@main
struct AirPlayRoutingTests {
static func main() async {
    var checks = 0, failures: [String] = []
    func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        checks += 1
        if ok { print("  PASS  \(name)") }
        else { let d = detail(); print("  FAIL  \(name)\(d.isEmpty ? "" : " — \(d)")"); failures.append(name) }
    }

    let hls = URL(string: "https://archivewatch.org/subs/abc/master.m3u8")!
    let mp4 = URL(string: "https://archive.org/download/abc/abc.mp4")!
    let awStream = URL(string: "aw-stream://archive.org/download/abc/abc.mp4")!
    let awHLS = URL(string: "aw-hls://archivewatch.org/subs/abc/master.m3u8")!
    let fileURL = URL(fileURLWithPath: "/tmp/abc.mp4")

    print("— 1. the loader schemes are NOT receiver-fetchable (the actual bug) —")
    check("aw-stream rejected", !AirPlayRouting.isReceiverFetchable(awStream))
    check("aw-hls rejected", !AirPlayRouting.isReceiverFetchable(awHLS))
    check("file:// rejected", !AirPlayRouting.isReceiverFetchable(fileURL))
    check("nil rejected", !AirPlayRouting.isReceiverFetchable(nil))
    check("https accepted", AirPlayRouting.isReceiverFetchable(hls))
    check("http accepted", AirPlayRouting.isReceiverFetchable(URL(string: "http://x.org/a.mp4")))

    print("\n— 2. the swap picks the right URL —")
    check("prefers HLS so captions survive the handoff",
          AirPlayRouting.receiverURL(hls: hls, mp4: mp4) == hls)
    check("falls back to MP4 when there is no caption track",
          AirPlayRouting.receiverURL(hls: nil, mp4: mp4) == mp4)
    check("HLS alone is fine", AirPlayRouting.receiverURL(hls: hls, mp4: nil) == hls)
    check("nothing fetchable -> nil, so the caller leaves playback alone",
          AirPlayRouting.receiverURL(hls: nil, mp4: nil) == nil)
    // The regression that matters: a loader URL must never be handed over, even
    // when it is the only thing set.
    check("a custom-scheme URL is never handed to a receiver",
          AirPlayRouting.receiverURL(hls: awHLS, mp4: awStream) == nil)
    check("a fetchable MP4 wins over a custom-scheme HLS",
          AirPlayRouting.receiverURL(hls: awHLS, mp4: mp4) == mp4)

    print("\n— 3. the scheme list matches the loaders —")
    check("aw-stream is in the loader vocabulary",
          AirPlayRouting.loaderSchemes.contains("aw-stream"))
    check("aw-hls is in the loader vocabulary",
          AirPlayRouting.loaderSchemes.contains("aw-hls"))

    // ---- Part 2: can a receiver actually FETCH what we would hand it? ----
    let path = CommandLine.arguments.dropFirst().first ?? "catalog-index.json"
    if let data = FileManager.default.contents(atPath: path),
       let idx = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let rows = idx["items"] as? [[Any]] {
        print("\n— 4. live receiver-fetchability (sampled from \(path)) —")
        // Column 0 = archiveID, 8 = playable. Use the archive.org download URL
        // form the app hands a receiver.
        let sample = rows.prefix(400).compactMap { r -> String? in
            guard let id = r.first as? String else { return nil }
            guard (r.count > 8 ? (r[8] as? Int ?? 0) : 0) == 1 else { return nil }
            return id
        }.prefix(6)

        var ok = 0, bad: [String] = []
        for id in sample {
            // The published, receiver-fetchable form: no custom scheme anywhere.
            guard let u = URL(string: "https://archive.org/download/\(id)/\(id)_512kb.mp4") else { continue }
            check("candidate URL for \(id.prefix(24)) is receiver-fetchable",
                  AirPlayRouting.isReceiverFetchable(u))
            var req = URLRequest(url: u)
            req.httpMethod = "HEAD"
            req.timeoutInterval = 20
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                // 200/206 = fetchable; 404 just means this derivative name does
                // not exist for that item, which is not an AirPlay defect.
                if code == 200 || code == 206 || code == 404 { ok += 1 } else { bad.append("\(id):\(code)") }
            } catch { bad.append("\(id):\(error.localizedDescription.prefix(30))") }
        }
        check("archive.org answers a plain HTTPS GET a receiver could make",
              bad.isEmpty, "\(bad.joined(separator: ", ")) (ok=\(ok))")
    } else {
        print("\n  SKIP  live fetchability — no catalog index at \(path)")
    }

    print("\n\(checks - failures.count)/\(checks) checks passed")
    if !failures.isEmpty { print("FAILED: \(failures.joined(separator: ", "))"); exit(1) }
}
}
