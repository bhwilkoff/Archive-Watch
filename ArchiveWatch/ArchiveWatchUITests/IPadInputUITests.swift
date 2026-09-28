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

    /// §12.2: a poster dropped on the sidebar's Favorites favorites the film.
    /// The film is un-favorited again at the end, so the owner's library is
    /// left as found; a film already in Favorites is not used.
    func test_13_dragPosterToFavorites() {
        launch()
        app.typeKey("6", modifierFlags: .command)
        sleep(2)
        let candidates = ["The Big Parade", "Brute Force", "Reefer Madness", "The Tingler"]
        let pick = candidates.first { !app.staticTexts[$0].exists }
        guard let film = pick else { return XCTFail("every candidate is already a favorite") }
        app.typeKey("1", modifierFlags: .command)
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", film)).firstMatch
        guard tile.waitForExistence(timeout: 10) else { return XCTFail("no \(film) tile on Home") }
        let target = sidebarEntry("Favorites")
        guard target.waitForExistence(timeout: 5) else { return XCTFail("no Favorites in the sidebar") }
        tile.press(forDuration: 1.0, thenDragTo: target)
        sleep(2)
        app.typeKey("6", modifierFlags: .command)
        let landed = app.staticTexts[film].waitForExistence(timeout: 5)
            || app.buttons.matching(NSPredicate(format: "label CONTAINS %@", film)).firstMatch.exists
        snap("favorites after drop")
        XCTAssertTrue(landed, "\(film) did not arrive in Favorites")
        guard landed else { return }
        // Leave the library as found.
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", film)).firstMatch.tap()
        let fav = app.buttons.matching(NSPredicate(format: "label == 'Remove from favorites'")).firstMatch
        if fav.waitForExistence(timeout: 10) { fav.tap() }
        sleep(1)
        snap("after un-favorite")
    }
}

