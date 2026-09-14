import Foundation

protocol LiveTelemetryProvider: Sendable {
    func telemetryStream() -> AsyncThrowingStream<TelemetryEnvelope, Error>
}

enum TelemetryStreamBuffer {
    static func latest(
        _ build: (AsyncThrowingStream<TelemetryEnvelope, Error>.Continuation) -> Void
    ) -> AsyncThrowingStream<TelemetryEnvelope, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1), build)
    }
}

protocol BridgeWebSocket: Sendable {
    func resume()
    func receive() async throws -> URLSessionWebSocketTask.Message
    func close()
}

extension URLSessionWebSocketTask: BridgeWebSocket {
    func close() {
        cancel(with: .goingAway, reason: nil)
    }
}

enum BridgeConnectionError: LocalizedError, Equatable {
    case invalidEndpoint
    case closed
    case pairAgain
    case stalled
    case bridgeTooOld
    case appTooOld
    case differentBridge

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "The saved PC address is invalid. Pair the bridge again."
        case .closed: "Bridge connection lost. Reconnecting…"
        case .pairAgain: "The bridge pairing changed. Scan its QR code again."
        case .stalled: "The bridge stopped sending telemetry. Reconnecting…"
        case .bridgeTooOld: "Your PC bridge is too old. Update GW2 Companion Bridge."
        case .appTooOld: "This PC bridge requires a newer version of the iPhone app."
        case .differentBridge: "This address belongs to a different PC bridge. Scan its QR code to connect."
        }
    }
}

private struct BridgeHello: Decodable {
    let protocolVersion: Int
    let bridgeId: String?
}

final class BridgeConnection: LiveTelemetryProvider, @unchecked Sendable {
    private let pairing: BridgePairing
    private let session: URLSession
    private let socketFactory: @Sendable (URL) -> any BridgeWebSocket

    init(pairing: BridgePairing,
         session: URLSession = .shared,
         socketFactory: (@Sendable (URL) -> any BridgeWebSocket)? = nil) {
        self.pairing = pairing
        self.session = session
        self.socketFactory = socketFactory ?? { session.webSocketTask(with: $0) }
    }

    func telemetryStream() -> AsyncThrowingStream<TelemetryEnvelope, Error> {
        TelemetryStreamBuffer.latest { continuation in
            let connectionTask = Task {
                do {
                    try await validatePairing()
                    let socket = try makeSocket()
                    socket.resume()
                    defer { socket.close() }
                    while !Task.isCancelled {
                        let message = try await receiveNext(from: socket)
                        let data: Data
                        switch message {
                        case let .data(value): data = value
                        case let .string(value): data = Data(value.utf8)
                        @unknown default: continue
                        }
                        let envelope = try JSONDecoder().decode(TelemetryEnvelope.self, from: data)
                        guard envelope.protocolVersion == BridgeProtocol.current else {
                            throw envelope.protocolVersion < BridgeProtocol.current
                                ? BridgeConnectionError.bridgeTooOld : BridgeConnectionError.appTooOld
                        }
                        continuation.yield(envelope)
                    }
                    continuation.finish()
                } catch {
                    guard !Task.isCancelled else {
                        continuation.finish()
                        return
                    }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                connectionTask.cancel()
            }
        }
    }

    private func validatePairing() async throws {
        guard let url = endpoint(scheme: "http", path: "/pairing/validate") else {
            throw BridgeConnectionError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("Bearer \(pairing.token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BridgeConnectionError.closed }
        if http.statusCode == 401 { throw BridgeConnectionError.pairAgain }
        guard (200..<300).contains(http.statusCode) else { throw BridgeConnectionError.closed }
        // A 204 response is accepted for compatibility with the original v1 bridge.
        guard !data.isEmpty else { return }
        let hello = try JSONDecoder().decode(BridgeHello.self, from: data)
        guard hello.protocolVersion == BridgeProtocol.current else {
            throw hello.protocolVersion < BridgeProtocol.current ? BridgeConnectionError.bridgeTooOld : BridgeConnectionError.appTooOld
        }
        if let expected = pairing.bridgeId, let actual = hello.bridgeId, expected != actual {
            throw BridgeConnectionError.differentBridge
        }
    }

    private func makeSocket() throws -> any BridgeWebSocket {
        guard var components = endpointComponents(scheme: "ws", path: "/telemetry") else {
            throw BridgeConnectionError.invalidEndpoint
        }
        components.queryItems = [URLQueryItem(name: "token", value: pairing.token)]
        guard let url = components.url else { throw BridgeConnectionError.invalidEndpoint }
        return socketFactory(url)
    }

    private func endpoint(scheme: String, path: String) -> URL? {
        endpointComponents(scheme: scheme, path: path)?.url
    }

    private func endpointComponents(scheme: String, path: String) -> URLComponents? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = pairing.host
        components.port = pairing.port
        components.path = path
        return components
    }

    private func receiveNext(from socket: any BridgeWebSocket) async throws -> URLSessionWebSocketTask.Message {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask { try await socket.receive() }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw BridgeConnectionError.stalled
            }
            guard let first = try await group.next() else { throw BridgeConnectionError.closed }
            group.cancelAll()
            return first
        }
    }
}

struct MockTelemetryProvider: LiveTelemetryProvider {
    func telemetryStream() -> AsyncThrowingStream<TelemetryEnvelope, Error> {
        TelemetryStreamBuffer.latest { continuation in
            let task = Task {
                let clock = ContinuousClock()
                let start = clock.now
                var tick: UInt32 = 0
                while !Task.isCancelled {
                    let seconds = Double(start.duration(to: clock.now).components.attoseconds) / 1e18 +
                        Double(start.duration(to: clock.now).components.seconds)
                    // Start opposite the acceptance-test hero challenge, then approach it after ~22 seconds.
                    let angle = seconds * 0.14 - .pi
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
                            continentX: 44_615.5 + cos(angle) * 520,
                            continentY: 29_863.7 + sin(angle) * 330,
                            avatarX: 0, avatarY: 0, avatarZ: 0,
                            headingX: -sin(angle), headingY: cos(angle)),
                        camera: CameraTelemetry(frontX: -sin(angle), frontY: 0, frontZ: -cos(angle)),
                        ui: UITelemetry(inCombat: false, mapOpen: false, gameHasFocus: true),
                        mount: MountTelemetry(index: 0),
                        statusMessage: nil))
                    try await Task.sleep(for: .milliseconds(50))
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
