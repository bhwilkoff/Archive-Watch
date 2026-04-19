import SwiftUI

// Canonical tvOS motion tokens. Mirrors docs/tvos-playbook.md §6 so the
// app's animation "feel" stays coherent and native — not a bag of one-off
// .easeOut(0.12) calls that read as stiff on a 10ft screen.
//
// Use these tokens everywhere. Don't invent ad-hoc animations.

enum Motion {
    /// Focus scale for tiles, cards, posters. Spring is critically-damped
    /// (~400ms) so it settles without overshoot — matches Apple's own
    /// `UIFocusAnimationCoordinator` timing.
    static let focus = Animation.spring(response: 0.4, dampingFraction: 0.82, blendDuration: 0)

    /// Snappy press-down for button activation feedback.
    static let press = Animation.spring(response: 0.25, dampingFraction: 0.75, blendDuration: 0)

    /// Default transition for view-level state swaps, sheet / modal present.
    static let transition = Animation.smooth(duration: 0.45)

    /// Ease for horizontal shelf auto-scroll — no spring (overshoot on
    /// content scroll is disorienting at 10ft).
    static let shelfScroll = Animation.timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.5)

    /// Tab / sidebar expand/collapse. Short, no bounce.
    static let chrome = Animation.easeInOut(duration: 0.28)

    /// Hero carousel crossfade between items.
    static let heroCrossfade = Animation.easeInOut(duration: 0.8)

    /// Focus scale factor for posters / cards.
    static let focusScalePoster: CGFloat = 1.08

    /// Focus scale factor for primary buttons.
    static let focusScaleButton: CGFloat = 1.06

    /// Focus scale factor for sidebar rows.
    static let focusScaleRow: CGFloat = 1.05
}
