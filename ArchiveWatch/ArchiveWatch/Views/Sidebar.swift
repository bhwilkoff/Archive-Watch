import SwiftUI

// Collapsible primary navigation. Expands when any sidebar row holds
// focus (so it reveals labels + gets out of the user's way for content
// when focus is elsewhere). UHF / Channels-style: subtle, quiet, pins
// the visual identity of the app without stealing the stage.

struct Sidebar: View {
    @Environment(Router.self) private var router
    @FocusState private var focusedTab: Router.Tab?

    private var isExpanded: Bool { focusedTab != nil }

    var body: some View {
        @Bindable var router = router

        VStack(alignment: .leading, spacing: 8) {
            brandMark
                .padding(.top, 48)
                .padding(.bottom, 32)
                .padding(.horizontal, isExpanded ? 28 : 24)

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
        .frame(width: isExpanded ? 320 : 104, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color.black, Color(white: 0.04)],
                startPoint: .top, endPoint: .bottom
            )
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            )
        )
        .animation(.easeOut(duration: 0.22), value: isExpanded)
    }

    private var brandMark: some View {
        HStack(spacing: 14) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color(hex: "#FF5C35") ?? .orange)
                .frame(width: 48, height: 48)
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ARCHIVE")
                        .font(.system(size: 12, weight: .black))
                        .tracking(2.5)
                        .foregroundStyle(.white.opacity(0.55))
                    Text("Watch")
                        .font(.system(size: 22, weight: .heavy, design: .serif))
                        .foregroundStyle(.white)
                }
                .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct SidebarRow: View {
    let tab: Router.Tab
    let selected: Bool
    let expanded: Bool
    let action: () -> Void

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                ZStack {
                    if selected {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: "#FF5C35") ?? .orange)
                            .frame(width: 4, height: 28)
                    } else {
                        Color.clear.frame(width: 4, height: 28)
                    }
                }
                Image(systemName: tab.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 32)
                if expanded {
                    Text(tab.title)
                        .font(.system(size: 20, weight: .semibold))
                        .transition(.opacity)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(
                isFocused ? .white :
                selected ? .white : .white.opacity(0.55)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isFocused ? Color.white.opacity(0.18) :
                        selected ? Color.white.opacity(0.06) : .clear
                    )
            )
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .scaleEffect(isFocused ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}
