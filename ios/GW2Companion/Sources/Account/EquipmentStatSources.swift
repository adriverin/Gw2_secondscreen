import Foundation

enum EquipmentStatSourceState: String, Equatable, Sendable {
    case used = "USED"
    case ignored = "IGNORED"
    case fallback = "FALLBACK"
    case unresolved = "Requires ArenaNet metadata refresh"
}

struct EquipmentStatSource: Equatable, Sendable, Identifiable {
    let label: String
    let state: EquipmentStatSourceState
    let attributes: [String: Int]
    let value: Int?
    let explanation: String
    var id: String { label }
}

struct EquipmentStatAuditEntry: Equatable, Sendable, Identifiable {
    let equipment: CharacterEquipment
    let itemName: String
    let included: Bool
    let exclusionReason: String?
    let sources: [EquipmentStatSource]
    var id: String { equipment.id }
    var baseAttributes: [String: Int] {
        sources.first { $0.label == "Selected equipment stats" && $0.state == .used }?.attributes
            ?? sources.first { $0.label == "Item infix attributes" && $0.state == .fallback }?.attributes ?? [:]
    }
    var defense: Int {
        sources.first { $0.label == "Defense" && $0.state == .used }?.value ?? 0
    }
}

enum EquipmentStatInputResolver {
    static let terrestrialArmorSlots = Set(["Helm", "Shoulders", "Coat", "Gloves", "Leggings", "Boots"])
    static let terrestrialSlots = terrestrialArmorSlots.union([
        "WeaponA1", "WeaponA2", "Backpack", "Accessory1", "Accessory2", "Amulet", "Ring1", "Ring2", "Relic"
    ])

    static func ignoredReason(_ equipment: CharacterEquipment, weaponSet: String) -> String? {
        if equipment.slot == "HelmAquatic" || equipment.slot.hasPrefix("WeaponAquatic") {
            return "Aquatic equipment is inactive in terrestrial context"
        }
        if equipment.slot.hasPrefix("WeaponA") || equipment.slot.hasPrefix("WeaponB") {
            if !equipment.slot.hasPrefix("Weapon\(weaponSet)") { return "Alternate terrestrial weapon set" }
        } else if !terrestrialSlots.contains(equipment.slot) {
            return "Not a terrestrial stat equipment slot"
        }
        // Explicitly selected inactive templates may say Armory; their slotted
        // records still belong to that template. Unslotted armory copies do not.
        return nil
    }

