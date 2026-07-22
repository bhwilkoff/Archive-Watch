// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PlaybackVerifierCLI",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PlaybackVerifierCLI",
            path: "Sources/PlaybackVerifierCLI"
        )
    ]
)
