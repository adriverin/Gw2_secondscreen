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
        openPrimary("Characters", app: app)
        XCTAssertTrue(app.navigationBars["Characters"].waitForExistence(timeout: 3))

        openMore("Inventory", app: app)
        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 3))
        openMore("Account", app: app)
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 3))
        openMore("Settings", app: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    private func openPrimary(_ name: String, app: XCUIApplication) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.tap()
    }

    private func openMore(_ name: String, app: XCUIApplication) {
        app.tabBars.buttons["More"].tap()
        let row = app.tables.staticTexts[name]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
    }
}
