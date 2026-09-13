import Foundation

struct ResolvedAchievementBit: Identifiable, Equatable, Sendable {
    let index: Int
    let bit: AchievementBit
    let title: String
    let isComplete: Bool?
    let ownershipHint: Bool?
    let provenance: [DataProvenance]
    var id: Int { index }
}

struct AchievementTrackingState: Equatable, Sendable {
    let definition: AchievementDefinition
    let progress: AccountAchievementProgress?
    let bits: [ResolvedAchievementBit]
    let progressAvailable: Bool

    var isComplete: Bool? { progressAvailable ? progress?.done ?? false : nil }

    var goalProgress: GoalProgress {
        if progress?.done == true {
            return GoalProgress(ready: 1, total: 1, label: "Completed", isAuthoritativeCompletion: true)
        }
        if !bits.isEmpty, progressAvailable {
            let complete = bits.filter { $0.isComplete == true }.count
            return GoalProgress(
                ready: complete, total: bits.count,
                label: "\(complete) of \(bits.count) objectives complete",
                isAuthoritativeCompletion: true)
        }
        if let current = progress?.current, let maximum = progress?.max, maximum > 0 {
            return GoalProgress(
                ready: min(current, maximum), total: maximum,
                label: "\(current) of \(maximum) complete", isAuthoritativeCompletion: true)
        }
        return GoalProgress(
            ready: 0, total: 0,
            label: progressAvailable ? "Incomplete" : "Account progress unavailable",
            isAuthoritativeCompletion: progressAvailable)
    }
}

enum AchievementTrackingEngine {
    static func merge(
        definition: AchievementDefinition,
        progress: AccountAchievementProgress?,
        progressPermissionAvailable: Bool,
        items: [Int: ItemMetadata] = [:], skins: [Int: SkinMetadata] = [:],
        minis: [Int: MiniMetadata] = [:], unlockedSkinIDs: Set<Int> = [],
        unlockedMiniIDs: Set<Int> = [], unlockPermissionAvailable: Bool = false
    ) -> AchievementTrackingState {
        let completedBits = Set(progress?.bits ?? [])
        let bits = (definition.bits ?? []).enumerated().map { index, bit in
            let title: String
            let ownership: Bool?
            switch bit {
            case let .text(text):
                title = text
                ownership = nil
            case let .item(id):
                title = items[id]?.name ?? "Item \(id)"
                ownership = nil
            case let .skin(id):
                title = skins[id]?.name ?? "Skin \(id)"
                ownership = unlockPermissionAvailable ? unlockedSkinIDs.contains(id) : nil
            case let .minipet(id):
                title = minis[id]?.name ?? "Mini \(id)"
                ownership = unlockPermissionAvailable ? unlockedMiniIDs.contains(id) : nil
            case let .unknown(type, id, text):
                title = text ?? "\(type) \(id.map(String.init) ?? "objective")"
                ownership = nil
            }
            return ResolvedAchievementBit(
                index: index, bit: bit, title: title,
                isComplete: progressPermissionAvailable ? (progress?.done == true || completedBits.contains(index)) : nil,
                ownershipHint: ownership,
                provenance: progressPermissionAvailable ? [.arenaNetPublic, .arenaNetAccount] : [.arenaNetPublic])
        }
        return AchievementTrackingState(
            definition: definition, progress: progress, bits: bits,
            progressAvailable: progressPermissionAvailable)
    }
}
