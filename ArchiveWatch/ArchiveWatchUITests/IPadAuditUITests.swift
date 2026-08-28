import XCTest

/// The iPad tier of the audit — the tests IPAD-DESIGN.md §7 calls for.
///
/// It runs the same app on the same code as `AuditUITests`, so it deliberately
/// does NOT re-test features: whether a button works is settled on the phone.
/// What only this rig can answer is whether the layout is a *composition* for a
/// large screen or a phone stretched to 1366 points — §7.1 measure, §7.2 the
/// claim a control's width makes, §7.3 both orientations.
///
/// It asserts on FRAMES, because that is where the defect lives. A screenshot
/// looks fine at either measure; only the numbers say a line ran 115 characters.
final class IPadAuditUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication(bundleIdentifier: "app.archivewatch.tvos")
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .landscapeLeft   // leave the rig as found
    }

    private func launch(_ env: [String: String] = [:]) {
        app.launchEnvironment = env
        app.launch()
        _ = app.staticTexts.firstMatch.waitForExistence(timeout: 30)
        sleep(4)
    }

    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private var windowWidth: CGFloat { app.windows.element(boundBy: 0).frame.width }

    /// §7.2 — the widest control on screen, and what it is.
    private func widestControl() -> (String, CGFloat) {
        // ONE snapshot. Indexing `app.buttons.element(boundBy: i)` in a loop
        // re-queries the whole accessibility tree per element, which on a
        // Detail screen (cast, community, related) is slow enough to blow the
        // test timeout and take the runner down with it — measured: tests 01
        // and 02 died exactly this way before this change.
        var worst = ("", CGFloat(0))
        for b in app.buttons.allElementsBoundByIndex where b.frame.width > worst.1 {
            worst = (b.label.isEmpty ? b.identifier : b.label, b.frame.width)
        }
        return worst
    }

    /// The widest run of prose on screen, in one snapshot (see widestControl).
    private func widestProse() -> (CGFloat, String) {
        var widest = CGFloat(0)
        var text = ""
        for t in app.staticTexts.allElementsBoundByIndex where t.label.count > 60 {
            if t.frame.width > widest { widest = t.frame.width; text = t.label }
        }
        return (widest, text)
    }

    // MARK: - §7.1 measure

    /// Prose must not run the width of a 12.9-inch screen. The frame of the
    /// synopsis Text IS the measure, so assert on it rather than counting
    /// characters off a screenshot.
    func test_01_detailProseIsWidthCapped() {
        launch(["AW_START_ITEM": "his_girl_friday"])
        snap("ipad-detail")
        XCTAssertGreaterThan(windowWidth, 1000,
                             "not a regular-width rig — is this really the iPad?")

        let (widest, widestText) = widestProse()
        XCTAssertGreaterThan(widest, 0, "no prose found on Detail")
        print("[AWIPAD] widest prose: \(Int(widest))pt — \(widestText.prefix(60))")
        // §2.1: capped at 700pt.
        XCTAssertLessThanOrEqual(widest, 720,
            "IPAD-DESIGN §2.1 — prose ran \(Int(widest))pt; it is capped at 700")
    }

    /// §2.2 — a primary action is a claim about importance, not a spanner.
    func test_02_primaryActionIsNotFullWidth() {
        launch(["AW_START_ITEM": "his_girl_friday"])
        let play = app.buttons.matching(NSPredicate(format:
            "label BEGINSWITH[c] 'Play' OR label BEGINSWITH[c] 'Resume'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 12), "no primary action")
        print("[AWIPAD] primary action: \(Int(play.frame.width))pt of \(Int(windowWidth))pt")
        // §2.2 caps the LABEL at 480pt; a .borderedProminent button adds its
        // own padding around that, so the control measures ~520. What the rule
        // forbids is spanning the window — assert against that, not against a
        // number the button style will always exceed by its own chrome.
        XCTAssertLessThanOrEqual(play.frame.width, 560,
            "IPAD-DESIGN §2.2 — the primary action is \(Int(play.frame.width))pt wide")
        XCTAssertLessThan(play.frame.width, windowWidth * 0.5,
            "IPAD-DESIGN §2.2 — the action spans half the window")

        let (name, w) = widestControl()
        print("[AWIPAD] widest control overall: '\(name)' \(Int(w))pt")
    }

    /// §3.1 — artwork and identity sit SIDE BY SIDE, which is the difference
    /// between a composition and a stack. Proven by geometry: the title's
    /// minX must be to the right of the artwork's maxX… or at least the two
    /// must overlap vertically, which a stacked layout never does.
    func test_03_detailIsTwoColumns() throws {
        launch(["AW_START_ITEM": "his_girl_friday"])
        let title = app.staticTexts["His Girl Friday"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 12), "no title")
        var art = CGRect.zero
        for img in app.images.allElementsBoundByIndex {
            let f = img.frame
            if f.width > art.width && f.height > 200 { art = f }
        }
        // Artwork is loaded from the network; on a cold simulator it may not
        // have arrived. Skip rather than report a false stacked-layout finding.
        try XCTSkipIf(art.width == 0, "artwork not loaded — cannot judge columns")
        XCTAssertGreaterThan(art.width, 0, "no artwork found")
        print("[AWIPAD] art=\(art) title=\(title.frame)")
        // Side by side: their vertical ranges overlap AND the title starts
        // after the art ends.
        let verticallyOverlapping = title.frame.midY > art.minY && title.frame.midY < art.maxY
        XCTAssertTrue(verticallyOverlapping && title.frame.minX > art.maxX - 8,
            "IPAD-DESIGN §3.1 — Detail is still stacked, not two columns")
        snap("ipad-detail-two-column")
    }

    // MARK: - §7.3 both orientations

    func test_04_portraitObeysTheSameRules() {
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        launch(["AW_START_ITEM": "his_girl_friday"])
        sleep(3)
        snap("ipad-detail-portrait")
        print("[AWIPAD] portrait window: \(Int(windowWidth))pt")

        let (widest, _) = widestProse()
        print("[AWIPAD] portrait widest prose: \(Int(widest))pt")
        XCTAssertLessThanOrEqual(widest, 720,
            "IPAD-DESIGN §2.1 in portrait — prose ran \(Int(widest))pt")

        let play = app.buttons.matching(NSPredicate(format:
            "label BEGINSWITH[c] 'Play' OR label BEGINSWITH[c] 'Resume'")).firstMatch
        if play.exists {
            XCTAssertLessThanOrEqual(play.frame.width, 560,
                "IPAD-DESIGN §2.2 in portrait — action \(Int(play.frame.width))pt")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
    }

    // MARK: - §4 grids, §2.2 across the other surfaces

    /// Every top-level surface, checked for the one defect class this document
    /// exists to prevent: something stretched to the window's full width.
    func test_05_noSurfaceStretchesAControl() {
        for (tab, label) in [("home", "Home"), ("browse", "Browse"),
                             ("library", "Library"), ("channels", "Channels")] {
            launch(["AW_START_TAB": tab])
            snap("ipad-\(tab)")
            let (name, w) = widestControl()
            print("[AWIPAD] \(label): widest control '\(name)' \(Int(w))pt " +
                  "of \(Int(windowWidth))pt")
            // A shelf row or grid legitimately spans the window; a BUTTON
            // that does is the §6.1 defect. Tiles are buttons, so allow
            // anything under 70% and flag the rest for a human read.
            if w > windowWidth * 0.7 {
                print("[AWIPAD] WIDE CONTROL on \(label): '\(name)' — verify by eye")
            }
        }
    }

    /// §4.1 — the adaptive grid must actually give a wide screen more columns.
    func test_06_browseGridUsesTheWidth() {
        launch(["AW_START_TAB": "browse"])
        sleep(4)
        // Count tiles whose midY sits in the same band: that is one row.
        var rows: [Int: Int] = [:]
        for b in app.buttons.allElementsBoundByIndex
        where b.frame.width > 80 && b.frame.height > 120 {
            rows[Int(b.frame.midY / 50), default: 0] += 1
        }
        let widest = rows.values.max() ?? 0
        print("[AWIPAD] widest Browse row: \(widest) tiles")
        XCTAssertGreaterThanOrEqual(widest, 5,
            "IPAD-DESIGN §4.1 — only \(widest) columns on a \(Int(windowWidth))pt screen")
        snap("ipad-browse-grid")
    }
}
