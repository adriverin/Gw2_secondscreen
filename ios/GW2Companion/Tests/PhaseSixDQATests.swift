import Foundation
import XCTest
@testable import GW2Companion

@MainActor
final class QAResultPersistenceTests: XCTestCase {
    func testRecordsPassFailAndReset() {
        let suite = "qa-persist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QAResultStore(defaults: defaults)
        store.record(id: "map.poi", state: .passed, note: " overlapped ")
        store.record(id: "account.bank", state: .failed, note: "empty", severity: .p1)
        XCTAssertEqual(store.result(for: "map.poi").state, .passed)
        XCTAssertEqual(store.result(for: "account.bank").severity, .p1)
        XCTAssertEqual(store.counts.failed, 1)
        XCTAssertEqual(store.counts.passed, 1)

        let restored = QAResultStore(defaults: defaults)
        XCTAssertEqual(restored.result(for: "map.poi").state, .passed)
        restored.reset()
        XCTAssertEqual(restored.result(for: "map.poi").state, .notTested)
        XCTAssertEqual(QAResultStore(defaults: defaults).result(for: "account.bank").state, .notTested)
    }

    func testDoesNotAutoPassBecauseDataExists() {
        let store = QAResultStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        XCTAssertEqual(store.result(for: "mumble.character").state, .notTested)
        XCTAssertEqual(QACatalog.checks.isEmpty, false)
    }
}

final class QARedactionTests: XCTestCase {
    func testScrubsSecretsAndCharacterPaths() {
        let secrets = QARedactionSecrets(
            apiKey: "ABCDEFGH-TEST-KEY-1234567890",
            pairingToken: "abcdefghijklmnopqrstuvwxyz123456",
            accountName: "Andrea.1234",
            characterNames: ["Test Mesmer"],
            portraitURLs: ["https://render.guildwars2.com/portrait.png"])
        let text = QARedaction.scrub(
            "key=ABCDEFGH-TEST-KEY-1234567890 token=abcdefghijklmnopqrstuvwxyz123456 Andrea.1234 Test Mesmer",
            secrets: secrets)
        XCTAssertFalse(text.contains("ABCDEFGH-TEST-KEY-1234567890"))
        XCTAssertFalse(text.contains("abcdefghijklmnopqrstuvwxyz123456"))
        XCTAssertFalse(text.contains("Andrea.1234"))
        XCTAssertEqual(QARedaction.name("Test Mesmer", reveal: false), "redacted")
        XCTAssertEqual(QARedaction.name("Test Mesmer", reveal: true), "Test Mesmer")
        XCTAssertEqual(QARedaction.apiPath("characters/Test%20Mesmer/inventory"), "characters/{name}/inventory")
    }
}

