import XCTest

/// IPAD-DESIGN §8-§11 with a hardware keyboard and a pointer, driven from
/// inside the app by XCUITest (the synthesized keys never touch the Mac).
/// Asserts where a command LANDS — the page it opens — not that a menu item
/// exists (Decision 133).
@MainActor
final class IPadInputUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication(bundleIdentifier: "app.archivewatch.tvos")
        // One orientation for every test: a rotation mid-test moved the sheet
        // under the assertion.
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func launch(_ env: [String: String] = [:]) {
        app.launchEnvironment = env
        app.launch()
        _ = app.staticTexts.firstMatch.waitForExistence(timeout: 30)
        sleep(4)
        // A film window left by an earlier test restores in front; every
        // test starts from the main window.
        closeFilmWindows()
    }

    /// A film window (§9.1) has no sidebar. Close any that a run left open
    /// with ⌘W, so the next launch lands on the main window.
    private func closeFilmWindows() {
        let sidebarFavorites = sidebarEntry("Favorites")
        for _ in 0..<3 where !sidebarFavorites.waitForExistence(timeout: 3) {
            app.typeKey("w", modifierFlags: .command)
            sleep(2)
            app.activate()
            sleep(3)
        }
    }

    /// A sidebar entry is a cell, not a button: match any element by label.
    private func sidebarEntry(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// §8.1: Go's shortcuts move between places; Settings… opens on ⌘, and
    /// ⌘. closes it.
    func test_09_goAndSettingsShortcuts() {
        launch()
        app.typeKey("5", modifierFlags: .command)
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5), "⌘5 did not open Search")
        snap("cmd-5 search")

        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Archive Watch"].waitForExistence(timeout: 5), "⌘1 did not open Home")

        app.typeKey(",", modifierFlags: .command)
        let settings = app.navigationBars["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "⌘, did not open Settings")
        snap("cmd-comma settings")
        // iPadOS's cancel key is ⌘. — Esc never closed Settings (measured).
        app.typeKey(".", modifierFlags: .command)
        sleep(1)
        snap("after cmd-period")
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: settings)
        waitForExpectations(timeout: 5)
    }

    /// §8.2 and §9.1: on a film's page, ⌘[ goes back, and More offers
    /// Open in New Window, which opens a second window of the app.
    func test_10_backAndNewWindow() {
        launch(["AW_START_ITEM": "Nosferatu_most_complete_version_93_mins."])
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 20), "Detail did not open")

        let more = app.buttons.matching(NSPredicate(format: "label == 'More'")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let open = app.buttons.matching(NSPredicate(format: "label == 'Open in New Window'")).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5), "More has no Open in New Window")
        snap("more menu")
        if open.exists {
            let before = app.windows.count
            open.tap()
            sleep(4)
            snap("after open in new window")
            XCTAssertGreaterThan(app.windows.count, before, "no second window appeared")
            // Closed by the next test's launch (closeFilmWindows), which is
            // also the ⌘W check.
        }
    }

    func test_11_backShortcut() {
        launch(["AW_START_ITEM": "Nosferatu_most_complete_version_93_mins."])
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 20), "Detail did not open")
        app.typeKey("[", modifierFlags: .command)
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: play)
        waitForExpectations(timeout: 5)
        snap("after cmd-[")
    }

    /// §11: a poster answers the pointer. Hover the first Continue Watching
    /// tile and photograph it; the lift is judged on the picture.
    func test_12_pointerHover() {
        launch()
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'The Tingler'")).firstMatch
        guard tile.waitForExistence(timeout: 10) else { return XCTFail("no tile to hover") }
        tile.hover()
        sleep(1)
        snap("hover tile")
    }

    /// Candidates for the drop, each with the id its page opens by, so the
    /// cleanup reaches the film by its id rather than by finding its tile.
    private static let dropCandidates: [(title: String, id: String)] = [
        ("The Big Parade", "rec-20231112164007"),
        ("Brute Force", "brute-force-1947-restored-movie-720p-hd"),
        ("Reefer Madness", "reefer-madness-4-k"),
        ("The Tingler", "the-tingler-1959_202510"),
    ]

    /// §12.2: a poster dropped on the sidebar's Favorites favorites the film.
    /// The film is un-favorited again at the end — by relaunching on its page
    /// and asserting the heart is empty — so the owner's library is left as
    /// found. (An earlier cleanup that looked the tile up again failed
    /// silently and left four films in the owner's Favorites.)
    func test_13_dragPosterToFavorites() {
        launch()
        app.typeKey("6", modifierFlags: .command)
        sleep(2)
        guard let pick = Self.dropCandidates.first(where: { !app.staticTexts[$0.title].exists }) else {
            return XCTFail("every candidate is already a favorite")
        }
        app.typeKey("1", modifierFlags: .command)
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", pick.title)).firstMatch
        guard tile.waitForExistence(timeout: 10) else { return XCTFail("no \(pick.title) tile on Home") }
        let target = sidebarEntry("Favorites")
        guard target.waitForExistence(timeout: 5) else { return XCTFail("no Favorites in the sidebar") }
        tile.press(forDuration: 1.0, thenDragTo: target)
        sleep(2)
        app.typeKey("6", modifierFlags: .command)
        let landed = app.staticTexts[pick.title].waitForExistence(timeout: 5)
        snap("favorites after drop")
        XCTAssertTrue(landed, "\(pick.title) did not arrive in Favorites")
        restore(pick.id)
    }

    /// Opens the film's page by id and leaves it NOT favorited, asserting so.
    private func restore(_ id: String) {
        launch(["AW_START_ITEM": id])
        let remove = app.buttons.matching(NSPredicate(format: "label == 'Remove from favorites'")).firstMatch
        let add = app.buttons.matching(NSPredicate(format: "label == 'Add to favorites'")).firstMatch
        _ = remove.waitForExistence(timeout: 20) || add.waitForExistence(timeout: 1)
        if remove.exists { remove.tap() }
        XCTAssertTrue(add.waitForExistence(timeout: 5), "\(id) is still a favorite")
    }

    /// IPAD-DESIGN §2.1: at regular width episode results form columns, so
    /// two of them share a row.
    func test_15_searchEpisodesInColumns() {
        launch(["AW_START_TAB": "search", "AW_SEARCH": "lone ranger"])
        let header = app.staticTexts["Episodes"]
        for _ in 0..<8 where !(header.exists && header.isHittable) { app.swipeUp() }
        app.swipeUp()
        sleep(1)
        snap("episode results")
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS 'S1'")).allElementsBoundByIndex
            .map { $0.frame }.filter { $0.width > 0 }
        let sharesARow = rows.contains { a in rows.contains { b in a != b && abs(a.minY - b.minY) < 2 } }
        XCTAssertTrue(sharesARow, "episode rows do not form columns: \(rows.prefix(4))")
    }

    /// Leaves the device on its Home Screen, so a widget there can be
    /// photographed (IPAD-DESIGN §14). Changes nothing.
    func test_98_showHomeScreen() {
        XCUIDevice.shared.press(.home)
        XCUIApplication(bundleIdentifier: "com.apple.springboard").activate()
        sleep(25)   // the capture is taken during this wait
    }

    /// IPAD-DESIGN §5b: at regular width the Clip Studio is a page with the
    /// picture leading and its settings in a column beside it. Cancelled
    /// without making anything.
    func test_16_clipStudioIsTwoColumns() {
        launch(["AW_START_ITEM": "Nosferatu_most_complete_version_93_mins."])
        let more = app.buttons.matching(NSPredicate(format: "label == 'More'")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        more.tap()
        let create = app.buttons.matching(NSPredicate(format: "label == 'Create a Clip'")).firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 5), "More has no Create a Clip")
        create.tap()
        let format = app.staticTexts.matching(NSPredicate(format: "label ==[c] 'Format'")).firstMatch
        XCTAssertTrue(format.waitForExistence(timeout: 60), "the editor did not open")
        sleep(3)
        snap("clip studio")
        let window = app.windows.firstMatch.frame
        // The settings column sits in the right-hand part of the window.
        XCTAssertGreaterThan(format.frame.minX, window.midX, "settings are not a column beside the picture")
        app.buttons.matching(NSPredicate(format: "label == 'Cancel'")).firstMatch.tap()
    }
}
