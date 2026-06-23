#if os(macOS)
import SwiftUI

// NavigationSplitView shell (docs/macOS-DESIGN.md §7): sidebar sections + a detail column
// that drills into Detail / Person / Collection. The player presents as a sheet over the
// detail column. Creation Studio gets its own DocumentGroup scene in a later phase.

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationSplitView {
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
                    .navigationDestination(for: ScreensaverRoute.self) { _ in ScreensaverView() }
            }
        }
        .sheet(item: $router.nowPlaying) { item in
            PlayerWindow(item: item)
                .frame(minWidth: 720, minHeight: 460)
        }
        .sheet(item: $router.nowPlayingEpisode) { ctx in
            EpisodePlayer(context: ctx)
                .frame(minWidth: 720, minHeight: 460)
        }
        .overlay {
            if !store.isReady {
                ProgressView("Loading catalog…").controlSize(.large)
            }
        }
    }

    @ViewBuilder private var sectionContent: some View {
        switch router.section {
        case .home:        HomeView()
        case .movies:      BrowseView(contentType: nil, title: "Movies")
        case .tv:          GridView(title: "TV", items: store.seriesCards())
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

            Button { NSDocumentController.shared.newDocument(nil) } label: {
                Label("New Project", systemImage: "plus").padding(.horizontal, 6)
            }
            .controlSize(.large).buttonStyle(.borderedProminent).keyboardShortcut("n")

            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Projects").font(.headline).padding(.bottom, 2)
                    ForEach(recents.prefix(8), id: \.self) { url in
                        Button {
                            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                        } label: {
                            Label(url.deletingPathExtension().lastPathComponent, systemImage: "doc.fill")
                        }
                        .buttonStyle(.link)
                    }
                }
                .frame(maxWidth: 480, alignment: .leading)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .navigationTitle("Creation Studio")
        .onAppear { recents = NSDocumentController.shared.recentDocumentURLs }
    }
}
#endif
