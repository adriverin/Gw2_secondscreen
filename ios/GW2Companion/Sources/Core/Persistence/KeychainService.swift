import Foundation
import Security

protocol SecureValueStore: Sendable {
    func save(_ data: Data, account: String) throws
    func read(account: String) throws -> Data?
    func delete(account: String) throws
}

struct KeychainService: SecureValueStore {
    let service: String

    init(service: String = "com.example.GW2Companion") { self.service = service }

    func save(_ data: Data, account: String) throws {
        try delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Credentials are available only while the device is unlocked and never migrate
            // to another device through a backup.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func read(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError.status(status) }
        return data
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}

enum KeychainError: Error { case status(OSStatus) }

struct CredentialStore: Sendable {
    private let secureStore: SecureValueStore
    private let apiKeyAccount = "gw2-api-key"
    private let bridgeAccount = "bridge-pairing"

    init(secureStore: SecureValueStore = KeychainService()) { self.secureStore = secureStore }

    func saveAPIKey(_ key: String) throws {
        try secureStore.save(Data(key.utf8), account: apiKeyAccount)
    }

    func getAPIKey() throws -> String? {
        guard let data = try secureStore.read(account: apiKeyAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteAPIKey() throws { try secureStore.delete(account: apiKeyAccount) }

    func savePairing(_ pairing: BridgePairing) throws {
        try secureStore.save(try JSONEncoder().encode(pairing), account: bridgeAccount)
    }

    func getPairing() throws -> BridgePairing? {
        guard let data = try secureStore.read(account: bridgeAccount) else { return nil }
        return try JSONDecoder().decode(BridgePairing.self, from: data)
    }

    func deletePairing() throws { try secureStore.delete(account: bridgeAccount) }
}
