import SwiftUI
import SwiftData

@main
struct ArchiveWatchApp: App {
    @State private var store = AppStore()
    @State private var router = Router()
    @State private var account = AccountStore()   // #11 Sign in with Apple
    private let modelContainer: ModelContainer

    init() {
        URLCache.shared = URLCache(
            memoryCapacity: 100_000_000,
            diskCapacity: 500_000_000
        )
        modelContainer = Self.makeModelContainer()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(router)
                .environment(account)
        }
        .modelContainer(modelContainer)
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
    }

    // SwiftData's default store lives in Application Support, which tvOS does
    // not let apps write to (it crashes on device with a permission error).
    // Prefer the App Group container — writable, persistent, and shared with
    // the Top Shelf extension — then fall back to the platform-default
    // location (Caches on tvOS), and finally to an in-memory store so the app
    // always launches.
    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([ContentItem.self, WatchProgress.self, Favorite.self,
                             Playlist.self, UserChannel.self, Tombstone.self])
        // cloudKitDatabase: .none is REQUIRED. Once the app carries the iCloud
        // entitlement, SwiftData otherwise tries to AUTO-mirror the store to
        // CloudKit (.automatic) — which crashes at store load because our models
        // use @Attribute(.unique) and non-optional fields, both unsupported by
        // CloudKit mirroring. We sync manually instead (CloudKitSyncService +
        // CKRecord), so the automatic mirror must be explicitly off.
        if let container = try? ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                groupContainer: .identifier(TopShelfSnapshot.appGroup),
                cloudKitDatabase: .none
            )
        ) {
            return container
        }
        if let container = try? ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        ) {
            return container
        }
        return try! ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }
}
