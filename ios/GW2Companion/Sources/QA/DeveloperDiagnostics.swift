import Foundation
import Network

enum QALogLimits {
    static let eventLimit = 200
    static let transitionLimit = 20
}

@MainActor
final class DeveloperDiagnostics: ObservableObject {
    static let shared = DeveloperDiagnostics()
    static let eventLimit = QALogLimits.eventLimit
    static let transitionLimit = QALogLimits.transitionLimit
    static let eventsKey = "qa.eventlog.v1"
    static let transitionsKey = "qa.connection.transitions.v1"

    @Published private(set) var events: [DeveloperEvent]
    @Published private(set) var transitions: [ConnectionTransition]
    @Published private(set) var apiDomains: [String: APIDomainStatus] = [:]
    @Published private(set) var domainRefresh: [QADomain: QADomainRefreshResult] = [:]
    @Published var mapSnapshot = MapQADiagnosticsSnapshot()
    @Published private(set) var todayFirstVaultMs: Int?
    @Published private(set) var todayScreenAppearedAt: Date?
    private var networkSatisfied: Bool?

    private let defaults: UserDefaults
    private var pathMonitor: NWPathMonitor?

    let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    init(defaults: UserDefaults = .standard, restore: Bool = true) {
        self.defaults = defaults
        if restore, let data = defaults.data(forKey: Self.eventsKey),
           let decoded = try? JSONDecoder().decode([DeveloperEvent].self, from: data) {
            events = Array(decoded.suffix(Self.eventLimit))
        } else {
            events = []
        }
        if restore, let data = defaults.data(forKey: Self.transitionsKey),
           let decoded = try? JSONDecoder().decode([ConnectionTransition].self, from: data) {
            transitions = Array(decoded.suffix(Self.transitionLimit))
        } else {
            transitions = []
        }
    }

    func record(_ message: String, at date: Date = Date(), secrets: QARedactionSecrets = .empty) {
        let scrubbed = QARedaction.scrub(message, secrets: secrets)
        events.append(DeveloperEvent(at: date, message: scrubbed))
        if events.count > Self.eventLimit {
            events = Array(events.suffix(Self.eventLimit))
        }
        persistEvents()
    }

    func recordConnection(from: TelemetryConnectionState, to: TelemetryConnectionState, at date: Date = Date()) {
        let transition = ConnectionTransition(at: date, from: from.qaKey, to: to.qaKey)
        transitions.append(transition)
        if transitions.count > Self.transitionLimit {
            transitions = Array(transitions.suffix(Self.transitionLimit))
        }
        persistTransitions()
        record(Self.eventMessage(for: to), at: date)
    }

    func recordAPICall(
        path: String, statusCode: Int?, error: String?, usedCache: Bool = false, at date: Date = Date(),
        schemaVersion: String? = nil, decodeSucceeded: Bool? = nil, decodePath: String? = nil
    ) {
        let domain = Self.domain(for: path)
        let message: String
        if let error, !error.isEmpty {
            message = error
        } else if let statusCode {
            message = Self.message(for: statusCode, domain: domain)
        } else {
            message = "Unknown"
        }
        let status = APIDomainStatus(
            domain: domain, endpoint: path, httpStatus: statusCode, schemaVersion: schemaVersion,
            message: message, usedCache: usedCache, updatedAt: date,
            decodeSucceeded: decodeSucceeded, decodePath: decodePath,
            source: usedCache ? "cache" : "live")
        apiDomains[domain] = status
        if statusCode == 429 {
            record("ArenaNet request rate-limited (HTTP 429)", at: date)
        }
        if decodeSucceeded == false {
            record("Decode failed for \(domain) \(path): \(decodePath ?? message)", at: date)
        }
    }

    func recordDomainRefresh(_ result: QADomainRefreshResult) {
        domainRefresh[result.domain] = result
        recordAPICall(
            path: result.domain.rawValue,
            statusCode: result.httpStatus,
            error: result.success ? nil : result.message,
            usedCache: result.usedCache,
            at: result.timestamp)
    }

    func recordTodayScreenAppeared(at date: Date = Date()) {
        todayScreenAppearedAt = date
        record("Today screen appeared", at: date)
    }

    func recordTodayFirstVault(at date: Date = Date()) {
        guard todayFirstVaultMs == nil else { return }
        if let start = todayScreenAppearedAt {
            todayFirstVaultMs = Int(date.timeIntervalSince(start) * 1_000)
            record("Today first Vault data published in \(todayFirstVaultMs ?? 0) ms", at: date)
        } else {
            record("Today first Vault data published", at: date)
        }
    }

