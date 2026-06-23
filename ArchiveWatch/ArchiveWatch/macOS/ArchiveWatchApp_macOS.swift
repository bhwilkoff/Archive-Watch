#if os(macOS)
import SwiftUI
import SwiftData

// Phase 0 macOS shell — parity face on the shared Swift Core (CatalogDB, AppStore,
// ResilientStreamLoader, CloudKitSyncService). The Creation Studio DocumentGroup
// (docs/macOS-DESIGN.md §2) is a later phase; this is the browse/play/library/search
// window that proves the Core-reuse thesis. Reuses the SAME CloudKit container as the
// other Apple platforms, so favorites/progress sync for free.

@main
struct ArchiveWatchMacApp: App {
    @State private var store = AppStore()
    @State private var router = AppRouter()
    @State private var account = AccountStore()
    @Environment(\.scenePhase) private var scenePhase
    private let modelContainer: ModelContainer

    init() {
        URLCache.shared = URLCache(memoryCapacity: 64_000_000, diskCapacity: 400_000_000)
        modelContainer = Self.makeModelContainer()
    }

    var body: some Scene {
        WindowGroup("Archive Watch") {
            RootView()
                .environment(store)
                .environment(router)
                .environment(account)
                .frame(minWidth: 960, minHeight: 600)
                .task { await store.load() }
                .task(id: account.isSignedIn) {
                    guard account.isSignedIn else { return }
                    await CloudKitSyncService.shared.sync(modelContainer.mainContext)
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active, account.isSignedIn else { return }
                    Task { await CloudKitSyncService.shared.sync(modelContainer.mainContext) }
                }
        }
        .modelContainer(modelContainer)
        .commands {
            SidebarCommands()
            CommandGroup(after: .newItem) {
                Button("Surprise Me") { router.surprise(store) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(store)
                .environment(account)
        }
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([WatchProgress.self, Favorite.self, Playlist.self,
                             UserChannel.self, Tombstone.self, VideoClip.self])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        if let c = try? ModelContainer(for: schema, configurations: config) { return c }
        let mem = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: mem)
    }
}
#endif
