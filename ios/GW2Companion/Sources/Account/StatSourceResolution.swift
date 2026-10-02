import Foundation

struct StatSourceResolutionPlan: Equatable, Sendable {
    var itemIDs: Set<Int> = []
    var itemStatIDs: Set<Int> = []
    var specializationIDs: Set<Int> = []
    var traitIDs: Set<Int> = []
    var needsEquipmentAttributes = false

    init(equipment: [CharacterEquipment], items: [Int: ItemMetadata], itemStats: [Int: ItemStatMetadata] = [:],
         build: CharacterBuild?, traits: [Int: TraitMetadata], specializations: [Int: SpecializationMetadata], weaponSet: String) {
        for entry in EquipmentStatInputResolver.audit(equipment: equipment, items: items, itemStats: itemStats, weaponSet: weaponSet)
            where entry.included {
            let record = entry.equipment
            if items[record.itemID] == nil || (items[record.itemID]?.requiresEquipmentDetails == true && items[record.itemID]?.details == nil) {
                itemIDs.insert(record.itemID)
            }
            if entry.baseAttributes.isEmpty && record.slot != "Relic" {
                needsEquipmentAttributes = true
                if items[record.itemID]?.details == nil || items[record.itemID]?.details?.attributeAdjustment == nil {
                    itemIDs.insert(record.itemID)
                }
                if let id = record.stats?.id, itemStats[id]?.attributes.isEmpty ?? true { itemStatIDs.insert(id) }
            }
            if entry.sources.contains(where: { $0.label == "Defense" && $0.state == .unresolved }) {
                itemIDs.insert(record.itemID)
            }
            for id in (record.upgrades ?? []) + (record.infusions ?? []) {
                if items[id]?.details == nil && StaticRuneAttributeCatalog.attributes(for: id, installedCount: 1) == nil { itemIDs.insert(id) }
            }
        }
        for selected in build?.specializations ?? [] {
            if let id = selected.id {
                let required = StaticTraitModifierCatalog.verifiedMinorIDs[id] ?? []
                if specializations[id] == nil || !required.isSubset(of: Set(specializations[id]?.minorTraits ?? [])) {
                    specializationIDs.insert(id)
                }
            }
            let ids = selected.traits.compactMap { $0 } + (selected.id.flatMap { specializations[$0]?.minorTraits } ?? [])
            for id in ids {
                if let trait = traits[id] {
                    let expected = StaticTraitModifierCatalog.rules[id]?.count ?? 0
                    let actual = StaticTraitModifierCatalog.adjustments(in: trait).count + StaticTraitModifierCatalog.conversions(in: trait).count
                    if expected > actual || (id == 1453 && StaticTraitModifierCatalog.criticalChance(in: trait) == 0) { traitIDs.insert(id) }
                } else { traitIDs.insert(id) }
            }
        }
    }
}

struct StatCoverageReport: Equatable, Sendable {
    var resolved = 0
    var total = 0
    var missing: [String] = []
    var dynamic: [String] = ["Food, utility effects, boons and live combat state", "Conditional traits and profession mechanics"]
    var isComplete: Bool { missing.isEmpty }
    var summary: String { "Deterministic sources resolved \(resolved) / \(total)" }

    init(stats: CharacterStaticStats, build: CharacterBuild?, traits: [Int: TraitMetadata], specializations: [Int: SpecializationMetadata]) {
        func record(_ complete: Bool, _ identity: String) {
            total += 1
            if complete { resolved += 1 } else { missing.append(identity) }
        }
        for entry in stats.equipmentSources where entry.included {
            let identity = "\(entry.equipment.slot) • \(entry.itemName) • item \(entry.equipment.itemID) • stats \(entry.equipment.stats?.id.map(String.init) ?? "missing")"
            if entry.equipment.slot != "Relic" {
                record(!entry.baseAttributes.isEmpty, identity + " — " + (entry.sources.first?.explanation ?? "Missing equipment.stats"))
            }
            if entry.equipment.slot == "Relic" && entry.baseAttributes.isEmpty { dynamic.append(identity + " — conditional relic effects excluded") }
            for source in entry.sources where source.label == "Item metadata" || source.label == "Defense" || source.label.hasPrefix("Upgrade") || source.label.hasPrefix("Infusion") {
                if source.state == .ignored {
                    if source.label != "Defense" { dynamic.append(identity + " — " + source.label + ": " + source.explanation) }
                    continue
                }
                record(source.state == .used || source.state == .fallback,
                       identity + " — " + source.label + ": " + source.explanation)
            }
        }
        var seenTraits = Set<Int>()
        for selected in build?.specializations ?? [] {
            guard let id = selected.id else { continue }
            let specialization = specializations[id]
            let required = StaticTraitModifierCatalog.verifiedMinorIDs[id] ?? []
            record(specialization != nil && required.isSubset(of: Set(specialization?.minorTraits ?? [])),
                   "Specialization \(id) — missing/incomplete metadata; automatic minor traits not fully evaluated")
            for traitID in selected.traits.compactMap({ $0 }) + (specialization?.minorTraits ?? []) where seenTraits.insert(traitID).inserted {
                guard let trait = traits[traitID] else {
                    record(false, "Trait \(traitID) — missing metadata")
                    continue
                }
                let expected = StaticTraitModifierCatalog.rules[traitID]?.count ?? (traitID == 1453 ? 1 : 0)
                let actual = StaticTraitModifierCatalog.adjustments(in: trait).count
                    + StaticTraitModifierCatalog.conversions(in: trait).count
                    + (StaticTraitModifierCatalog.criticalChance(in: trait) > 0 ? 1 : 0)
                if expected > 0 { record(actual == expected, "Trait \(traitID) • \(trait.name) — static rule/API facts mismatch") }
                else if traitID == 1343 {
                    dynamic.append("Trait 1343 • \(trait.name) — Fury/bleeding-target conditional effects excluded")
                } else if StaticTraitModifierCatalog.hasPotentialStaticFacts(trait) {
                    record(false, "Trait \(traitID) • \(trait.name) — unsupported static/conditional facts; no safe rule")
                } else { dynamic.append("Trait \(traitID) • \(trait.name) — conditional/combat effect excluded") }
            }
        }
        if build == nil { record(false, "Active build unavailable; deterministic traits not evaluated") }
    }
}

struct StatSourceRepairProgress: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    var status: String
}
