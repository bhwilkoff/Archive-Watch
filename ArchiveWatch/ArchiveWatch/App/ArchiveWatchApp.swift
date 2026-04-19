import SwiftUI
import SwiftData

@main
struct ArchiveWatchApp: App {
    @State private var store = AppStore()
    @State private var router = Router()

    init() {
        URLCache.shared = URLCache(
            memoryCapacity: 100_000_000,
            diskCapacity: 500_000_000
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(router)
        }
        .modelContainer(for: [ContentItem.self, WatchProgress.self, Favorite.self])
    }
}
