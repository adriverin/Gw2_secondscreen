import CoreGraphics
import XCTest
@testable import GW2Companion

final class TileProjectionTests: XCTestCase {
    private let projection = ArenaNetTileProjection.shared

    func testTyriaUsesCurrentContinentSpaceAtReferenceZoomSeven() {
        let config = projection.configuration(continentID: 1)
        XCTAssertEqual(config.referenceZoom, 7)
        XCTAssertEqual(config.advertisedMaxZoom, 8)
        XCTAssertFalse(config.usesLegacyTileOrigin)
    }

    func testOfficialLandmarksProjectOntoVerifiedArtworkTiles() throws {
        for landmark in MapAlignmentLandmarks.coreTyria {
            let tileWorld = try XCTUnwrap(projection.tileWorldCoordinate(
                from: landmark.continent, continentID: landmark.continentID, mapFloor: landmark.floor))
            XCTAssertEqual(tileWorld.x, landmark.continent.x, accuracy: 0.0001)
            XCTAssertEqual(tileWorld.y, landmark.continent.y, accuracy: 0.0001)
            let tile = try XCTUnwrap(projection.tileIndex(
                from: tileWorld, zoom: 7, continentID: landmark.continentID))
            XCTAssertEqual(tile, landmark.expectedTile, "\(landmark.name) must sit on verified artwork")
        }
    }

    func testKessexHillsDoesNotUseOceanNorthwestTiles() throws {
        let waypoint = MapAlignmentLandmarks.kessexHavenWaypoint
        let tileWorld = try XCTUnwrap(projection.tileWorldCoordinate(
            from: waypoint.continent, continentID: 1, mapFloor: 1))
        let tile = try XCTUnwrap(projection.tileIndex(from: tileWorld, zoom: 7, continentID: 1))

        XCTAssertEqual(tile, TileIndex(zoom: 7, x: 175, y: 122))
        // Former max-zoom-8 projection requested z=7 x=87 y=61 — ocean NW of Kessex.
        XCTAssertNotEqual(tile, TileIndex(zoom: 7, x: 87, y: 61))
        // Applying the EoD shift would also miss Kessex artwork.
        let legacy = EndOfDragonsShift.legacy(fromCurrent: waypoint.continent.x, y: waypoint.continent.y)
        let shifted = try XCTUnwrap(projection.tileIndex(from: legacy, zoom: 7, continentID: 1))
        XCTAssertNotEqual(shifted, tile)
        XCTAssertEqual(shifted, TileIndex(zoom: 7, x: 47, y: 58))
    }

    func testQueensdaleAndSparkflyFitPaintedArtworkCoverage() {
        XCTAssertTrue(projection.mapHasPaintedArtwork(MapAlignmentLandmarks.queensdaleMetadata))
        XCTAssertTrue(projection.mapHasPaintedArtwork(MapAlignmentLandmarks.kessexHillsMetadata))
        XCTAssertTrue(projection.mapHasPaintedArtwork(MapAlignmentLandmarks.sparkflyFenMetadata))
        XCTAssertTrue(projection.mapHasPaintedArtwork(MapAlignmentLandmarks.lionsArchMetadata))
        XCTAssertFalse(projection.mapHasPaintedArtwork(MapAlignmentLandmarks.unsupportedNewMapMetadata))
    }

    func testTileIndicesNeverWrap() {
        XCTAssertNil(projection.tileIndex(
            from: TileWorldCoordinate(x: -1, y: 31_380), zoom: 7, continentID: 1))
        XCTAssertNil(projection.tileIndex(
            from: TileWorldCoordinate(x: 44_843, y: -8), zoom: 7, continentID: 1))
        let config = projection.configuration(continentID: 1)
        XCTAssertNil(projection.tileWorldRect(
            for: TileIndex(zoom: 7, x: Int(config.continentWidth / 256) + 8, y: 10), continentID: 1))
        XCTAssertNil(ArenaNetTileProvider().tileURL(continent: 1, floor: 1, zoom: 7, x: -3, y: 10))
        XCTAssertNil(ArenaNetTileProvider().tileURL(continent: 1, floor: 1, zoom: 8, x: 175, y: 122))
        XCTAssertNotNil(ArenaNetTileProvider().tileURL(continent: 1, floor: 1, zoom: 7, x: 175, y: 122))
    }

