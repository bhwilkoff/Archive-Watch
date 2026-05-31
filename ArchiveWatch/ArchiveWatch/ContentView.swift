import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if let error = store.loadError {
                LoadErrorView(message: error)
            } else if store.catalog != nil {
                RootView()
            } else {
                ProgressView("Loading catalog…")
                    .foregroundStyle(.white)
                    .task { await store.loadBundledData() }
            }
        }
        .preferredColorScheme(.dark)
        // Deep links (archivewatch://item/{id}, /surprise, …) from Top
        // Shelf taps and App Intents. Drop into the same inbox the App
        // Intents use; RootView consumes it once the catalog is loaded.
        .onOpenURL { url in
            if let request = IntentInbox.request(for: url) {
                IntentInbox.shared.request = request
            }
        }
    }
}

private struct LoadErrorView: View {
    let message: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)
            Text("Catalog not loaded")
                .font(.title.bold())
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 120)
        }
    }
}
