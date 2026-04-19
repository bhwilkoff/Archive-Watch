import SwiftUI

// Custom PrimitiveButtonStyles for tvOS. Per docs/tvos-playbook.md §2.1,
// .buttonStyle(.plain) silently destroys focusability on tvOS — it's a
// trap to avoid. These styles read @Environment(\.isFocused) to render
// our own focus treatment and pair with .focusEffectDisabled() to
// suppress the default halo.
//
// Use .buttonStyle(.card) from Apple when you want stock poster
// parallax. These styles cover every other case.

// MARK: - Poster-like content (shelves, grids)

struct PosterButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    struct StyleBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: PrimitiveButtonStyleConfiguration

        var body: some View {
            configuration.label
                .scaleEffect(isFocused ? Motion.focusScalePoster : 1.0)
                .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: 24, y: 10)
                .animation(Motion.focus, value: isFocused)
                .contentShape(Rectangle())
                .onTapGesture { configuration.trigger() }
        }
    }
}

// MARK: - Chip / filter bubble

struct ChipButtonStyle: PrimitiveButtonStyle {
    let accent: Color
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, accent: accent, isOn: isOn)
    }

    struct StyleBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: PrimitiveButtonStyleConfiguration
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
                .contentShape(Capsule())
                .onTapGesture { configuration.trigger() }
        }
    }
}

// MARK: - Sidebar row

struct SidebarRowStyle: PrimitiveButtonStyle {
    let selected: Bool
    let expanded: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, selected: selected, expanded: expanded, accent: accent)
    }

    struct StyleBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: PrimitiveButtonStyleConfiguration
        let selected: Bool
        let expanded: Bool
        let accent: Color

        var body: some View {
            configuration.label
                .foregroundStyle(rowForeground)
                .padding(.horizontal, expanded ? 20 : 0)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: expanded ? .leading : .center)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(rowFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(rowStroke, lineWidth: isFocused ? 2 : 1)
                        )
                        .padding(.horizontal, expanded ? 12 : 14)
                )
                .scaleEffect(isFocused ? Motion.focusScalePoster :
                             selected ? Motion.focusScaleRow : 1.0)
                .shadow(color: shadowColor, radius: isFocused ? 18 : 10, y: 4)
                .animation(Motion.focus, value: isFocused)
                .animation(Motion.chrome, value: selected)
                .contentShape(Rectangle())
                .onTapGesture { configuration.trigger() }
        }

        private var rowForeground: Color {
            if isFocused { return .white }
            if selected { return .white }
            return .white.opacity(0.55)
        }

        private var rowFill: Color {
            if isFocused { return .white.opacity(0.18) }
            if selected { return accent.opacity(0.85) }
            return .clear
        }

        private var rowStroke: Color {
            if isFocused { return .white }
            if selected { return accent }
            return .white.opacity(0.06)
        }

        private var shadowColor: Color {
            if isFocused { return .black.opacity(0.4) }
            if selected  { return accent.opacity(0.5) }
            return .clear
        }
    }
}

// MARK: - Primary CTA (Play button, Roll Again, etc.)

struct PrimaryCTAStyle: PrimitiveButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, accent: accent)
    }

    struct StyleBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: PrimitiveButtonStyleConfiguration
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
                .contentShape(Capsule())
                .onTapGesture { configuration.trigger() }
        }
    }
}

// MARK: - Icon-only circular button (Favorite heart)

struct CircleIconStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    struct StyleBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: PrimitiveButtonStyleConfiguration

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
                .contentShape(Circle())
                .onTapGesture { configuration.trigger() }
        }
    }
}
