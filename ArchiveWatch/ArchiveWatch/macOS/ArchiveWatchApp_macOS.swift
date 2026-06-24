#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

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
                .task {
                    // Creation Studio engine self-test (spike #3) — no-op unless AW_CS_SELFTEST=1.
                    if ProcessInfo.processInfo.environment["AW_CS_PERFTEST"] == "1" {
                        await CreationStudioPerfTest.run(store: store)
                    } else if CreationStudioSelfTest.isEnabled {
                        await CreationStudioSelfTest.run(store: store)
                    }
                }
                .task(id: account.isSignedIn) {
                    guard account.isSignedIn else { return }
                    await CloudKitSyncService.shared.sync(modelContainer.mainContext)
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active, account.isSignedIn else { return }
                    Task { await CloudKitSyncService.shared.sync(modelContainer.mainContext) }
                }
                // Deep links (archivewatch://item/{id} · /surprise · /random) and
                // Universal Links (https://archivewatch.org/item/{id}) — the share URLs
                // every platform emits. Routes into the detail column.
                .onOpenURL { route($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { route(url) }
                }
        }
        .modelContainer(modelContainer)
        .commands {
            SidebarCommands()
            // With a WindowGroup (first) + a DocumentGroup, SwiftUI binds ⌘N to the
            // WindowGroup (a new Library window). Re-point New at a new Creation Studio
            // PROJECT — NSDocumentController routes to the DocumentGroup's document type.
            CommandGroup(replacing: .newItem) {
                Button("New Project") { NSDocumentController.shared.newDocument(nil) }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("Surprise Me") { router.surprise(store) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        // Creation Studio editor (docs/macOS-DESIGN.md §2). A DocumentGroup bound to the
        // `.archiveproj` package — the FCP "project timeline" face, distinct from the
        // WindowGroup Library face above. File ▸ New (⌘N) creates a project. The proxy-clip
        // LIBRARY is the shared SwiftData store (Rule "Library ≠ Project").
        // newDocument is an @Sendable (nonisolated) closure, but SwiftUI creates documents on
        // the main thread (NSDocumentController) — assumeIsolated is the native bridge to the
        // main-actor ClipProjectDocument initializer.
        DocumentGroup(newDocument: { ClipProjectDocument() }) { configuration in
            ProjectEditorView(document: configuration.document)
                .environment(store)
                .frame(minWidth: 740, minHeight: 500)   // fixed sidebars (240+280) + a shrinkable center
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1200, height: 760)

        Settings {
            SettingsView()
                .environment(store)
                .environment(account)
        }
    }

    /// Route a deep link / universal link into the detail column. Handles item links
    /// (open Detail) and surprise/random (open a random playable Detail) — the same
    /// scope iOS's onOpenURL covers.
    private func route(_ url: URL) {
        let parts = url.pathComponents.filter { $0 != "/" }
        let host = url.host
        if host == "surprise" || host == "random"
            || parts.contains("surprise") || parts.contains("random") {
            if let item = store.randomPlayable() { router.openDetail(item) }
            return
        }
        // archivewatch://item/{id}  or  https://archivewatch.org/item/{id}
        var id: String?
        if let i = parts.firstIndex(of: "item"), i + 1 < parts.count { id = parts[i + 1] }
        else if host == "item", let first = parts.first { id = first }
        if let id, let item = store.item(id) { router.openDetail(item) }
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([WatchProgress.self, Favorite.self, Playlist.self,
                             UserChannel.self, Tombstone.self, VideoClip.self,
                             LibraryClip.self])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        if let c = try? ModelContainer(for: schema, configurations: config) { return c }
        let mem = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: mem)
    }
}
#endif