    func recordCachedToday() {
        record("Using cached Today data")
        recordAPICall(path: "today", statusCode: nil, error: "Using cached Today data", usedCache: true)
    }

    func clearEvents() {
        events = []
        persistEvents()
    }

    func clearTransitions() {
        transitions = []
        persistTransitions()
    }

    func reset() {
        clearEvents()
        clearTransitions()
        apiDomains = [:]
        domainRefresh = [:]
        todayFirstVaultMs = nil
        todayScreenAppearedAt = nil
    }

    func startNetworkMonitor() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let satisfied = path.status == .satisfied
                let previous = self.networkSatisfied
                self.networkSatisfied = satisfied
                guard previous != satisfied else { return }
                if satisfied {
                    self.record(path.usesInterfaceType(.wifi) ? "Network available (Wi-Fi)" : "Network available")
                } else {
                    self.record("Wi-Fi unavailable")
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "gw2.qa.path"))
    }

    var copiedEventLog: String {
        events.map { $0.line(formatter: timeFormatter) }.joined(separator: "\n")
    }

    nonisolated static func domain(for path: String) -> String {
        let clean = QARedaction.apiPath(path).split(separator: "?").first.map(String.init) ?? path
        if clean.hasPrefix("tokeninfo") { return "apiKey" }
        if clean.hasPrefix("account/bank") { return AccountLoadDomain.bank.title }
        if clean.hasPrefix("account/materials") { return AccountLoadDomain.materials.title }
        if clean.hasPrefix("account/inventory") { return AccountLoadDomain.sharedInventory.title }
        if clean.hasPrefix("account/wallet") { return AccountLoadDomain.wallet.title }
        if clean.hasPrefix("account/recipes") { return AccountLoadDomain.recipesUnlocked.title }
        if clean.contains("/inventory") { return AccountLoadDomain.characterInventory.title }
        if clean.contains("equipmenttabs") { return AccountLoadDomain.equipmentTabs.title }
        if clean.contains("buildtabs") { return AccountLoadDomain.buildTabs.title }
        if clean.contains("/equipment") { return AccountLoadDomain.equipment.title }
        if clean.contains("achievement") || clean.hasPrefix("account/achievements") {
            return AccountLoadDomain.achievements.title
        }
        if clean.contains("wizardsvault") || clean.contains("worldboss") || clean.contains("mapchest")
            || clean.contains("dailycrafting") || clean.hasPrefix("raids") || clean.hasPrefix("dungeons")
            || clean.hasPrefix("account/raids") || clean.hasPrefix("account/dungeons") {
            return AccountLoadDomain.today.title
        }
        if clean.hasPrefix("characters") { return AccountLoadDomain.characters.title }
        if clean.hasPrefix("account") { return AccountLoadDomain.account.title }
        return clean.split(separator: "/").first.map(String.init) ?? "other"
    }

    static func eventMessage(for state: TelemetryConnectionState) -> String {
        switch state {
        case .unpaired: "Bridge unpaired"
        case .disconnected: "Bridge disconnected"
        case .connecting: "Connecting"
        case .reconnecting: "Reconnecting"
        case .connectedLive: "GW2 telemetry live"
        case .connectedNoGW2: "GW2 not running"
        case .stale: "Telemetry stale"
        case .pairingInvalid: "Pairing invalid"
        case .protocolMismatch: "Protocol mismatch"
        case .positionUnavailable: "Position unavailable"
        }
    }

    private static func message(for status: Int, domain: String) -> String {
        switch status {
        case 200, 206: "OK"
        case 403: "HTTP 403"
        case 401: "API key invalid"
        case 429: "HTTP 429"
        default: HTTPURLResponse.localizedString(forStatusCode: status)
        }
    }

    private func persistEvents() {
        defaults.set(try? JSONEncoder().encode(events), forKey: Self.eventsKey)
    }

    private func persistTransitions() {
        defaults.set(try? JSONEncoder().encode(transitions), forKey: Self.transitionsKey)
    }
}

extension TelemetryConnectionState {
    var qaKey: String {
        switch self {
        case .unpaired: "unpaired"
        case .disconnected: "disconnected"
        case .connecting: "connecting"
        case .reconnecting: "reconnecting"
        case .connectedLive: "connectedLive"
        case .connectedNoGW2: "connectedNoGW2"
        case .stale: "stale"
        case .pairingInvalid: "pairingInvalid"
        case .protocolMismatch: "protocolMismatch"
        case .positionUnavailable: "positionUnavailable"
        }
    }
}
