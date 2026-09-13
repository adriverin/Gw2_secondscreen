import Foundation
import XCTest
@testable import GW2Companion

final class PhaseThreeObjectiveParsingTests: XCTestCase {
    func testOfficialContinentFixturesProduceAllSupportedWorldTypes() throws {
        let fixtureNames = ["continent-floor-queensdale", "continent-floor-sparkfly", "continent-floor-verdant-brink"]
        var objectives: [MapObjective] = []
        for name in fixtureNames {
            let data = try fixtureData(name)
            let floor = try JSONDecoder().decode(GW2FloorMetadata.self, from: data)
            objectives += floor.regions.values.flatMap(\.maps.values).flatMap { $0.objectives() }
        }
        XCTAssertTrue(objectives.allSatisfy { $0.source == .arenaNet })
        XCTAssertEqual(Set(objectives.map(\.type)), [
            .waypoint, .vista, .landmark, .renownHeart, .heroChallenge, .masteryInsight, .adventure
        ])
        XCTAssertEqual(objectives.first { $0.name == "Shaemoor Waypoint" }?.chatLink, "[&BO8AAAA=]")
        XCTAssertEqual(objectives.first { $0.type == .renownHeart }?.level, 2)
    }

    func testMapFilteringRetainsOnlyRequestedMap() throws {
        let data = try fixtureData("continent-floor-queensdale")
        let floor = try JSONDecoder().decode(GW2FloorMetadata.self, from: data)
        let all = floor.regions.values.flatMap(\.maps.values).flatMap { $0.objectives() }
        XCTAssertTrue(all.filter { $0.mapId == 15 }.allSatisfy { $0.mapId == 15 })
        XCTAssertEqual(all.filter { $0.mapId == 999 }.count, 0)
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
}

final class MapObjectiveCacheTests: XCTestCase {
    func testOfficialObjectivesRemainAvailableFromPersistentCacheOffline() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhaseThreeObjectiveCache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let onlineConfiguration = URLSessionConfiguration.ephemeral
        onlineConfiguration.protocolClasses = [FixedFloorURLProtocol.self]
        let online = GW2APIClient(
            session: URLSession(configuration: onlineConfiguration),
            diskCache: MetadataDiskCache(directory: directory))
        let loaded = try await online.objectives(continentId: 1, floor: 1, mapId: 15, language: "en")
        XCTAssertEqual(loaded.map(\.name), ["Cached Waypoint"])

        let offlineConfiguration = URLSessionConfiguration.ephemeral
        offlineConfiguration.protocolClasses = [OfflineFloorURLProtocol.self]
        let offline = GW2APIClient(
            session: URLSession(configuration: offlineConfiguration),
            diskCache: MetadataDiskCache(directory: directory))
        let restored = try await offline.objectives(continentId: 1, floor: 1, mapId: 15, language: "en")
        XCTAssertEqual(restored, loaded)
    }
}

final class ObjectiveDistanceEngineTests: XCTestCase {
    func testDistanceAndBearingAreDeterministic() {
        let start = ContinentPoint(x: 10, y: 10)
        XCTAssertEqual(ObjectiveDistanceEngine.distance(from: start, to: ContinentPoint(x: 13, y: 14)), 5, accuracy: 0.0001)
        XCTAssertEqual(ObjectiveDistanceEngine.bearing(from: start, to: ContinentPoint(x: 10, y: 0)), 0, accuracy: 0.0001)
        XCTAssertEqual(ObjectiveDistanceEngine.bearing(from: start, to: ContinentPoint(x: 20, y: 10)), 90, accuracy: 0.0001)
    }

    func testAllEightCardinalDirections() {
        let origin = ContinentPoint(x: 0, y: 0)
        let cases: [(ContinentPoint, CardinalDirection)] = [
            (.init(x: 0, y: -1), .n), (.init(x: 1, y: -1), .ne),
            (.init(x: 1, y: 0), .e), (.init(x: 1, y: 1), .se),
            (.init(x: 0, y: 1), .s), (.init(x: -1, y: 1), .sw),
            (.init(x: -1, y: 0), .w), (.init(x: -1, y: -1), .nw)
        ]
        for (point, expected) in cases {
            XCTAssertEqual(ObjectiveDistanceEngine.cardinalDirection(from: origin, to: point), expected)
        }
    }

    func testNearbySortAndArrivalFireOnceUntilLeavingRadius() throws {
        let near = objective("near", x: 10, y: 0)
        let far = objective("far", x: 100, y: 0)
        let engine = ObjectiveProximityEngine(minimumInterval: 0, minimumMovement: 0)
        let first = try XCTUnwrap(engine.evaluate(
            player: .init(x: 0, y: 0), objectives: [far, near], targetID: near.id, force: true))
        XCTAssertEqual(first.nearby.map(\.id), [near.id, far.id])
        XCTAssertTrue(first.targetReached)
        let repeated = try XCTUnwrap(engine.evaluate(
            player: .init(x: 0, y: 0), objectives: [far, near], targetID: near.id, force: true))
        XCTAssertFalse(repeated.targetReached)
        XCTAssertTrue(repeated.newlyVisited.isEmpty)
    }

    func testNearestNeighborRouteUsesStableTieBreak() {
        let values = [objective("c", x: 20, y: 0), objective("b", x: 10, y: 0), objective("a", x: 0, y: 10)]
        XCTAssertEqual(RouteGenerator.nearestNeighbor(from: .init(x: 0, y: 0), objectives: values).map(\.rawValue), ["a", "b", "c"])
    }

