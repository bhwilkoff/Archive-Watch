#if os(tvOS)
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if let error = store.loadError {
                LoadErrorView(message: error)
            } else if store.isReady {
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
        // #11b live sync: pull/push when the app comes to the foreground (so a
        // second Apple TV picks up changes made on the first), and arm the
        // What's New background refresh when leaving.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { BackgroundRefresh.schedule() }
            else if phase == .active {
                Task { await CloudKitSyncService.shared.sync(modelContext) }
            }
        }
        // #11b live sync: a gentle periodic pull while in use, so two TVs left on
        // converge without a foreground event. Reentrancy-guarded in the service.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if scenePhase == .active {
                    await CloudKitSyncService.shared.sync(modelContext)
                }
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

#endif
