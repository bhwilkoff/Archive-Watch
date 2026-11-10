import XCTest

/// The iPhone Duo tier (iOS-DESIGN §2.8). Runs on the owner's Duo in whatever
/// pose it is in; a launch door cannot reach a surface that lives behind the
/// vertical strip's overflow, so this taps its way there the way a person does.
/// Every step prints `[AWDUO]` lines and files a window screenshot.
@MainActor
final class DuoAuditUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication(bundleIdentifier: "app.archivewatch.tvos")
    }

    private func launch(_ env: [String: String] = [:]) {
        app.launchEnvironment = env
        app.launch()
        _ = app.staticTexts.firstMatch.waitForExistence(timeout: 40)
        sleep(5)
    }

    private func snap(_ name: String) {
        // A full-screen cover leaves the first window with an empty frame.
        let win = app.windows.allElementsBoundByIndex.first { $0.frame.width > 0 }
        let a = XCTAttachment(screenshot: win?.screenshot() ?? XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func log(_ s: String) { print("[AWDUO] \(s)") }

    private func describeWindow() {
        let w = app.windows.firstMatch.frame
        log("window \(Int(w.width))x\(Int(w.height))")
        for b in app.tabBars.buttons.allElementsBoundByIndex {
            log("tab '\(b.label)' id=\(b.identifier) frame=\(b.frame.integral)")
        }
        // The Duo's vertical strip: every element in the trailing 100pt.
        if let snap = try? app.snapshot() {
            func walk(_ e: XCUIElementSnapshot) {
                if e.frame.minX > w.width - 100, e.frame.width < 100, e.frame.width > 10,
                   !e.label.isEmpty || !e.identifier.isEmpty {
                    log("strip \(e.elementType.rawValue) '\(e.label)' id=\(e.identifier) frame=\(e.frame.integral)")
                }
                e.children.forEach(walk)
            }
            walk(snap)
        }
    }

    /// The control that reaches a place: a tab, a sidebar row, or an entry in
    /// the strip's overflow menu, whichever this pose offers.
    private func reach(_ title: String) -> Bool {
        let tab = app.tabBars.buttons[title]
        if tab.exists, tab.isHittable { tab.tap(); return true }
        let any = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
        if any.exists, any.isHittable { any.tap(); return true }
        let cell = app.cells.containing(.staticText, identifier: title).firstMatch
        if cell.exists, cell.isHittable { cell.tap(); return true }
        let more = app.buttons.matching(NSPredicate(format:
            "label ==[c] 'More' OR identifier CONTAINS[c] 'more' OR label CONTAINS[c] 'more' OR identifier CONTAINS[c] 'overflow'")).firstMatch
        if more.exists {
            more.tap(); sleep(2)
            snap("overflow-for-\(title)")
            log("overflow opened; tree:\n\(app.debugDescription.prefix(6000))")
            for q in [app.buttons[title], app.menuItems[title], app.cells.containing(.staticText, identifier: title).firstMatch,
                      app.staticTexts[title]] where q.exists {
                q.tap(); return true
            }
        }
        // The strip holds the phone's five tabs; Browse's scope control and
        // Library's rows reach the places, as on the phone.
        if title == "Surprise" {
            let b = app.buttons["Surprise me"]
            if b.exists { b.tap(); return true }
        }
        let host = ["Films": "Browse", "TV": "Browse", "Collections": "Browse",
                    "Downloads": "Library", "Favorites": "Library", "History": "Library",
                    "Playlists": "Library", "Clips": "Library"][title]
        if let host {
            let h = app.buttons.matching(NSPredicate(format: "label == %@", host)).firstMatch
            if h.exists { h.tap(); sleep(2) }
            let seg = app.segmentedControls.buttons[title]
            if seg.exists { seg.tap(); return true }
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            if row.exists { row.tap(); return true }
        }
        log("NO WAY to reach \(title)")
        return false
    }

    func test_01_shell() {
        launch(["AW_RESET_TABS": "1"])
        sleep(2)
        describeWindow()
        snap("home")
        log("tree:\n\(app.debugDescription.prefix(8000))")
    }

    func test_02_collectionsOpen() {
        launch()
        XCTAssertTrue(reach("Collections"), "Collections unreachable")
        sleep(3)
        snap("collections-list")
        describeWindow()
        let row = app.buttons.containing(.staticText, identifier: "Prelinger Archives").firstMatch
        let row2 = app.staticTexts["Prelinger Archives"]
        let target = row.exists ? row : row2
        guard target.waitForExistence(timeout: 10) else {
            XCTFail("no Prelinger row"); log("tree:\n\(app.debugDescription.prefix(8000))"); return
        }
        log("row frame \(target.frame.integral) hittable=\(target.isHittable)")
        target.tap()
        sleep(4)
        snap("collection-after-tap")
        describeWindow()
        let opened = app.staticTexts["About Bananas"].exists
            || app.navigationBars["Prelinger Archives"].exists
            || app.staticTexts.matching(NSPredicate(format: "label == 'Prelinger Archives'")).count > 1
        log("opened=\(opened)")
        log("tree after tap:\n\(app.debugDescription.prefix(10000))")
        XCTAssertTrue(opened, "tapping a collection did not open its grid")
        // Then a film from it, and Back twice.
        let poster = app.buttons.containing(.staticText, identifier: "About Bananas").firstMatch
        if poster.exists { poster.tap(); sleep(4); snap("collection-film") }
        log("after film tap tree:\n\(app.debugDescription.prefix(4000))")
    }

    func test_03_everyPlace() {
        launch()
        for place in ["Browse", "Channels", "Search", "Library", "Films", "TV", "Collections",
                      "Downloads", "Favorites", "History", "Playlists", "Clips",
                      "Home", "Surprise", "Home"] {
            let ok = reach(place)
            sleep(3)
            log("place \(place) reached=\(ok)")
            snap("place-\(place)")
            if place == "Collections" || place == "Films" {
                log("tree \(place):\n\(app.debugDescription.prefix(3000))")
            }
        }
    }

    /// The inner display upright: a sidebar with the places, not the strip.
    func test_04_portraitSidebar() throws {
        launch()
        XCUIDevice.shared.orientation = .portrait
        sleep(4)
        let f = app.windows.firstMatch.frame
        if f.width > f.height {
            XCUIDevice.shared.orientation = .landscapeLeft
            // The inner display follows the HINGE, not a simulated rotation.
            throw XCTSkip("the device stayed landscape (\(Int(f.width))x\(Int(f.height))); turn the Duo upright to run this")
        }
        describeWindow()
        snap("portrait-home")
        for t in ["Films", "TV", "Collections", "Favorites"] {
            log("sidebar has \(t): \(app.buttons.matching(NSPredicate(format: "label == %@", t)).count + app.cells.containing(.staticText, identifier: t).count)")
        }
        if reach("Collections") {
            sleep(3)
            let target = app.staticTexts["Prelinger Archives"]
            if target.waitForExistence(timeout: 8) { target.tap(); sleep(4) }
            log("portrait collection opened=\(app.staticTexts["About Bananas"].exists)")
            snap("portrait-collection")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
    }

    /// Detail at the Duo's landscape height, then the player (muted).
    func test_05_detailAndPlayer() {
        launch(["AW_START_ITEM": "his_girl_friday", "AW_NO_RESUME": "1"])
        let play = app.buttons.matching(NSPredicate(format:
            "label BEGINSWITH[c] 'Play' OR label BEGINSWITH[c] 'Resume'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 15), "no Play on Detail")
        let w = app.windows.firstMatch.frame
        log("detail play frame \(play.frame.integral) in \(Int(w.width))x\(Int(w.height)) onScreen=\(play.frame.maxY < w.height)")
        snap("detail")
        launch(["AW_START_ITEM": "his_girl_friday", "AW_AUTOPLAY": "1", "AW_MUTE": "1", "AW_NO_RESUME": "1"])
        sleep(15)
        snap("player-idle")
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        snap("player-controls")
        log("player tree:\n\(app.debugDescription.prefix(5000))")
    }
}
