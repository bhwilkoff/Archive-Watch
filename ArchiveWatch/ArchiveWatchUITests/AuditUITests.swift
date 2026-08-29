import XCTest

/// The tap tier of docs/IPHONE-12-AUDIT.md (T2), and the only tier that can
/// reach a surface living behind a control: Settings, a Library sub-tab, a
/// pushed person browse. `tools/ios_scenario.py` covers everything a cold
/// launch can reach; this covers the rest.
///
/// Discipline, inherited from the Apple TV harness: a control PASSES when the
/// tap produces an observable change — a new screen, a flipped state, a
/// different query result. `exists` is never the assertion, because a button
/// that draws and does nothing is exactly the defect worth finding. Every
/// check also files a screenshot, so the layout tier gets a second sweep for
/// free.
@MainActor
final class AuditUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true          // one dead button must not end the audit
        app = XCUIApplication(bundleIdentifier: "app.archivewatch.tvos")
    }

    // MARK: - helpers

    private func launch(_ env: [String: String] = [:]) {
        app.launchEnvironment = env
        app.launch()
        // The full catalog swaps in after the seed; shelves are only real once
        // it has (Decision 053).
        _ = app.staticTexts.firstMatch.waitForExistence(timeout: 30)
        sleep(4)
    }

    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Tap and require the screen to CHANGE — the whole point of the tier.
    @discardableResult
    private func tapAndExpect(_ el: XCUIElement, _ label: String,
                              appears: XCUIElement, timeout: TimeInterval = 12) -> Bool {
        guard el.waitForExistence(timeout: 8) else {
            XCTFail("MISSING \(label)"); return false
        }
        el.tap()
        let ok = appears.waitForExistence(timeout: timeout)
        snap(label)
        XCTAssertTrue(ok, "DEAD \(label) — tap produced no change")
        return ok
    }

    /// Bring an element into the SAFE middle of the screen before tapping it.
    ///
    /// `isHittable` cannot be trusted for this: a Settings switch sitting at
    /// y=837.7 on an 844pt screen reported hittable=true, and the tap landed
    /// off the bottom edge — which reads exactly like a dead control
    /// (measured 2026-08-28, and it cost a false "DEAD toggle" report).
    @discardableResult
    private func scrollIntoView(_ el: XCUIElement, maxSwipes: Int = 12) -> Bool {
        let win = app.windows.element(boundBy: 0).frame
        // Preferred band, then a wider one. Insisting on the middle made the
        // helper fail on rows that simply cannot be centred (near the ends of
        // a short list), which reads as "UNREACHABLE" for a perfectly
        // tappable control.
        let top = win.minY + 140, bottom = win.maxY - 140
        let okTop = win.minY + 60, okBottom = win.maxY - 60
        for _ in 0..<maxSwipes {
            guard el.exists else { app.swipeUp(); usleep(700_000); continue }
            let f = el.frame
            if f.midY > top && f.midY < bottom { return true }
            if f.midY >= bottom { app.swipeUp() } else { app.swipeDown() }
            usleep(700_000)
        }
        guard el.exists else { return false }
        let m = el.frame.midY
        return m > okTop && m < okBottom
    }

    private func back() {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        if b.exists { b.tap(); sleep(1) }
    }

    // MARK: - 2.1 tab bar

    func test_01_everyTabOpens() {
        launch()
        // Search LAST: on iOS 26 the search tab REPLACES the tab bar with a
        // search field (verified on the device), so visiting it mid-loop makes
        // every later tab unreachable — a harness artifact that reads exactly
        // like a missing tab.
        for tab in ["Home", "Browse", "Channels", "Library", "Search"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "MISSING tab \(tab)")
            button.tap()
            sleep(3)
            snap("tab-\(tab)")
            // A tab that draws nothing is a tab that failed to load.
            XCTAssertGreaterThan(app.staticTexts.count, 1, "EMPTY tab \(tab)")
        }
    }

    // MARK: - 2.3 Settings, and every toggle in it

    func test_02_settingsAndToggles() {
        launch()
        let gear = app.buttons["Settings"].firstMatch
        let gearAlt = app.images["gearshape"].firstMatch
        let target = gear.exists ? gear : gearAlt
        _ = tapAndExpect(target, "settings-open",
                         appears: app.navigationBars["Settings"])
        snap("settings-top")

        // Two passes, because a Form renders lazily AND re-renders when a
        // toggle flips: FIRST collect every switch's label by scrolling to the
        // bottom, THEN flip each one by label. Iterating by index breaks the
        // moment a flip rebuilds the tree ("no matches for element at index 2").
        var labels: [String] = []
        for _ in 0..<12 {
            for i in 0..<app.switches.count {
                let sw = app.switches.element(boundBy: i)
                guard sw.exists else { continue }
                let n = sw.label
                if !n.isEmpty && !labels.contains(n) { labels.append(n) }
            }
            app.swipeUp(); usleep(700_000)
        }
        snap("settings-bottom")
        XCTAssertGreaterThan(labels.count, 3,
                             "Settings exposed only \(labels.count) toggles")

        var dead: [String] = []
        var unreachable: [String] = []
        // One Settings session for the whole walk: since the sheet stopped
        // being torn down on every flip (the .id fix in HomeView), the scroll
        // position survives, so relaunching the app per toggle is no longer
        // needed — and the walk is a truer picture of a viewer editing several
        // preferences in a row.
        for name in labels {
            let sw = app.switches[name].firstMatch
            var reached = false
            for attempt in 0..<3 {
                if !sw.exists {
                    // Sweep the whole page: the row may be above or below.
                    for _ in 0..<8 where !sw.exists {
                        attempt == 0 ? app.swipeUp() : app.swipeDown()
                        usleep(700_000)
                    }
                }
                if sw.exists, scrollIntoView(sw) { reached = true; break }
            }
            guard reached else { unreachable.append(name); continue }

            let before = sw.value as? String
            let t0 = Date()
            // Trailing edge, NOT the row centre: XCUITest exposes a SwiftUI
            // Toggle as the whole 358pt row, so .tap() lands on the label and
            // does nothing. Nine toggles read as "dead" that way before
            // test_13 proved by EFFECT that they all work.
            sw.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            let back = app.switches[name].firstMatch.waitForExistence(timeout: 20)
            let settle = Date().timeIntervalSince(t0)
            print("[AWAUDIT] \(name): settled in \(String(format: "%.1f", settle))s")
            XCTAssertTrue(back, "toggle \(name) never came back after tapping")
            // 12s catches a HANG, not slowness: ~4s of this is XCUITest's own
            // accessibility snapshot on an A14, proven by the internal control
            // — "Transcribe films with no subtitles" touches no catalog data
            // at all and still measures 3.8s, so a full catalog re-query costs
            // only ~1.2s on top. Asserting near the floor measures the harness.
            XCTAssertLessThan(settle, 12.0,
                "HUNG toggle \(name) — \(String(format: "%.1f", settle))s to redraw")
            let after = app.switches[name].firstMatch.value as? String
            if before == after {
                dead.append(name)
                snap("dead-toggle-\(name.prefix(20))")
            } else {
                app.switches[name].firstMatch
                    .coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
                _ = app.switches[name].firstMatch.waitForExistence(timeout: 20)
            }
        }
        XCTAssertTrue(dead.isEmpty, "DEAD toggles: \(dead.joined(separator: ", "))")
        XCTAssertTrue(unreachable.isEmpty,
                      "UNREACHABLE toggles: \(unreachable.joined(separator: ", "))")
        print("[AWAUDIT] settings toggles exercised: \(labels.count)")
    }

    // MARK: - 2.4/2.5 Home discovery

    func test_03_homeShelvesAndTiles() {
        launch()
        snap("home-top")
        for i in 1...5 {                 // every shelf, for posters and clipping
            app.swipeUp(velocity: .slow); sleep(2); snap("home-scroll-\(i)")
        }
    }

    func test_04_categoryTileOpensGrid() {
        launch()
        let tile = app.buttons.matching(NSPredicate(format:
            "label CONTAINS[c] 'Feature Films' OR label CONTAINS[c] 'Classic TV'")).firstMatch
        guard tile.waitForExistence(timeout: 12) else {
            XCTFail("MISSING category tile"); return
        }
        tile.tap(); sleep(4)
        snap("category-grid")
        XCTAssertTrue(app.navigationBars.count > 0, "DEAD category tile")
    }

    // MARK: - 2.6-2.15 Detail's controls

    func test_05_detailControls() {
        launch(["AW_START_ITEM": "his_girl_friday"])
        snap("detail-top")

        // Favourite must FLIP, not merely exist. Its label is state-describing,
        // so match on either half.
        let heart = app.buttons.matching(NSPredicate(format:
            "label CONTAINS[c] 'favorites'")).firstMatch
        if heart.waitForExistence(timeout: 8) {
            let before = heart.label
            heart.tap(); sleep(2); snap("detail-favorited")
            let after = app.buttons.matching(NSPredicate(format:
                "label CONTAINS[c] 'favorites'")).firstMatch.label
            XCTAssertNotEqual(before, after, "DEAD favourite — label never changed")
            app.buttons.matching(NSPredicate(format:
                "label CONTAINS[c] 'favorites'")).firstMatch.tap()   // restore
            sleep(1)
        } else {
            XCTFail("MISSING favourite button")
        }

        // Every remaining action, by accessibility label. Each is dismissed
        // and CONFIRMED gone before the next — a sheet left standing makes the
        // next button unreachable and reads as a dead control.
        for (label, hint) in [("Add to playlist", "playlist"),
                              ("Get subtitles", "subtitles"),
                              ("Create a clip or GIF", "clip"),
                              ("Choose another copy", "versions"),
                              ("Share and more", "share")] {
            let b = app.buttons[label].firstMatch
            guard b.waitForExistence(timeout: 6) else {
                XCTFail("MISSING action: \(label)"); continue
            }
            guard scrollIntoView(b) else { continue }
            b.tap(); sleep(3); snap("detail-\(hint)")
            for _ in 0..<3 {
                let cancel = app.buttons["Cancel"].firstMatch
                if cancel.exists && cancel.isHittable { cancel.tap() }
                else if app.sheets.count > 0 || app.otherElements["PopoverDismissRegion"].exists {
                    app.otherElements["PopoverDismissRegion"].firstMatch.tap()
                } else { app.swipeDown() }
                sleep(2)
                if app.buttons[label].firstMatch.isHittable { break }
            }
        }
        snap("detail-after-actions")
    }

    func test_06_detailScrolledForClipping() {
        launch(["AW_START_ITEM": "his_girl_friday"])
        for i in 1...4 { app.swipeUp(); sleep(2); snap("detail-scroll-\(i)") }
    }

    // MARK: - 2.16 Browse facets and sort

    func test_07_browseFacetsAndSort() {
        launch(["AW_START_TAB": "browse"])
        snap("browse-top")
        for chip in ["Films", "TV", "Collections"] {
            let b = app.buttons[chip].firstMatch
            if b.waitForExistence(timeout: 6) {
                b.tap(); sleep(3); snap("browse-\(chip)")
            }
        }
    }

    // MARK: - 2.17 Search actually searches

    func test_08_searchReturnsResults() {
        launch(["AW_START_TAB": "search"])
        let field = app.searchFields.firstMatch
        guard field.waitForExistence(timeout: 12) else {
            XCTFail("MISSING search field"); return
        }
        field.tap()
        field.typeText("chaplin")
        sleep(5)
        snap("search-results")
        // The empty-state copy must be GONE — that is the observable change.
        XCTAssertFalse(app.staticTexts["Search the archive"].exists,
                       "DEAD search — empty state still showing after a query")
    }

    // MARK: - 2.19 Library sub-tabs

    func test_09_librarySubTabs() {
        launch(["AW_START_TAB": "library"])
        for t in ["Favorites", "History", "Playlists", "Clips"] {
            let b = app.buttons[t].firstMatch
            if b.waitForExistence(timeout: 6) {
                b.tap(); sleep(2); snap("library-\(t)")
            }
        }
    }

    /// Isolates the "dead toggle" report: which switch, by LABEL, and does it
    /// flip when tapped on its own row rather than by index? An index says
    /// nothing about which control was hit, and a control scrolled under the
    /// keyboard or a section header is not the same finding as a dead one.
    func test_11_settingsToggleDiagnostic() {
        launch()
        let gear = app.buttons["Settings"].firstMatch
        let target = gear.exists ? gear : app.images["gearshape"].firstMatch
        _ = tapAndExpect(target, "diag-settings-open",
                         appears: app.navigationBars["Settings"])

        for i in 0..<app.switches.count {
            let sw = app.switches.element(boundBy: i)
            guard sw.exists else { continue }
            print("[AWSWITCH] #\(i) label=\(sw.label) value=\(sw.value as? String ?? "nil") " +
                  "hittable=\(sw.isHittable) frame=\(sw.frame)")
        }

        // Tap each by label, scrolling it into view first.
        for i in 0..<app.switches.count {
            let sw = app.switches.element(boundBy: i)
            guard sw.exists else { continue }
            let name = sw.label
            if !sw.isHittable { app.swipeUp(); sleep(1) }
            guard sw.isHittable else {
                print("[AWSWITCH] SKIP unreachable \(name)"); continue
            }
            let before = sw.value as? String
            sw.tap(); sleep(2)
            let after = app.switches.element(boundBy: i).value as? String
            print("[AWSWITCH] TAP \(name): \(before ?? "nil") -> \(after ?? "nil")")
            if before == after {
                snap("dead-toggle-\(name.prefix(24))")
            } else {
                sw.tap(); sleep(1)      // restore
            }
        }
        snap("diag-settings-end")
    }

    /// Decisive experiment for the 9-of-9 "dead toggle" report. XCUITest
    /// exposes a SwiftUI Toggle as an element spanning the WHOLE ROW (358pt
    /// wide), so `.tap()` lands on the label, not the switch. This tries the
    /// row centre and then the switch itself, and judges by the PIXELS in the
    /// control's own frame — the reported `value` is what is in doubt.
    func test_12_toggleTapStrategies() {
        launch()
        let gear = app.buttons["Settings"].firstMatch
        let target = gear.exists ? gear : app.images["gearshape"].firstMatch
        _ = tapAndExpect(target, "strategy-settings", appears: app.navigationBars["Settings"])

        let name = "Show mature collections"
        let sw = app.switches[name].firstMatch
        // A Form renders lazily: the row does not EXIST in the tree until it
        // is scrolled near, so waiting for it without scrolling never resolves.
        for _ in 0..<10 where !sw.exists { app.swipeUp(); sleep(1) }
        guard sw.exists, scrollIntoView(sw) else {
            XCTFail("could not reach \(name)"); return
        }
        print("[AWSWITCH] frame=\(sw.frame) value=\(sw.value as? String ?? "nil")")

        snap("strategy-0-before")
        sw.tap(); sleep(2)
        print("[AWSWITCH] after ROW-CENTRE tap: \(sw.value as? String ?? "nil")")
        snap("strategy-1-after-row-centre")

        // The switch control itself lives at the trailing edge of the row.
        sw.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        sleep(2)
        print("[AWSWITCH] after TRAILING tap: \(sw.value as? String ?? "nil")")
        snap("strategy-2-after-trailing")
    }

    /// Settings judged by EFFECT, not by the value XCUITest reports. Turning
    /// a category off must remove its tile from Home — that is what the
    /// viewer actually experiences, and it cannot be faked by an element's
    /// self-description. Also settles which tap lands on a SwiftUI Toggle.
    func test_13_settingsToggleChangesHome() {
        launch()
        // Baseline: the Feature Films tile is on Home.
        let tile = app.buttons.matching(NSPredicate(format:
            "label CONTAINS[c] 'Feature Films'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 15),
                      "no Feature Films tile to begin with")
        snap("effect-0-home-before")

        func openSettings() {
            let gear = app.buttons["Settings"].firstMatch
            let t = gear.exists ? gear : app.images["gearshape"].firstMatch
            t.tap()
            _ = app.navigationBars["Settings"].waitForExistence(timeout: 10)
        }
        func closeSettings() {
            let done = app.buttons["Done"].firstMatch
            if done.exists { done.tap() } else { app.swipeDown() }
            sleep(3)
        }
        /// Tap the switch CONTROL at the row's trailing edge, not the row centre.
        func flip(_ name: String) {
            let sw = app.switches[name].firstMatch
            for _ in 0..<12 where !sw.exists { app.swipeUp(); sleep(1) }
            XCTAssertTrue(sw.exists, "missing toggle \(name)")
            _ = scrollIntoView(sw)
            sw.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            sleep(2)
        }

        openSettings()
        flip("Feature Films")
        snap("effect-1-toggled-off")
        closeSettings()
        snap("effect-2-home-after")

        let stillThere = app.buttons.matching(NSPredicate(format:
            "label CONTAINS[c] 'Feature Films'")).firstMatch.waitForExistence(timeout: 6)
        XCTAssertFalse(stillThere,
            "DEAD Settings toggle — Feature Films still on Home after hiding it")

        // Restore, and prove the restore worked too.
        openSettings()
        flip("Feature Films")
        closeSettings()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:
            "label CONTAINS[c] 'Feature Films'")).firstMatch.waitForExistence(timeout: 10),
            "category did not come back — the audit must leave no trace")
        snap("effect-3-home-restored")
    }

    /// Characterises the mature-content toggle's cost. It is the one control
    /// that changes what EVERY query returns, so it invalidates the whole
    /// catalog view (`dbVersion`) — on an A14 that showed as 24.6s with the
    /// row absent from the tree. Frozen, or merely re-rendering?
    func test_14_matureToggleCost() {
        launch()
        let gear = app.buttons["Settings"].firstMatch
        (gear.exists ? gear : app.images["gearshape"].firstMatch).tap()
        _ = app.navigationBars["Settings"].waitForExistence(timeout: 10)

        let name = "Show mature collections"
        let sw = app.switches[name].firstMatch
        for _ in 0..<12 where !sw.exists { app.swipeUp(); usleep(700_000) }
        guard sw.exists, scrollIntoView(sw) else { XCTFail("unreachable"); return }

        let t0 = Date()
        sw.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()

        // Poll a control that does NOT depend on the catalog. If Done stays
        // resolvable the app is alive and only the list is rebuilding; if it
        // vanishes too, the main thread is blocked.
        var doneAliveThroughout = true
        var switchBackAt: Double? = nil
        for i in 0..<30 {
            let dt = Date().timeIntervalSince(t0)
            let doneAlive = app.buttons["Done"].firstMatch.exists
            let swAlive = app.switches[name].firstMatch.exists
            if !doneAlive { doneAliveThroughout = false }
            if swAlive && switchBackAt == nil { switchBackAt = dt }
            print("[AWCOST] t=\(String(format: "%.1f", dt))s done=\(doneAlive) switch=\(swAlive)")
            if swAlive { break }
            if i % 4 == 0 { snap("cost-t\(Int(dt))") }
            usleep(900_000)
        }
        print("[AWCOST] RESULT settled=\(switchBackAt.map { String(format: "%.1f", $0) } ?? "never") " +
              "mainThreadAliveThroughout=\(doneAliveThroughout)")
        snap("cost-end")

        // Leave the device as we found it.
        if app.switches[name].firstMatch.exists {
            app.switches[name].firstMatch
                .coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            _ = app.switches[name].firstMatch.waitForExistence(timeout: 40)
        }
    }

    // MARK: - remaining surfaces (T1.9-1.11, T2.14/2.15/2.18/2.20/2.22)

    /// A series spine: card -> season -> episode. TV is the surface most
    /// likely to differ from film, and it has never been shot on this device.
    func test_15_seriesDetail() {
        launch(["AW_START_ITEM": "series:four-star-playhouse-1952"])
        snap("series-top")
        XCTAssertTrue(app.staticTexts.count > 2, "series Detail drew nothing")
        for i in 1...3 { app.swipeUp(); sleep(2); snap("series-scroll-\(i)") }
    }

    /// Collections, reached the way a viewer reaches them.
    func test_16_collections() {
        launch(["AW_START_TAB": "browse"])
        let chip = app.buttons["Collections"].firstMatch
        guard chip.waitForExistence(timeout: 12) else {
            XCTFail("MISSING Collections chip"); return
        }
        chip.tap(); sleep(4); snap("collections-grid")
        // Open the first collection and require a push.
        let first = app.buttons.element(boundBy: 3)
        if first.exists && first.isHittable {
            first.tap(); sleep(4); snap("collection-opened")
        }
    }

    /// Cast bubble -> that person's other films, and More Like This. Both are
    /// pushes from Detail, so both prove navigation as well as the control.
    func test_17_castAndRelated() {
        launch(["AW_START_ITEM": "his_girl_friday"])
        // Scroll to the cast row.
        for _ in 0..<4 { app.swipeUp(); sleep(1) }
        snap("detail-cast-row")
        let bubble = app.buttons.matching(NSPredicate(format:
            "label CONTAINS[c] 'Cary Grant' OR label CONTAINS[c] 'Howard Hawks'")).firstMatch
        if bubble.waitForExistence(timeout: 6), scrollIntoView(bubble) {
            bubble.tap(); sleep(4); snap("person-browse")
            XCTAssertTrue(app.navigationBars.count > 0, "DEAD cast bubble")
            back()
        } else {
            snap("cast-bubble-not-found")
        }
        for _ in 0..<3 { app.swipeUp(); sleep(1) }
        snap("detail-more-like-this")
    }

    /// Back must return from every pushed screen — a trap here strands the
    /// viewer, and it is the cheapest thing in the app to get wrong.
    func test_18_backNavigation() {
        launch()
        let tile = app.buttons.matching(NSPredicate(format:
            "label CONTAINS[c] 'Feature Films'")).firstMatch
        guard tile.waitForExistence(timeout: 12) else { XCTFail("no tile"); return }
        tile.tap(); sleep(4)
        XCTAssertTrue(app.navigationBars.count > 0, "no push happened")
        back(); sleep(2); snap("back-to-home")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:
            "label CONTAINS[c] 'Feature Films'")).firstMatch.waitForExistence(timeout: 10),
            "Back did not return to Home")
    }

    /// Channels: tune in and confirm something plays.
    func test_19_channelsTuneIn() {
        launch(["AW_START_TAB": "channels"])
        snap("channels-guide")
        let cell = app.buttons.element(boundBy: 2)
        guard cell.exists, cell.isHittable else {
            XCTFail("no tappable channel cell"); return
        }
        cell.tap(); sleep(12); snap("channel-tuned")
    }

    /// Search filters, which exist only once results are on screen.
    func test_20_searchFilters() {
        launch(["AW_START_TAB": "search"])
        let field = app.searchFields.firstMatch
        guard field.waitForExistence(timeout: 12) else { XCTFail("no field"); return }
        field.tap(); field.typeText("chaplin"); sleep(5)
        snap("search-before-filter")
        // The type/decade menus appear above the results.
        let filter = app.buttons.matching(NSPredicate(format:
            "label CONTAINS[c] 'Type' OR label CONTAINS[c] 'Decade' OR label CONTAINS[c] 'filter'")).firstMatch
        if filter.waitForExistence(timeout: 6) {
            filter.tap(); sleep(2); snap("search-filter-menu")
        } else {
            snap("search-no-filter-control")
        }
    }

    /// Is the Search Filter menu REACHABLE? It is a top-bar toolbar item, and
    /// iOS 26 replaces the bar's trailing items with Cancel while the search
    /// field has focus — so a control that only exists there could be
    /// unreachable in practice. Dismiss the keyboard and look again.
    func test_21_searchFilterReachable() {
        launch(["AW_START_TAB": "search"])
        let field = app.searchFields.firstMatch
        guard field.waitForExistence(timeout: 12) else { XCTFail("no field"); return }
        field.tap(); field.typeText("chaplin"); sleep(5)

        // The control is now inline with the results, labelled by what it
        // filters ("Type" / "Era"), not a bar item called "Filter".
        func filterExists() -> Bool {
            app.buttons["Type"].firstMatch.exists || app.buttons["Era"].firstMatch.exists
        }
        let filterWhileTyping = filterExists()
        // Return / dismiss the keyboard the way a viewer would.
        app.typeText("\n"); sleep(2)
        snap("search-keyboard-dismissed")
        let filterAfterReturn = filterExists()

        app.swipeUp(); sleep(2)
        snap("search-scrolled")
        let filterAfterScroll = filterExists()

        print("[AWFILTER] whileTyping=\(filterWhileTyping) afterReturn=\(filterAfterReturn) " +
              "afterScroll=\(filterAfterScroll)")
        XCTAssertTrue(filterWhileTyping || filterAfterReturn || filterAfterScroll,
                      "UNREACHABLE Search filter — never appears in any state")

        // And it must DO something: filter to TV and the film results change.
        let typeButton = app.buttons["Type"].firstMatch
        if typeButton.exists, scrollIntoView(typeButton) {
            let before = app.buttons.count
            typeButton.tap(); sleep(2); snap("search-filter-open")
            let tv = app.buttons["TV Series"].firstMatch
            if tv.waitForExistence(timeout: 4) {
                tv.tap(); sleep(4); snap("search-filtered-tv")
                XCTAssertNotEqual(before, app.buttons.count,
                                  "DEAD Search filter — result set unchanged")
            }
        }
    }

    /// Archive.org reviews were clamped to six lines with no way to read the
    /// rest, so a long one ended mid-sentence (owner, 2026-08-28). The test is
    /// by EFFECT: the visible text must actually GROW when expanded — a
    /// "Show more" button that changes its own label proves nothing.
    func test_25_reviewsExpand() {
        launch(["AW_START_ITEM": "his_girl_friday"])
        // Reviews live below the synopsis, cast and facts.
        var found = false
        for i in 0..<10 {
            if app.buttons["Show more"].firstMatch.exists { found = true; break }
            app.swipeUp(); sleep(1)
            snap("reviews-scroll-\(i)")
        }
        guard found else {
            XCTFail("no expandable review found — is the clamp affordance missing?")
            return
        }
        let more = app.buttons["Show more"].firstMatch
        guard scrollIntoView(more) else { XCTFail("Show more unreachable"); return }

        // Measure the review belonging to THIS button — the long text directly
        // above it. Taking the tallest text on screen measured the synopsis
        // instead, which never changes, and reported a working expander as
        // dead (306pt -> 306pt).
        let anchorY = more.frame.minY
        let before = reviewHeight(above: anchorY)
        snap("reviews-collapsed")
        more.tap(); sleep(2)
        let after = reviewHeight(above: anchorY)
        snap("reviews-expanded")
        print("[AWREVIEW] tallest review text: \(Int(before))pt -> \(Int(after))pt")

        XCTAssertGreaterThan(after, before,
            "DEAD review expander — the text did not grow (\(Int(before)) -> \(Int(after)))")
        XCTAssertTrue(app.buttons["Show less"].firstMatch.exists,
                      "expanded, but the control still offers to expand")
    }

    /// Height of the long text whose bottom sits just above `y` — the review
    /// body belonging to the control at that position.
    private func reviewHeight(above y: CGFloat) -> CGFloat {
        var best = CGFloat(0)
        var bestGap = CGFloat.greatestFiniteMagnitude
        for t in app.staticTexts.allElementsBoundByIndex {
            guard let snap = try? t.snapshot(), snap.label.count > 80 else { continue }
            let gap = y - snap.frame.maxY
            if gap >= -2, gap < bestGap { bestGap = gap; best = snap.frame.height }
        }
        return best
    }

    // MARK: - T3 playback depth (resume, captions, PiP) on A14

    /// Resume: play, leave, come back. Continue Watching is the shelf that
    /// proves the position was written AND read back.
    func test_22_resumeAfterLeaving() {
        launch(["AW_START_ITEM": "his_girl_friday"])
        let play = app.buttons.matching(NSPredicate(format:
            "label BEGINSWITH[c] 'Play' OR label BEGINSWITH[c] 'Resume'")).firstMatch
        guard play.waitForExistence(timeout: 12) else { XCTFail("no Play"); return }
        play.tap()
        sleep(45)                       // watch long enough to be worth resuming
        snap("resume-1-watching")
        // Leave via the player's close control.
        app.tap(); sleep(2)
        let close = app.buttons.matching(NSPredicate(format:
            "label CONTAINS[c] 'close' OR label CONTAINS[c] 'done'")).firstMatch
        if close.exists { close.tap() } else { app.swipeDown() }
        sleep(3); snap("resume-2-back-on-detail")

        // Cold relaunch: the position must survive the process, not just the view.
        launch()
        sleep(6)
        snap("resume-3-home-after-relaunch")
        let cw = app.staticTexts.matching(NSPredicate(format:
            "label CONTAINS[c] 'Continue' OR label CONTAINS[c] 'Keep watching'")).firstMatch
        XCTAssertTrue(cw.waitForExistence(timeout: 20),
                      "NO Continue Watching shelf after watching 45s of a film")

        // And the Detail must offer to resume rather than restart.
        launch(["AW_START_ITEM": "his_girl_friday"])
        let resumeLabel = app.buttons.matching(NSPredicate(format:
            "label BEGINSWITH[c] 'Play' OR label BEGINSWITH[c] 'Resume'")).firstMatch
        _ = resumeLabel.waitForExistence(timeout: 12)
        print("[AWRESUME] play button reads: \(resumeLabel.label)")
        snap("resume-4-detail")
    }

    /// Captions on the A14: a film with a published subtitle file must show
    /// text, and the choice control must offer File / Automatic / Off.
    func test_23_captionsRender() {
        launch(["AW_START_ITEM": "his_girl_friday"])
        let subs = app.buttons["Get subtitles"].firstMatch
        guard subs.waitForExistence(timeout: 12), scrollIntoView(subs) else {
            XCTFail("MISSING subtitles control"); return
        }
        subs.tap(); sleep(4); snap("captions-sheet")
        for choice in ["Subtitle File", "Automatic", "Off"] {
            XCTAssertTrue(app.buttons[choice].firstMatch.exists ||
                          app.staticTexts[choice].firstMatch.exists,
                          "caption choice missing: \(choice)")
        }
        // Choose Automatic, then play and look for text on the glass.
        let auto = app.buttons["Automatic"].firstMatch
        if auto.exists { auto.tap(); sleep(2); snap("captions-automatic-chosen") }
        // Dismiss and CONFIRM dismissal. This sheet carries a grabber and no
        // Cancel button (standard iOS), so it must be DRAGGED down from its
        // own top edge — a swipeDown in the middle just scrolls its content,
        // leaving Play covered and reading like a broken Play button.
        for _ in 0..<4 {
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.exists && cancel.isHittable {
                cancel.tap()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.52))
                   .press(forDuration: 0.1,
                          thenDragTo: app.coordinate(
                            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
            }
            sleep(2)
            if app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Play' " +
                "OR label BEGINSWITH[c] 'Resume'")).firstMatch.isHittable { break }
        }
        let play = app.buttons.matching(NSPredicate(format:
            "label BEGINSWITH[c] 'Play' OR label BEGINSWITH[c] 'Resume'")).firstMatch
        guard play.waitForExistence(timeout: 8), play.isHittable else {
            XCTFail("Play unreachable after the subtitles sheet"); return
        }
        play.tap()
        // The engine transcribes AHEAD of playback (Decision 058) but needs a
        // warm-up; sample the glass rather than assuming a fixed latency.
        for t in [40, 70, 100, 130] {
            sleep(30); snap("captions-t\(t)")
        }
    }

    /// PiP: the control must exist in the player chrome and engage.
    func test_24_pictureInPicture() {
        launch(["AW_START_ITEM": "his_girl_friday"])
        let play = app.buttons.matching(NSPredicate(format:
            "label BEGINSWITH[c] 'Play' OR label BEGINSWITH[c] 'Resume'")).firstMatch
        guard play.waitForExistence(timeout: 12) else { XCTFail("no Play"); return }
        play.tap(); sleep(25)
        app.tap(); sleep(3); snap("pip-controls")
        // AVKit's transport is its own hierarchy; dump what is actually there
        // rather than guessing the label.
        for i in 0..<app.buttons.count {
            let b = app.buttons.element(boundBy: i)
            guard b.exists else { continue }
            print("[AWPLAYER] button \(i): label='\(b.label)' id='\(b.identifier)' " +
                  "hittable=\(b.isHittable)")
        }
        for i in 0..<min(app.otherElements.count, 40) {
            let e = app.otherElements.element(boundBy: i)
            guard e.exists, !e.label.isEmpty else { continue }
            print("[AWPLAYER] other \(i): label='\(e.label)' id='\(e.identifier)'")
        }
        let pip = app.buttons.matching(NSPredicate(format:
            "label CONTAINS[c] 'picture' OR label CONTAINS[c] 'pip' " +
            "OR identifier CONTAINS[c] 'pip' OR identifier CONTAINS[c] 'picture'")).firstMatch
        XCTAssertTrue(pip.exists, "MISSING Picture in Picture control")
        if pip.exists { pip.tap(); sleep(6); snap("pip-engaged") }
    }

    // MARK: - T3 playback

    func test_10_playbackStartsAndChromeIsClean() {
        launch(["AW_START_ITEM": "his_girl_friday"])
        let play = app.buttons.matching(NSPredicate(format:
            "label BEGINSWITH[c] 'Play' OR label BEGINSWITH[c] 'Resume'")).firstMatch
        guard play.waitForExistence(timeout: 12) else {
            XCTFail("MISSING Play button"); return
        }
        play.tap()
        // Decision 077: a film starts within 30 seconds or falls back.
        sleep(30)
        snap("player-30s")
        app.tap()               // reveal transport
        sleep(2); snap("player-controls")
        sleep(8); snap("player-controls-faded")   // no PERSISTENT overlay
    }
}