    func testWrongAPIMaxZoomWouldDisplaceKessexOntoOcean() {
        let continent = MapAlignmentLandmarks.kessexHavenWaypoint.continent
        let incorrectScale = pow(2.0, Double(8 - 7))
        let displaced = TileIndex(
            zoom: 7,
            x: Int(floor(continent.x / incorrectScale / 256)),
            y: Int(floor(continent.y / incorrectScale / 256)))
        XCTAssertEqual(displaced, TileIndex(zoom: 7, x: 87, y: 61))
    }

    func testViewportUsesProjectionReferenceZoomNotAPIMaxZoom() {
        let transform = MapViewportTransform(
            center: MapAlignmentLandmarks.kessexHavenWaypoint.continent,
            zoom: 7, magnification: 1, dragOffset: .zero,
            size: CGSize(width: 256, height: 256), tileReferenceZoom: 7)
        XCTAssertEqual(transform.worldUnitsPerScreenPoint, 1, accuracy: 0.0001)
        let screen = transform.screenPosition(for: transform.center)
        XCTAssertEqual(screen.x, 128, accuracy: 0.001)
        XCTAssertEqual(screen.y, 128, accuracy: 0.001)
    }

    func testMapContinentRectDrivesFitBoundsIndependentOfTileSpace() throws {
        let bounds = try XCTUnwrap(MapAlignmentLandmarks.kessexHillsMetadata.continentBounds)
        XCTAssertEqual(bounds.minX, 42_112, accuracy: 0.1)
        XCTAssertEqual(bounds.minY, 30_464, accuracy: 0.1)
        let center = try XCTUnwrap(MapAlignmentLandmarks.kessexHillsMetadata.continentCenter)
        let tile = try XCTUnwrap(projection.tileIndex(
            from: TileWorldCoordinate(x: center.x, y: center.y), zoom: 7, continentID: 1))
        XCTAssertEqual(tile, TileIndex(zoom: 7, x: 172, y: 123))
    }
}

final class InventoryNavigationAndFixtureTests: XCTestCase {
    func testInventoryIsAnIPhonePrimaryDestination() {
        XCTAssertEqual(AppTab.iPhonePrimary, [.session, .map, .goals, .inventory])
        XCTAssertEqual(AppTab.iPhoneMore, [.characters, .account, .settings])
        XCTAssertEqual(AppTab.iPadSidebar, [.session, .map, .goals, .characters, .inventory, .account, .settings])
        XCTAssertTrue(AppTab.iPhonePrimary.contains(.inventory))
        XCTAssertFalse(AppTab.iPhoneMore.contains(.inventory))
    }

    @MainActor
    func testMissingInventoriesPermissionDoesNotRemoveTheDestination() {
        XCTAssertTrue(AppTab.allCases.contains(.inventory))
        let info = TokenInfo(id: "limited", name: "Limited", permissions: ["account", "characters"])
        let permissions = PermissionSet(info.permissions)
        XCTAssertFalse(permissions.contains(.inventories))
        XCTAssertTrue(permissions.contains(.account))
        XCTAssertTrue(permissions.contains(.characters))
    }

    func testMithrilAggregatesAcrossCharactersBankMaterialsAndShared() {
        let holdings = AccountHoldingAggregator.aggregate([
            (.character("Andrea"), [InventorySlot(id: 19697, count: 173)]),
            (.character("Ranger"), [InventorySlot(id: 19697, count: 173)]),
            (.bank, [InventorySlot(id: 19697, count: 211)]),
            (.sharedInventory, [InventorySlot(id: 19697, count: 100)]),
            (.materialStorage, [InventorySlot(id: 19697, count: 250)])
        ])
        let mithril = holdings.first { $0.itemID == 19697 }
        XCTAssertEqual(mithril?.totalQuantity, 907)
        XCTAssertEqual(Set(mithril?.locations.map(\.location) ?? []), [
            .character("Andrea"), .character("Ranger"), .bank, .sharedInventory, .materialStorage
        ])
    }

    func testBankNullSlotsAreEmptyNotErrors() throws {
        let data = Data(#"[{"id":19697,"count":211},null,{"id":46731,"count":4},null]"#.utf8)
        let slots = try JSONDecoder().decode([InventorySlot?].self, from: data)
        XCTAssertEqual(slots.count, 4)
        XCTAssertEqual(slots.compactMap { $0 }.count, 2)
        XCTAssertNil(slots[1])
        XCTAssertNil(slots[3])
    }
}
