import SwiftUI

// Collapsible primary navigation. Expands when any sidebar row holds
// focus and collapses back to an icon rail when focus moves to the
// content area. UHF / Channels-style: quiet at rest, reveals structure
// on attention.

struct Sidebar: View {
    @Environment(Router.self) private var router
    @FocusState private var focusedTab: Router.Tab?

    private var isExpanded: Bool { focusedTab != nil }

    // Collapsed is narrow enough to feel like a rail but wide enough to
    // comfortably center the glyph. Expanded gives room for full labels.
    private let collapsedWidth: CGFloat = 120
    private let expandedWidth:  CGFloat = 320

    var body: some View {
        VStack(spacing: 4) {
            brandMark
                .padding(.top, 56)
                .padding(.bottom, 40)

            ForEach(Router.Tab.allCases) { tab in
                SidebarRow(
                    tab: tab,
                    selected: router.tab == tab,
                    expanded: isExpanded
                ) {
                    router.select(tab)
                }
                .focused($focusedTab, equals: tab)
            }

            Spacer()
        }
        .frame(width: isExpanded ? expandedWidth : collapsedWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            ZStack(alignment: .trailing) {
                LinearGradient(
                    colors: [Color.black, Color(white: 0.04)],
                    startPoint: .top, endPoint: .bottom
                )
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)
            }
            .ignoresSafeArea()
        )
        .animation(.easeOut(duration: 0.22), value: isExpanded)
        // Declare the whole sidebar as one focus section so tvOS treats
        // the content area as a distinct neighbor. Right-arrow out of any
        // row travels to the content section cleanly.
        .focusSection()
    }

    private var brandMark: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color(hex: "#FF5C35") ?? .orange)
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
}

private struct SidebarRow: View {
    let tab: Router.Tab
    let selected: Bool
    let expanded: Bool
    let action: () -> Void

    @Environment(\.isFocused) private var isFocused

    private var accent: Color { Color(hex: "#FF5C35") ?? .orange }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: tab.icon)
                    .font(.system(size: selected ? 24 : 22, weight: .semibold))
                    .frame(width: 32, height: 32)
                if expanded {
                    Text(tab.title)
                        .font(.system(size: selected ? 20 : 19,
                                      weight: selected ? .bold : .semibold))
                        .transition(.opacity)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(
                isFocused ? .white :
                selected ? accent : .white.opacity(0.55)
            )
            .padding(.horizontal, expanded ? 24 : 0)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: expanded ? .leading : .center)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isFocused ? Color.white.opacity(0.22) :
                        selected ? accent.opacity(0.22) : .clear
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                selected && !isFocused ? accent.opacity(0.55) : .clear,
                                lineWidth: 1.5
                            )
                    )
                    .padding(.horizontal, expanded ? 12 : 14)
            )
            .overlay(alignment: .leading) {
                if selected && expanded {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent)
                        .frame(width: 4, height: 28)
                        .padding(.leading, 4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        // Both focused and selected deserve visual weight. Focused is the
        // strongest (user is acting on it); selected is persistent state.
        .scaleEffect(isFocused ? 1.08 : selected ? 1.05 : 1.0)
        .shadow(color: selected && !isFocused ? accent.opacity(0.35) : .clear,
                radius: 10, y: 2)
        .animation(.easeOut(duration: 0.12), value: isFocused)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}
