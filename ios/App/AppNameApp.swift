import SwiftUI
import SwiftData

@main
struct AppNameApp: App {
    // Configure URLCache at launch for better image/network caching
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
                // .environment(AuthManager())  // FILL IN: your auth manager
        }
        // .modelContainer(for: [/* your SwiftData models */])
    }
}
