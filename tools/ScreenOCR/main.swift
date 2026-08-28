// Screen OCR for the external-observation ATV harness: what text is ACTUALLY
// on the glass? Reads screenshots (devicectl capture) and emits JSON per file:
// caption-region text (bottom 30%), notice text anywhere, all boxes.
//
// Build: swiftc -O tools/ScreenOCR/main.swift -o /tmp/awocr
// Run:   /tmp/awocr shot1.png shot2.png ...   -> one JSON line per file

import Foundation
import Vision
import AppKit

// `w` lets a caller judge CLIPPING: a line whose box runs to the frame edge
// is text the layout could not fit, which no self-report ever reveals.
struct Line: Codable { let text: String; let x: Double; let y: Double; let h: Double; let w: Double }
struct Result: Codable {
    let file: String
    let captionRegion: [String]   // bottom 30% of the frame, top-to-bottom
    let allText: [Line]
}

for path in CommandLine.arguments.dropFirst() {
    guard let img = NSImage(contentsOfFile: path),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        FileHandle.standardError.write("cannot read \(path)\n".data(using: .utf8)!)
        continue
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false     // report what is drawn, not a guess
    let handler = VNImageRequestHandler(cgImage: cg)
    try? handler.perform([request])
    var lines: [Line] = []
    for obs in request.results ?? [] {
        guard let top = obs.topCandidates(1).first else { continue }
        let b = obs.boundingBox   // normalized, origin bottom-left
        lines.append(Line(text: top.string, x: b.origin.x, y: b.origin.y, h: b.height, w: b.width))
    }
    // Caption region: bottom 30% of the frame (y < 0.30 in Vision's
    // bottom-origin coordinates), sorted top-to-bottom.
    let caption = lines.filter { $0.y < 0.30 }
        .sorted { $0.y > $1.y }
        .map(\.text)
    let res = Result(file: (path as NSString).lastPathComponent,
                     captionRegion: caption, allText: lines)
    let data = try! JSONEncoder().encode(res)
    print(String(data: data, encoding: .utf8)!)
}