final class QASupportBundleTests: XCTestCase {
    func testReportVersioningAndRedaction() {
        let secrets = QARedactionSecrets(
            apiKey: "secret-api-key-value-32chars-min",
            pairingToken: "abcdefghijklmnopqrstuvwxyz123456",
            accountName: "Hidden.0001",
            characterNames: ["Hidden Character"],
            portraitURLs: [])
        let document = QASupportBundle.make(
            context: QAExportContext(
                appVersion: "1.0", build: "9", iosVersion: "18.0", deviceModel: "iPhone17,1",
                bridgeVersion: "1.0.0", telemetryProtocolVersion: 1, connectionState: "connectedLive",
                connectionTransitions: [ConnectionTransition(from: "connecting", to: "connectedLive")],
                qaResults: [
                    QACheckResult(id: "account.bank", state: .failed, note: "Hidden.0001 secret-api-key-value-32chars-min", severity: .p0)
                ],
                map: MapQADiagnosticsSnapshot(mapID: 15, mapName: "Queensdale", continentID: 1, floor: 1,
                                              continentX: 1, continentY: 2, artworkAvailable: true,
                                              coverageReason: .withinKnownPaintedCoverage),
                telemetryPacketsPerSecond: 18, telemetryAgeSeconds: 0.2,
                apiPermissions: ["account", "inventories"],
                accountSource: .live, accountMetadataUpdatedAt: Date(timeIntervalSince1970: 1),
                charactersUpdatedAt: Date(timeIntervalSince1970: 2),
                inventoryUpdatedAt: Date(timeIntervalSince1970: 3),
                todayUpdatedAt: Date(timeIntervalSince1970: 4), todaySource: .cached,
                pricesUpdatedAt: Date(timeIntervalSince1970: 5),
                apiDomains: [APIDomainStatus(domain: "inventory", httpStatus: 403, message: "Missing inventories permission", usedCache: false, updatedAt: Date(timeIntervalSince1970: 6))],
                events: [DeveloperEvent(at: Date(timeIntervalSince1970: 7), message: "Bridge connected Hidden.0001")],
                memory: MemoryDiagnosticsSnapshot(
                    tileCacheCount: 4, imageMemoryCacheCount: 8, mapIconCount: 3,
                    activeMapMarkers: 12, activeObjectives: 40, telemetryPacketsPerSecond: 18,
                    availableMemoryBytes: 1_000),
                secrets: secrets),
            now: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(document.schemaVersion, 1)
        let json = QASupportBundle.jsonString(document)
        let text = QASupportBundle.readableText(document)
        XCTAssertTrue(json.contains("\"schemaVersion\" : 1") || json.contains("\"schemaVersion\":1") || json.contains("schemaVersion"))
        XCTAssertFalse(QARedaction.containsUnredactedSecrets(json, secrets: secrets))
        XCTAssertFalse(QARedaction.containsUnredactedSecrets(text, secrets: secrets))
        XCTAssertFalse(json.contains("Hidden.0001"))
        XCTAssertFalse(json.contains("secret-api-key-value-32chars-min"))
        XCTAssertTrue(document.failureNotes.contains { $0.contains("account.bank") })
        XCTAssertEqual(document.accountSource, "LIVE ACCOUNT RESPONSE")
        XCTAssertEqual(document.todaySource, "CACHED")
    }
}

@MainActor
final class DeveloperEventLogTests: XCTestCase {
    func testEventLogIsBoundedAndTransitionsAreRecorded() {
        let defaults = UserDefaults(suiteName: "qa-events-\(UUID().uuidString)")!
        let log = DeveloperDiagnostics(defaults: defaults, restore: false)
        for index in 0..<250 {
            log.record("event \(index)")
        }
        XCTAssertEqual(log.events.count, QALogLimits.eventLimit)
        XCTAssertEqual(log.events.first?.message, "event 50")
        log.recordConnection(from: .connecting, to: .connectedLive)
        XCTAssertEqual(log.transitions.last?.to, "connectedLive")
        XCTAssertTrue(log.copiedEventLog.contains("GW2 telemetry live"))
        XCTAssertFalse(log.copiedEventLog.contains("abcdefghijklmnopqrstuvwxyz123456"))
    }
}

@MainActor
final class AccountDataSourceLabelTests: XCTestCase {
    func testLiveAndCachedLabels() {
        XCTAssertEqual(AccountDataSource.live.qaLabel, "LIVE ACCOUNT RESPONSE")
        XCTAssertEqual(AccountDataSource.cached.qaLabel, "CACHED")
        let result = AccountStore.mapAPIError(GW2APIError.missingPermission("inventories"))
        XCTAssertEqual(result.status, 403)
        XCTAssertTrue(result.message.contains("inventories"))
    }
}

final class ConnectionTransitionLoggingTests: XCTestCase {
    func testStateMachineKeysMatchQAVisualization() {
        XCTAssertEqual(TelemetryConnectionState.disconnected.qaKey, "disconnected")
        XCTAssertEqual(TelemetryConnectionState.connecting.qaKey, "connecting")
        XCTAssertEqual(TelemetryConnectionState.connectedNoGW2.qaKey, "connectedNoGW2")
        XCTAssertEqual(TelemetryConnectionState.connectedLive.qaKey, "connectedLive")
        XCTAssertEqual(TelemetryConnectionState.stale.qaKey, "stale")
        XCTAssertEqual(TelemetryConnectionState.reconnecting.qaKey, "reconnecting")
        XCTAssertEqual(TelemetryConnectionState.pairingInvalid.qaKey, "pairingInvalid")
        XCTAssertEqual(TelemetryConnectionState.protocolMismatch("x").qaKey, "protocolMismatch")
    }
}

final class BoundedCacheTests: XCTestCase {
    func testMemoryCacheEvictsOldestWhenOverLimit() {
        var cache = BoundedMemoryCache<String, Int>(countLimit: 2, totalCostLimit: 1_000)
        cache.set(1, for: "a")
        cache.set(2, for: "b")
        cache.set(3, for: "c")
        XCTAssertEqual(cache.count, 2)
        XCTAssertNil(cache["a"])
        XCTAssertEqual(cache["b"], 2)
        XCTAssertEqual(cache["c"], 3)
    }

    func testDiskPrunerRemovesOldestFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for index in 0..<5 {
            let url = directory.appending(path: "\(index).dat")
            try Data([UInt8(index)]).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: Double(index))], ofItemAtPath: url.path)
        }
        DiskCachePruner.prune(directory: directory, maxFiles: 2)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(remaining, ["3.dat", "4.dat"])
    }
}

final class MapCoverageAndAlignmentTests: XCTestCase {
    func testCoverageDistinguishesMissingArtworkFromMissingMetadata() {
        XCTAssertEqual(MapQADiagnostics.coverage(metadata: nil, tile: nil).reason, .mapMetadataMissing)
        let queensdale = MapAlignmentLandmarks.queensdaleMetadata
        let tile = TileIndex(zoom: 7, x: 170, y: 111)
        XCTAssertEqual(MapQADiagnostics.coverage(metadata: queensdale, tile: tile).reason, .withinKnownPaintedCoverage)
        XCTAssertTrue(MapQADiagnostics.coverage(metadata: queensdale, tile: tile).available)
        let measurement = MapAlignmentMeasurement.measure(
            player: ContinentCoordinate(x: 43_728.4, y: 28_589.9),
            landmark: MapAlignmentLandmarks.shaemoorWaypoint.continent)
        XCTAssertEqual(measurement.distance, 0, accuracy: 0.01)
        XCTAssertFalse(measurement.visuallyOverlapsSuggestion && measurement.distance > 75)
    }
}

final class SoakScenarioTests: XCTestCase {
    func testScriptIncludesDisconnectReconnectMapAndCharacterChanges() {
        let frames = SoakScenario.script(duration: 80)
        let steps = frames.map(\.step)
        XCTAssertTrue(steps.contains(.disconnect))
        XCTAssertTrue(steps.contains(.reconnect))
        XCTAssertTrue(steps.contains(.map(23)))
        XCTAssertTrue(steps.contains(.character("Soak Beta")))
        let envelope = SoakScenario.apply(
            .disconnect,
            to: TelemetryEnvelope(
                protocolVersion: 1, timestampUnixMs: 1, connected: true, uiTick: 1,
                positionAvailable: true, character: nil, map: nil, player: nil, camera: nil,
                ui: UITelemetry(inCombat: false, mapOpen: false, gameHasFocus: true),
                mount: MountTelemetry(index: 0),
                statusMessage: nil),
            tick: 2)
        XCTAssertFalse(envelope.connected)
        XCTAssertEqual(TelemetryStore.state(for: envelope), .connectedNoGW2)
    }
}

final class EarlyBetaGateTests: XCTestCase {
    func testQAToolsAreHiddenUnlessDeveloperMode() {
        XCTAssertFalse(EarlyBeta.qaToolsVisible(developerMode: false))
        XCTAssertTrue(EarlyBeta.qaToolsVisible(developerMode: true))
#if DEBUG
        XCTAssertTrue(EarlyBeta.allowsTileDebugGrid)
        XCTAssertTrue(EarlyBeta.allowsFixtureData)
#else
        XCTAssertFalse(EarlyBeta.allowsTileDebugGrid)
        XCTAssertFalse(EarlyBeta.allowsFixtureData)
#endif
    }
}

final class OptionalUiVersionDecodingTests: XCTestCase {
    func testLegacyTelemetryJSONStillDecodesWithoutUiVersion() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "telemetry.v1", withExtension: "json"))
        let value = try JSONDecoder().decode(TelemetryEnvelope.self, from: Data(contentsOf: url))
        XCTAssertNil(value.uiVersion)
        XCTAssertEqual(value.uiTick, 182_930)
    }
}
