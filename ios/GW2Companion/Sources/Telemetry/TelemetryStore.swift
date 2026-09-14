import Foundation

enum TelemetryConnectionState: Equatable {
    case unpaired
    case disconnected
    case connecting
    case reconnecting
    case connectedLive
    case connectedNoGW2
    case stale
    case pairingInvalid
    case protocolMismatch(String)
    case positionUnavailable(String)

    var label: String {
        switch self {
        case .unpaired: "PAIR PC"
        case .disconnected: "PC UNREACHABLE"
        case .connecting: "CONNECTING…"
        case .reconnecting: "RECONNECTING…"
        case .connectedLive: "LIVE"
        case .connectedNoGW2: "GW2 NOT RUNNING"
        case .stale: "TELEMETRY STALE"
        case .pairingInvalid: "PAIR AGAIN"
        case .protocolMismatch: "UPDATE REQUIRED"
        case .positionUnavailable: "POSITION UNAVAILABLE"
        }
    }
}

enum TelemetryConnectionEvent: Equatable {
    case startConnecting
    case transportLost
    case retryScheduled
    case received(TelemetryEnvelope)
    case authenticationRejected
    case incompatibleProtocol(String)
    case forgetPairing
}

enum TelemetryConnectionStateMachine {
    static func transition(from state: TelemetryConnectionState, event: TelemetryConnectionEvent) -> TelemetryConnectionState {
        switch event {
        case .startConnecting: .connecting
        case .transportLost: .disconnected
        case .retryScheduled: .reconnecting
        case let .received(envelope): TelemetryStore.state(for: envelope)
        case .authenticationRejected: .pairingInvalid
        case let .incompatibleProtocol(message): .protocolMismatch(message)
        case .forgetPairing: .unpaired
        }
    }
}

@MainActor
final class TelemetryStore: ObservableObject {
    @Published private(set) var latest: TelemetryEnvelope?
    @Published private(set) var state: TelemetryConnectionState = .unpaired
    @Published private(set) var isSimulating = false
    @Published private(set) var savedPairing: BridgePairing?
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var packetsPerSecond = 0

    private let credentials: CredentialStore
    private var connectionTask: Task<Void, Never>?
    private var isActive = true
    private var packetTimes: [Date] = []

    init(credentials: CredentialStore = CredentialStore()) { self.credentials = credentials }

    func connectSavedPairing() {
        guard !isSimulating else { return }
        do {
            guard let pairing = try credentials.getPairing() else {
                state = .unpaired
                return
            }
            savedPairing = pairing
            run(provider: BridgeConnection(pairing: pairing), reconnect: true)
        } catch {
            state = .unpaired
        }
    }

    func pair(_ pairing: BridgePairing) throws {
        guard pairing.isValid else { throw PairingError.invalidPayload }
        try credentials.savePairing(pairing)
        savedPairing = pairing
        isSimulating = false
        run(provider: BridgeConnection(pairing: pairing), reconnect: true)
    }

    func forgetPairing() {
        try? credentials.deletePairing()
        connectionTask?.cancel()
        latest = nil
        savedPairing = nil
        lastUpdate = nil
        packetsPerSecond = 0
        isSimulating = false
        state = .unpaired
    }

    func startSimulation() {
        isSimulating = true
        run(provider: MockTelemetryProvider(), reconnect: false)
    }

    func stopSimulation() {
        isSimulating = false
        connectionTask?.cancel()
        latest = nil
        connectSavedPairing()
    }

    func setAppActive(_ active: Bool) {
        isActive = active
        if active {
            if isSimulating { run(provider: MockTelemetryProvider(), reconnect: false) }
            else { connectSavedPairing() }
        } else {
            connectionTask?.cancel()
        }
    }

    private func run(provider: some LiveTelemetryProvider, reconnect: Bool) {
        connectionTask?.cancel()
        state = TelemetryConnectionStateMachine.transition(from: state, event: .startConnecting)
        connectionTask = Task { [weak self] in
            var backoff = 1.0
            while let self, !Task.isCancelled, self.isActive {
                do {
                    for try await telemetry in provider.telemetryStream() {
                        guard !Task.isCancelled else { return }
                        self.latest = telemetry
                        self.state = TelemetryConnectionStateMachine.transition(from: self.state, event: .received(telemetry))
                        self.recordPacket()
                        backoff = 1
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    if case BridgeConnectionError.pairAgain = error {
                        self.state = TelemetryConnectionStateMachine.transition(from: self.state, event: .authenticationRejected)
                        return
                    }
                    if let bridgeError = error as? BridgeConnectionError,
                       bridgeError == .bridgeTooOld || bridgeError == .appTooOld || bridgeError == .differentBridge {
                        self.state = TelemetryConnectionStateMachine.transition(
                            from: self.state,
                            event: .incompatibleProtocol(bridgeError.errorDescription ?? "The app and bridge are incompatible."))
                        return
                    }
                    self.state = TelemetryConnectionStateMachine.transition(from: self.state, event: .transportLost)
                }
                guard reconnect else { return }
                try? await Task.sleep(for: .seconds(backoff))
                backoff = min(backoff * 2, 30)
                if !Task.isCancelled {
                    self.state = TelemetryConnectionStateMachine.transition(from: self.state, event: .retryScheduled)
                }
            }
        }
    }

    nonisolated static func state(for telemetry: TelemetryEnvelope) -> TelemetryConnectionState {
        guard telemetry.connected else { return .connectedNoGW2 }
        if telemetry.statusMessage == "Telemetry is stale." { return .stale }
        guard telemetry.positionAvailable else {
            return .positionUnavailable(telemetry.statusMessage ?? "Live positioning is unavailable on this map.")
        }
        return .connectedLive
    }

    private func recordPacket(now: Date = Date()) {
        lastUpdate = now
        packetTimes.append(now)
        packetTimes.removeAll { now.timeIntervalSince($0) > 1 }
        packetsPerSecond = packetTimes.count
    }
}