    private func objective(_ id: String, x: Double, y: Double, type: MapObjectiveType = .heroChallenge, map: Int = 15) -> MapObjective {
        MapObjective(id: .init(id), mapId: map, name: id, type: type, continentX: x, continentY: y,
                     source: .arenaNet, chatLink: nil, level: nil, description: nil, state: .unknown)
    }
}

@MainActor
final class MapObjectiveStoreTests: XCTestCase {
    func testPersistenceAndCompletionSemanticsSurviveRelaunch() async throws {
        let suite = "PhaseThreeStore-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let target = objective("target", x: 10, y: 10)
        let provider = FixedObjectiveProvider(values: [target])

        let first = MapObjectiveStore(defaults: defaults, proximity: .init(minimumInterval: 0, minimumMovement: 0))
        first.setIdentity(accountID: "account", characterName: "Andrea")
        await first.load(provider: provider, metadata: metadata(15))
        first.markManuallyCompleted(target.id)
        first.updatePlayer(.init(x: 10, y: 10), force: true)
        XCTAssertEqual(first.objective(target.id)?.state, .manuallyCompleted)

        let relaunched = MapObjectiveStore(defaults: defaults)
        relaunched.setIdentity(accountID: "account", characterName: "Andrea")
        await relaunched.load(provider: provider, metadata: metadata(15))
        XCTAssertEqual(relaunched.objective(target.id)?.state, .manuallyCompleted)
    }

    func testHiddenLayersDoNotParticipateInNearbyAndTransitionClearsOldMap() async {
        let store = freshStore()
        let waypoint = objective("waypoint", x: 5, y: 0, type: .waypoint)
        let vista = objective("vista", x: 1, y: 0, type: .vista)
        await store.load(provider: FixedObjectiveProvider(values: [waypoint, vista]), metadata: metadata(15))
        store.visibleTypes = [.waypoint]
        store.updatePlayer(.init(x: 0, y: 0), force: true)
        XCTAssertEqual(store.nearby.map(\.id), [waypoint.id])

        store.transition(to: 50)
        XCTAssertTrue(store.objectives.isEmpty)
        XCTAssertTrue(store.visibleObjectives.isEmpty)
    }

    func testArrivalAdvancesRouteAndMarksOnlyVisited() async throws {
        let store = freshStore()
        let first = objective("first", x: 10, y: 0)
        let second = objective("second", x: 200, y: 0)
        await store.load(provider: FixedObjectiveProvider(values: [first, second]), metadata: metadata(15))
        store.addToRoute(first)
        store.addToRoute(second)
        store.startRoute()
        store.updatePlayer(.init(x: 10, y: 0), force: true)
        XCTAssertEqual(store.objective(first.id)?.state, .visited)
        XCTAssertNotEqual(store.objective(first.id)?.state, .manuallyCompleted)
        XCTAssertEqual(store.currentTargetID, second.id)
    }

    func testQueensdaleSimulationReachesOfficialHeroChallengeAndAdvances() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "continent-floor-queensdale", withExtension: "json"))
        let floor = try JSONDecoder().decode(GW2FloorMetadata.self, from: Data(contentsOf: url))
        let values = floor.regions.values.flatMap(\.maps.values).flatMap { $0.objectives() }
        let hero = try XCTUnwrap(values.first { $0.id.rawValue == "arenanet:15:hero:0-7" })
        let waypoint = try XCTUnwrap(values.first { $0.type == .waypoint })
        let store = freshStore()
        await store.load(provider: FixedObjectiveProvider(values: values), metadata: metadata(15))
        store.addToRoute(hero)
        store.addToRoute(waypoint)
        store.startRoute()

        // Angle zero in both bridge and iOS simulations is this exact east point.
        store.updatePlayer(.init(x: 45_135.5, y: 29_863.7), force: true)

        XCTAssertEqual(store.objective(hero.id)?.state, .visited)
        XCTAssertEqual(store.currentTargetID, waypoint.id)
    }

    private func freshStore() -> MapObjectiveStore {
        let defaults = UserDefaults(suiteName: "PhaseThreeStore-\(UUID().uuidString)")!
        return MapObjectiveStore(defaults: defaults, proximity: .init(minimumInterval: 0, minimumMovement: 0))
    }

    private func objective(_ id: String, x: Double, y: Double, type: MapObjectiveType = .heroChallenge) -> MapObjective {
        MapObjective(id: .init(id), mapId: 15, name: id, type: type, continentX: x, continentY: y,
                     source: .arenaNet, chatLink: nil, level: nil, description: nil, state: .unknown)
    }

    private func metadata(_ id: Int) -> GW2MapMetadata {
        GW2MapMetadata(id: id, name: "Map \(id)", continentId: 1, defaultFloor: 1,
                       mapRect: [[0, 0], [100, 100]], continentRect: [[0, 0], [100, 100]])
    }
}

private struct FixedObjectiveProvider: MapObjectiveDataProvider {
    let values: [MapObjective]
    func objectives(continentId: Int, floor: Int, mapId: Int, language: String) async throws -> [MapObjective] {
        values.filter { $0.mapId == mapId }
    }
}

private final class FixedFloorURLProtocol: URLProtocol, @unchecked Sendable {
    private static let payload = Data(#"{"regions":{"4":{"maps":{"15":{"id":15,"points_of_interest":{"1":{"name":"Cached Waypoint","type":"waypoint","coord":[10,20],"id":1,"chat_link":"[&A=]"}}}}}}}"#.utf8)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class OfflineFloorURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
