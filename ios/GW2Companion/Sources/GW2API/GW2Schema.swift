import Foundation

/// ArenaNet schema versions used by Companion.
///
/// Production never uses `v=latest`. Schema is sent only on endpoints whose
/// documented payload shape depends on a specific version, and only as the
/// documented `?v=` query parameter. ArenaNet still accepts `X-Schema-Version`,
/// but the header can return the wrong schema version.
enum GW2Schema {
    /// Modern character build-template / equipment-tab schema.
    /// Required by `/v2/characters/:id/buildtabs` and `/equipmenttabs`.
    /// Also requested for character profile and inventory so bags, relics,
    /// and template metadata decode against the same tested shape.
    static let characterTemplates = "2019-12-19T00:00:00.000Z"

    /// Account-level endpoints (bank, materials, wallet, tokeninfo) do not
    /// need a schema pin; their documented fields are stable without it.
    static let account: String? = nil

    /// Public static metadata (recipes, items, currencies) is requested
    /// without a schema pin.
    static let publicMetadata: String? = nil

    static func version(for path: String) -> String? {
        let clean = path.split(separator: "?").first.map(String.init) ?? path
        if clean == "characters" || clean.hasPrefix("characters/") {
            return characterTemplates
        }
        return nil
    }

    /// Appends `v=<schema>` when the path needs a pin, leaving other endpoints unchanged.
    static func applyingQuery(to path: String) -> String {
        guard let version = version(for: path) else { return path }
        let query = path.split(separator: "?", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
        let alreadyPinned = query.split(separator: "&").contains { pair in
            pair == "v=\(version)" || pair.hasPrefix("v=")
        }
        if alreadyPinned { return path }
        if path.contains("?") {
            return "\(path)&v=\(version)"
        }
        return "\(path)?v=\(version)"
    }
}
