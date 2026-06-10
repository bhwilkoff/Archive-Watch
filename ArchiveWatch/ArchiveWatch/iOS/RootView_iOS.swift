#if os(iOS)
import SwiftUI
import SwiftData

// Native iOS shell: a bottom TabView (iPhone). Each tab is a NavigationStack with a
// shared `navigationDestination` for Catalog.Item → Detail. Search is its own tab
// (`role: .search` on iOS 26). iPad adaptivity (NavigationSplitView) is Phase 2.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(AccountStore.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    private let inbox = IntentInbox.shared

    var body: some View {
        @Bindable var router = router
        if let error = store.loadError {
            ContentUnavailableView("Catalog unavailable", systemImage: "wifi.slash",
                                   description: Text(error))
        } else if !store.isReady {
            ProgressView("Loading the archive…")
        } else {
            TabView(selection: $router.tab) {
                Tab(Router.Tab.home.title, systemImage: Router.Tab.home.systemImage, value: Router.Tab.home) {
                    NavigationStack(path: $router.homePath) { HomeView().withItemDestination() }
                }
                Tab(Router.Tab.browse.title, systemImage: Router.Tab.browse.systemImage, value: Router.Tab.browse) {
                    NavigationStack(path: $router.browsePath) { BrowseView().withItemDestination() }
                }
                Tab(Router.Tab.channels.title, systemImage: Router.Tab.channels.systemImage,
                    value: Router.Tab.channels) {
                    NavigationStack(path: $router.channelsPath) { ChannelsView().withItemDestination() }
                }
                Tab(Router.Tab.search.title, systemImage: Router.Tab.search.systemImage,
                    value: Router.Tab.search, role: .search) {
                    NavigationStack(path: $router.searchPath) { SearchView().withItemDestination() }
                }
                Tab(Router.Tab.library.title, systemImage: Router.Tab.library.systemImage, value: Router.Tab.library) {
                    NavigationStack(path: $router.libraryPath) { LibraryView().withItemDestination() }
                }
            }
            // Adapts per form factor: a bottom tab bar on iPhone, a sidebar on
            // iPad/regular width (the same control tvOS uses). Native idiom for
            // both without a separate NavigationSplitView code path.
            .tabViewStyle(.sidebarAdaptable)
            // Siri/Shortcuts + deep links land in the inbox; act once foreground.
            .onChange(of: inbox.request) { handle(inbox.request) }
            .task { handle(inbox.request) }
            // Screenshot/dev affordance (the tvOS RootView hooks, iOS twin):
            // AW_START_TAB=channels lands on a tab, AW_START_ITEM=<archiveID>
            // deep-opens that Detail. No-ops unless the env vars are set.
            .task {
                let env = ProcessInfo.processInfo.environment
                if let raw = env["AW_START_TAB"], let t = Router.Tab(rawValue: raw) {
                    router.tab = t
                }
                if let id = env["AW_START_ITEM"], let item = store.item(id) {
                    router.openDetail(item)
                }
            }
            // #11b live sync, the tvOS ContentView triggers mirrored (the iPhone
            // previously synced only at launch + after local edits, so Library
            // changes made on the Apple TV never arrived mid-session). Gated on
            // sign-in: Decision 022 — nothing leaves the device until opted in.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && account.isSignedIn {
                    Task { await CloudKitSyncService.shared.sync(modelContext) }
                }
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    if scenePhase == .active && account.isSignedIn {
                        await CloudKitSyncService.shared.sync(modelContext)
                    }
                }
            }
        }
    }

    private func handle(_ request: IntentInbox.Request?) {
        guard let request else { return }
        switch request {
        case .surprise, .randomFilm:
            if let item = store.dbRandomPlayable() {
                router.tab = .home
                router.openDetail(item)
            }
        case .randomCategory:
            router.tab = .browse
        case .openItem(let id):
            if let item = store.item(id) { router.openDetail(item) }
        }
        inbox.request = nil
    }
}

extension View {
    /// Shared push destinations so every tab can open Detail, a series, a
    /// collection, or a filtered grid identically (Home's category/decade tiles
    /// and Surprise's decade action push these from outside the Browse tab).
    func withItemDestination() -> some View {
        navigationDestination(for: Catalog.Item.self) { DetailView(item: $0) }
            .navigationDestination(for: SeriesRef.self) { SeriesDetailView(card: $0.card) }
            .navigationDestination(for: CollectionRef.self) { CollectionGridView(ref: $0) }
            .navigationDestination(for: BrowseFilterRoute.self) { FilteredGridView(route: $0) }
            .navigationDestination(for: SurpriseRoute.self) { _ in SurpriseView() }
            .navigationDestination(for: PublicDomainRoute.self) { _ in PublicDomainView() }
            .navigationDestination(for: ChannelsRoute.self) { _ in ChannelsView() }
            .navigationDestination(for: CartoonRoute.self) { _ in CartoonView() }
            .navigationDestination(for: ChannelScheduleRoute.self) {
                ChannelScheduleView(channelID: $0.channelID)
            }
    }
}

#endif
