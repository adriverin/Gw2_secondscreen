import Foundation

enum AccountLoadDomain: String, CaseIterable, Identifiable, Sendable {
    case account
    case characters
    case characterInventory
    case bank
    case materials
    case sharedInventory
    case equipment
    case equipmentTabs
    case buildTabs
    case wallet
    case achievements
    case today
    case recipesUnlocked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: "Account"
        case .characters: "Characters"
        case .characterInventory: "Character Inventory"
        case .bank: "Bank"
        case .materials: "Materials"
        case .sharedInventory: "Shared Inventory"
        case .equipment: "Equipment"
        case .equipmentTabs: "Equipment Tabs"
        case .buildTabs: "Build Tabs"
        case .wallet: "Wallet"
        case .achievements: "Achievements"
        case .today: "Today"
        case .recipesUnlocked: "Recipes unlocked"
        }
    }

    var requiredPermissions: [AccountPermission] {
        switch self {
        case .account: [.account]
        case .characters: [.account, .characters]
        case .characterInventory: [.account, .characters, .inventories]
        case .bank, .materials, .sharedInventory: [.account, .inventories]
        case .equipment, .equipmentTabs: [.account, .characters]
        case .buildTabs: [.account, .characters, .builds]
        case .wallet: [.account, .wallet]
        case .achievements, .today: [.account, .progression]
        case .recipesUnlocked: [.account, .unlocks]
        }
    }
}

enum AccountDomainPhase: String, Codable, Sendable {
    case idle
    case loading
    case live
    case cached
    case failed
    case missingPermission
}

struct AccountDomainStatus: Equatable, Sendable, Identifiable {
    var id: AccountLoadDomain { domain }
    var domain: AccountLoadDomain
    var phase: AccountDomainPhase
    var endpoint: String?
    var httpStatus: Int?
    var schemaVersion: String?
    var source: AccountDataSource
    var decodeSucceeded: Bool?
    var decodePath: String?
    var message: String?
    var updatedAt: Date?

    static func idle(_ domain: AccountLoadDomain) -> AccountDomainStatus {
        AccountDomainStatus(
            domain: domain, phase: .idle, endpoint: nil, httpStatus: nil, schemaVersion: nil,
            source: .unknown, decodeSucceeded: nil, decodePath: nil, message: nil, updatedAt: nil)
    }

    var qaSummary: String {
        let code = httpStatus.map(String.init) ?? "—"
        let schema = schemaVersion ?? "none"
        let live = source == .cached ? "cache" : "live"
        let decode = decodeSucceeded == false ? "decode failed \(decodePath ?? "")" : "decode ok"
        return "\(domain.title) \(endpoint ?? "") \(code) schema \(schema) \(live) \(decode) \(message ?? "")"
    }

    var diagnosticsBlock: String {
        """
        Domain: \(domain.title)
        Endpoint: \(endpoint ?? "—")
        HTTP status: \(httpStatus.map(String.init) ?? "—")
        Schema version requested: \(schemaVersion ?? "none")
        Live vs cache: \(source == .cached ? "cache" : "live")
        Response timestamp: \(updatedAt?.formatted(date: .abbreviated, time: .standard) ?? "—")
        Decode: \(decodeSucceeded == false ? "failure" : "success")
        Decode error coding path: \(decodePath ?? "—")
        Safe error description: \(message ?? "—")
        """
    }
}

enum WalletPresentation {
    static let pinnedIDs = [1, 4, 2, 3, 23, 63]

    static func ordered(
        wallet: [WalletEntry], currencies: [Int: CurrencyMetadata], query: String
    ) -> [WalletEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = wallet.filter { entry in
            guard !needle.isEmpty else { return true }
            let name = currencies[entry.id]?.name ?? "Currency \(entry.id)"
            let description = currencies[entry.id]?.description ?? ""
            return name.localizedCaseInsensitiveContains(needle)
                || description.localizedCaseInsensitiveContains(needle)
                || String(entry.id) == needle
        }
        return filtered.sorted { lhs, rhs in
            let left = currencies[lhs.id]?.order ?? lhs.id
            let right = currencies[rhs.id]?.order ?? rhs.id
            if left != right { return left < right }
            return lhs.id < rhs.id
        }
    }

    static func pinned(
        wallet: [WalletEntry], currencies: [Int: CurrencyMetadata]
    ) -> [WalletEntry] {
        pinnedIDs.compactMap { id in wallet.first(where: { $0.id == id }) }
            .filter { currencies[$0.id] != nil || true }
    }
}

enum GatheringCoverageCopy {
    static func layerMessage(availability: GatheringStore.Availability, mapName: String?) -> String? {
        switch availability {
        case .unavailable:
            let place = mapName.map { "\($0): " } ?? ""
            return "\(place)No Companion gathering dataset yet"
        case .failed:
            return "Gathering coverage unavailable"
        case .available(0):
            return "Companion gathering dataset is empty for this map"
        default:
            return nil
        }
    }

    static func banner(availability: GatheringStore.Availability) -> String? {
        switch availability {
        case .unavailable: "Gathering coverage unavailable"
        case .failed: "Gathering locations could not be loaded."
        case .available(0): "Companion gathering dataset is empty for this map"
        default: nil
        }
    }

    static func coverageTitle(availability: GatheringStore.Availability) -> String {
        switch availability {
        case .available(let count) where count > 0: "Partial coverage"
        case .available: "Dataset present, no markers"
        case .unavailable: "No Companion gathering dataset yet"
        case .failed: "Coverage unavailable"
        case .idle, .loading: "Checking coverage"
        }
    }
}
