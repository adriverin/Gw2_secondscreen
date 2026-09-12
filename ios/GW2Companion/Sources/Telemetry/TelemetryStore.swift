import Foundation

enum TelemetryConnectionState: Equatable {
    case unpaired
    case connecting
    case reconnecting
    case live
    case bridgeOffline
    case pairAgain
    case gameNotRunning
    case positionUnavailable(String)

    var label: String {
        switch self {
        case .unpaired: "PAIR PC"
        case .connecting: "CONNECTING…"
        case .reconnecting: "RECONNECTING…"
        case .live: "LIVE"
        case .bridgeOffline: "BRIDGE OFFLINE"
        case .pairAgain: "PAIR AGAIN"
        case .gameNotRunning: "GW2 NOT RUNNING"
        case .positionUnavailable: "POSITION UNAVAILABLE"
        }
    }
}

@MainActor
final class TelemetryStore: ObservableObject {
    @Published private(set) var latest: TelemetryEnvelope?
    @Published private(set) var state: TelemetryConnectionState = .unpaired
    @Published private(set) var isSimulating = false

    private let credentials: CredentialStore
    private var connectionTask: Task<Void, Never>?
    private var isActive = true

    init(credentials: CredentialStore = CredentialStore()) { self.credentials = credentials }

    func connectSavedPairing() {
        guard !isSimulating else { return }
        do {
            guard let pairing = try credentials.getPairing() else {
                state = .unpaired
                return
            }
            run(provider: BridgeConnection(pairing: pairing), reconnect: true)
        } catch {
            state = .unpaired
        }
    }

    func pair(_ pairing: BridgePairing) throws {
        guard pairing.isValid else { throw PairingError.invalidPayload }
        try credentials.savePairing(pairing)
        isSimulating = false
        run(provider: BridgeConnection(pairing: pairing), reconnect: true)
    }

    func forgetPairing() {
        try? credentials.deletePairing()
        connectionTask?.cancel()
        latest = nil
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
        state = .connecting
        connectionTask = Task { [weak self] in
            var backoff = 1.0
            while let self, !Task.isCancelled, self.isActive {
                do {
                    for try await telemetry in provider.telemetryStream() {
                        guard !Task.isCancelled else { return }
                        self.latest = telemetry
                        self.state = Self.state(for: telemetry)
                        backoff = 1
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    if case BridgeConnectionError.pairAgain = error {
                        self.state = .pairAgain
                        return
                    }
                    self.state = .bridgeOffline
                }
                guard reconnect else { return }
                try? await Task.sleep(for: .seconds(backoff))
                backoff = min(backoff * 2, 30)
                if !Task.isCancelled { self.state = .reconnecting }
            }
        }
    }

    static func state(for telemetry: TelemetryEnvelope) -> TelemetryConnectionState {
        guard telemetry.connected else { return .gameNotRunning }
        guard telemetry.positionAvailable else {
            return .positionUnavailable(telemetry.statusMessage ?? "Live positioning is unavailable on this map.")
        }
        return .live
    }
}
