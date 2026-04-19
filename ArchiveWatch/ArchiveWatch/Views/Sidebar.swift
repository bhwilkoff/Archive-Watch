import SwiftUI

// Primary navigation rail. Collapses to a narrow icon strip when focus
// is elsewhere, expands when any row holds focus. Wrapped in a
// GlassEffectContainer so the Liquid Glass transitions between row
// states morph together instead of flashing individually (the tvOS 26
// canonical pattern for grouped glass surfaces — WWDC25 "Meet Liquid
// Glass").
//
// Text labels use `.opacity` + a clipped container rather than an
// `if isExpanded` block so they fade coherently with the width change
// and never ghost past the collapse.

struct Sidebar: View {
    @Environment(Router.self) private var router
    @FocusState private var focusedTab: Router.Tab?

    private var isExpanded: Bool { focusedTab != nil }

    private let collapsedWidth: CGFloat = 96
    private let expandedWidth:  CGFloat = 280
    private let accent = Color(hex: "#FF5C35") ?? .orange

    var body: some View {
        GlassEffectContainer {
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
            // Clip the container so any text mid-fade during the
            // collapse animation can't paint outside the new width.
            .clipped()
            .background(sidebarBackground)
            .animation(Motion.chrome, value: isExpanded)
        }
        .focusSection()
    }

    // Row label. Text is always in the tree (no `if`) so the opacity
    // + width animation fades it out coherently rather than removing
    // it mid-transition.
    @ViewBuilder
    private func row(for tab: Router.Tab) -> some View {
        HStack(spacing: 18) {
            Image(systemName: tab.icon)
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 36, height: 36)
            Text(tab.title)
                .font(.system(size: 23, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: true, vertical: false)
                .opacity(isExpanded ? 1 : 0)
            Spacer(minLength: 0)
                .opacity(isExpanded ? 1 : 0)
        }
    }

    private var brandMark: some View {
        HStack(spacing: 18) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("ARCHIVE")
                    .font(.system(size: 13, weight: .black))
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.55))
                Text("Watch")
                    .font(.system(size: 23, weight: .heavy, design: .serif))
                    .foregroundStyle(.white)
            }
            .fixedSize()
            .opacity(isExpanded ? 1 : 0)
            Spacer(minLength: 0)
                .opacity(isExpanded ? 1 : 0)
        }
        .padding(.leading, isExpanded ? 30 : 0)
        .padding(.trailing, isExpanded ? 16 : 0)
        .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
    }

    @ViewBuilder
    private var sidebarBackground: some View {
        ZStack(alignment: .trailing) {
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
