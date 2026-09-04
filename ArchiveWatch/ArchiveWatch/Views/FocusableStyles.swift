#if os(tvOS)
import SwiftUI

// ButtonStyles for tvOS 26. Each uses Liquid Glass where the tvOS 26
// HIG prescribes it (chips, CTAs, icon buttons, sidebar rows), reads
// @Environment(\.isFocused) for a custom focus treatment, and pairs
// with .focusEffectDisabled() at call sites to suppress the default
// halo. Per docs/tvos-playbook.md §2.1: never .buttonStyle(.plain) —
// it silently breaks focusability on tvOS.

// MARK: - Poster-like content (shelves, grids)
//
// Poster tiles use the system .buttonStyle(.card) at call sites, not
// this style — .card gives us Apple's parallax + focus ring for free.
// Kept here for non-image tappable tiles.

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
                .foregroundStyle(chipForeground)
                .padding(.horizontal, 26)
                .padding(.vertical, 14)
                .glassEffect(chipGlass, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isFocused ? Color.white : (isOn ? accent : Color.white.opacity(0.12)),
                            lineWidth: isFocused ? 3 : (isOn ? 2 : 1)
                        )
                )
                .scaleEffect(isFocused ? Motion.focusScaleButton : 1.0)
                .animation(Motion.focus, value: isFocused)
        }

        private var chipGlass: Glass {
            if isFocused || isOn {
                return .regular.tint(accent).interactive()
            }
            return .regular.interactive()
        }

        private var chipForeground: Color {
            if isFocused { return .white }
            if isOn { return .white }
            return .white.opacity(0.85)
        }
    }
}

// MARK: - Sidebar row
//
// Apple TV 17.2+ sidebar pattern, upgraded to Liquid Glass for tvOS 26:
// selection is a quiet 4pt accent bar on the leading edge + bolder
// text. Focus pours a tinted Liquid Glass panel behind the row with
// a soft interactive sheen. No loud accent-fill pill.

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
                // Leading accent bar — persistent selection cue that
                // doesn't shout. Absent when not selected so the rail
                // reads quiet at rest.
                Rectangle()
                    .fill(selected ? accent : Color.clear)
                    .frame(width: 4)
                    .padding(.vertical, 6)

                configuration.label
                    .foregroundStyle(rowForeground)
                    .padding(.leading, expanded ? 16 : 0)
                    .padding(.trailing, expanded ? 16 : 0)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: expanded ? .leading : .center)
            }
            .glassEffect(rowGlass, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 10)
            .scaleEffect(isFocused ? Motion.focusScaleButton : 1.0)
            .animation(Motion.focus, value: isFocused)
            .animation(Motion.chrome, value: selected)
        }

        private var rowGlass: Glass {
            // Focused: interactive glass that responds to Siri Remote.
            // Unfocused + selected: a whisper of tint so the row has
            //   presence without competing with content.
            // Default: clear glass (which reads as near-nothing).
            if isFocused {
                return .regular.tint(accent.opacity(0.35)).interactive()
            }
            if selected {
                return .regular.tint(accent.opacity(0.15))
            }
            return .clear
        }

        private var rowForeground: Color {
            if isFocused { return .white }
            if selected { return .white }
            return .white.opacity(0.55)
        }
    }
}

// MARK: - Primary CTA (Play, Roll Again, etc.)

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
                .glassEffect(.regular.tint(accent).interactive(), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isFocused ? Color.white : Color.white.opacity(0.2),
                        lineWidth: isFocused ? 3 : 1
                    )
                )
                .scaleEffect(isFocused ? Motion.focusScaleButton : 1.0)
                .shadow(color: accent.opacity(isFocused ? 0.55 : 0.25),
                        radius: isFocused ? 28 : 16, y: 6)
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
                .glassEffect(.regular.interactive(), in: Circle())
                .overlay(
                    Circle().strokeBorder(
                        isFocused ? Color.white : Color.white.opacity(0.15),
                        lineWidth: isFocused ? 3 : 1
                    )
                )
                .scaleEffect(isFocused ? Motion.focusScaleButton : 1.0)
                .animation(Motion.focus, value: isFocused)
        }
    }
}

// Legible utility / chrome button for dark surfaces (Channels header, failure
// screens, sheet secondaries). Guarantees contrast in BOTH focus states:
// unfocused = white text on a faint capsule (reads on dark chrome); focused =
// black text on a solid white capsule. Replaces the system `.bordered` (which
// rendered low-contrast ACCENT text on dark) and the `.tint(.white)` hack (which
// produced white-text-on-white-fill when focused).
// MARK: - Reading block
//
// For long-form text a viewer must be able to reach, scroll to and READ: a
// synopsis, a review. Focus changes NOTHING about the geometry — no padding
// swing, no line-limit swing, no scale. That rule is the whole point of this
// style: the previous synopsis block expanded from 6 lines to its full length
// while focused, so the page reflowed every time focus passed through it on
// the way down (owner, 2026-09-04: "the description text reflows multiple
// times as you scroll down the page"). A block that resizes as focus crosses
// it makes everything below it jump, repeatedly, while the viewer is trying
// to read.
//
// Focus is shown by a ring and a lift in contrast, both of which are free.
// Expanding is a deliberate Select, never a side effect of scrolling.
struct ReadingCardStyle: ButtonStyle {
    var padded: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, padded: padded)
    }

    struct StyleBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyleConfiguration
        let padded: Bool

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                // CONSTANT padding — not `isFocused ? 16 : 0`.
                .padding(padded ? 16 : 0)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(isFocused ? 0.10 : 0.0))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(isFocused ? 0.55 : 0.0),
                                      lineWidth: 2)
                }
                // No scaleEffect either: a scaled block shifts the text under
                // the viewer's eye mid-sentence.
                .animation(Motion.focus, value: isFocused)
        }
    }
}

struct BarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    struct StyleBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyleConfiguration

        var body: some View {
            configuration.label
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .foregroundStyle(isFocused ? Color.black : Color.white)
                .background(
                    isFocused ? AnyShapeStyle(Color.white)
                              : AnyShapeStyle(Color.white.opacity(0.16)),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(isFocused ? 0 : 0.28), lineWidth: 1)
                )
                .scaleEffect(isFocused ? Motion.focusScaleButton : 1.0)
                .animation(Motion.focus, value: isFocused)
        }
    }
}

#endif
