#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

// Phase 0 macOS shell — parity face on the shared Swift Core (CatalogDB, AppStore,
// ResilientStreamLoader, CloudKitSyncService). The Creation Studio DocumentGroup
// (docs/macOS-DESIGN.md §2) is a later phase; this is the browse/play/library/search
// window that proves the Core-reuse thesis. Reuses the SAME CloudKit container as the
// other Apple platforms, so favorites/progress sync for free.

/// Opening a window from a menu needs `openWindow`, which is an Environment
/// value — so the command is a small VIEW rather than a bare `Button`, which
/// is how SwiftUI intends a command to reach a scene.
private struct StudioWindowCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Watch Together Studio") { openWindow(id: StudioWindowID.studio) }
            .keyboardShortcut("s", modifiers: [.command, .shift])
    }
}

/// The Studio window's scene id, in one place because three files name it.
enum StudioWindowID {
    static let studio = "watch-together-studio"
}

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
        #if DEBUG
        // AW_KEYCHAIN_PROBE=1 — settles §6.1 on macOS from INSIDE the signed,
        // sandboxed app, which §9.rrr showed is the only place it can be
        // settled. Prints and exits; it is not a mode anyone can reach by
        // using the app.
        if ProcessInfo.processInfo.environment["AW_KEYCHAIN_PROBE"] == "1" {
            print("=== Watch Together §6.1: where the tokens land (macOS) ===")
            for line in StudioTokenStore.describeStorage() { print("  " + line) }
            print("=== end ===")
            exit(0)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup("Archive Watch") {
            RootView()
                .environment(store)
                .environment(router)
                .environment(account)
                .frame(minWidth: 960, minHeight: 600)
                .task { await store.load() }
                // Downloads must be wired before any view reads one: this
                // re-attaches to transfers the system carried on while the app
                // was closed, and repairs rows whose file moved (Decision 099).
                .task { DownloadManager.shared.configure(container: modelContainer) }
                .task { NetworkMonitor.shared.start() }
                .task {
                    // Supercut benchmark: the bench now runs INSIDE the editor scene (on the visible
                    // editor's bound model, so the full UI load contends — owner 2026-06-27). Here we
                    // only FORCE the editor document open so that scene + its .task reliably appear on
                    // a headless/CLI launch (state restoration otherwise may not open it).
                    if CreationStudioBench.isEnabled || CreationStudioFeatureAudit.isEnabled || CreationStudioStress.isEnabled || CreationStudioProjectAudit.isEnabled || CreationStudioSupercutAudit.isEnabled || CreationStudioTest.mode != nil {
                        CreationStudioBench.mark("TASK-FIRED open-editor")
                        await store.load()
                        NSDocumentController.shared.newDocument(nil)
                    }
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
                    guard phase == .active else { return }
                    if account.isSignedIn {
                        Task { await CloudKitSyncService.shared.sync(modelContainer.mainContext) }
                    }
                    // load() runs once per process; a Mac left open for days
                    // would otherwise never see a newer catalog.
                    Task { await store.refreshCatalogIfStale() }
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
                // Rule B13g — going live is a MENU COMMAND, because §B13a
                // forbids a second window and §B13b forbids hand-drawing into
                // the player's chrome, which rules out both obvious places.
                //
                // B13g left two questions unanswered, and these are the
                // CONSERVATIVE readings rather than decisions:
                //  • it lives beside the existing commands rather than in a new
                //    top-level Broadcast menu, because inventing a menu is the
                //    larger claim;
                //  • it is DISABLED with no film playing, because §B13a makes the
                //    Studio the player in a production mode and a broadcast of
                //    nothing is not a state the engine can serve.
                Button("Go Live…") { router.showGoLive = true }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(router.nowPlaying == nil)
                // The Studio window is NOT disabled without a film. §D5 says
                // a host should be able to open it, see what it offers and
                // set their levels before anything is broadcast; a control
                // that is grey until you already started is one you find
                // after you needed it.
                StudioWindowCommand()
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

        // WATCH TOGETHER STUDIO (macOS-DESIGN §D1) — its own window, so it
        // survives the player going full-screen and can hold the program
        // preview, the inputs and the mixer at once. `Window` rather than
        // `WindowGroup`: there is one broadcast, so there is one Studio.
        Window("Watch Together Studio", id: StudioWindowID.studio) {
            StudioWindowView()
                .environment(store)
                .environment(router)
        }
        .defaultSize(width: 1080, height: 860)

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
        // A SHARED PLAYLIST FIRST, before anything looks at the path: it
        // arrives as an ordinary https link because the whole point is that it
        // opens for somebody with no app at all, and the playlist is INSIDE
        // the url — nothing to resolve, nothing to wait for.
        if let shared = PlaylistShare.shared(from: url) {
            router.path.append(SharedListRoute(name: shared.name,
                                               archiveIDs: shared.archiveIDs))
            return
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        let host = url.host
        if host == "surprise" || host == "random"
            || parts.contains("surprise") || parts.contains("random") {
            if let item = store.randomFeatureFilm() { router.openDetail(item) }
            return
        }
        // archivewatch://item/{id}  or  https://archivewatch.org/item/{id}
        var id: String?
        if let i = parts.firstIndex(of: "item"), i + 1 < parts.count { id = parts[i + 1] }
        else if host == "item", let first = parts.first { id = first }
        if let id, let item = store.item(id) { router.openDetail(item) }
    }

    private static func makeModelContainer() -> ModelContainer {
        // DownloadedFilm is registered here but NOT synced — it names a file on
        // this Mac (iOS-DESIGN §9.7, Decision 099).
        let schema = Schema([WatchProgress.self, Favorite.self, Playlist.self,
                             UserChannel.self, Tombstone.self, VideoClip.self,
                             LibraryClip.self, DownloadedFilm.self])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        if let c = try? ModelContainer(for: schema, configurations: config) { return c }
        let mem = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: mem)
    }
}
#endif
