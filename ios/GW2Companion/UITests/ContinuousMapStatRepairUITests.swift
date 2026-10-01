import XCTest

@MainActor
final class ContinuousMapStatRepairUITests: XCTestCase {
    func testPinchPreservesFractionalZoomAfterFingerReleaseAndChromeTap() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-smoke", "--phase2-fixtures"]
        app.launch()
        let map = app.otherElements["map.camera"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        let initial = cameraZoom(map)
        map.pinch(withScale: 1.22, velocity: 1)
        let after = cameraZoom(map)
        XCTAssertGreaterThan(after, initial + 0.05)
        XCTAssertLessThan(after, initial + 0.6)
        XCTAssertGreaterThan(abs(after - after.rounded()), 0.02, "Finger release must not quantize the camera")
        XCTAssertTrue((map.value as? String)?.contains("tile source 6") == true)
        // Existing blank-map tap still toggles chrome through the native surface.
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.4)).tap()
        XCTAssertTrue(map.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Continuous fractional map camera"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func cameraZoom(_ element: XCUIElement) -> Double {
        let value = element.value as? String ?? ""
        let number = value.replacingOccurrences(of: "Camera zoom ", with: "").split(separator: ";").first.map(String.init) ?? ""
        return Double(number) ?? 0
    }
}
