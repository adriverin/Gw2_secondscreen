import Foundation

struct CharacterStatBreakdown: Equatable, Sendable {
    var base: Int = 0
    var equipment: Int = 0
    var upgradeComponents: Int = 0
    var runes: Int = 0
    var sigils: Int = 0
    var infusions: Int = 0
    var relic: Int = 0
    var traits: Int = 0
    var professionEffects: Int = 0
    var otherDeterministic: Int = 0

    var upgrades: Int { upgradeComponents + runes + sigils + relic }
    var total: Int {
        base + equipment + upgradeComponents + runes + sigils + infusions
            + relic + traits + professionEffects + otherDeterministic
    }

    var components: [(String, Int)] {
        [
            ("Base", base), ("Equipment selected stats", equipment),
            ("Upgrade components", upgradeComponents), ("Runes", runes),
            ("Sigils", sigils), ("Infusions", infusions), ("Relic", relic),
            ("Traits", traits), ("Profession effects", professionEffects),
            ("Other deterministic", otherDeterministic)
        ]
    }
}

struct CharacterDefenseBreakdown: Equatable, Sendable {
    var armorPieces = 0
    var shield = 0
    var other = 0
    var total: Int { armorPieces + shield + other }
}

struct CharacterDerivedStats: Equatable, Sendable {
    var criticalChancePercent: Double?
    var criticalDamagePercent: Double?
    var boonDurationPercent: Double?
    var conditionDurationPercent: Double?
    var armor: Int?
    var health: Int?
    var availableForLevel: Bool
    var criticalChanceFromPrecision: Double? = nil
    var criticalChanceBuildModifier: Double = 0
}

enum CharacterStatCoverage: String, Equatable, Sendable {
    case high = "High"
    case partial = "Partial"
}

struct CharacterStaticStats: Equatable, Sendable {
    var level: Int
    var profession: String
    var attributes: [String: CharacterStatBreakdown]
    var derived: CharacterDerivedStats
    var defense: CharacterDefenseBreakdown
    var modeledTraitCount: Int
    var excludedTraitCount: Int
    var coverage: CharacterStatCoverage
    var excludedSources: [String]
    var equipmentSources: [EquipmentStatAuditEntry] = []

    var equipmentDefense: Int { defense.total }
    func total(for key: String) -> Int { attributes[CharacterStatEngine.canonicalAttribute(key)]?.total ?? 0 }
}

enum StaticRuneAttributeCatalog {
    static let version = "pve-2026-10-01-v2"

    struct Rule: Sendable {
        let itemID: Int
        let itemName: String
        let perPieceBonuses: [[String: Int]]
    }

    // ArenaNet /v2/items/24836 exposes these bonuses as a string array. They are
    // curated here rather than parsed at runtime, so localization cannot alter stats.
    static let rules = [
        Rule(itemID: 24836, itemName: "Superior Rune of the Scholar", perPieceBonuses: [
            ["Power": 25], ["Ferocity": 35], ["Power": 50],
            ["Ferocity": 65], ["Power": 100], ["Ferocity": 125]
        ]),
        Rule(itemID: 24771, itemName: "Superior Rune of Melandru", perPieceBonuses: [
            ["Toughness": 25], ["Vitality": 35], ["Toughness": 50],
            [:], ["Toughness": 100], [:]
        ])
    ]

    static func attributes(for item: ItemMetadata, installedCount: Int) -> [String: Int]? {
        attributes(for: item.id, installedCount: installedCount)
    }

    static func attributes(for itemID: Int, installedCount: Int) -> [String: Int]? {
        guard let rule = rules.first(where: { $0.itemID == itemID }) else { return nil }
        var result: [String: Int] = [:]
        for values in rule.perPieceBonuses.prefix(max(0, installedCount)) {
            for (key, value) in values { result[key, default: 0] += value }
        }
        return result
    }
}

enum StaticTraitModifierCatalog {
    static let version = "pve-2026-10-02-v4"
    static let verifiedMinorIDs: [Int: Set<Int>] = [4: [1446, 1448, 1453]]

