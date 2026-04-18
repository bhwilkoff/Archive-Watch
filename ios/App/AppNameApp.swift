import SwiftUI
import SwiftData

// Rename this type + file to `ArchiveWatchApp` when the Xcode tvOS
// project is created. The name must match the Product Name exactly.

@main
struct AppNameApp: App {
    init() {
        URLCache.shared = URLCache(
            memoryCapacity: 100_000_000,  // 100 MB
            diskCapacity: 500_000_000     // 500 MB
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView {
                ContentView().environment(AppStore())
            }
        }
        .modelContainer(for: [ContentItem.self])
    }
}

// Tiny wrapper whose only job is to access the model context injected
// by `.modelContainer(for:)` and run the seed-catalog prime on first
// launch. Kept as a separate view so the content gets the real
// context, not one from a second container.
private struct RootView<Content: View>: View {
    @Environment(\.modelContext) private var modelContext
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .task { SeedCatalog.prime(into: modelContext) }
    }
}
