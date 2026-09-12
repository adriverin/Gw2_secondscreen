import Foundation

protocol LiveTelemetryProvider: Sendable {
    func telemetryStream() -> AsyncThrowingStream<TelemetryEnvelope, Error>
}

enum BridgeConnectionError: LocalizedError {
    case invalidEndpoint
    case closed

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "The saved PC address is invalid. Pair the bridge again."
        case .closed: "Bridge connection lost. Reconnecting…"
        }
    }
}

final class BridgeConnection: LiveTelemetryProvider, @unchecked Sendable {
    private let pairing: BridgePairing
    private let session: URLSession

    init(pairing: BridgePairing, session: URLSession = .shared) {
        self.pairing = pairing
        self.session = session
    }

    func telemetryStream() -> AsyncThrowingStream<TelemetryEnvelope, Error> {
        AsyncThrowingStream { continuation in
            guard var components = URLComponents() as URLComponents? else {
                continuation.finish(throwing: BridgeConnectionError.invalidEndpoint)
                return
            }
            components.scheme = "ws"
            components.host = pairing.host
            components.port = pairing.port
            components.path = "/telemetry"
            components.queryItems = [URLQueryItem(name: "token", value: pairing.token)]
            guard let url = components.url else {
                continuation.finish(throwing: BridgeConnectionError.invalidEndpoint)
                return
            }

            let socket = session.webSocketTask(with: url)
            socket.resume()
            let receiveTask = Task {
                do {
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        let data: Data
                        switch message {
                        case let .data(value): data = value
                        case let .string(value): data = Data(value.utf8)
                        @unknown default: continue
                        }
                        let envelope = try JSONDecoder().decode(TelemetryEnvelope.self, from: data)
                        guard envelope.protocolVersion == 1 else { continue }
                        continuation.yield(envelope)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                receiveTask.cancel()
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }
}

struct MockTelemetryProvider: LiveTelemetryProvider {
    func telemetryStream() -> AsyncThrowingStream<TelemetryEnvelope, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let clock = ContinuousClock()
                let start = clock.now
                var tick: UInt32 = 0
                while !Task.isCancelled {
                    let seconds = Double(start.duration(to: clock.now).components.attoseconds) / 1e18 +
                        Double(start.duration(to: clock.now).components.seconds)
                    let angle = seconds * 0.14
                    tick &+= 1
                    continuation.yield(TelemetryEnvelope(
                        protocolVersion: 1,
                        timestampUnixMs: Int64(Date().timeIntervalSince1970 * 1_000),
                        connected: true,
                        uiTick: tick,
                        positionAvailable: true,
                        character: CharacterTelemetry(name: "Test Mesmer", profession: 8, specialization: 0, race: 0),
                        map: MapTelemetry(id: 15, type: 5, shardId: 1, instanceId: 1),
                        player: PlayerTelemetry(
                            continentX: 15_710 + cos(angle) * 520,
                            continentY: 13_370 + sin(angle) * 330,
                            avatarX: 0, avatarY: 0, avatarZ: 0,
                            headingX: -sin(angle), headingY: cos(angle)),
                        camera: CameraTelemetry(frontX: -sin(angle), frontY: 0, frontZ: -cos(angle)),
                        ui: UITelemetry(inCombat: false, mapOpen: false, gameHasFocus: true),
                        mount: MountTelemetry(index: 0),
                        statusMessage: nil))
                    try await Task.sleep(for: .milliseconds(67))
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
