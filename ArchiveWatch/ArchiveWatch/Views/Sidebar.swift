import SwiftUI

// Overlay sidebar. Presents as a Liquid Glass panel over the content
// rather than a rail that pushes content aside. Visible only when
// RootView toggles it in (edge-trigger caught a left-arrow from
// content). Pressing right-arrow from the rightmost item — or Menu /
// Back — dismisses and hands focus back to the content area.

struct SidebarOverlay: View {
    @Binding var tab: Router.Tab
    let onDismiss: () -> Void

    @FocusState private var focused: Router.Tab?
    private let accent = Color(hex: "#FF5C35") ?? .orange
    private let panelWidth: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            brand
                .padding(.top, 56)
                .padding(.bottom, 32)
                .padding(.horizontal, 24)

            ForEach(Router.Tab.allCases) { navTab in
                row(for: navTab)
                    .focused($focused, equals: navTab)
            }

            Spacer(minLength: 0)
        }
        .frame(width: panelWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            // Liquid Glass panel — translucent, content flows beneath.
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
        )
        .overlay(alignment: .trailing) {
            // Fine trailing divider so the panel reads as a discrete
            // surface over the content, not a bleed.
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
                .ignoresSafeArea()
        }
        .defaultFocus($focused, tab, priority: .userInitiated)
        .onExitCommand { onDismiss() }
    }

    // MARK: - Row

    private func row(for navTab: Router.Tab) -> some View {
        Button {
            tab = navTab
            onDismiss()
        } label: {
            HStack(spacing: 18) {
                Image(systemName: navTab.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 36, height: 36)
                Text(navTab.title)
                    .font(.system(size: 23, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(SidebarRowStyle(
            selected: tab == navTab,
            expanded: true,
            accent: accent
        ))
        .focusEffectDisabled()
        // Right-arrow at the row dismisses — hands focus back to the
        // content area beneath.
        .onMoveCommand { direction in
            if direction == .right { onDismiss() }
        }
    }

    private var brand: some View {
        HStack(spacing: 14) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 30, weight: .bold))
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
            Spacer(minLength: 0)
        }
    }
}
