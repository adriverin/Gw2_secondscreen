import XCTest

@MainActor
final class PhaseSixHRepairUITests: XCTestCase {
    func testLegendaryHasOneHeroFourCompactRowsAndCollapsedChildren() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-smoke", "--phase2-fixtures", "--phase6h-fixtures"]
        app.launch()
        let sidebar = app.buttons["sidebar.goals"]
        if sidebar.waitForExistence(timeout: 5) { sidebar.tap() }
        else { app.tabBars.buttons["Goals"].tap() }
        let progress = app.staticTexts["legendary.primaryProgress"]
        if !progress.waitForExistence(timeout: 5) { app.staticTexts["Twilight"].firstMatch.tap() }
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "legendary.primaryProgress").count, 1)
        XCTAssertEqual(progress.label, "0 of 4 major requirements ready")
        for name in ["Dusk", "Gift of Twilight", "Gift of Fortune", "Gift of Mastery"] {
            XCTAssertTrue(app.staticTexts[name].firstMatch.exists, name)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Phase 6H compact Legendary detail"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertFalse(app.staticTexts["Gift of Battle"].exists)
        XCTAssertFalse(app.staticTexts["Gift of Exploration"].exists)
        let mastery = app.buttons["legendary.requirement.19674"]
        XCTAssertTrue(mastery.exists)
        mastery.tap()
        XCTAssertTrue(app.staticTexts["Gift of Battle"].waitForExistence(timeout: 3))
        mastery.tap()
        XCTAssertTrue(app.staticTexts["Gift of Battle"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.switches["legendary.showCompleted"].exists)
    }

    func testPriceAlreadyAvailableBeforeMetadataDoesNotExposeRawID() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-smoke", "--phase2-fixtures", "--phase6h-fixtures", "--phase6h-price-race"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Loading item details…"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Buy now · each"].exists, "Price fixture is already available while metadata is delayed")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Phase 6H price before metadata"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertFalse(app.staticTexts["ITEM 29185"].exists)
        XCTAssertFalse(app.staticTexts["Item 29185"].exists)
        XCTAssertTrue(app.staticTexts["Dusk"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["ITEM 29185"].exists)
    }

    func testPriceRequestShowsCheckingWithKnownMetadataThenAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-smoke", "--phase2-fixtures", "--phase6h-fixtures", "--tp-loading-regression"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Checking Trading Post…"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Dusk"].exists)
        XCTAssertFalse(app.staticTexts["Trading Post price unavailable"].exists)
        XCTAssertFalse(app.staticTexts["A Trading Post price is not available."].exists)
        XCTAssertTrue(app.staticTexts["Buy now · each"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Checking Trading Post…"].exists)
    }

    func testStaleCachedPriceStaysVisibleWhileRefreshing() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-smoke", "--phase2-fixtures", "--phase6h-fixtures", "--tp-loading-regression", "--tp-stale-regression"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Refreshing…"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Last known price"].exists)
        XCTAssertTrue(app.staticTexts["Buy now · each"].exists)
        XCTAssertFalse(app.staticTexts["Trading Post price unavailable"].exists)
        XCTAssertTrue(app.staticTexts["Refreshing…"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Buy now · each"].exists)
    }
}
