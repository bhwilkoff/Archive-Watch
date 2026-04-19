import SwiftUI

// Primary navigation rail. Collapses to a 120pt icon strip when focus is
// elsewhere; expands to 320pt with labels when any row holds focus.
// Selection is rendered with a solid accent fill + white stroke so it
// reads clearly at 10ft (per docs/tvos-playbook.md §5 — focus is the
// single strongest brightness affordance, but persistent selection needs
// to be unmistakable too).

struct Sidebar: View {
    @Environment(Router.self) private var router
    @FocusState private var focusedTab: Router.Tab?

    private var isExpanded: Bool { focusedTab != nil }
    private let collapsedWidth: CGFloat = 120
    private let expandedWidth:  CGFloat = 320
    private let accent = Color(hex: "#FF5C35") ?? .orange

    var body: some View {
        VStack(spacing: 6) {
            brandMark
                .padding(.top, 56)
                .padding(.bottom, 40)

            ForEach(Router.Tab.allCases) { tab in
                Button {
                    router.select(tab)
                } label: {
                    HStack(spacing: 18) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 24, weight: .semibold))
                            .frame(width: 32, height: 32)
                        if isExpanded {
                            Text(tab.title)
                                .font(.system(size: 20, weight: .semibold))
                                .lineLimit(1)
                                .transition(.opacity)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .buttonStyle(SidebarRowStyle(
                    selected: router.tab == tab,
                    expanded: isExpanded,
                    accent: accent
                ))
                .focusEffectDisabled()
                .focused($focusedTab, equals: tab)
            }

            Spacer()
        }
        .frame(width: isExpanded ? expandedWidth : collapsedWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(sidebarBackground)
        .animation(Motion.chrome, value: isExpanded)
        // Focus section means the sidebar forms one traversal unit —
        // tvOS picks a sibling section (content) when the user presses
        // right-arrow past the rail's edge.
        .focusSection()
    }

    private var brandMark: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 44, height: 44)
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ARCHIVE")
                        .font(.system(size: 11, weight: .black))
                        .tracking(2.5)
                        .foregroundStyle(.white.opacity(0.55))
                    Text("Watch")
                        .font(.system(size: 20, weight: .heavy, design: .serif))
                        .foregroundStyle(.white)
                }
                .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var sidebarBackground: some View {
        ZStack(alignment: .trailing) {
            // Dark-first, per §5. Gradient keeps the rail from reading as
            // a solid stripe on top of busy hero art.
            LinearGradient(
                colors: [Color.black, Color(white: 0.05)],
                startPoint: .top, endPoint: .bottom
            )
            // Hairline separator gives the rail presence without a heavy
            // divider — same move as Apple TV's own sidebar.
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
        }
        .ignoresSafeArea()
    }
}
