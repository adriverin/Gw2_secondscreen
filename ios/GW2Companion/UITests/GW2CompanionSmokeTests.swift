import XCTest

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

        XCTAssertTrue(scrollUntilExists(app, identifiers: ["qa.mapAlignment"], texts: ["Map Alignment workflow"]))
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

    private func scrollUntilExists(_ app: XCUIApplication, identifiers: [String], texts: [String]) -> Bool {
        for _ in 0..<8 {
            if identifiers.contains(where: { app.descendants(matching: .any)[$0].exists }) { return true }
            if texts.contains(where: { app.staticTexts[$0].exists || app.buttons[$0].exists }) { return true }
            app.swipeUp()
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
