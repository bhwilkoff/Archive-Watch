import SwiftUI

// Primary navigation rail. Collapses to a narrow icon strip when focus
// is elsewhere; expands to a labeled rail when any row holds focus.
// Proportions tuned so icons line up between brand and rows and the
// collapsed width doesn't waste stage on either side of the glyph.

struct Sidebar: View {
    @Environment(Router.self) private var router
    @FocusState private var focusedTab: Router.Tab?

    private var isExpanded: Bool { focusedTab != nil }

    private let collapsedWidth: CGFloat = 96
    private let expandedWidth:  CGFloat = 280
    private let accent = Color(hex: "#FF5C35") ?? .orange

    var body: some View {
        VStack(spacing: 6) {
            brandMark
                .padding(.top, 48)
                .padding(.bottom, 28)

            ForEach(Router.Tab.allCases) { tab in
                Button {
                    router.select(tab)
                } label: {
                    row(for: tab)
                }
                .buttonStyle(SidebarRowStyle(
                    selected: router.tab == tab,
                    expanded: isExpanded,
                    accent: accent
                ))
                .focusEffectDisabled()
                .focused($focusedTab, equals: tab)
            }

            Spacer(minLength: 0)
        }
        .frame(width: isExpanded ? expandedWidth : collapsedWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(sidebarBackground)
        .animation(Motion.chrome, value: isExpanded)
        .focusSection()
    }

    // Row label — HStack that holds the icon at a fixed x so icons align
    // vertically between brand and rows, collapsed or expanded.
    @ViewBuilder
    private func row(for tab: Router.Tab) -> some View {
        HStack(spacing: 18) {
            Image(systemName: tab.icon)
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 36, height: 36)
            if isExpanded {
                Text(tab.title)
                    .font(.system(size: 23, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .transition(.opacity)
                Spacer(minLength: 0)
            }
        }
    }

    // Brand mark — same icon column width as rows so the moon glyph
    // sits directly above the nav glyphs. No floating misalignment.
    private var brandMark: some View {
        HStack(spacing: 18) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ARCHIVE")
                        .font(.system(size: 13, weight: .black))
                        .tracking(2.5)
                        .foregroundStyle(.white.opacity(0.55))
                    Text("Watch")
                        .font(.system(size: 23, weight: .heavy, design: .serif))
                        .foregroundStyle(.white)
                }
                .transition(.opacity)
                Spacer(minLength: 0)
            }
        }
        // Match the row style's accent-bar offset (4pt) + interior
        // padding (16pt) so icons line up with row icons below.
        .padding(.leading, isExpanded ? 30 : 0)
        .padding(.trailing, isExpanded ? 16 : 0)
        .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
    }

    @ViewBuilder
    private var sidebarBackground: some View {
        ZStack(alignment: .trailing) {
            // Dark-first gradient (playbook §5). Gives the rail presence
            // without reading as a hard-edged stripe.
            LinearGradient(
                colors: [Color.black, Color(white: 0.03)],
                startPoint: .top, endPoint: .bottom
            )
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
        }
        .ignoresSafeArea()
    }
}
