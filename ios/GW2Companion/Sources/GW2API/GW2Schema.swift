import Foundation

/// ArenaNet schema versions used by Companion.
///
/// Production never uses `v=latest`. Schema is sent only on endpoints whose
/// documented payload shape depends on a specific version.
enum GW2Schema {
    /// Modern character build-template / equipment-tab schema.
    /// Required by `/v2/characters/:id/buildtabs` and `/equipmenttabs`.
    /// Also requested for character profile and inventory so bags, relics,
    /// and template metadata decode against the same tested shape.
    static let characterTemplates = "2019-12-19T00:00:00.000Z"

    /// Account-level endpoints (bank, materials, wallet, tokeninfo) do not
    /// need a schema header; their documented fields are stable without it.
    static let account: String? = nil

    /// Public static metadata (recipes, items, currencies) is requested
    /// without a schema header.
    static let publicMetadata: String? = nil

    static func version(for path: String) -> String? {
        let clean = path.split(separator: "?").first.map(String.init) ?? path
        if clean == "characters" || clean.hasPrefix("characters/") {
            return characterTemplates
        }
        return nil
    }

    static func headerValue(for path: String) -> String? { version(for: path) }
}
