import Foundation

enum EquipmentStatSourceState: String, Equatable, Sendable {
    case used = "USED"
    case ignored = "IGNORED"
    case fallback = "FALLBACK"
    case unresolved = "UNRESOLVED"
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
        equipment: [CharacterEquipment], items: [Int: ItemMetadata], weaponSet: String = "A"
    ) -> [EquipmentStatAuditEntry] {
        var seenSlots = Set<String>()
        return equipment.map { equipped in
            let item = items[equipped.itemID]
            let reason = ignoredReason(equipped, weaponSet: weaponSet)
                ?? (seenSlots.insert(equipped.slot).inserted ? nil : "Duplicate slot record")
            let included = reason == nil
            let selected = equipped.stats?.attributes ?? [:]
            let infix = Dictionary(
                (item?.details?.infixUpgrade?.attributes ?? []).map { ($0.attribute, $0.modifier) },
                uniquingKeysWith: +)
            let selectable = equipped.stats?.id != nil || !(item?.details?.statChoices?.isEmpty ?? true)
            let selectedState: EquipmentStatSourceState = !included ? .ignored : !selected.isEmpty ? .used : .unresolved
            let infixState: EquipmentStatSourceState = !included || !selected.isEmpty
                ? .ignored : selectable || infix.isEmpty ? .unresolved : .fallback
            let wantsDefense = terrestrialArmorSlots.contains(equipped.slot) || item?.details?.type == "Shield"
            let defenseState: EquipmentStatSourceState = !included || !wantsDefense
                ? .ignored : item?.details?.defense == nil ? .unresolved : .used
            var sources = [
                EquipmentStatSource(
                    label: "Selected equipment stats", state: selectedState, attributes: selected, value: nil,
                    explanation: !selected.isEmpty ? "Account endpoint attributes are authoritative" : "No resolved attributes in this record"),
                EquipmentStatSource(
                    label: "Item infix attributes", state: infixState, attributes: infix, value: nil,
                    explanation: !selected.isEmpty ? "Selected attributes take precedence; not counted twice"
                        : selectable ? "Selected prefix unresolved; generic defaults cannot substitute" : "Fixed item attributes"),
                EquipmentStatSource(
                    label: "Defense", state: defenseState, attributes: [:], value: item?.details?.defense,
                    explanation: "Active terrestrial armor or shield only")
            ]
            for (kind, ids) in [("Upgrade", equipped.upgrades ?? []), ("Infusion", equipped.infusions ?? [])] {
                for (index, id) in ids.enumerated() {
                    let metadata = items[id]
                    let attributes = Dictionary(
                        (metadata?.details?.infixUpgrade?.attributes ?? []).map { ($0.attribute, $0.modifier) },
                        uniquingKeysWith: +)
                    sources.append(EquipmentStatSource(
                        label: "\(kind) \(index + 1) • \(id) • \(metadata?.name ?? "metadata unavailable")",
                        state: !included ? .ignored : metadata == nil ? .unresolved
                            : !attributes.isEmpty ? .used
                            : metadata?.details?.type == "Rune"
                                && StaticRuneAttributeCatalog.attributes(for: metadata!, installedCount: 1) != nil ? .used : .unresolved,
                        attributes: attributes, value: nil,
                        explanation: "Structured attributes or existing curated rune rule; conditional effects excluded"))
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
                guard record.stats?.attributes?.isEmpty ?? true else { return record }
                let matches = response.equipment.filter { candidate in
                    candidate.itemID == record.itemID && candidate.slot == record.slot
                        && (candidate.tabs?.contains(tab.tab)
                            ?? (tab.isActive && ["Equipped", "EquippedFromLegendaryArmory"].contains(candidate.location ?? "Equipped")))
                        && (record.stats?.id == nil || record.stats?.id == candidate.stats?.id)
                }
                guard matches.count == 1, let source = matches.first,
                      !(source.stats?.attributes?.isEmpty ?? true) else { return record }
                var result = record
                result.stats = source.stats
                return result
            }
            return EquipmentTab(tab: tab.tab, name: tab.name, isActive: tab.isActive, equipment: equipment)
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
