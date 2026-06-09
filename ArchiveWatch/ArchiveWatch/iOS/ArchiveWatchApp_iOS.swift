#if os(iOS)
import SwiftUI
import SwiftData

@main
struct ArchiveWatchApp: App {
    @State private var store = AppStore()
    @State private var router = Router()
    @State private var account = AccountStore()   // #11 Sign in with Apple (optional; gates sync)
    private let modelContainer: ModelContainer

    init() {
        URLCache.shared = URLCache(memoryCapacity: 64_000_000, diskCapacity: 400_000_000)
        modelContainer = Self.makeModelContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .environment(account)
                .preferredColorScheme(.dark)
                .task { await store.load() }
                // Pull synced favorites/playlists/progress on launch (Decision 022).
                // No-op when signed out / CloudKit unavailable. Shares the Apple TV's
                // private DB so an iPhone on the same iCloud syncs with the Apple TV.
                .task { await CloudKitSyncService.shared.sync(modelContainer.mainContext) }
                // Deep links + Universal Links. archivewatch:// surprise/random/item
                // routes go through the IntentInbox (same path Siri uses); https item
                // links resolve directly.
                .onOpenURL { url in
                    if let request = IntentInbox.request(for: url) {
                        IntentInbox.shared.request = request
                    } else if let id = DeepLink.itemID(from: url), let item = store.item(id) {
                        router.openDetail(item)
                    }
                }
        }
        .modelContainer(modelContainer)
    }

    // SwiftData store in the App Group container (shared with future widgets), then
    // the platform default, then in-memory — so the app always launches. Manual
    // CloudKit sync (cloudKitDatabase: .none) reuses the tvOS CloudKitSyncService,
    // so an iPhone signed into the same iCloud account syncs WITH the Apple TV.
    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([WatchProgress.self, Favorite.self, Playlist.self,
                             UserChannel.self, Tombstone.self])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        if let c = try? ModelContainer(for: schema, configurations: config) { return c }
        let mem = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: mem)
    }
}

enum DeepLink {
    /// archivewatch://item/{id} or https://…/item/{id}
    static func itemID(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        if let i = parts.firstIndex(of: "item"), i + 1 < parts.count { return parts[i + 1] }
        if url.host == "item", let id = parts.first { return id }
        return nil
    }
}

#endif