    static func audit(
        equipment: [CharacterEquipment], items: [Int: ItemMetadata], itemStats: [Int: ItemStatMetadata] = [:],
        weaponSet: String = "A"
    ) -> [EquipmentStatAuditEntry] {
        var seenSlots = Set<String>()
        return equipment.map { equipped in
            let item = items[equipped.itemID]
            let reason = ignoredReason(equipped, weaponSet: weaponSet)
                ?? (seenSlots.insert(equipped.slot).inserted ? nil : "Duplicate slot record")
            let included = reason == nil
            let accountAttributes = equipped.stats?.attributes ?? [:]
            let selectedID = equipped.stats?.id
            let reconstructed: [String: Int] = {
                guard accountAttributes.isEmpty, let selectedID, let details = item?.details else { return [:] }
                // An exact prefix match is safe even when itemstats is unavailable.
                if details.infixUpgrade?.id == selectedID, let attributes = details.infixUpgrade?.attributes, !attributes.isEmpty {
                    return Dictionary(attributes.map { ($0.attribute, $0.modifier) }, uniquingKeysWith: +)
                }
                guard let choices = details.statChoices, choices.contains(selectedID),
                      let adjustment = details.attributeAdjustment, let prefix = itemStats[selectedID]
                else { return [:] }
                return prefix.attributes(adjustment: adjustment) ?? [:]
            }()
            let selected = accountAttributes.isEmpty ? reconstructed : accountAttributes
            let infix = Dictionary(
                (item?.details?.infixUpgrade?.attributes ?? []).map { ($0.attribute, $0.modifier) },
                uniquingKeysWith: +)
            let selectable = equipped.stats?.id != nil || !(item?.details?.statChoices?.isEmpty ?? true)
            let selectedState: EquipmentStatSourceState = !included || (selected.isEmpty && !selectable && !infix.isEmpty)
                ? .ignored : !selected.isEmpty ? .used : .unresolved
            let infixState: EquipmentStatSourceState = !included || !selected.isEmpty
                ? .ignored : selectable || infix.isEmpty ? .unresolved : .fallback
            let wantsDefense = terrestrialArmorSlots.contains(equipped.slot) || item?.details?.type == "Shield"
                || (equipped.slot.hasPrefix("Weapon") && item?.details == nil)
            let defenseState: EquipmentStatSourceState = !included || !wantsDefense
                ? .ignored : item?.details?.defense == nil ? .unresolved : .used
            var sources = [
                EquipmentStatSource(
                    label: "Selected equipment stats", state: selectedState, attributes: selected, value: nil,
                    explanation: equipped.statsAreCached ? "Cached selected stats retained from the same character/tab/slot/item; account refresh incomplete"
                        : !accountAttributes.isEmpty ? "Account endpoint attributes are authoritative"
                        : !reconstructed.isEmpty ? "Selected prefix reconstructed from structured item metadata (not generic defaults)"
                        : item == nil || item?.details == nil ? "Missing item metadata"
                        : selectedID == nil ? "Missing equipment.stats; no selected prefix ID"
                        : itemStats[selectedID!] == nil ? "Missing itemstat metadata for selected stats ID"
                        : "Unsupported selectable stats: missing adjustment or selected ID not in stat_choices"),
                EquipmentStatSource(
                    label: "Item infix attributes", state: infixState, attributes: infix, value: nil,
                    explanation: !selected.isEmpty ? "Selected attributes take precedence; not counted twice"
                        : selectable ? "Selected prefix unresolved; generic defaults cannot substitute" : "Fixed item attributes"),
                EquipmentStatSource(
                    label: "Defense", state: defenseState, attributes: [:], value: item?.details?.defense,
                    explanation: item?.details?.defense == nil && wantsDefense ? "Missing item metadata/details.defense for active armor or possible shield" : "Active terrestrial armor or shield only"),
                EquipmentStatSource(
                    label: "Item metadata", state: !included ? .ignored
                        : item == nil || (item?.requiresEquipmentDetails == true && item?.details == nil) ? .unresolved : .used,
                    attributes: [:], value: nil, explanation: "Needed to classify fixed attributes, upgrades and active shield defense")
            ]
            for (kind, ids) in [("Upgrade", equipped.upgrades ?? []), ("Infusion", equipped.infusions ?? [])] {
                for (index, id) in ids.enumerated() {
                    let metadata = items[id]
                    let attributes = Dictionary(
                        (metadata?.details?.infixUpgrade?.attributes ?? []).map { ($0.attribute, $0.modifier) },
                        uniquingKeysWith: +)
                    let knownRune = kind == "Upgrade" && StaticRuneAttributeCatalog.attributes(for: id, installedCount: 1) != nil
                    let inactiveRune = (knownRune || metadata?.details?.type == "Rune") && !terrestrialArmorSlots.contains(equipped.slot)
                    let name = metadata?.name ?? StaticRuneAttributeCatalog.rules.first(where: { $0.itemID == id })?.itemName ?? "metadata unavailable"
                    sources.append(EquipmentStatSource(
                        label: "\(kind) \(index + 1) • \(id) • \(name)",
                        state: !included || inactiveRune ? .ignored : knownRune ? .used : metadata == nil ? .unresolved
                            : !attributes.isEmpty ? .used
                            : metadata?.details?.type == "Sigil" ? .ignored
                            : metadata?.details?.type == "Rune"
                                && StaticRuneAttributeCatalog.attributes(for: metadata!, installedCount: 1) != nil ? .used : .unresolved,
                        attributes: attributes, value: nil,
                        explanation: inactiveRune ? "Rune is not installed on active terrestrial armor"
                            : knownRune ? "Versioned ID-keyed static rune rule; no runtime prose parsing"
                            : metadata == nil || metadata?.details == nil ? "Missing item metadata"
                            : metadata?.details?.type == "Sigil" && attributes.isEmpty ? "Conditional sigil effect; intentionally excluded"
                            : !attributes.isEmpty ? "Structured infix attributes; canonical aliases applied by stat engine"
                            : metadata?.details?.type == "Rune" ? "ID-keyed rune catalog; incoming duration effects never affect outgoing duration"
                            : "Unsupported static upgrade/infusion: no structured attributes"))
                }
            }
            return EquipmentStatAuditEntry(
                equipment: equipped, itemName: item?.name ?? "Metadata unavailable",
                included: included, exclusionReason: reason, sources: sources)
        }
    }

    /// Hydrate only unambiguous copies in the requested template. Never transfer
    /// another tab's prefix to a reused legendary item.
    static func hydratedTabs(_ tabs: [EquipmentTab], from response: CharacterEquipmentResponse) -> [EquipmentTab] {
        tabs.map { tab in
            let equipment = tab.equipment.map { record in
                guard record.statsAreCached || (record.stats?.attributes?.isEmpty ?? true) else { return record }
                let matches = response.equipment.filter { candidate in
                    candidate.itemID == record.itemID && candidate.slot == record.slot
                        && (candidate.tabs?.contains(tab.tab)
                            ?? (tab.isActive && ["Equipped", "EquippedFromLegendaryArmory"].contains(candidate.location ?? "Equipped")))
                        && (record.statsAreCached || record.stats?.id == nil || record.stats?.id == candidate.stats?.id)
                }
                guard matches.count == 1, let source = matches.first,
                      source.stats?.id != nil || !(source.stats?.attributes?.isEmpty ?? true) else { return record }
                var result = record
                result = mergingRecord(source, cached: record, identity: record)
                return result
            }
            return EquipmentTab(tab: tab.tab, name: tab.name, isActive: tab.isActive, equipment: equipment)
        }
    }

