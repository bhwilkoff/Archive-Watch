#if os(tvOS)
import SwiftUI
import SwiftData

// Top-level shell. Uses tvOS 26's native TabView with
// .sidebarAdaptable — Apple's own adaptive sidebar. This is the only
// navigation pattern where tvOS's focus engine reliably lets you walk
// back and forth between the sidebar and the content with arrow keys.
// Every custom attempt broke that traversal in a different way.
//
// Each Tab hosts a NavigationStack bound to a path on the Router, so:
//   • Pushing a DetailView or filtered BrowseView appends to the
//     current tab's path via .navigationDestination(for:).
//   • Pressing Back on the Siri Remote pops naturally.
//   • NavigationStack preserves the underlying view's scroll + focus
//     state when popping — no custom state persistence to manage.
//   • Switching tabs and returning restores that tab's exact spot.

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    private let inbox = IntentInbox.shared

    // #83 idle screensaver. Opt-in (store.screensaverIdleEnabled) and gated on
    // !isPlayingVideo so it can NEVER appear over a video. Counts 30s ticks of
    // low activity; resets on tab switch, scene change, or playback start/stop.
    @State private var idleSeconds = 0
    @State private var showSaver = false
    // Screenshot/dev affordance only (AW_START_CHANNEL): opens a channel-context
    // player to verify the VHS overlay over live video. No-op in production.
    @State private var devChannelItems: [Catalog.Item] = []
    @State private var showDevChannel = false
    @State private var showCaptionDiag = false
    private let idleThreshold = 300   // 5 minutes

    var body: some View {
        // Tabs are split into builder groups; one 12-tab TabView closure trips the
        // SwiftUI type-checker's "unable to type-check in reasonable time" limit.
        // #17: feeds completed + in-progress IDs into the store. Mounted at the
        // ROOT, not inside Home — watched state is a badge on every poster now
        // (owner, 2026-08-17), so a launch that lands on any other tab must
        // still have it. It used to live in HomeView, where it only had to be
        // right for Home's hide-watched filter; opening Library directly left
        // the set empty and every finished film looked unwatched.
        TabView(selection: tabSelection) {
            browseTabs
            modeTabs
            libraryTabs
        }
        .tabViewStyle(.sidebarAdaptable)
        .preferredColorScheme(.dark)
        .overlay { WatchedHomeSync() }
        // Keeps the Top Shelf snapshot (App Group) in sync with the
        // catalog + watch progress. No-ops until the App Group exists.
        .background { TopShelfUpdater() }
        // Siri / Shortcuts requests (Decision 015). Handle one set before
        // we appeared (cold launch via "Hey Siri…") and any set while live.
        .task { handleIntent(inbox.request) }
        // Ask once whether this device has speech models at all — an Apple TV
        // ships the API and none of the assets, and the app must not claim
        // otherwise (see CaptionCapability).
        .task { CaptionCapability.shared.probe() }
        .onChange(of: inbox.request) { _, req in handleIntent(req) }
        // #11: best-effort CloudKit sync on launch (no-ops until the entitlement
        // is configured — CloudSync.entitlementConfigured).
        .task { await CloudKitSyncService.shared.sync(modelContext) }
        // Screenshot/dev affordance: `AW_START_ITEM=<archiveID>` deep-opens that
        // item's Detail once the DB is ready; add `AW_AUTOPLAY=1` to also start
        // playback, which is how the Top Shelf's Play route is exercised on a
        // simulator (`simctl openurl` raises a system "Open in…?" prompt that
        // needs a Simulator GUI to dismiss). Both unset in production (no-op).
        .task {
            // `AW_START_TAB=<tab>` lands directly on a tab, the tvOS twin of the
            // macOS hook. Verifying a Library change otherwise means driving the
            // sidebar blind over the remote, and the standing rule here is that
            // the glass is the test — so the harness needs to reach a surface
            // without depending on focus luck. Unset in production (no-op).
            if let raw = ProcessInfo.processInfo.environment["AW_START_TAB"],
               let tab = Router.Tab(rawValue: raw) {
                router.tab = tab
            }
            // `AW_SET_TRANSCRIBE=1|0` sets the transcribe-when-missing default
            // deterministically. The Settings toggle proved undrivable by
            // remote presses (three warmed selects on the focused row, fresh
            // reboot included, never flipped it) and a harness that cannot
            // restore state it disturbed is a harness that lies. Unset in
            // production (no-op).
            if let v = ProcessInfo.processInfo.environment["AW_SET_TRANSCRIBE"] {
                LiveCaptions.transcribeWhenMissing = (v == "1")
                awdiag("[AWCAP] transcribeWhenMissing set to %@ via env", v)
            }
            guard let id = ProcessInfo.processInfo.environment["AW_START_ITEM"] else { return }
            openDeepLinkedItem(
                id, autoplay: ProcessInfo.processInfo.environment["AW_AUTOPLAY"] == "1")
        }
        // Dev affordance: `AW_CAPTION_DIAG=1` runs the caption probe at launch
        // with every line printed to stdout — which, with the app launched via
        // `devicectl device process launch --console`, makes a paired Apple TV
        // readable from the development Mac. That closes the gap this bug
        // lived in: three caption fixes shipped on Mac-only evidence because
        // the one device that could falsify them had no readable console.
        // The diagnostics UI is PRESENTED, not just run: the first headless
        // run couldn't rule out generation being gated on active rendering,
        // and the visible player makes the probe match real playback anyway.
        // Unset in production (no-op).
        .task {
            guard ProcessInfo.processInfo.environment["AW_CAPTION_DIAG"] == "1" else { return }
            showCaptionDiag = true
            try? await Task.sleep(nanoseconds: 1_000_000_000)   // let the cover land
            await CaptionDiagnostics.shared.run()
        }
        // Dev affordance: `AW_UI_AUDIT=1` exercises every tab's data spine,
        // every Browse facet/sort, and every Settings toggle's consumption,
        // printing PASS/FAIL per check — the T1 tier of docs/TVOS-AUDIT.md,
        // read from the dev Mac via `devicectl launch --console`. Unset in
        // production (no-op).
        .task {
            guard FunctionalAudit.enabled else { return }
            await FunctionalAudit.run(store: store)
        }
        .fullScreenCover(isPresented: $showCaptionDiag) { CaptionDiagnosticsView() }
        // Screenshot/dev affordance: `AW_START_MODE=kids|party|saver` lands on that
        // immersive tab once the catalog is ready (`saver` also opens the running
        // screensaver directly). Unset in production (no-op).
        .task {
            guard let m = ProcessInfo.processInfo.environment["AW_START_MODE"] else { return }
            let tab: Router.Tab? = ["kids": .cartoons, "party": .party, "saver": .screensaver][m]
            guard let tab else { return }
            for _ in 0..<150 {
                if store.isReady {
                    router.tab = tab
                    if m == "saver" { showSaver = true }
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        // Screenshot/dev affordance: `AW_START_CHANNEL` opens a channel-context
        // player (VHS overlay over live video) once the DB is ready. No-op in prod.
        .task {
            guard ProcessInfo.processInfo.environment["AW_START_CHANNEL"] != nil else { return }
            for _ in 0..<150 {
                if store.isReady {
                    let items = store.dbBrowse(contentType: "feature-film", sort: .popular, limit: 12)
                        .filter { $0.videoURLParsed != nil }
                    if !items.isEmpty { devChannelItems = items; showDevChannel = true; return }
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        .fullScreenCover(isPresented: $showDevChannel) {
            if let screen = PlayerScreen(lineup: devChannelItems, channelContext: true) {
                screen
            }
        }
        // #83 idle screensaver (opt-in, never over playback).
        .fullScreenCover(isPresented: $showSaver) { ScreensaverView() }
        // Native structured-concurrency idle tick (replaces a Combine Timer.publish): cancelled on
        // disappear; reads observable/@State live each iteration. The reset onChanges below still zero
        // the counter on any activity.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { break }
                guard store.screensaverIdleEnabled, !store.isPlayingVideo,
                      scenePhase == .active, !showSaver else { idleSeconds = 0; continue }
                idleSeconds += 30
                if idleSeconds >= idleThreshold { idleSeconds = 0; showSaver = true }
            }
        }
        .onChange(of: router.tab) { _, _ in idleSeconds = 0 }
        .onChange(of: store.isPlayingVideo) { _, _ in idleSeconds = 0 }
        .onChange(of: scenePhase) { _, _ in idleSeconds = 0 }
        .onChange(of: showSaver) { _, shown in if !shown { idleSeconds = 0 } }
    }

    /// Route a Siri/Shortcuts request into the live navigation state.
    private func handleIntent(_ request: IntentInbox.Request?) {
        guard let request else { return }
        switch request {
        case .surprise:
            router.surprisePath = NavigationPath()
            router.tab = .surprise
        case .randomFilm:
            if let film = store.dbRandomFeatureFilm() {
                router.homePath = NavigationPath()
                router.tab = .home
                router.homePath.append(film)
            }
        case .randomCategory:
            if let category = store.featured?.categories.randomElement() {
                router.browsePath = NavigationPath()
                router.tab = .browse
                router.browsePath.append(BrowseFilter(category: category.id))
            }
        case .openItem(let id):
            openDeepLinkedItem(id, autoplay: false)
        case .playItem(let id):
            openDeepLinkedItem(id, autoplay: true)
        }
        inbox.request = nil
    }

    /// Open a title arriving from a deep link (Top Shelf tap, Handoff, Siri).
    ///
    /// Retries while the full catalog swaps in: a cold launch paints from the
    /// lean bundled seed, which holds only a few thousand of the ~40k titles, so
    /// resolving once would silently drop the tap for most of the catalog and
    /// look exactly like a broken tile.
    private func openDeepLinkedItem(_ id: String, autoplay: Bool) {
        func land(_ item: Catalog.Item) {
            if autoplay { router.autoplayItemID = item.archiveID }
            router.homePath = NavigationPath()
            router.tab = .home
            router.homePath.append(item)
        }
        if let item = store.dbItem(id) { land(item); return }
        Task {
            for _ in 0..<25 {
                try? await Task.sleep(for: .milliseconds(200))
                if let item = store.dbItem(id) { land(item); return }
            }
        }
    }

    /// Sidebar tab selection always lands at that tab's root view.
    /// Three cases, all handled the same way — reset the incoming
    /// tab's NavigationPath:
    ///   • Switching tabs (old != new): clear both paths.
    ///   • Re-selecting the current tab while on a pushed view
    ///     (old == new): pop back to that tab's root — matches the
    ///     standard iOS/tvOS tab-bar convention where tapping the
    ///     current tab takes you to top.
    /// On tvOS, the TabView binding setter fires for both cases
    /// (same-value writes are not suppressed by SwiftUI here).
    @TabContentBuilder<Router.Tab>
    private var browseTabs: some TabContent<Router.Tab> {
        @Bindable var router = router
        Tab("Home", systemImage: "house.fill", value: Router.Tab.home) {
            NavigationStack(path: $router.homePath) { HomeView().attachDestinations() }
        }
        Tab("Movies", systemImage: "film.fill", value: Router.Tab.browse) {
            NavigationStack(path: $router.browsePath) { BrowseView().attachDestinations() }
        }
        Tab("TV Shows", systemImage: "tv.fill", value: Router.Tab.tvShows) {
            NavigationStack(path: $router.tvShowsPath) { TVShowsView().attachDestinations() }
        }
        Tab("Channels", systemImage: "play.tv.fill", value: Router.Tab.channels) {
            NavigationStack(path: $router.channelsPath) { ChannelsView().attachDestinations() }
        }
    }

    @TabContentBuilder<Router.Tab>
    private var modeTabs: some TabContent<Router.Tab> {
        @Bindable var router = router
        Tab("Cartoons", systemImage: "pawprint.fill", value: Router.Tab.cartoons) {
            NavigationStack(path: $router.cartoonsPath) { KidsModeView() }
        }
        Tab("Party Play", systemImage: "sparkles.tv.fill", value: Router.Tab.party) {
            NavigationStack(path: $router.partyPath) { PartyView().attachDestinations() }
        }
        Tab("Screensaver", systemImage: "photo.stack.fill", value: Router.Tab.screensaver) {
            NavigationStack(path: $router.screensaverPath) { ScreensaverHomeView() }
        }
    }

    @TabContentBuilder<Router.Tab>
    private var libraryTabs: some TabContent<Router.Tab> {
        @Bindable var router = router
        Tab("Collections", systemImage: "square.stack.3d.up.fill", value: Router.Tab.collections) {
            NavigationStack(path: $router.collectionsPath) { CollectionsView().attachDestinations() }
        }
        Tab("Search", systemImage: "magnifyingglass", value: Router.Tab.search, role: .search) {
            NavigationStack(path: $router.searchPath) { SearchView().attachDestinations() }
        }
        Tab("Library", systemImage: "books.vertical.fill", value: Router.Tab.favorites) {
            NavigationStack(path: $router.favoritesPath) { FavoritesView().attachDestinations() }
        }
        Tab("Surprise", systemImage: "dice.fill", value: Router.Tab.surprise) {
            NavigationStack(path: $router.surprisePath) { SurpriseView().attachDestinations() }
        }
        Tab("Settings", systemImage: "gearshape.fill", value: Router.Tab.settings) {
            NavigationStack(path: $router.settingsPath) { SettingsView().attachDestinations() }
        }
    }

    private var tabSelection: Binding<Router.Tab> {
        Binding(
            get: { router.tab },
            set: { newTab in
                if newTab != router.tab {
                    resetPath(for: router.tab)
                }
                resetPath(for: newTab)
                router.tab = newTab
            }
        )
    }

    private func resetPath(for tab: Router.Tab) {
        switch tab {
        case .home:        router.homePath = NavigationPath()
        case .browse:      router.browsePath = NavigationPath()
        case .tvShows:     router.tvShowsPath = NavigationPath()
        case .channels:    router.channelsPath = NavigationPath()
        case .cartoons:    router.cartoonsPath = NavigationPath()
        case .party:       router.partyPath = NavigationPath()
        case .screensaver: router.screensaverPath = NavigationPath()
        case .collections: router.collectionsPath = NavigationPath()
        case .search:      router.searchPath = NavigationPath()
        case .favorites:   router.favoritesPath = NavigationPath()
        case .surprise:    router.surprisePath = NavigationPath()
        case .settings:    router.settingsPath = NavigationPath()
        }
    }
}

extension View {
    func attachDestinations() -> some View {
        self
            .navigationDestination(for: Catalog.Item.self) { item in
                // Only real series cards (with a seriesID populated by the
                // exporter) route to SeriesDetailView for the lazy
                // /series/{seriesID}.json fetch. Individual tv-series-
                // classified items that fell out of clustering stay on
                // the regular DetailView and play as single items.
                if item.contentType == "tv-series" && item.seriesID != nil {
                    SeriesDetailView(seriesCard: item)
                } else {
                    DetailView(item: item)
                }
            }
            .navigationDestination(for: BrowseFilter.self) { filter in
                BrowseView(filter: filter)
            }
            .navigationDestination(for: PublicDomainRoute.self) { _ in
                PublicDomainView()
            }
            .navigationDestination(for: PlaylistRoute.self) { route in
                PlaylistDetailView(playlistID: route.id)
            }
    }
}

#endif
