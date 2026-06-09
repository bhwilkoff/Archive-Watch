// swift-tools-version: 6.0
// ArchiveWatchCore — the platform-neutral core shared by the iOS app (and, after a
// later safe refactor, the tvOS app). Models, on-disk catalog query layer, catalog
// download+inflate, resilient streaming, the continuous-playback queue, the channel
// scheduler, the editorial loaders, and CloudKit sync — NO platform UI. This package
// doubles as the compile-verification harness for the reused core (Decision 028).
import PackageDescription

let package = Package(
    name: "ArchiveWatchCore",
    platforms: [.iOS(.v17), .tvOS(.v17)],
    products: [
        .library(name: "ArchiveWatchCore", targets: ["ArchiveWatchCore"]),
    ],
    targets: [
        .target(
            name: "ArchiveWatchCore",
            path: "Core"
        ),
    ]
)
