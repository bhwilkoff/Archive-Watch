import SwiftUI

// Custom ButtonStyles for tvOS. Per docs/tvos-playbook.md §2.1,
// .buttonStyle(.plain) silently destroys focusability on tvOS — these
// styles cover every other case without tripping that landmine.
//
// Key choice: ButtonStyle, not PrimitiveButtonStyle. SwiftUI's Button
// handles clickpad-center activation natively with ButtonStyle; the
// .onTapGesture trick that's standard on iOS/macOS PrimitiveButtonStyle
// does NOT reliably fire on tvOS's remote (that's what was making the
// sidebar feel "nonfunctional"). Each style reads
// @Environment(\.isFocused) inside the makeBody view to drive the
// custom focus treatment, and is paired with .focusEffectDisabled() at
// the call site to suppress the default tvOS halo.

// MARK: - Poster-like content (shelves, grids)

struct PosterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    struct StyleBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyleConfiguration

        var body: some View {
            configuration.label
                .scaleEffect(isFocused ? Motion.focusScalePoster : 1.0)
                .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: 24, y: 10)
                .animation(Motion.focus, value: isFocused)
        }
    }
}

// MARK: - Chip / filter bubble

struct ChipButtonStyle: ButtonStyle {
    let accent: Color
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, accent: accent, isOn: isOn)
    }

    struct StyleBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyleConfiguration
        let accent: Color
        let isOn: Bool

        var body: some View {
            configuration.label
                .font(.callout.weight(.semibold))
                .foregroundStyle(
                    isFocused ? Color.white :
                    isOn ? Color.white : Color.white.opacity(0.85)
                )
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    Capsule().fill(
                        isFocused ? accent :
                        isOn ? accent.opacity(0.9) :
                        Color.white.opacity(0.08)
                    )
                )
                .overlay(
                    Capsule().strokeBorder(
                        isFocused ? Color.white :
                        isOn ? accent : Color.white.opacity(0.12),
                        lineWidth: isFocused ? 3 : 1
                    )
                )
                .scaleEffect(isFocused ? Motion.focusScaleButton : 1.0)
                .shadow(color: isFocused ? accent.opacity(0.6) : .clear, radius: 16, y: 4)
                .animation(Motion.focus, value: isFocused)
        }
    }
}

// MARK: - Sidebar row
//
// Apple TV 17.2+ sidebar pattern: selection is a quiet 4pt accent bar
// on the leading edge + bolder text — NOT a full accent-fill pill. The
// focus state is the only "loud" affordance. This keeps the sidebar
// from dominating the stage when the user is deep in content.

struct SidebarRowStyle: ButtonStyle {
    let selected: Bool
    let expanded: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, selected: selected, expanded: expanded, accent: accent)
    }

    struct StyleBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        let expanded: Bool
        let accent: Color

        var body: some View {
            HStack(spacing: 0) {
                // Leading accent bar: only present when selected.
                // Persistent visual cue that doesn't shout.
                Rectangle()
                    .fill(selected ? accent : Color.clear)
                    .frame(width: 4)
                    .padding(.vertical, 4)

                configuration.label
                    .foregroundStyle(rowForeground)
                    .padding(.leading, expanded ? 16 : 0)
                    .padding(.trailing, expanded ? 16 : 0)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: expanded ? .leading : .center)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? Color.white.opacity(0.14) : Color.clear)
                    .padding(.horizontal, expanded ? 12 : 14)
            )
            .scaleEffect(isFocused ? Motion.focusScaleButton : 1.0)
            .animation(Motion.focus, value: isFocused)
            .animation(Motion.chrome, value: selected)
        }

        private var rowForeground: Color {
            if isFocused { return .white }
            if selected { return .white }
            return .white.opacity(0.55)
        }
    }
}

// MARK: - Primary CTA (Play button, Roll Again, etc.)

struct PrimaryCTAStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, accent: accent)
    }

    struct StyleBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyleConfiguration
        let accent: Color

        var body: some View {
            configuration.label
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [accent, accent.mix(with: .black, 0.15)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                )
                .overlay(
                    Capsule().strokeBorder(
                        isFocused ? Color.white : Color.white.opacity(0.15),
                        lineWidth: isFocused ? 3 : 1
                    )
                )
                .scaleEffect(isFocused ? Motion.focusScaleButton : 1.0)
                .shadow(color: accent.opacity(isFocused ? 0.7 : 0.35),
                        radius: isFocused ? 24 : 14, y: 6)
                .animation(Motion.focus, value: isFocused)
        }
    }
}

// MARK: - Icon-only circular button (Favorite heart)

struct CircleIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    struct StyleBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyleConfiguration

        var body: some View {
            configuration.label
                .background(
                    Circle().fill(
                        isFocused ? Color.white.opacity(0.25) : Color.white.opacity(0.08)
                    )
                )
                .overlay(
                    Circle().strokeBorder(
                        isFocused ? Color.white : Color.white.opacity(0.12),
                        lineWidth: isFocused ? 3 : 1
                    )
                )
                .scaleEffect(isFocused ? Motion.focusScaleButton : 1.0)
                .animation(Motion.focus, value: isFocused)
        }
    }
}
