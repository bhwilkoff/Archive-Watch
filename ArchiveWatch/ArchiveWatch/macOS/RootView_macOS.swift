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
        case .home:    HomeView()
        case .movies:  BrowseView(contentType: nil, title: "Movies")
        case .tv:      GridView(title: "TV", items: store.seriesCards())
        case .search:  SearchView()
        case .library: LibraryView()
        }
    }
}
#endif