    /// Verified /v2/traits/1453: Percent 5 is unconditional; its AttributeAdjust
    /// Power 10 describes extra Power per Might and must NOT be added flat.
    static func criticalChance(in trait: TraitMetadata) -> Double {
        guard trait.id == 1453, trait.facts.contains(where: {
            $0.type == "Percent" && $0.percent == 5
        }) else { return 0 }
        return 5
    }

    enum Rule: Sendable {
        case adjust(apiTarget: String, attribute: String, value: Int)
        case conversion(apiSource: String, source: String, apiTarget: String, target: String, percent: Double)
    }

    /// Curated PvE rules execute locally. Structured facts validate the shipped
    /// catalog, but absence/incomplete metadata is not evidence of a rule change.
    static let rules: [Int: [Rule]] = [
        232: [.conversion(apiSource: "Precision", source: "Precision", apiTarget: "CritDamage", target: "Ferocity", percent: 7)],
        275: [.conversion(apiSource: "Toughness", source: "Toughness", apiTarget: "ConditionDamage", target: "ConditionDamage", percent: 10)],
        325: [.adjust(apiTarget: "ConditionDamage", attribute: "ConditionDamage", value: 180)],
        568: [.adjust(apiTarget: "CritDamage", attribute: "Ferocity", value: 150)],
        803: [.adjust(apiTarget: "Precision", attribute: "Precision", value: 180)],
        810: [.conversion(apiSource: "Precision", source: "Precision", apiTarget: "ConditionDamage", target: "ConditionDamage", percent: 13)],
        829: [.conversion(apiSource: "Power", source: "Power", apiTarget: "Vitality", target: "Vitality", percent: 10)],
        861: [.adjust(apiTarget: "Vitality", attribute: "Vitality", value: 180)],
        978: [.conversion(apiSource: "Power", source: "Power", apiTarget: "Healing", target: "HealingPower", percent: 7)],
        1232: [.adjust(apiTarget: "ConditionDuration", attribute: "Expertise", value: 150)],
        1449: [
            .conversion(apiSource: "Power", source: "Power", apiTarget: "Vitality", target: "Vitality", percent: 10),
            .conversion(apiSource: "Power", source: "Power", apiTarget: "CritDamage", target: "Ferocity", percent: 10)
        ],
        1556: [.conversion(apiSource: "Power", source: "Power", apiTarget: "ConditionDamage", target: "ConditionDamage", percent: 10)]
    ]

    static func adjustments(in trait: TraitMetadata) -> [(String, Int)] {
        guard let rules = rules[trait.id] else { return [] }
        return rules.compactMap { rule in
            guard case let .adjust(apiTarget, attribute, value) = rule,
                  trait.facts.contains(where: {
                    $0.type == "AttributeAdjust" && $0.target == apiTarget && $0.value == value
                  }) else { return nil }
            return (attribute, value)
        }
    }

    static func conversions(in trait: TraitMetadata) -> [(source: String, target: String, percent: Double)] {
        guard let rules = rules[trait.id] else { return [] }
        return rules.compactMap { rule in
            guard case let .conversion(apiSource, source, apiTarget, target, percent) = rule,
                  trait.facts.contains(where: {
                    $0.type == "BuffConversion" && $0.source == apiSource
                        && ($0.target == apiTarget || (trait.id == 1449 && apiTarget == "CritDamage" && $0.target == "Ferocity"))
                        && abs(($0.percent ?? -Double.infinity) - percent) < 0.001
                  }) else { return nil }
            return (source, target, percent)
        }
    }

    static func hasPotentialStaticFacts(_ trait: TraitMetadata) -> Bool {
        trait.facts.contains { ["AttributeAdjust", "BuffConversion"].contains($0.type) }
    }

    static func supports(_ id: Int) -> Bool { rules[id] != nil || id == 1453 }

    enum Validation: Equatable {
        case verified, metadataDiffers, mechanicalMismatch
    }

