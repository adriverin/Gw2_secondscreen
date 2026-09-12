import Foundation

struct TelemetryEnvelope: Codable, Sendable, Equatable {
    let protocolVersion: Int
    let timestampUnixMs: Int64
    let connected: Bool
    let uiTick: UInt32
    let positionAvailable: Bool
    let character: CharacterTelemetry?
    let map: MapTelemetry?
    let player: PlayerTelemetry?
    let camera: CameraTelemetry?
    let ui: UITelemetry
    let mount: MountTelemetry
    let statusMessage: String?
}

struct CharacterTelemetry: Codable, Sendable, Equatable {
    let name: String
    let profession: Int?
    let specialization: Int?
    let race: Int?
}

struct MapTelemetry: Codable, Sendable, Equatable {
    let id: Int
    let type: UInt32
    let shardId: UInt32
    let instanceId: UInt32
}

struct PlayerTelemetry: Codable, Sendable, Equatable {
    let continentX: Double
    let continentY: Double
    let avatarX: Double
    let avatarY: Double
    let avatarZ: Double
    let headingX: Double
    let headingY: Double
}

struct CameraTelemetry: Codable, Sendable, Equatable {
    let frontX: Double
    let frontY: Double
    let frontZ: Double
}

struct UITelemetry: Codable, Sendable, Equatable {
    let inCombat: Bool
    let mapOpen: Bool
    let gameHasFocus: Bool
}

struct MountTelemetry: Codable, Sendable, Equatable { let index: UInt8 }

struct BridgePairing: Codable, Sendable, Equatable {
    let version: Int
    let host: String
    let port: Int
    let token: String

    init(version: Int = 1, host: String, port: Int, token: String) {
        self.version = version
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.port = port
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        version == 1 && !host.isEmpty && (1...65_535).contains(port) && token.count >= 16
    }

    static func decodeQR(_ string: String) throws -> BridgePairing {
        guard let data = string.data(using: .utf8) else { throw PairingError.invalidPayload }
        let pairing = try JSONDecoder().decode(BridgePairing.self, from: data)
        guard pairing.isValid else { throw PairingError.invalidPayload }
        return pairing
    }
}

enum PairingError: LocalizedError {
    case invalidPayload
    var errorDescription: String? { "That QR code is not a valid GW2 Companion pairing code." }
}
