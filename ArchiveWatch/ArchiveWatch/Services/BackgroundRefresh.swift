import BackgroundTasks
import Foundation

// Background "What's New" refresh (Decision 015 / M4).
//
// Keeps the catalog disk cache current so the next launch — and the Top
// Shelf snapshot rebuilt then — reflects fresh uploads. The identifier is
// declared in Info.plist (BGTaskSchedulerPermittedIdentifiers) and the
// handler is registered via the SwiftUI `.backgroundTask(.appRefresh:)`
// modifier on the app scene.

enum BackgroundRefresh {
    static let identifier = "com.bhwilkoff.archivewatch.refresh"

    /// Submit the next app-refresh request. Safe to call repeatedly; the
    /// scheduler coalesces duplicate identifiers.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60) // ~6h
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Runs when the system grants background time: refresh the catalog
    /// cache, then re-arm for next time.
    static func run() async {
        _ = await CatalogRefreshService.shared.refresh()
        schedule()
    }
}
