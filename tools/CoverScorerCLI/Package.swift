// swift-tools-version: 5.9
//
// CoverScorerCLI — on-device Apple Vision scoring for frame-extracted cover
// candidates (#86). Adapted from the BOBA-Playbook CardRecognitionCLI pattern
// (macOS Swift package, Vision framework, runs locally or on a macos runner).
//
// Build:   cd tools/CoverScorerCLI && swift build -c release
// Binary:  .build/release/coverscorer
//
// Given candidate JPEGs it returns, per image, an on-device Vision read:
// text coverage (OCR), face count + size, and Apple's aesthetics score +
// isUtility flag — enough to pick the best-of-N and reject title cards /
// intertitles / documents that pixel heuristics miss. No network, no API key.

import PackageDescription

let package = Package(
    name: "CoverScorerCLI",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "coverscorer", targets: ["CoverScorerCLI"])
    ],
    targets: [
        .executableTarget(name: "CoverScorerCLI", path: "Sources/CoverScorerCLI")
    ]
)
