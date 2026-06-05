// coverscorer — score cover candidates on-device with Apple Vision (#86).
//
// Usage:
//   coverscorer img1.jpg img2.jpg ...        # paths as args
//   coverscorer --stdin                      # one path per line on stdin
//
// Emits a JSON array, one object per image:
//   { path, textCoverage, textCount, faceCount, faceMaxArea,
//     aesthetics, isUtility, score, reject }
//
// score: higher is a better cover. reject: true => a title card / intertitle /
// document / blank that should NOT be used (caller keeps the procedural card).
// All on-device — no network, no API key.

import Foundation
import Vision
import CoreGraphics
import ImageIO

struct CoverScore: Codable {
    let path: String
    let textCoverage: Double   // sum of OCR box areas / frame (0..~1)
    let textCount: Int
    let faceCount: Int
    let faceMaxArea: Double     // largest face area / frame (0..1)
    let aesthetics: Double      // Apple overall aesthetics score (-1..1), 0 if N/A
    let isUtility: Bool         // Apple flag: screenshot/document/receipt-like
    let score: Double
    let reject: Bool
}

func loadCGImage(_ path: String) -> CGImage? {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let src = CGImageSourceCreateWithURL(url, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    return img
}

func scoreImage(_ path: String) -> CoverScore {
    guard let cg = loadCGImage(path) else {
        return CoverScore(path: path, textCoverage: 0, textCount: 0, faceCount: 0,
                          faceMaxArea: 0, aesthetics: -1, isUtility: true,
                          score: -1000, reject: true)
    }

    let textReq = VNRecognizeTextRequest()
    textReq.recognitionLevel = .fast
    textReq.usesLanguageCorrection = false
    let faceReq = VNDetectFaceRectanglesRequest()

    var requests: [VNRequest] = [textReq, faceReq]
    var aesthReq: VNImageBasedRequest?
    if #available(macOS 15.0, *) {
        let a = VNCalculateImageAestheticsScoresRequest()
        aesthReq = a
        requests.append(a)
    }

    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    try? handler.perform(requests)

    // Text coverage: fraction of the frame covered by recognized text. A title
    // card / intertitle / document is text-dominant; a real scene barely is.
    var textCoverage = 0.0
    var textCount = 0
    if let obs = textReq.results {
        for o in obs {
            guard let c = o.topCandidates(1).first, c.confidence > 0.3 else { continue }
            textCount += 1
            textCoverage += Double(o.boundingBox.width * o.boundingBox.height)
        }
    }

    // Faces: count + largest area. A big, clear face makes the strongest cover.
    var faceCount = 0
    var faceMaxArea = 0.0
    if let obs = faceReq.results {
        faceCount = obs.count
        for o in obs {
            faceMaxArea = max(faceMaxArea, Double(o.boundingBox.width * o.boundingBox.height))
        }
    }

    // Apple aesthetics + utility flag (macOS 15+).
    var aesthetics = 0.0
    var isUtility = false
    if #available(macOS 15.0, *),
       let a = aesthReq as? VNCalculateImageAestheticsScoresRequest,
       let r = a.results?.first {
        aesthetics = Double(r.overallScore)
        isUtility = r.isUtility
    }

    // A cover is rejected if Apple calls it a utility image (document/screenshot)
    // or text dominates the frame (intertitle / title card / credits).
    let reject = isUtility || textCoverage > 0.12

    // Composite: aesthetics carries the most weight; a prominent face is a big
    // bonus; text coverage is penalized; a reject is pushed below everything.
    var score = aesthetics * 100.0
        + faceMaxArea * 300.0
        + Double(faceCount) * 12.0
        - textCoverage * 500.0
    if reject { score -= 1000.0 }

    return CoverScore(path: path, textCoverage: textCoverage, textCount: textCount,
                      faceCount: faceCount, faceMaxArea: faceMaxArea,
                      aesthetics: aesthetics, isUtility: isUtility,
                      score: score, reject: reject)
}

// ---- entry ----
var paths = Array(CommandLine.arguments.dropFirst())
if paths.first == "--stdin" {
    paths = []
    while let line = readLine() {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { paths.append(t) }
    }
}

let results = paths.map(scoreImage)
let encoder = JSONEncoder()
encoder.outputFormatting = []
if let data = try? encoder.encode(results), let s = String(data: data, encoding: .utf8) {
    print(s)
} else {
    print("[]")
}
