import XCTest
import UIKit

@MainActor
final class ContinuousMapStatRepairUITests: XCTestCase {
    func testRapidDetailedKessexZoomPanRetainsPaintedRasterThroughFailureAndCancellation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-smoke", "--phase2-fixtures", "--map-handoff-regression"]
        app.launch()
        let map = app.otherElements["map.camera"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        // Give the complete coarse backing one bounded chance to load. All
        // following gestures overlap slower detailed replacement requests.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.darkCoverage(app: app, map: map) < 0.2
        }, object: map)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        for scale in [0.7, 0.65, 0.7, 1.45, 1.6, 0.72] {
            map.pinch(withScale: scale, velocity: scale < 1 ? -2 : 2)
            let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
            start.press(forDuration: 0.01, thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.55)))
            XCTAssertLessThan(darkCoverage(app: app, map: map), 0.2, "Large dark rectangles must never replace retained artwork")
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Atomic raster handoff after scale \(scale)"
            attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertGreaterThan(cameraZoom(map), 2)
        XCTAssertLessThan(cameraZoom(map), 7)
    }

    private func darkCoverage(app: XCUIApplication, map: XCUIElement) -> Double {
        let screenshot = app.screenshot().image
        guard let cg = screenshot.cgImage else { return 1 }
        let scale = CGFloat(cg.width) / screenshot.size.width
        let region = CGRect(x: map.frame.midX - 70, y: map.frame.midY - 70, width: 140, height: 140)
        guard let cropped = cg.cropping(to: CGRect(x: region.minX * scale, y: region.minY * scale,
                                                   width: region.width * scale, height: region.height * scale)) else { return 1 }
        let width = 40, height = 40
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 1 }
        let dark = stride(from: 0, to: bytes.count, by: 4).filter { max(bytes[$0], bytes[$0 + 1], bytes[$0 + 2]) < 55 }.count
        return Double(dark) / Double(width * height)
    }

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
