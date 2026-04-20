import SwiftUI

// Top-level shell. Custom overlay sidebar + full-screen content.
//
// Why custom: TabView's .sidebarAdaptable on tvOS 26 always reserves
// a rail of screen, which the user reads as a "black band" next to
// the content. We want the sidebar to behave as a true overlay — a
// trigger strip at the left edge when hidden, a Liquid Glass panel
// sliding in when invoked. Content stays full-width, edge-to-edge.
//
// All five tab stacks live in a ZStack so switching tabs preserves
// scroll + focus state. Per-tab NavigationStack still handles back
// button restoration for pushed detail / filtered browse views.

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var sidebarShown: Bool = false
    @FocusState private var edgeTriggerFocused: Bool

    var body: some View {
        @Bindable var router = router

        ZStack(alignment: .leading) {
            // Content — all tab NavigationStacks, only the active one
            // is visible + hit-testable. Keeps per-tab state alive.
            contentArea(router: router)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusSection()

            // Invisible focus guide on the leading edge. Catches
            // left-arrow presses from content's leftmost column and
            // toggles the sidebar in.
            edgeTrigger

            // Sidebar overlay — Liquid Glass panel sliding in over the
            // content. Not present in the tree when hidden, so it
            // can't steal focus on launch.
            if sidebarShown {
                SidebarOverlay(
                    tab: $router.tab,
                    onDismiss: {
                        withAnimation(Motion.chrome) { sidebarShown = false }
                    }
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
                .focusSection()
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .animation(Motion.chrome, value: sidebarShown)
    }

    // Slim invisible trigger strip. tvOS's focus engine lands on this
    // when the user arrows left past the leftmost focusable in content;
    // we then show the sidebar and hand off focus.
    private var edgeTrigger: some View {
        Color.clear
            .frame(width: 12)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .focusable(true)
            .focused($edgeTriggerFocused)
            .onChange(of: edgeTriggerFocused) { _, focused in
                if focused {
                    withAnimation(Motion.chrome) { sidebarShown = true }
                    // Release the edge-trigger's focus so the sidebar
                    // can claim it via defaultFocus.
                    edgeTriggerFocused = false
                }
            }
    }

    @ViewBuilder
    private func contentArea(router: Router) -> some View {
        @Bindable var router = router
        ZStack {
            tabStack(.home, path: $router.homePath) { HomeView() }
            tabStack(.browse, path: $router.browsePath) { BrowseView() }
            tabStack(.collections, path: $router.collectionsPath) { CollectionsView() }
            tabStack(.search, path: $router.searchPath) { SearchView() }
            tabStack(.surprise, path: $router.surprisePath) { SurpriseView() }
        }
    }

    @ViewBuilder
    private func tabStack<Content: View>(
        _ tab: Router.Tab,
        path: Binding<NavigationPath>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let active = router.tab == tab
        NavigationStack(path: path) {
            content().attachDestinations()
        }
        .opacity(active ? 1 : 0)
        .allowsHitTesting(active)
    }
}

extension View {
    func attachDestinations() -> some View {
        self
            .navigationDestination(for: Catalog.Item.self) { item in
                DetailView(item: item)
            }
            .navigationDestination(for: BrowseFilter.self) { filter in
                BrowseView(filter: filter)
            }
    }
}
