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

final class CoinAmountTests: XCTestCase {
    func testCopperBoundaries() {
        let cases: [(Int, CoinAmount)] = [
            (0, CoinAmount(gold: 0, silver: 0, copper: 0)),
            (99, CoinAmount(gold: 0, silver: 0, copper: 99)),
            (100, CoinAmount(gold: 0, silver: 1, copper: 0)),
            (9_999, CoinAmount(gold: 0, silver: 99, copper: 99)),
            (10_000, CoinAmount(gold: 1, silver: 0, copper: 0)),
            (526_532, CoinAmount(gold: 52, silver: 65, copper: 32))
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(CoinAmount(copperValue: raw), expected)
        }
    }
}

final class MapLandmarkTests: XCTestCase {
    func testDecodesOfficialFloorMarkerTypes() throws {
        let data = Data(#"""
        {
          "id":15,
          "points_of_interest":{
            "1":{"name":"Village Waypoint","type":"waypoint","floor":1,"coord":[10,20],"id":1,"chat_link":"[&A=]"},
            "2":{"name":"Old Mill","type":"landmark","floor":1,"coord":[30,40],"id":2,"chat_link":"[&B=]"},
            "3":{"name":"","type":"vista","floor":1,"coord":[50,60],"id":3,"chat_link":"[&C=]"}
          },
          "tasks":{"4":{"objective":"Help the villagers","level":5,"coord":[70,80],"bounds":[],"id":4,"chat_link":"[&D=]"}},
          "skill_challenges":[{"coord":[90,100],"id":"0-5"},{"coord":[110,120]}]
        }
        """#.utf8)
        let map = try JSONDecoder().decode(GW2FloorMap.self, from: data)
        let landmarks = map.landmarks()

        XCTAssertEqual(Set(landmarks.map(\.kind)), Set(MapLandmarkKind.allCases))
        XCTAssertEqual(landmarks.filter { $0.kind == .heroChallenge }.count, 2)
        XCTAssertEqual(landmarks.first(where: { $0.kind == .vista })?.name, "Vista")
        XCTAssertEqual(landmarks.first(where: { $0.kind == .waypoint })?.chatLink, "[&A=]")
    }

    func testConvertsTacOWorldMetersToContinentCoordinates() throws {
        let metadata = GW2MapMetadata(
            id: 15, name: "Queensdale", continentId: 1, defaultFloor: 1,
            mapRect: [[-43_008, -27_648], [43_008, 30_720]],
            continentRect: [[9_856, 11_648], [13_440, 14_080]])
        let point = try GW2CoordinateTransformer(metadata: metadata).continentPoint(worldX: -193.448, worldZ: 324.628)

        XCTAssertEqual(point.x, 11_330.664, accuracy: 0.01)
        XCTAssertEqual(point.y, 13_460.526, accuracy: 0.01)
    }
}

@MainActor
final class MapStoreTests: XCTestCase {
    func testEmptyLayerSelectionsArePreserved() {
        let suite = "GW2CompanionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([], forKey: "visibleGatheringCategories")
        defaults.set([], forKey: "visibleGatheringReliabilities")
        defaults.set([], forKey: "visibleMapLandmarkKinds")

        XCTAssertTrue(GatheringStore(defaults: defaults).categories.isEmpty)
        XCTAssertTrue(GatheringStore(defaults: defaults).reliabilities.isEmpty)
        XCTAssertTrue(MapOverlayStore(defaults: defaults).visibleKinds.isEmpty)
    }

    func testOlderMapLoadCannotReplaceNewerMap() async {
        let store = MapOverlayStore(defaults: UserDefaults(suiteName: "GW2CompanionTests-\(UUID().uuidString)")!)
        let provider = DelayedLandmarkProvider()
        let old = GW2MapMetadata(id: 1, name: "Old", continentId: 1, defaultFloor: 1,
                                mapRect: [[0, 0], [1, 1]], continentRect: [[0, 0], [1, 1]])
        let new = GW2MapMetadata(id: 2, name: "New", continentId: 1, defaultFloor: 1,
                                mapRect: [[0, 0], [1, 1]], continentRect: [[0, 0], [1, 1]])

        let olderTask = Task { await store.load(provider: provider, metadata: old) }
        try? await Task.sleep(for: .milliseconds(10))
        await store.load(provider: provider, metadata: new)
        await olderTask.value

        XCTAssertEqual(store.landmarks.map(\.name), ["Map 2"])
    }
}

private actor DelayedLandmarkProvider: MapLandmarkDataProvider {
    func landmarks(continentId: Int, floor: Int, mapId: Int) async throws -> [MapLandmark] {
        try await Task.sleep(for: .milliseconds(mapId == 1 ? 100 : 5))
        return [MapLandmark(
            id: "map-\(mapId)", kind: .waypoint, name: "Map \(mapId)",
            coordinate: ContinentPoint(x: Double(mapId), y: 0), chatLink: nil)]
    }
}

final class BridgeConnectionTests: XCTestCase {
    func testUnauthorizedPairingIsReportedDistinctly() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UnauthorizedURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let connection = BridgeConnection(
            pairing: BridgePairing(host: "192.0.2.1", port: 38291, token: String(repeating: "a", count: 32)),
            session: session)

        do {
            for try await _ in connection.telemetryStream() {}
            XCTFail("Expected an invalid pairing error")
        } catch {
            XCTAssertEqual(error as? BridgeConnectionError, .pairAgain)
        }
    }

    func testCancellingStreamClosesSocket() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AcceptedURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let started = expectation(description: "socket started")
        let closed = expectation(description: "socket closed")
        let socket = BlockingBridgeSocket(started: started, closed: closed)
        let connection = BridgeConnection(
            pairing: BridgePairing(host: "192.0.2.1", port: 38291, token: String(repeating: "a", count: 32)),
            session: session,
            socketFactory: { _ in socket })

        let consumer = Task {
            do {
                for try await _ in connection.telemetryStream() {}
            } catch is CancellationError {
                // Expected when the consumer is cancelled.
            } catch {
                XCTFail("Unexpected connection error: \(error)")
            }
        }
        await fulfillment(of: [started], timeout: 1)
        consumer.cancel()
        await fulfillment(of: [closed], timeout: 1)
        _ = await consumer.result
    }
}

private final class UnauthorizedURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class AcceptedURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class BlockingBridgeSocket: BridgeWebSocket, @unchecked Sendable {
    private let started: XCTestExpectation
    private let closed: XCTestExpectation

    init(started: XCTestExpectation, closed: XCTestExpectation) {
        self.started = started
        self.closed = closed
    }

    func resume() { started.fulfill() }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await Task.sleep(for: .seconds(60))
        throw BridgeConnectionError.closed
    }

    func close() { closed.fulfill() }
}