    /// Only positive contradictions in relevant mechanical fields block a rule.
    /// Missing fields/facts, order, text, icons and unrelated targets do not.
    static func validation(id: Int, metadata: TraitMetadata?) -> Validation {
        guard let metadata else { return .metadataDiffers }
        if (id == 1449 || id == 1453), let specialization = metadata.specialization, specialization != 4 {
            return .mechanicalMismatch
        }
        for rule in rules[id] ?? [] {
            switch rule {
            case let .adjust(apiTarget, _, value):
                for fact in metadata.facts where fact.target.map(CharacterStatEngine.canonicalAttribute) == CharacterStatEngine.canonicalAttribute(apiTarget) {
                    if fact.type == "AttributeAdjust", let actual = fact.value, actual != value { return .mechanicalMismatch }
                    if fact.type == "BuffConversion", fact.source != nil, fact.percent != nil { return .mechanicalMismatch }
                }
            case let .conversion(apiSource, _, apiTarget, _, percent):
                for fact in metadata.facts where fact.target.map(CharacterStatEngine.canonicalAttribute) == CharacterStatEngine.canonicalAttribute(apiTarget) {
                    if fact.type == "AttributeAdjust", fact.value != nil { return .mechanicalMismatch }
                    if fact.type == "BuffConversion" {
                        if let source = fact.source, CharacterStatEngine.canonicalAttribute(source) != CharacterStatEngine.canonicalAttribute(apiSource) { return .mechanicalMismatch }
                        if let actual = fact.percent, abs(actual - percent) > 0.001 { return .mechanicalMismatch }
                    }
                }
            }
        }
        if id == 1449 {
            // A full two-conversion replacement can positively identify a
            // changed target. A lone unrelated/incomplete fact cannot. Extra
            // conversions never invalidate the intact known pair.
            let powerConversions = metadata.facts.filter { $0.type == "BuffConversion" && $0.source == "Power" && $0.target != nil && $0.percent != nil }
            let targets = Set(powerConversions.compactMap(\.target).map(CharacterStatEngine.canonicalAttribute))
            let expected: Set<String> = ["Vitality", "Ferocity"]
            if targets.count >= 2 && !expected.isSubset(of: targets) && !targets.subtracting(expected).isEmpty {
                return .mechanicalMismatch
            }
        }
        if id == 1453 {
            // Pinnacle's sole Percent fact is critical chance. Other fact types
            // (notably Power per Might) are irrelevant to its unconditional rule.
            let percentages = metadata.facts.filter { $0.type == "Percent" }.compactMap(\.percent)
            if percentages.count == 1, percentages[0] != 5 { return .mechanicalMismatch }
            return criticalChance(in: metadata) == 5 ? .verified : .metadataDiffers
        }
        let expected = rules[id]?.count ?? 0
        return adjustments(in: metadata).count + conversions(in: metadata).count == expected ? .verified : .metadataDiffers
    }

    static func runtimeAdjustments(id: Int, metadata: TraitMetadata?) -> [(String, Int)] {
        guard validation(id: id, metadata: metadata) != .mechanicalMismatch else { return [] }
        return (rules[id] ?? []).compactMap {
            guard case let .adjust(_, attribute, value) = $0 else { return nil }
            return (attribute, value)
        }
    }

    static func runtimeConversions(id: Int, metadata: TraitMetadata?) -> [(source: String, target: String, percent: Double)] {
        guard validation(id: id, metadata: metadata) != .mechanicalMismatch else { return [] }
        return (rules[id] ?? []).compactMap {
            guard case let .conversion(_, source, _, target, percent) = $0 else { return nil }
            return (source, target, percent)
        }
    }
}

enum CharacterStatEngine {
    static let displayOrder = [
        "Power", "Precision", "Toughness", "Vitality",
        "Ferocity", "ConditionDamage", "Expertise", "Concentration", "HealingPower"
    ]

    static let primaryAttributes = ["Power", "Precision", "Toughness", "Vitality"]
    static let secondaryAttributes = [
        "Ferocity", "ConditionDamage", "Expertise", "Concentration", "HealingPower"
    ]

    static func equipmentAttributes(
        equipment: [CharacterEquipment], items: [Int: ItemMetadata], upgrades: [Int: ItemMetadata]
    ) -> CharacterEquipmentStats {
        let metadata = items.merging(upgrades) { current, _ in current }
        return CharacterEquipmentStats(attributes: totals(from: calculate(equipment: equipment, items: metadata).attributes))
    }

