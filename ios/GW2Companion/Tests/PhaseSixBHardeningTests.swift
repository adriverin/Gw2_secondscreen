import XCTest
@testable import GW2Companion

final class PairingHardeningTests: XCTestCase {
    func testDecodesVersionedPairingWithStableBridgeIdentity() throws {
        let json = #"{"version":1,"host":"192.168.1.42","port":38291,"token":"abcdefghijklmnopqrstuvwxyz123456","bridgeId":"0123456789abcdef"}"#
        let pairing = try BridgePairing.decodeQR(json)
        XCTAssertEqual(pairing.bridgeId, "0123456789abcdef")
        XCTAssertTrue(pairing.isValid)
    }

    func testOldPairingMigratesWithoutBridgeIdentity() throws {
        let json = #"{"version":1,"host":"gaming-pc.local","port":38291,"token":"abcdefghijklmnopqrstuvwxyz123456"}"#
        let pairing = try JSONDecoder().decode(BridgePairing.self, from: Data(json.utf8))
        XCTAssertNil(pairing.bridgeId)
        XCTAssertTrue(pairing.isValid)
    }

    func testRejectsUnsupportedAndMalformedQRPayloads() {
        let future = #"{"version":99,"host":"192.168.1.42","port":38291,"token":"abcdefghijklmnopqrstuvwxyz123456"}"#
        XCTAssertThrowsError(try BridgePairing.decodeQR(future)) { error in
            XCTAssertEqual(error as? PairingError, .unsupportedVersion(99))
        }
        for value in ["not json", #"{"version":1,"host":"https://evil.example/x","port":38291,"token":"abcdefghijklmnopqrstuvwxyz123456"}"#] {
            XCTAssertThrowsError(try BridgePairing.decodeQR(value))
        }
    }
}

final class ConnectionStateMachineTests: XCTestCase {
    func testWifiLossAndRecovery() {
        let live = telemetry(connected: true, positionAvailable: true)
        var state: TelemetryConnectionState = .connectedLive
        state = TelemetryConnectionStateMachine.transition(from: state, event: .transportLost)
        XCTAssertEqual(state, .disconnected)
        state = TelemetryConnectionStateMachine.transition(from: state, event: .retryScheduled)
        XCTAssertEqual(state, .reconnecting)
        state = TelemetryConnectionStateMachine.transition(from: state, event: .received(live))
        XCTAssertEqual(state, .connectedLive)
    }

    func testBridgeRestartAndAuthenticationFailureAreDistinct() {
        XCTAssertEqual(
            TelemetryConnectionStateMachine.transition(from: .connectedLive, event: .transportLost),
            .disconnected)
        XCTAssertEqual(
            TelemetryConnectionStateMachine.transition(from: .reconnecting, event: .authenticationRejected),
            .pairingInvalid)
        XCTAssertEqual(
            TelemetryConnectionStateMachine.transition(from: .connecting, event: .incompatibleProtocol("Update required")),
            .protocolMismatch("Update required"))
    }

    func testNoGameStaleAndUnavailableStates() {
        XCTAssertEqual(TelemetryStore.state(for: telemetry(connected: false, positionAvailable: false)), .connectedNoGW2)
        XCTAssertEqual(TelemetryStore.state(for: telemetry(connected: true, positionAvailable: false, status: "Telemetry is stale.")), .stale)
        XCTAssertEqual(
            TelemetryStore.state(for: telemetry(connected: true, positionAvailable: false, status: "Competitive map")),
            .positionUnavailable("Competitive map"))
    }

    private func telemetry(connected: Bool, positionAvailable: Bool, status: String? = nil) -> TelemetryEnvelope {
        TelemetryEnvelope(
            protocolVersion: 1, timestampUnixMs: 1, connected: connected, uiTick: 1,
            positionAvailable: positionAvailable, character: nil, map: nil, player: nil, camera: nil,
            ui: UITelemetry(inCombat: false, mapOpen: false, gameHasFocus: false),
            mount: MountTelemetry(index: 0), statusMessage: status)
    }
}

final class CacheCorruptionHardeningTests: XCTestCase {
    func testCorruptCacheIsIsolatedToOneEntry() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{broken".utf8).write(to: directory.appending(path: "broken.json"))
        let cache = MetadataDiskCache(directory: directory)
        let broken = await cache.load([Int: String].self, named: "broken")
        XCTAssertNil(broken)
        await cache.save([1: "preserved"], named: "healthy")
        let healthy = await cache.load([Int: String].self, named: "healthy")
        XCTAssertEqual(healthy, [1: "preserved"])
    }
}

final class CredentialRedactionTests: XCTestCase {
    func testPairingDescriptionsNeverExposeToken() throws {
        let token = "abcdefghijklmnopqrstuvwxyz123456"
        let pairing = BridgePairing(host: "192.168.1.42", port: 38291, token: token, bridgeId: "bridge")
        XCTAssertFalse(String(describing: pairing).contains(token), "Do not log BridgePairing values; synthesized descriptions contain secrets.")
    }
}

final class ErrorPresentationTests: XCTestCase {
    private struct TechnicalFailure: Error {}

    func testUnknownTechnicalErrorsUseSafeFallbackCopy() {
        XCTAssertEqual(
            TechnicalFailure().userFacingMessage(fallback: "Saved data is still available."),
            "Saved data is still available.")
    }

    func testKnownAPIErrorsKeepTheirUserFacingCopy() {
        XCTAssertTrue(
            GW2APIError.invalidAPIKey.userFacingMessage(fallback: "fallback").contains("invalid or has been revoked"))
    }
}

final class PersistenceMigrationTests: XCTestCase {
    func testPhaseFourGoalEnvelopeRemainsReadable() throws {
        let oldData = try JSONEncoder().encode(GoalScopeSnapshot(schemaVersion: 1, goals: []))
        let decoded = try JSONDecoder().decode(GoalScopeSnapshot.self, from: oldData)
        XCTAssertEqual(decoded.schemaVersion, GoalScopeSnapshot.schemaVersion)
        XCTAssertTrue(decoded.goals.isEmpty)
    }

    func testPhaseFiveSessionEnvelopeRemainsReadable() throws {
        let oldData = try JSONEncoder().encode(
            SessionPersistenceSnapshot(
                schemaVersion: 1, preferences: PlanningPreferences(), userMethods: [],
                activeSession: nil, history: []))
        let decoded = try JSONDecoder().decode(SessionPersistenceSnapshot.self, from: oldData)
        XCTAssertEqual(decoded.schemaVersion, SessionPersistenceSnapshot.schemaVersion)
        XCTAssertNil(decoded.activeSession)
    }
}
