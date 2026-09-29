#if os(iOS) || os(tvOS) || os(macOS)
import AppIntents
import Foundation

// Open Film for Siri and Shortcuts, shared by iPhone, iPad, Apple TV and Mac
// (the iPad loop v1.42.889, owner-verified; the cross-platform review found
// tvOS and the Mac without it). iOS and tvOS hand the id to their
// IntentInbox (`.openItem`); the Mac, which had no intents at all, to
// MacIntentInbox below. Each RootView opens the film once it is foreground.

// MARK: - A film Siri and Shortcuts can name

/// A title in the catalog, by its archive.org id. What Siri says back is the
/// catalog's own title and year — no copy of our own.
struct FilmEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Film"
    static let defaultQuery = FilmQuery()

    let id: String
    let title: String
    let year: Int?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: year.map { "\(String($0))" })
    }

    init(_ item: Catalog.Item) {
        id = item.archiveID; title = item.title; year = item.year
    }
}

/// Resolves a spoken or typed title with the app's own search (the ranking
/// every Apple platform shares, tvOS-DESIGN §3.3b), against the catalog the
/// app last downloaded — the same file the app opens.
struct FilmQuery: EntityStringQuery {
    @MainActor private static var db: CatalogDB?

    @MainActor private static func catalog() async -> CatalogDB? {
        if let db { return db }
        let path = await CatalogRefreshService.shared.cachedDatabasePath()
            ?? Bundle.main.path(forResource: "seed", ofType: "sqlite")
        db = path.flatMap { CatalogDB(path: $0) }
        return db
    }

    @MainActor func entities(for identifiers: [String]) async throws -> [FilmEntity] {
        guard let db = await Self.catalog() else { return [] }
        return identifiers.compactMap { db.item($0) }.map(FilmEntity.init)
    }

    @MainActor func entities(matching string: String) async throws -> [FilmEntity] {
        guard let db = await Self.catalog() else { return [] }
        return db.search(string, limit: 10).filter { !$0.isEpisode }.map(FilmEntity.init)
    }

    func suggestedEntities() async throws -> [FilmEntity] { [] }
}

struct OpenFilmIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Film"
    static let description = IntentDescription("Open a film's page in Archive Watch.")
    static let openAppWhenRun = true

    @Parameter(title: "Film", requestValueDialog: "Which film?")
    var film: FilmEntity

    @MainActor func perform() async throws -> some IntentResult {
        #if os(macOS)
        MacIntentInbox.shared.openItemID = film.id
        #else
        IntentInbox.shared.request = .openItem(film.id)
        #endif
        return .result()
    }
}

#if os(macOS)
/// The Mac's request inbox for intents (iOS and tvOS have IntentInbox).
@MainActor @Observable
final class MacIntentInbox {
    static let shared = MacIntentInbox()
    var openItemID: String?
}

struct ArchiveWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenFilmIntent(),
            phrases: ["Open a film in \(.applicationName)", "Find a film in \(.applicationName)"],
            shortTitle: "Open Film", systemImageName: "film"
        )
    }
}
#endif
#endif
