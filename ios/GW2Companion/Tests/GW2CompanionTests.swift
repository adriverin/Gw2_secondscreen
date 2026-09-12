import XCTest
@testable import GW2Companion

final class TelemetryDecodingTests: XCTestCase {
    func testDecodesV1AndIgnoresFutureFields() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "telemetry.v1", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let value = try JSONDecoder().decode(TelemetryEnvelope.self, from: data)
        XCTAssertEqual(value.character?.name, "Example Character")
        XCTAssertEqual(value.map?.id, 15)
        XCTAssertEqual(value.player?.continentX, 11000.2)
    }
}

final class TokenInfoTests: XCTestCase {
    func testPermissionParsing() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "tokeninfo", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let info = try JSONDecoder().decode(TokenInfo.self, from: data)
        XCTAssertTrue(info.permissions.contains("inventories"))
        XCTAssertFalse(info.permissions.contains("tradingpost"))
    }
}

final class CoordinateTransformerTests: XCTestCase {
    func testMapAndContinentRoundTripWithYAxisInversion() throws {
        let metadata = GW2MapMetadata(id: 15, name: "Test", continentId: 1, defaultFloor: 1,
                                      mapRect: [[0, 0], [1_000, 2_000]], continentRect: [[10_000, 12_000], [12_000, 16_000]])
        let transformer = GW2CoordinateTransformer(metadata: metadata)
        let map = try transformer.mapPoint(from: ContinentPoint(x: 10_500, y: 13_000))
        XCTAssertEqual(map.x, 250, accuracy: 0.001)
        XCTAssertEqual(map.y, 1_500, accuracy: 0.001)
        let roundTrip = try transformer.continentPoint(from: map)
        XCTAssertEqual(roundTrip.x, 10_500, accuracy: 0.001)
        XCTAssertEqual(roundTrip.y, 13_000, accuracy: 0.001)
    }

    func testTileCoordinateAtMaximumZoom() {
        let metadata = GW2MapMetadata(id: 15, name: "Test", continentId: 1, defaultFloor: 1,
                                      mapRect: [[0, 0], [1, 1]], continentRect: [[0, 0], [1, 1]])
        let tile = GW2CoordinateTransformer(metadata: metadata).tilePoint(from: ContinentPoint(x: 513, y: 770), zoom: 7)
        XCTAssertEqual(tile.tileX, 2)
        XCTAssertEqual(tile.tileY, 3)
        XCTAssertEqual(tile.pixelX, 1)
        XCTAssertEqual(tile.pixelY, 2)
    }
}

final class GatheringTests: XCTestCase {
    private let nodes = [
        GatheringNode(id: "near", mapId: 15, continentX: 12, continentY: 10, category: .ore, name: "Near", reliability: .fixed, source: nil, notes: nil),
        GatheringNode(id: "far", mapId: 15, continentX: 50, continentY: 50, category: .wood, name: "Far", reliability: .possible, source: nil, notes: nil),
        GatheringNode(id: "other", mapId: 50, continentX: 10, continentY: 10, category: .plant, name: "Other", reliability: .fixed, source: nil, notes: nil)
    ]

    func testNearestNode() {
        XCTAssertEqual(GatheringGeometry.nearest(to: ContinentPoint(x: 10, y: 10), among: Array(nodes.prefix(2)))?.id, "near")
    }

    func testVisitedDetectionUsesRadius() {
        let visited = GatheringGeometry.nodesWithin(radius: 3, of: ContinentPoint(x: 10, y: 10), among: nodes)
        XCTAssertEqual(visited, ["near", "other"])
    }

    func testFilteringByMapAndCategory() {
        let filtered = nodes.filter { $0.mapId == 15 && $0.category == .ore }
        XCTAssertEqual(filtered.map(\.id), ["near"])
    }
}

final class APIBatchingTests: XCTestCase {
    func testCharacterInventoryEnvelopeDecoding() throws {
        let data = Data(#"{"bags":[{"id":20,"size":20,"inventory":[{"id":19697,"count":12},null]},null]}"#.utf8)
        let response = try JSONDecoder().decode(CharacterInventoryResponse.self, from: data)
        XCTAssertEqual(response.bags.compactMap { $0 }.first?.inventory?.compactMap { $0 }.first?.count, 12)
    }

    func testIDsAreDeduplicatedAndSorted() {
        XCTAssertEqual(GW2APIClient.batchedIDs([9, 2, 9, 3, 2]), ["2", "3", "9"])
    }

    func testChunksRespectTwoHundredItemLimit() {
        let chunks = GW2APIClient.chunks(of: Array(0..<401), size: 200)
        XCTAssertEqual(chunks.map(\.count), [200, 200, 1])
    }
}
