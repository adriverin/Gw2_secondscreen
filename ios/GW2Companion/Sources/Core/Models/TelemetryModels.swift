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
    var uiVersion: UInt32? = nil
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

struct BridgePairing: Codable, Sendable, Equatable, CustomStringConvertible {
    let version: Int
    let host: String
    let port: Int
    let token: String
    let bridgeId: String?

    init(version: Int = 1, host: String, port: Int, token: String, bridgeId: String? = nil) {
        self.version = version
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.port = port
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bridgeId = bridgeId?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        version == BridgeProtocol.current && Self.isValidHost(host) &&
            (1...65_535).contains(port) && token.count >= 32 &&
            token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    var description: String {
        "BridgePairing(version: \(version), host: \(host), port: \(port), bridgeId: \(bridgeId ?? "legacy"), token: [REDACTED])"
    }

    static func decodeQR(_ string: String) throws -> BridgePairing {
        guard let data = string.data(using: .utf8), data.count <= 4_096 else { throw PairingError.invalidPayload }
        let pairing: BridgePairing
        do { pairing = try JSONDecoder().decode(BridgePairing.self, from: data) }
        catch { throw PairingError.invalidPayload }
        guard pairing.version == BridgeProtocol.current else {
            throw PairingError.unsupportedVersion(pairing.version)
        }
        guard Self.isValidHost(pairing.host) else { throw PairingError.invalidHost }
        guard (1...65_535).contains(pairing.port) else { throw PairingError.invalidPort }
        guard pairing.token.count >= 32 else { throw PairingError.invalidToken }
        return pairing
    }

    private static func isValidHost(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 253, !value.contains("://"), !value.contains("/"),
              !value.contains("?"), !value.contains("#"), !value.contains(" ") else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || ".:-_".unicodeScalars.contains($0)
        }
    }
}

enum BridgeProtocol {
    static let current = 1
}

enum PairingError: LocalizedError, Equatable {
    case invalidPayload
    case unsupportedVersion(Int)
    case invalidHost
    case invalidPort
    case invalidToken

    var errorDescription: String? {
        switch self {
        case .invalidPayload: "That QR code is not a GW2 Companion Bridge pairing code."
        case .unsupportedVersion: "This QR code uses an unsupported bridge version. Update the bridge and try again."
        case .invalidHost: "The pairing code does not contain a valid PC address."
        case .invalidPort: "The pairing code does not contain a valid network port."
        case .invalidToken: "This pairing code is incomplete or expired. Regenerate it on the PC and try again."
        }
    }
}