    static func calculate(
        character: GW2Character? = nil,
        equipment: [CharacterEquipment],
        items: [Int: ItemMetadata],
        build: CharacterBuild? = nil,
        traits: [Int: TraitMetadata] = [:],
        specializations: [Int: SpecializationMetadata] = [:],
        itemStats: [Int: ItemStatMetadata] = [:],
        weaponSet: String = "A"
    ) -> CharacterStaticStats {
        var breakdowns = Dictionary(uniqueKeysWithValues: displayOrder.map { ($0, CharacterStatBreakdown()) })
        let level = character?.level ?? 0
        if level >= 80 {
            for key in primaryAttributes { breakdowns[key, default: CharacterStatBreakdown()].base = 1_000 }
        }

        var defense = CharacterDefenseBreakdown()
        var runeCounts: [Int: Int] = [:]
        var runesWithStructuredAttributes = Set<Int>()
        var unknownRuneCount = 0
        var excludedSigilCount = 0
        var excludedRelicCount = 0
        var unresolvedSelectableStatCount = 0
        var exclusions: [String] = []
        let equipmentSources = EquipmentStatInputResolver.audit(
            equipment: equipment, items: items, itemStats: itemStats, weaponSet: weaponSet)

        for entry in equipmentSources where entry.included {
            let equipped = entry.equipment
            let item = items[equipped.itemID]
            let isRelic = equipped.slot.caseInsensitiveCompare("Relic") == .orderedSame
            let baseAttributes = entry.baseAttributes
            if baseAttributes.isEmpty && !isRelic { unresolvedSelectableStatCount += 1 }
            for (rawKey, value) in baseAttributes {
                let key = canonicalAttribute(rawKey)
                if isRelic { breakdowns[key, default: CharacterStatBreakdown()].relic += value }
                else { breakdowns[key, default: CharacterStatBreakdown()].equipment += value }
            }

            if let item, entry.defense > 0 {
                let value = entry.defense
                if item.details?.type?.caseInsensitiveCompare("Shield") == .orderedSame
                    || equipped.slot.localizedCaseInsensitiveContains("Shield") {
                    defense.shield += value
                } else if item.type?.caseInsensitiveCompare("Armor") == .orderedSame
                            || Self.isArmorSlot(equipped.slot) {
                    defense.armorPieces += value
                }
            }

            if isRelic, baseAttributes.isEmpty { excludedRelicCount += 1 }

            for upgradeID in equipped.upgrades ?? [] {
                if StaticRuneAttributeCatalog.attributes(for: upgradeID, installedCount: 1) != nil {
                    if EquipmentStatInputResolver.terrestrialArmorSlots.contains(equipped.slot) {
                        runeCounts[upgradeID, default: 0] += 1
                    }
                    continue
                }
                guard let upgrade = items[upgradeID] else { continue }
                let kind = upgrade.details?.type?.lowercased()
                let attributes = upgrade.details?.infixUpgrade?.attributes ?? []
                if kind == "rune" {
                    guard EquipmentStatInputResolver.terrestrialArmorSlots.contains(equipped.slot) else { continue }
                    runeCounts[upgradeID, default: 0] += 1
                    if !attributes.isEmpty {
                        runesWithStructuredAttributes.insert(upgradeID)
                        add(attributes, to: &breakdowns, category: .runes)
                    }
                } else if kind == "sigil" {
                    if attributes.isEmpty { excludedSigilCount += 1 }
                    else { add(attributes, to: &breakdowns, category: .sigils) }
                } else {
                    add(attributes, to: &breakdowns, category: .upgrades)
                }
            }
            for infusionID in equipped.infusions ?? [] {
                add(items[infusionID]?.details?.infixUpgrade?.attributes ?? [], to: &breakdowns, category: .infusions)
            }
        }

        for (runeID, count) in runeCounts where !runesWithStructuredAttributes.contains(runeID) {
            guard let values = StaticRuneAttributeCatalog.attributes(for: runeID, installedCount: count)
            else {
                unknownRuneCount += count
                continue
            }
            for (key, value) in values {
                breakdowns[canonicalAttribute(key), default: CharacterStatBreakdown()].runes += value
            }
        }

        if unknownRuneCount > 0 { exclusions.append("Rune bonuses not fully modeled (\(unknownRuneCount) equipped)") }
        if excludedSigilCount > 0 { exclusions.append("\(excludedSigilCount) conditional or unsupported sigil effects excluded") }
        if excludedRelicCount > 0 { exclusions.append("\(excludedRelicCount) conditional relic effects excluded") }
        if unresolvedSelectableStatCount > 0 {
            exclusions.append("\(unresolvedSelectableStatCount) equipment attribute sources unresolved (including selectable equipment stat source unavailable)")
        }
        let missingDefense = equipmentSources.filter {
            $0.included && $0.sources.contains { $0.label == "Defense" && $0.state == .unresolved }
        }.count
        if missingDefense > 0 { exclusions.append("\(missingDefense) active armor/shield defense sources unresolved") }
        let missingUpgrades = equipmentSources.flatMap(\.sources).filter {
            $0.state == .unresolved && ($0.label.hasPrefix("Upgrade") || $0.label.hasPrefix("Infusion"))
        }.count
        if missingUpgrades > 0 { exclusions.append("\(missingUpgrades) upgrade/infusion sources unmodeled or unresolved") }

        let activeTraitIDs = activeTraits(build: build, specializations: specializations)
        var modeledTraits = 0
        var excludedTraits = 0
        var conversions: [(source: String, target: String, percent: Double)] = []
        var criticalChanceModifier = 0.0
        for id in activeTraitIDs.sorted() {
            if id == 1449 && build?.specializations.contains(where: { $0.id == 4 && $0.traits.contains(1449) }) != true { continue }
            let trait = traits[id]
            guard trait != nil || StaticTraitModifierCatalog.supports(id) else {
                excludedTraits += 1
                continue
            }
            let adjustments = StaticTraitModifierCatalog.runtimeAdjustments(id: id, metadata: trait)
            let traitConversions = StaticTraitModifierCatalog.runtimeConversions(id: id, metadata: trait)
            let crit = id == 1453 && build?.specializations.contains(where: { $0.id == 4 }) == true
                && StaticTraitModifierCatalog.validation(id: id, metadata: trait) != .mechanicalMismatch ? 5.0 : 0
            criticalChanceModifier += crit
            if !adjustments.isEmpty || !traitConversions.isEmpty || crit != 0 {
                modeledTraits += 1
                for (key, value) in adjustments {
                    breakdowns[canonicalAttribute(key), default: CharacterStatBreakdown()].traits += value
                }
                conversions.append(contentsOf: traitConversions)
            } else if StaticTraitModifierCatalog.supports(id) || trait.map(StaticTraitModifierCatalog.hasPotentialStaticFacts) == true {
                excludedTraits += 1
            }
        }
        // Phases: base → equipment → upgrades/runes/infusions → flat traits →
        // conversions → derived. All conversions read the SAME pre-conversion
        // snapshot, so no trait-ID iteration order can create recursive gains.
        let conversionInputs = breakdowns.mapValues(\.total)
        for conversion in conversions {
            let sourceTotal = conversionInputs[canonicalAttribute(conversion.source)] ?? 0
            let amount = Int((Double(sourceTotal) * conversion.percent / 100.0).rounded(.down))
            breakdowns[canonicalAttribute(conversion.target), default: CharacterStatBreakdown()].traits += amount
        }
        if excludedTraits > 0 { exclusions.append("\(excludedTraits) trait modifiers excluded or conditional") }
        exclusions.append("Food, utility effects, boons, and live combat state are unavailable")
        exclusions.append("Unstructured profession mechanics are excluded")

        let toughness = breakdowns["Toughness"]?.total ?? 0
        let vitality = breakdowns["Vitality"]?.total ?? 0
        let precision = breakdowns["Precision"]?.total ?? 0
        let ferocity = breakdowns["Ferocity"]?.total ?? 0
        let concentration = breakdowns["Concentration"]?.total ?? 0
        let expertise = breakdowns["Expertise"]?.total ?? 0
        let derived: CharacterDerivedStats
        if level >= 80 {
            derived = CharacterDerivedStats(
                criticalChancePercent: criticalChance(precision: precision) + criticalChanceModifier,
                criticalDamagePercent: criticalDamage(ferocity: ferocity),
                boonDurationPercent: duration(attribute: concentration),
                conditionDurationPercent: duration(attribute: expertise),
                armor: toughness + defense.total,
                health: professionBaseHealth(character?.profession) + vitality * 10,
                availableForLevel: true,
                criticalChanceFromPrecision: criticalChance(precision: precision),
                criticalChanceBuildModifier: criticalChanceModifier)
        } else {
            derived = CharacterDerivedStats(
                criticalChancePercent: nil, criticalDamagePercent: nil, boonDurationPercent: nil,
                conditionDurationPercent: nil, armor: toughness + defense.total,
                health: nil, availableForLevel: false)
        }
        return CharacterStaticStats(
            level: level, profession: character?.profession ?? "", attributes: breakdowns,
            derived: derived, defense: defense,
            modeledTraitCount: modeledTraits, excludedTraitCount: excludedTraits,
            coverage: exclusions.isEmpty ? .high : .partial,
            excludedSources: exclusions, equipmentSources: equipmentSources)
    }

