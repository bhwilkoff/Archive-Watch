#if os(macOS)
import SwiftUI
import AppKit

// NavigationSplitView shell (docs/macOS-DESIGN.md §7): sidebar sections + a detail column
// that drills into Detail / Person / Collection. The player presents as a sheet over the
// detail column. Creation Studio gets its own DocumentGroup scene in a later phase.

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        // The player REPLACES the browse UI as the window root while playing (not an overlay on the
        // split view) — otherwise the split view keeps owning the window toolbar, so its sidebar toggle
        // + the previous view's title bled through over the player. As the root, the player's own
        // NavigationStack title (the movie) + its X button are the only window chrome.
        Group {
            if let item = router.nowPlaying {
                PlayerWindow(item: item)
            } else if let ctx = router.nowPlayingEpisode {
                EpisodePlayer(context: ctx)
            } else {
                browse
            }
        }
        .overlay {
            if !store.isReady {
                ProgressView("Loading catalog…").controlSize(.large)
            }
        }
        // Screensaver: a real full-window, full-screen poster wall (not a nav push that keeps the
        // sidebar). Covers everything; click / Esc / the ✕ exits + leaves macOS full-screen.
        .overlay {
            if router.screensaverActive {
                ScreensaverView(onExit: { exitScreensaver() })
                    .transition(.opacity)
                    .onAppear { setFullScreen(true) }
                    .onExitCommand { exitScreensaver() }   // Esc
            }
        }
        // Screenshot/test launch hooks (the macOS analogue of the iOS/tvOS AW_START_* hooks) — inert
        // unless the env vars are set, so the shipping app is unaffected. Lets the screenshot driver
        // land on any sidebar section (AW_START_TAB) or open a specific title's Detail (AW_START_ITEM)
        // deterministically, since SwiftUI's AX tree isn't reliably scriptable from the shell.
        .task { await applyLaunchOverrides() }
    }

    private func applyLaunchOverrides() async {
        let env = ProcessInfo.processInfo.environment
        guard env["AW_START_TAB"] != nil || env["AW_START_ITEM"] != nil else { return }
        for _ in 0..<160 where !store.isReady { try? await Task.sleep(for: .milliseconds(250)) }
        if let tab = env["AW_START_TAB"], let s = AppRouter.Section(rawValue: tab) {
            router.section = s
        }
        if let id = env["AW_START_ITEM"] {
            // Wait for the full DB to swap in (richer metadata + designed art than the seed).
            for _ in 0..<80 where store.itemsByIDs([id]).first == nil {
                try? await Task.sleep(for: .milliseconds(250))
            }
            if let it = store.itemsByIDs([id]).first {
                router.openDetail(it)
                // AW_AUTOPLAY starts playback too, so a test can reach the PLAYER
                // without clicking — the same reason the other hooks exist, and
                // the only way to verify live captions in the real app (SwiftUI
                // exposes no scriptable Play button, as noted above).
                if ProcessInfo.processInfo.environment["AW_AUTOPLAY"] == "1" {
                    router.play(it)
                }
            }
        }
    }

    /// The browse UI (sidebar + detail). Shown as the window root EXCEPT while a title is playing.
    private var browse: some View {
        @Bindable var router = router
        return NavigationSplitView {
            List(AppRouter.Section.allCases, selection: $router.section) { section in
                Label(section.title, systemImage: section.systemImage).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .navigationTitle("Archive Watch")
        } detail: {
            NavigationStack(path: $router.path) {
                sectionContent
                    .navigationDestination(for: Catalog.Item.self) { DetailView(item: $0) }
                    .navigationDestination(for: PersonRoute.self) {
                        GridView(title: $0.name, items: store.byPerson($0.name))
                    }
                    .navigationDestination(for: CollectionRoute.self) {
                        GridView(title: $0.title, items: store.byCollection($0.id))
                    }
                    .navigationDestination(for: SeriesRef.self) { SeriesDetailView(card: $0.card) }
                    .navigationDestination(for: BrowseFilterRoute.self) { FilteredGridView(route: $0) }
                    .navigationDestination(for: PublicDomainRoute.self) { _ in PublicDomainView() }
                    .navigationDestination(for: CartoonRoute.self) { _ in CartoonView() }
                    .navigationDestination(for: PartyRoute.self) { _ in PartyPlayView() }
            }
        }
    }

    private func exitScreensaver() {
        setFullScreen(false)
        router.screensaverActive = false
    }
    private func setFullScreen(_ on: Bool) {
        guard let w = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first else { return }
        if w.styleMask.contains(.fullScreen) != on { w.toggleFullScreen(nil) }
    }

    @ViewBuilder private var sectionContent: some View {
        switch router.section {
        case .home:        HomeView()
        case .movies:      BrowseView(contentType: nil, title: "Movies")
        case .tv:          TVBrowseView()
        case .channels:    ChannelsView()
        case .collections: CollectionsList()
        case .surprise:    SurpriseView()
        case .search:      SearchView()
        case .library:     LibraryView()
        case .create:      CreationStudioLanding()
        }
    }
}

// Creation Studio is a Mac-exclusive DocumentGroup editor (Decision 042). This in-app landing
// makes it reachable from the main window (not just File ▸ New): start a new project or reopen
// a recent one — each opens its own editor window.
private struct CreationStudioLanding: View {
    @State private var recents: [URL] = []

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "movieclapper.fill")
                .font(.system(size: 60)).foregroundStyle(.tint)
            Text("Creation Studio").font(.largeTitle.bold())
            Text("Cut public-domain films from the archive into clips, montages, and supercuts — then export to share. A Mac-only editor.")
                .font(.title3).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 480)

            HStack(spacing: 12) {
                Button { NSDocumentController.shared.newDocument(nil) } label: {
                    Label("New Project", systemImage: "plus").padding(.horizontal, 6)
                }
                .controlSize(.large).buttonStyle(.borderedProminent).keyboardShortcut("n")
                Button { openProject() } label: {
                    Label("Open Project…", systemImage: "folder").padding(.horizontal, 6)
                }
                .controlSize(.large).keyboardShortcut("o")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Recent Projects").font(.headline).padding(.bottom, 2)
                if recents.isEmpty {
                    Text("Projects you save will appear here. Use New Project to start one, or Open Project… to load an existing .archiveproj.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(recents.prefix(10), id: \.self) { url in
                        Button {
                            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                        } label: {
                            Label(url.deletingPathExtension().lastPathComponent, systemImage: "movieclapper")
                        }
                        .buttonStyle(.link)
                    }
                }
            }
            .frame(maxWidth: 480, alignment: .leading)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .navigationTitle("Creation Studio")
        .onAppear { recents = NSDocumentController.shared.recentDocumentURLs }
        // Refresh after a save in a document window (recents update when the app re-activates).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            recents = NSDocumentController.shared.recentDocumentURLs
        }
    }

    private func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.archiveProject]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
    }
}
#endif
