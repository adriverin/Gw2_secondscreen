import XCTest
import UIKit

@MainActor
final class GW2CompanionSmokeTests: XCTestCase {
    func testCriticalNavigationDestinationsOpen() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-smoke", "--phase2-fixtures", "--simulate-telemetry"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Map"].waitForExistence(timeout: 5))
        openPrimary("Today", app: app)
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 3))
        openPrimary("Goals", app: app)
        XCTAssertTrue(app.navigationBars["Goals"].waitForExistence(timeout: 3))
        openPrimary("Inventory", app: app)
        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 3))

        openMore("Characters", app: app)
        XCTAssertTrue(app.navigationBars["Characters"].waitForExistence(timeout: 3))
        openMore("Account", app: app)
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 3))
        openMore("Settings", app: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    func testInventoryHubRendersBankMaterialsSharedCharacterAndSearch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-smoke", "--phase2-fixtures", "--simulate-telemetry"]
        app.launch()

        openPrimary("Inventory", app: app)
        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 5))

        tapSection("bank", app: app)
        XCTAssertTrue(hasMithril(app), "Bank should show Mithril Ore")

        tapSection("materials", app: app)
        XCTAssertTrue(
            app.staticTexts["Material Storage"].waitForExistence(timeout: 3)
            || app.staticTexts["Basic Crafting Materials"].waitForExistence(timeout: 1)
            || app.otherElements["inventory.materials"].waitForExistence(timeout: 1)
        )
        XCTAssertTrue(hasMithril(app), "Materials should show Mithril Ore")

        tapSection("shared", app: app)
        XCTAssertTrue(hasMithril(app), "Shared inventory should show Mithril Ore")

        tapSection("characters", app: app)
        let andrea = app.descendants(matching: .any)["inventory.character.Andrea"]
        XCTAssertTrue(andrea.waitForExistence(timeout: 3) || app.staticTexts["Andrea"].waitForExistence(timeout: 2))
        if andrea.exists { andrea.tap() } else { app.staticTexts["Andrea"].tap() }
        XCTAssertTrue(
            hasMithril(app)
            || app.staticTexts["Starter Backpack"].waitForExistence(timeout: 2)
            || app.staticTexts["Bag 1"].waitForExistence(timeout: 2)
        )

        for _ in 0..<4 {
            if app.textFields["inventory.search.field"].exists { break }
            if app.buttons["inventory.section.all"].exists {
                app.buttons["inventory.section.all"].tap()
                break
            }
            if app.navigationBars.buttons["Inventory"].exists {
                app.navigationBars.buttons["Inventory"].tap()
            } else if app.navigationBars.buttons.count > 0 {
                app.navigationBars.buttons.element(boundBy: 0).tap()
            }
        }
        tapSection("all", app: app)
        let search = app.textFields["inventory.search.field"]
        XCTAssertTrue(search.waitForExistence(timeout: 4) || app.textFields["Search all inventory"].waitForExistence(timeout: 2))
        let field = search.exists ? search : app.textFields["Search all inventory"]
        field.tap()
        field.typeText("Mithril")
        XCTAssertTrue(hasMithril(app), "Search should find Mithril Ore")
    }

    func testMissingInventoriesPermissionKeepsInventoryVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-smoke", "--phase2-no-inventories", "--simulate-telemetry"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Inventory"].waitForExistence(timeout: 5))
        openPrimary("Inventory", app: app)
        XCTAssertTrue(app.staticTexts["Inventory access isn't enabled"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["Replace API Key"].waitForExistence(timeout: 3)
            || app.staticTexts["Replace API Key"].exists
        )

        openPrimary("Today", app: app)
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 3))
        openPrimary("Map", app: app)
        XCTAssertTrue(app.tabBars.buttons["Map"].waitForExistence(timeout: 3))
    }

    func testWalletAllCurrenciesDisclosureUpdatesImmediately() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-smoke", "--phase2-fixtures", "--simulate-telemetry",
            "-wallet.allExpanded.v1.fixture_account", "NO"
        ]
        app.launch()

        openMore("Account", app: app)
        XCTAssertTrue(scrollUntilExists(
            app, identifiers: [], texts: ["All Currencies"]))
        let disclosure = app.buttons["All Currencies"].firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 2))
        XCTAssertEqual(disclosure.value as? String, "Collapsed")
        // Currency rows combine their accessibility children. Match the row's
        // combined label instead of requiring a standalone StaticText leaf.
        let fractal = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Fractal Relic")).firstMatch
        XCTAssertFalse(fractal.exists)
        disclosure.tap()
        XCTAssertEqual(disclosure.value as? String, "Expanded")
        XCTAssertTrue(fractal.waitForExistence(timeout: 2),
                      "All Currencies should expand without changing tabs")
        disclosure.tap()
        XCTAssertEqual(disclosure.value as? String, "Collapsed")
        XCTAssertFalse(fractal.waitForExistence(timeout: 0.5),
                       "All Currencies should collapse immediately")
    }

    private func tapSection(_ id: String, app: XCUIApplication) {
        let button = app.buttons["inventory.section.\(id)"]
        XCTAssertTrue(button.waitForExistence(timeout: 3), "Missing inventory section \(id)")
        button.tap()
    }

    private func hasMithril(_ app: XCUIApplication) -> Bool {
        app.descendants(matching: .any)["inventory.item.Mithril Ore"].firstMatch.waitForExistence(timeout: 3)
            || app.staticTexts["Mithril Ore"].waitForExistence(timeout: 1)
            || app.buttons["Mithril Ore, quantity 211"].waitForExistence(timeout: 1)
            || app.buttons["Mithril Ore, quantity 250"].waitForExistence(timeout: 1)
            || app.buttons["Mithril Ore, quantity 100"].waitForExistence(timeout: 1)
            || app.buttons["Mithril Ore, quantity 173"].waitForExistence(timeout: 1)
    }

    func testDeveloperQAModeMapAlignmentInventoryAPIAndExport() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-smoke", "--developer-mode", "--phase2-fixtures", "--simulate-telemetry",
            "-developer.mode.enabled", "YES"
        ]
        app.launch()

        openMore("Settings", app: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        revealDeveloperQA(app)

        let qaLink = app.descendants(matching: .any)["settings.developer.qa"].firstMatch
        let qaLabel = app.staticTexts["Real Hardware QA"].firstMatch
        let qaButton = app.buttons["Real Hardware QA"].firstMatch
        XCTAssertTrue(
            qaLink.waitForExistence(timeout: 3) || qaLabel.waitForExistence(timeout: 2) || qaButton.waitForExistence(timeout: 2),
            "Real Hardware QA should be visible in Developer settings")
        if qaLink.exists { qaLink.tap() }
        else if qaButton.exists { qaButton.tap() }
        else { qaLabel.tap() }

        XCTAssertTrue(
            app.navigationBars["Real Hardware QA"].waitForExistence(timeout: 5)
            || app.descendants(matching: .any)["qa.screen"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(scrollUntilExists(app, identifiers: ["qa.inventory", "Characters loaded"], texts: ["Account inventory", "Characters loaded"]))
        XCTAssertTrue(scrollUntilExists(app, identifiers: ["qa.api"], texts: ["API key", "Validated"]))

        // Live diagnostics precede the inventory/API sections. Return upward
        // rather than searching farther down the long QA checklist.
        XCTAssertTrue(scrollUntilExists(app, identifiers: ["qa.mapAlignment"], texts: ["Map Alignment workflow"], searchUpward: true))
        let alignment = app.descendants(matching: .any)["qa.mapAlignment"].firstMatch
        if alignment.exists {
            alignment.tap()
        } else if app.staticTexts["Map Alignment workflow"].exists {
            app.staticTexts["Map Alignment workflow"].tap()
        } else if app.buttons["Map Alignment workflow"].exists {
            app.buttons["Map Alignment workflow"].tap()
        }
        XCTAssertTrue(
            app.navigationBars["Map Alignment"].waitForExistence(timeout: 3)
            || app.staticTexts["Stand directly on a waypoint in Guild Wars 2."].waitForExistence(timeout: 2)
        )
        if app.navigationBars.buttons["Real Hardware QA"].exists {
            app.navigationBars.buttons["Real Hardware QA"].tap()
        } else if app.navigationBars.buttons.count > 0 {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        XCTAssertTrue(scrollUntilExists(app, identifiers: ["qa.export"], texts: ["Capture QA Snapshot", "Export"]))
        let export = app.descendants(matching: .any)["qa.export"].firstMatch
        if export.exists {
            export.tap()
        } else if app.buttons["Capture QA Snapshot"].exists {
            app.buttons["Capture QA Snapshot"].tap()
        }
        XCTAssertTrue(
            app.navigationBars["QA Snapshot"].waitForExistence(timeout: 3)
            || app.staticTexts["QA Snapshot"].waitForExistence(timeout: 2)
        )
    }

    private func scrollUntilExists(_ app: XCUIApplication, identifiers: [String], texts: [String], searchUpward: Bool = false) -> Bool {
        for _ in 0..<8 {
            if identifiers.contains(where: { app.descendants(matching: .any)[$0].exists }) { return true }
            if texts.contains(where: { app.staticTexts[$0].exists || app.buttons[$0].exists }) { return true }
            if searchUpward { app.swipeDown() } else { app.swipeUp() }
        }
        return identifiers.contains(where: { app.descendants(matching: .any)[$0].exists })
            || texts.contains(where: { app.staticTexts[$0].exists || app.buttons[$0].exists })
    }

    private func revealDeveloperQA(_ app: XCUIApplication) {
        if app.descendants(matching: .any)["settings.developer.qa"].waitForExistence(timeout: 1)
            || app.staticTexts["Real Hardware QA"].exists
            || app.buttons["Real Hardware QA"].exists {
            return
        }
        let about = app.staticTexts["GW2 Companion"].firstMatch.exists
            ? app.staticTexts["GW2 Companion"].firstMatch
            : app.buttons["GW2 Companion"].firstMatch
        if about.waitForExistence(timeout: 2) {
            for _ in 0..<8 { about.tap() }
        }
        for _ in 0..<3 { app.swipeUp() }
    }

    private func openPrimary(_ name: String, app: XCUIApplication) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.tap()
    }

    private func openMore(_ name: String, app: XCUIApplication) {
        app.tabBars.buttons["More"].tap()
        let identified = app.descendants(matching: .any)["more.\(name.lowercased())"]
        if identified.waitForExistence(timeout: 2) {
            identified.tap()
            return
        }
        let row = app.buttons[name].firstMatch.exists ? app.buttons[name].firstMatch : app.staticTexts[name]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
    }
}

/// Review artifacts accompany stable interaction assertions; no pixel snapshots are asserted.
@MainActor
final class PhaseSevenProductUITests: XCTestCase {
    func testCharacterTabsRemainUsable() {
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-smoke", "--phase2-fixtures", "--phase6h-fixtures", "--phase7-preview"]
        app.launch()
        open("Characters", app: app)
        app.staticTexts["Andrea"].firstMatch.press(forDuration: 0.1)
        XCTAssertTrue(app.buttons["character.section.build"].waitForExistence(timeout: 5))
        app.buttons["character.section.build"].press(forDuration: 0.1)
        XCTAssertTrue(app.staticTexts["Skills"].waitForExistence(timeout: 5))
        capture("Character Build focused", app: app)
        app.buttons["character.section.stats"].press(forDuration: 0.1)
        XCTAssertTrue(app.staticTexts["Estimated static stats"].waitForExistence(timeout: 5))
        capture("Character Stats focused", app: app)
    }

    func testDesignReviewAndCoreInteractions() {
        let app = XCUIApplication()
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        XCUIDevice.shared.orientation = pad ? .landscapeLeft : .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launchArguments = ["--ui-smoke", "--phase2-fixtures", "--phase6h-fixtures", "--phase7-preview", "--simulate-telemetry"]
        app.launch()

        open("Today", app: app)
        XCTAssertTrue(app.buttons["today.planSession"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Daily,")).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Weekly,")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Data source"].exists)
        capture("Today", app: app)
        let quickWin = app.staticTexts["Claim reward in game"].firstMatch
        if quickWin.exists {
            quickWin.press(forDuration: 0.1)
            XCTAssertTrue(app.staticTexts["Claim this reward inside Guild Wars 2. Rewards are claimed in game."].waitForExistence(timeout: 3))
            app.navigationBars.buttons.element(boundBy: 0).press(forDuration: 0.1)
        }

        open("Map", app: app)
        let map = app.otherElements["map.camera"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        capture("Live Map", app: app)
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.42)).press(forDuration: 0.1)
        XCTAssertTrue(app.buttons["map.chrome.sidebar"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["map.chrome.navigator"].exists)
        capture("Immersive Map", app: app)
        app.buttons["map.chrome.sidebar"].press(forDuration: 0.1)

        open("Characters", app: app)
        let roster = app.buttons["character.roster.Andrea"]
        let andrea = app.staticTexts["Andrea"].firstMatch
        XCTAssertTrue(roster.waitForExistence(timeout: 4) || andrea.waitForExistence(timeout: 4))
        capture("Characters", app: app)
        if roster.exists { roster.press(forDuration: 0.1) } else { andrea.press(forDuration: 0.1) }
        XCTAssertTrue(app.buttons["character.section.equipment"].waitForExistence(timeout: 4))
        capture("Character detail", app: app)
        app.buttons["character.section.build"].press(forDuration: 0.1)
        XCTAssertTrue(app.buttons["character.section.build"].waitForExistence(timeout: 3))
        if !app.staticTexts["Skills"].exists { app.scrollViews["character.profile"].swipeUp() }
        XCTAssertTrue(app.staticTexts["Skills"].waitForExistence(timeout: 3))
        app.scrollViews["character.profile"].swipeDown()
        capture("Character build", app: app)
        app.buttons["character.section.stats"].press(forDuration: 0.1)
        XCTAssertTrue(app.staticTexts["Estimated static stats"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Character Stat Audit"].exists)
        let calculation = app.buttons["stats.calculationDetails"]
        if !calculation.isHittable { app.scrollViews["character.profile"].swipeUp() }
        XCTAssertTrue(calculation.exists)
        calculation.press(forDuration: 0.1)
        app.scrollViews["character.profile"].swipeDown()
        capture("Character stats", app: app)
        app.buttons["character.section.inventory"].press(forDuration: 0.1)
        XCTAssertTrue(app.staticTexts["Starter Backpack"].waitForExistence(timeout: 3) || app.staticTexts["Bag 1"].exists)

        open("Inventory", app: app)
        for section in ["bank", "materials", "shared", "all"] {
            XCTAssertTrue(app.buttons["inventory.section.\(section)"].waitForExistence(timeout: 3))
            app.buttons["inventory.section.\(section)"].press(forDuration: 0.1)
        }
        capture("Inventory", app: app)
        let ore = app.buttons["inventory.item.Mithril Ore"].firstMatch
        XCTAssertTrue(ore.waitForExistence(timeout: 3))
        ore.press(forDuration: 0.1)
        XCTAssertTrue(app.navigationBars["Item"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Total"].exists)
        capture("Item detail", app: app)
        app.buttons["Done"].press(forDuration: 0.1)

        open("Goals", app: app)
        if !app.staticTexts["legendary.primaryProgress"].waitForExistence(timeout: 3) {
            app.staticTexts["Twilight"].firstMatch.press(forDuration: 0.1)
        }
        XCTAssertTrue(app.staticTexts["legendary.primaryProgress"].waitForExistence(timeout: 5))
        capture("Legendary Twilight", app: app)
        let mastery = app.buttons["legendary.requirement.19674"]
        if !mastery.isHittable { app.swipeUp() }
        XCTAssertTrue(mastery.exists)
        mastery.press(forDuration: 0.1)
        XCTAssertEqual(mastery.value as? String, "Expanded")
        mastery.press(forDuration: 0.1)
        XCTAssertEqual(mastery.value as? String, "Collapsed")

        open("Today", app: app)
        app.buttons["today.planSession"].press(forDuration: 0.1)
        XCTAssertTrue(app.buttons["Create Plan"].waitForExistence(timeout: 5))
        app.buttons["Create Plan"].press(forDuration: 0.1)
        XCTAssertTrue(app.buttons["Start Session"].waitForExistence(timeout: 5))
        capture("Session Planner", app: app)
        app.buttons["Start Session"].press(forDuration: 0.1)
        XCTAssertTrue(app.navigationBars["Your Session"].waitForExistence(timeout: 3))
        capture("Active Session", app: app)
    }

    func testSupportingScreensAndOnboarding() {
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-smoke", "--phase2-fixtures", "--phase7-preview",
                               "-wallet.allExpanded.v1.fixture_account", "NO"]
        app.launch()
        open("Account", app: app)
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 5))
        capture("Account and Wallet", app: app)
        let currencies = app.buttons["All Currencies"].firstMatch
        for _ in 0..<4 {
            if currencies.exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(currencies.waitForExistence(timeout: 3))
        XCTAssertEqual(currencies.value as? String, "Collapsed")
        currencies.tap()
        XCTAssertEqual(currencies.value as? String, "Expanded")
        capture("Wallet expanded", app: app)
        open("Settings", app: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture("Settings", app: app)
        XCTAssertFalse(app.buttons["UI Gallery"].exists)
        app.terminate()
        app.launchArguments = ["--phase2-fixtures", "--phase7-preview", "-onboarding.completed.v1", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["Get Started"].waitForExistence(timeout: 5))
        capture("Onboarding welcome", app: app)
        app.buttons["Get Started"].press(forDuration: 0.1)
        XCTAssertTrue(app.secureTextFields["ArenaNet API key"].waitForExistence(timeout: 5))
        capture("Onboarding account", app: app)
        app.buttons["Skip for Now"].press(forDuration: 0.1)
        XCTAssertTrue(app.buttons["Enter Details Manually"].waitForExistence(timeout: 5))
        capture("Onboarding PC", app: app)
        app.buttons["Skip for Now"].press(forDuration: 0.1)
    }

    private func open(_ name: String, app: XCUIApplication) {
        let sidebar = app.buttons["sidebar.\(name.lowercased())"]
        if sidebar.exists && sidebar.isHittable { sidebar.press(forDuration: 0.1); return }
        if app.tabBars.buttons[name].exists { app.tabBars.buttons[name].press(forDuration: 0.1); return }
        if app.tabBars.buttons["More"].exists {
            app.tabBars.buttons["More"].press(forDuration: 0.1)
            let more = app.buttons["more.\(name.lowercased())"]
            XCTAssertTrue(more.waitForExistence(timeout: 3)); more.press(forDuration: 0.1); return
        }
        let restore = app.buttons["map.chrome.sidebar"]
        if restore.exists { restore.press(forDuration: 0.1) }
        XCTAssertTrue(sidebar.waitForExistence(timeout: 3)); sidebar.press(forDuration: 0.1)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Phase 7 \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad landscape" : "iPhone") · \(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }
}


#if !DEBUG
@MainActor
final class PhaseSevenReleaseUITests: XCTestCase {
    func testReleaseHidesDeveloperToolsEvenWithSavedPreference() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-smoke", "--developer-mode"]
        app.launch()
        let sidebar = app.buttons["sidebar.settings"]
        if sidebar.waitForExistence(timeout: 3) {
            sidebar.tap()
        } else {
            app.tabBars.buttons["More"].tap()
            app.buttons["Settings"].tap()
        }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.swipeUp()
        let version = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "GW2 Companion")).firstMatch
        if version.exists && version.isHittable {
            for _ in 0..<7 { version.tap() }
        }
        XCTAssertFalse(app.staticTexts["Developer"].exists)
        XCTAssertFalse(app.buttons["UI Gallery"].exists)
        XCTAssertFalse(app.buttons["settings.developer.qa"].exists)
        XCTAssertFalse(app.buttons["Map Calibration"].exists)
        XCTAssertFalse(app.buttons["Start Telemetry Simulation"].exists)
        app.swipeDown()
        app.swipeDown()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Gaming PC")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Connect to PC"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Developer"].exists)
        XCTAssertFalse(app.buttons["Start simulated movement"].exists)
    }
}
#endif