    static func canonicalAttribute(_ key: String) -> String {
        switch key.lowercased().replacingOccurrences(of: " ", with: "") {
        case "critdamage", "ferocity": "Ferocity"
        case "conditionduration", "expertise": "Expertise"
        case "boonduration", "concentration": "Concentration"
        case "healing", "healingpower": "HealingPower"
        case "conditiondamage": "ConditionDamage"
        case "power": "Power"
        case "precision": "Precision"
        case "toughness": "Toughness"
        case "vitality": "Vitality"
        default: key
        }
    }

    static func displayName(_ key: String) -> String { canonicalAttribute(key).readableGW2Attribute }

    static func criticalChance(precision: Int) -> Double { 5 + Double(precision - 1_000) / 21.0 }
    static func criticalDamage(ferocity: Int) -> Double { 150 + Double(ferocity) / 15.0 }
    static func duration(attribute: Int) -> Double { min(100, max(0, Double(attribute) / 15.0)) }

    private enum AdditionCategory { case upgrades, runes, sigils, infusions }

    private static func add(
        _ attributes: [ItemAttribute],
        to breakdowns: inout [String: CharacterStatBreakdown],
        category: AdditionCategory
    ) {
        for attribute in attributes {
            let key = canonicalAttribute(attribute.attribute)
            switch category {
            case .upgrades: breakdowns[key, default: CharacterStatBreakdown()].upgradeComponents += attribute.modifier
            case .runes: breakdowns[key, default: CharacterStatBreakdown()].runes += attribute.modifier
            case .sigils: breakdowns[key, default: CharacterStatBreakdown()].sigils += attribute.modifier
            case .infusions: breakdowns[key, default: CharacterStatBreakdown()].infusions += attribute.modifier
            }
        }
    }

