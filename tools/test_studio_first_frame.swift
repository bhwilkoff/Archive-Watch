// §8.60 — going live cannot hang on the encoder's first frame (launch audit B).
//   live    — a real VideoToolbox session returns its avcC
//   dead    — a session that is gone throws within ~5 s instead of waiting
//             forever (before: the continuation was never resumed)
import Foundation
import CoreVideo

func pixelBuffer() -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, 640, 360, kCVPixelFormatType_32BGRA,
                        [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &pb)
    return pb!
}

@main struct FirstFrameTest {
    static func main() async {
        var ok = true
        let live = H264Encoder(width: 640, height: 360, frameRate: 30, bitrate: 2_000_000)
        do {
            try live.start()
            let avcC = try await live.encodeAndAwaitFormat(pixelBuffer())
            print("  live: avcC \(avcC?.count ?? 0) bytes")
            ok = ok && (avcC?.count ?? 0) > 0
        } catch { print("  live: threw \(error)"); ok = false }
        live.stop()

        let dead = H264Encoder(width: 640, height: 360, frameRate: 30, bitrate: 2_000_000)
        try? dead.start(); dead.stop()          // the session is gone, as after -12903
        let t0 = Date()
        do {
            _ = try await dead.encodeAndAwaitFormat(pixelBuffer())
            print("  dead: returned — expected a throw"); ok = false
        } catch {
            let s = Date().timeIntervalSince(t0)
            print(String(format: "  dead: threw after %.1f s (%@)", s, "\(error)"))
            ok = ok && s < 7
        }
        print(ok ? "PASS" : "FAIL"); exit(ok ? 0 : 1)
    }
}
