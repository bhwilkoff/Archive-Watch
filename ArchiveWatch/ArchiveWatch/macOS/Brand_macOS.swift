#if os(macOS)
import SwiftUI

// Brand tokens for the Mac — the same two constants as iOS's `Brand`
// (Design_iOS.swift) and css/:root. The Studio wrote the marquee orange three
// ways (a hex string twice, RGB components three times); one name now.
// Warnings keep the SYSTEM orange: the brand color is chrome, never a signal
// that something is wrong (CLAUDE.md's shared design system).
enum Brand {
    static let primary = Color(hex: "#FF5C35") ?? .orange   // marquee orange
    static let accent  = Color(hex: "#0047FF") ?? .blue     // links / interactive
}
#endif
