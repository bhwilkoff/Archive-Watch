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
    @State private var startItemOpened = false
    private let inbox = IntentInbox.shared

    private let network = NetworkMonitor.shared

    var body: some View {
        // Listening starts at launch, not once the catalog is ready: a SharePlay
        // continuation COLD-LAUNCHES the app, and gating the listener behind
        // `store.isReady` left nobody listening during the loading screen.
        VStack(spacing: 0) {
            offlineBanner
            shell
        }
        .task { WatchTogether.shared.listen() }
        .task { network.start() }
    }

    /// One slim bar, and only when there is no network (Decision 099).
    ///
    /// It says what still works rather than what broke: the catalog is a local
    /// SQLite file, so browsing, searching and every downloaded film carry on
    /// exactly as before — the only thing that cannot happen is streaming.
    /// Saying "no connection" alone would read as "the app is broken", which is
    /// the opposite of what this feature made true.
    @ViewBuilder private var offlineBanner: some View {
        if !network.isOnline {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                Text("Offline — your downloads still play")
                    .font(.footnote.weight(.medium))
                Spacer(minLength: 0)
                Button("Downloads") { router.tab = .library }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(.orange.opacity(0.22))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var shell: some View {
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
            .task { CaptionCapability.shared.probe() }
            // On-device end-to-end audit of offline downloads (AW_DOWNLOAD_AUDIT=1).
            // No-op otherwise; see tools/download_audit.py.
            .task {
                guard DownloadAudit.enabled else { return }
                await DownloadAudit.run(store: store, container: modelContext.container)
            }
            // A SharePlay session someone else started names a film; route to it
            // so DetailView can start playback and join the group. Without this
            // the session was joined and then nothing happened — the app opened
            // and sat there (owner, 2026-09-01). iOS has no `playItem` inbox
            // case like tvOS, so the routing is explicit here.
            //
            // Keyed on dbVersion as well as the id: a session that arrives during
            // a cold launch sets pendingJoin BEFORE this view exists, and onChange
            // only fires for changes it was present for — so the arrival would be
            // missed exactly in the continuation case. The id survives until
            // consumed, so re-reading it on each catalog swap also covers a film
            // held only in the full catalog, not the bundled seed.
            .task(id: store.dbVersion) { routeSharePlayJoin() }
            .onChange(of: WatchTogether.shared.pendingJoin) { routeSharePlayJoin() }
            // Screenshot/dev affordance (the tvOS RootView hooks, iOS twin):
            // AW_START_TAB=channels lands on a tab, AW_START_ITEM=<archiveID>
            // deep-opens that Detail. No-ops unless the env vars are set.
            // Re-runs on dbVersion so an item only in the FULL catalog (not the
            // bundled seed) opens once the downloaded DB swaps in.
            .task(id: store.dbVersion) {
                let env = ProcessInfo.processInfo.environment
                if let raw = env["AW_START_TAB"], let t = Router.Tab(rawValue: raw) {
                    router.tab = t
                }
                if !startItemOpened, let id = env["AW_START_ITEM"],
                   let item = store.item(id) {
                    startItemOpened = true
                    router.openDetail(item)
                }
            }
            // #11b live sync, the tvOS ContentView triggers mirrored (the iPhone
            // previously synced only at launch + after local edits, so Library
            // changes made on the Apple TV never arrived mid-session). Gated on
            // sign-in: Decision 022 — nothing leaves the device until opted in.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                if account.isSignedIn {
                    Task { await CloudKitSyncService.shared.sync(modelContext) }
                }
                // load() is memoized and runs once per process; without this a
                // resumed app keeps serving its cold-launch catalog.
                Task { await store.refreshCatalogIfStale() }
            }
            // Keyed on scenePhase deliberately: an unkeyed .task captures the
            // View struct once, so the `scenePhase` it read was frozen at
            // appear time — if the view first appeared while .inactive (common
            // on cold launch), the guard never passed again and periodic sync
            // silently never ran for the whole session.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    if account.isSignedIn {
                        await CloudKitSyncService.shared.sync(modelContext)
                    }
                }
            }
        }
    }

    private func routeSharePlayJoin() {
        guard let id = WatchTogether.shared.pendingJoin,
              let item = store.item(id) else { return }
        router.tab = .home
        router.openDetail(item)
    }

    private func handle(_ request: IntentInbox.Request?) {
        guard let request else { return }
        switch request {
        case .surprise, .randomFilm:
            if let item = store.dbRandomFeatureFilm() {
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
