import SwiftUI

// Top-level shell. Two-pane layout: sidebar on the left, content on the
// right. No TabView, no NavigationStack — everything lives in one
// continuous focus realm so the tvOS focus engine can traverse the
// entire app with arrow keys.
//
// Back button (Menu on the remote) pops the current push stack; when
// already at a tab root it does nothing, matching tvOS convention.

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            ContentArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Mark content as its own focus section. Paired with the
                // Sidebar's .focusSection(), this tells tvOS to treat the
                // two panes as neighbors the focus engine can step
                // between with left/right arrow keys.
                .focusSection()
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onExitCommand {
            if !router.isAtRoot { router.pop() }
        }
        .onAppear {
            #if DEBUG
            LayoutCheck.runAll(store: store)
            #endif
        }
    }
}

struct ContentArea: View {
    @Environment(Router.self) private var router

    var body: some View {
        // Show the topmost pushed destination if any; otherwise the
        // active tab's root view. All swaps happen inside this single
        // container — no NavigationStack, no focus realm boundary.
        Group {
            if let top = router.stack.last {
                switch top {
                case .item(let item):
                    DetailView(item: item)
                case .filter(let filter):
                    BrowseView(filter: filter)
                }
            } else {
                switch router.tab {
                case .home:        HomeView()
                case .browse:      BrowseView()
                case .collections: CollectionsView()
                case .search:      SearchView()
                case .surprise:    SurpriseView()
                }
            }
        }
    }
}
