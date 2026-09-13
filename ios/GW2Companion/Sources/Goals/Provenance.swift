import Foundation

/// Describes where a fact came from. Provenance is data, not presentation, so it can
/// travel with calculations and survive persistence.
enum DataProvenance: String, Codable, CaseIterable, Sendable, Identifiable {
    case arenaNetAccount
    case arenaNetPublic
    case liveTelemetry
    case companionObserved
    case userDeclared
    case derived

    var id: Self { self }

    var title: String {
        switch self {
        case .arenaNetAccount: "ArenaNet account"
        case .arenaNetPublic: "ArenaNet public data"
        case .liveTelemetry: "Live telemetry"
        case .companionObserved: "Companion observed"
        case .userDeclared: "User declared"
        case .derived: "Derived calculation"
        }
    }
}

struct ProvenanceDependency: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let label: String
    let detail: String
    let provenance: DataProvenance
    let observedAt: Date?

    init(
        id: UUID = UUID(), label: String, detail: String,
        provenance: DataProvenance, observedAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.detail = detail
        self.provenance = provenance
        self.observedAt = observedAt
    }
}

struct ExplainableValue<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    let value: Value
    let provenance: DataProvenance
    let dependencies: [ProvenanceDependency]
    let calculatedAt: Date
}
