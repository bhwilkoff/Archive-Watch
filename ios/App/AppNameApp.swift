import SwiftUI
import SwiftData

// Rename this type + file to `ArchiveWatchApp` when the Xcode tvOS
// project is created. The name must match the Product Name exactly.

@main
struct AppNameApp: App {
    init() {
        URLCache.shared = URLCache(
            memoryCapacity: 100_000_000,  // 100 MB
            diskCapacity: 500_000_000     // 500 MB
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(AppStore())
        }
        .modelContainer(for: [ContentItem.self])
    }
}
