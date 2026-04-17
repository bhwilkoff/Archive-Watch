import SwiftUI

/// Global app state — injected via @Environment(AppStore.self).
/// Uses @Observable (iOS 17+) for automatic SwiftUI updates.
@Observable
final class AppStore {
    var navigationPath = NavigationPath()
    var selectedTab: String? = "home"

    // FILL IN: Add app-wide state here
    // Examples:
    // var unreadCount = 0
    // var currentUserAvatar: String?
}
