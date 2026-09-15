import Foundation

struct CharacterStatBreakdown: Equatable, Sendable {
    var base: Int = 0
    var equipment: Int = 0
    var upgrades: Int = 0
    var infusions: Int = 0

    var total: Int { base + equipment + upgrades + infusions }
}

struct CharacterDerivedStats: Equatable, Sendable {
    var criticalChancePercent: Double?
    var criticalDamagePercent: Double?
    var boonDurationPercent: Double?
    var conditionDurationPercent: Double?
    var armor: Int?
    var health: Int?
    var availableForLevel: Bool
}

struct CharacterStaticStats: Equatable, Sendable {
    var level: Int
    var profession: String
    var attributes: [String: CharacterStatBreakdown]
    var derived: CharacterDerivedStats
    var equipmentDefense: Int

    func total(for key: String) -> Int { attributes[key]?.total ?? 0 }
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
        CharacterEquipmentStats(attributes: totals(from: calculate(equipment: equipment, items: items).attributes))
    }

    static func calculate(
        character: GW2Character? = nil,
        equipment: [CharacterEquipment],
        items: [Int: ItemMetadata]
    ) -> CharacterStaticStats {
        var breakdowns: [String: CharacterStatBreakdown] = [:]
        let level = character?.level ?? 0
        if let character, character.level >= 80 {
            for key in primaryAttributes {
                breakdowns[key, default: CharacterStatBreakdown()].base = 1_000
            }
        }
        var defense = 0
        for equipped in equipment {
            let selected = equipped.stats?.attributes ?? [:]
            for (key, value) in selected {
                breakdowns[key, default: CharacterStatBreakdown()].equipment += value
            }
            if let item = items[equipped.itemID] {
                if selected.isEmpty {
                    item.details?.infixUpgrade?.attributes.forEach {
                        breakdowns[$0.attribute, default: CharacterStatBreakdown()].equipment += $0.modifier
                    }
                }
                defense += item.details?.defense ?? 0
            }
            for upgradeID in equipped.upgrades ?? [] {
                items[upgradeID]?.details?.infixUpgrade?.attributes.forEach {
                    breakdowns[$0.attribute, default: CharacterStatBreakdown()].upgrades += $0.modifier
                }
            }
            for infusionID in equipped.infusions ?? [] {
                items[infusionID]?.details?.infixUpgrade?.attributes.forEach {
                    breakdowns[$0.attribute, default: CharacterStatBreakdown()].infusions += $0.modifier
                }
            }
        }
        let toughness = breakdowns["Toughness"]?.total ?? 0
        let vitality = breakdowns["Vitality"]?.total ?? 0
        let precision = breakdowns["Precision"]?.total ?? 0
        let ferocity = breakdowns["Ferocity"]?.total ?? 0
        let concentration = breakdowns["Concentration"]?.total ?? 0
        let expertise = breakdowns["Expertise"]?.total ?? 0
        let derived: CharacterDerivedStats
        if level >= 80 {
            derived = CharacterDerivedStats(
                criticalChancePercent: 5 + Double(max(0, precision - 1_000)) / 21.0,
                criticalDamagePercent: 150 + Double(ferocity) / 15.0,
                boonDurationPercent: Double(concentration) / 15.0,
                conditionDurationPercent: Double(expertise) / 15.0,
                armor: toughness + defense,
                health: professionBaseHealth(character?.profession) + vitality * 10,
                availableForLevel: true)
        } else {
            derived = CharacterDerivedStats(
                criticalChancePercent: nil, criticalDamagePercent: nil, boonDurationPercent: nil,
                conditionDurationPercent: nil, armor: toughness + defense, health: nil, availableForLevel: false)
        }
        return CharacterStaticStats(
            level: level, profession: character?.profession ?? "", attributes: breakdowns,
            derived: derived, equipmentDefense: defense)
    }

    static func displayName(_ key: String) -> String {
        key.readableGW2Attribute
    }

    private static func totals(from breakdowns: [String: CharacterStatBreakdown]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: breakdowns.map { ($0.key, $0.value.total) })
    }

    /// Level-80 profession health excluding vitality. Warrior/Necromancer 9212, adventurer 5922, scholar 1645.
    static func professionBaseHealth(_ profession: String?) -> Int {
        switch profession?.lowercased() {
        case "warrior", "necromancer": 9_212
        case "guardian", "revenant", "engineer", "ranger": 5_922
        case "thief", "elementalist", "mesmer": 1_645
        default: 5_922
        }
    }
}