    private static func activeTraits(
        build: CharacterBuild?, specializations: [Int: SpecializationMetadata]
    ) -> Set<Int> {
        guard let build else { return [] }
        var ids = Set(build.specializations.flatMap(\.traits).compactMap { $0 })
        for selected in build.specializations {
            guard let id = selected.id else { continue }
            ids.formUnion(StaticTraitModifierCatalog.verifiedMinorIDs[id] ?? [])
            ids.formUnion(specializations[id]?.minorTraits ?? [])
        }
        return ids
    }

    private static func isArmorSlot(_ slot: String) -> Bool {
        ["Helm", "Shoulders", "Coat", "Gloves", "Leggings", "Boots"].contains {
            slot.localizedCaseInsensitiveContains($0)
        }
    }

    private static func totals(from breakdowns: [String: CharacterStatBreakdown]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: breakdowns.map { ($0.key, $0.value.total) })
    }

    /// Level-80 profession health excluding the 10,000 health contributed by base Vitality.
    static func professionBaseHealth(_ profession: String?) -> Int {
        switch profession?.lowercased() {
        case "warrior", "necromancer": 9_212
        case "guardian", "revenant", "engineer", "ranger": 5_922
        case "thief", "elementalist", "mesmer": 1_645
        default: 5_922
        }
    }
}