    /// Callers supply tabs from ONE character only. Match the template and the
    /// exact slot/item; never append disappeared slots or borrow another tab.
    static func mergingTabs(_ incoming: [EquipmentTab], cached: [EquipmentTab]) -> [EquipmentTab] {
        incoming.map { tab in
            guard let previous = cached.first(where: { $0.tab == tab.tab }) else { return tab }
            let records = tab.equipment.map { record in
                let matches = previous.equipment.filter { $0.slot == record.slot && $0.itemID == record.itemID }
                guard matches.count == 1 else { return record }
                return mergingRecord(record, cached: matches[0])
            }
            return EquipmentTab(tab: tab.tab, name: tab.name, isActive: tab.isActive, equipment: records)
        }
    }

    private static func mergingRecord(_ incoming: CharacterEquipment, cached: CharacterEquipment,
                                      identity: CharacterEquipment? = nil) -> CharacterEquipment {
        var result = identity ?? incoming
        result.upgrades = incoming.upgrades ?? cached.upgrades
        result.infusions = incoming.infusions ?? cached.infusions
        result.dyes = incoming.dyes ?? cached.dyes
        result.skin = incoming.skin ?? cached.skin
        result.binding = incoming.binding ?? cached.binding
        result.boundTo = incoming.boundTo ?? cached.boundTo
        result.stats = incoming.stats
        result.statsAreCached = incoming.statsAreCached
        if let old = cached.stats {
            let fresh = incoming.stats
            let freshAttributes = fresh?.attributes.flatMap { $0.isEmpty ? nil : $0 }
            if let newID = fresh?.id, newID != old.id {
                // A known different prefix invalidates every previous attribute.
            } else if freshAttributes == nil {
                result.stats = SelectedItemStats(id: fresh?.id ?? old.id, attributes: old.attributes)
                result.statsAreCached = incoming.statsAreCached || (fresh?.id == nil && old.id != nil) || !(old.attributes?.isEmpty ?? true)
            } else if fresh?.id == nil, old.id != nil {
                // Nested fields follow the same non-null merge policy. Fresh
                // attributes win; only the omitted selected ID is cached.
                result.stats = SelectedItemStats(id: old.id, attributes: freshAttributes)
                result.statsAreCached = true
            }
        }
        return result
    }
}

/// Allowlisted raw DTO shape captured BEFORE Codable conversion. Neither the
/// response body nor headers/URLs/API keys are retained in these diagnostics.
struct EquipmentPayloadDiagnostic: Equatable, Sendable, Identifiable {
    let endpoint: String
    let tab: Int?
    let itemID: Int
    let slot: String
    let statsObjectPresent: Bool
    let selectedStatID: Int?
    let attributeKeys: [String]
    var id: String { "\(endpoint)-\(tab ?? 0)-\(slot)-\(itemID)-\(selectedStatID ?? 0)" }
    var summary: String {
        "\(endpoint) • tab \(tab.map(String.init) ?? "not supplied") • \(slot) • item \(itemID) • raw stats \(statsObjectPresent ? "present" : "absent") • selected ID \(selectedStatID.map(String.init) ?? "absent") • attributes \(attributeKeys.joined(separator: ", "))"
    }

    static func capture(_ data: Data, endpoint: String, tab: Int? = nil) -> [Self] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let containers = (root as? [[String: Any]]) ?? (root as? [String: Any]).map { [$0] } ?? []
        return containers.flatMap { container in
            (container["equipment"] as? [[String: Any]] ?? []).compactMap { raw in
                guard let itemID = raw["id"] as? Int else { return nil }
                let stats = raw["stats"] as? [String: Any]
                return Self(endpoint: endpoint, tab: container["tab"] as? Int ?? tab, itemID: itemID,
                            slot: raw["slot"] as? String ?? "Unknown", statsObjectPresent: stats != nil,
                            selectedStatID: stats?["id"] as? Int,
                            attributeKeys: (stats?["attributes"] as? [String: Any])?.keys.sorted() ?? [])
            }
        }
    }
}

enum StatAuditNumber {
    static func parse(_ text: String, fractional: Bool, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        guard let number = formatter.number(from: trimmed) else { return nil }
        let value = number.doubleValue
        return value.isFinite && (fractional || value.rounded() == value) ? value : nil
    }

    static func editable(_ value: Double, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 4
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func difference(calculated: Double, observed: Double) -> Double { calculated - observed }
}
