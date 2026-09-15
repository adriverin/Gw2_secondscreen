import Foundation
import os

struct MaterialRowSnapshot: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    let name: String
    let normalizedName: String
    let count: Int
    let categoryID: Int
    let iconURL: URL?
    let rarity: String
    let metadataCached: Bool
}

struct MaterialSectionSnapshot: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let order: Int
    let rows: [MaterialRowSnapshot]
}

struct MaterialSnapshotMetrics: Equatable, Sendable {
    var generationNanoseconds: Int64
    var rowModelsCreated: Int
    var metadataLookups: Int
    var uncachedMetadataCount: Int
    var uncachedIconCount: Int
    var sectionCount: Int
    var ownedRowCount: Int
    var totalRowCount: Int
}

struct MaterialStorageSnapshot: Equatable, Sendable {
    let sections: [MaterialSectionSnapshot]
    let updatedAt: Date
    let source: AccountDataSource
    let metrics: MaterialSnapshotMetrics

    var ownedRowCount: Int { metrics.ownedRowCount }
    var totalRowCount: Int { metrics.totalRowCount }
}

struct MaterialStoragePresentedSnapshot: Equatable, Sendable {
    let sections: [MaterialSectionSnapshot]
    let visibleRowCount: Int
    let ownedRowCount: Int
    let totalRowCount: Int
    let showAll: Bool
    let query: String
    let source: AccountDataSource
    let updatedAt: Date
}

enum MaterialStorageInstrumentation {
    static let signposter = OSSignposter(subsystem: "com.example.GW2Companion", category: "Materials")
    static let buildName: StaticString = "MaterialSnapshot.build"
    static let presentName: StaticString = "MaterialSnapshot.present"
    static let presentationCount = OSAllocatedUnfairLock(initialState: 0)

    static func resetPresentationCount() {
        presentationCount.withLock { $0 = 0 }
    }

    static func currentPresentationCount() -> Int {
        presentationCount.withLock { $0 }
    }
}

enum MaterialStorageSnapshotBuilder {
    static func build(
        materials: [AccountMaterial],
        categories: [Int: MaterialCategoryMetadata],
        metadata: [Int: ItemMetadata],
        source: AccountDataSource,
        updatedAt: Date = Date()
    ) -> MaterialStorageSnapshot {
        let signpostID = MaterialStorageInstrumentation.signposter.makeSignpostID()
        let state = MaterialStorageInstrumentation.signposter.beginInterval(
            MaterialStorageInstrumentation.buildName, id: signpostID)
        let clock = ContinuousClock.now

        var materialsByID: [Int: AccountMaterial] = [:]
        materialsByID.reserveCapacity(materials.count)
        for material in materials { materialsByID[material.id] = material }

        var assigned: Set<Int> = []
        assigned.reserveCapacity(max(materials.count, 64))

        var metadataLookups = 0
        var uncachedMetadata = 0
        var uncachedIcons = 0
        var ownedRows = 0
        var totalRows = 0

        let sortedCategories = categories.values.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.id < rhs.id
        }

        var sections: [MaterialSectionSnapshot] = []
        sections.reserveCapacity(sortedCategories.count + 1)

        for category in sortedCategories {
            var rows: [MaterialRowSnapshot] = []
            rows.reserveCapacity(category.items.count)
            for itemID in category.items {
                assigned.insert(itemID)
                let row = rowSnapshot(
                    itemID: itemID, categoryID: category.id, material: materialsByID[itemID],
                    metadata: metadata, lookups: &metadataLookups, uncachedMetadata: &uncachedMetadata,
                    uncachedIcons: &uncachedIcons)
                if row.count > 0 { ownedRows += 1 }
                totalRows += 1
                rows.append(row)
            }
            sections.append(
                MaterialSectionSnapshot(id: category.id, name: category.name, order: category.order, rows: rows))
        }

        let leftovers = materials.filter { !assigned.contains($0.id) }.sorted { $0.id < $1.id }
        if !leftovers.isEmpty {
            var rows: [MaterialRowSnapshot] = []
            rows.reserveCapacity(leftovers.count)
            for material in leftovers {
                let row = rowSnapshot(
                    itemID: material.id, categoryID: 0, material: material, metadata: metadata,
                    lookups: &metadataLookups, uncachedMetadata: &uncachedMetadata, uncachedIcons: &uncachedIcons)
                if row.count > 0 { ownedRows += 1 }
                totalRows += 1
                rows.append(row)
            }
            sections.append(
                MaterialSectionSnapshot(id: 0, name: "Uncategorized", order: Int.max, rows: rows))
        }

        let elapsed = ContinuousClock.now - clock
        let nanoseconds = elapsed.components.seconds * 1_000_000_000
            + elapsed.components.attoseconds / 1_000_000_000
        let metrics = MaterialSnapshotMetrics(
            generationNanoseconds: nanoseconds,
            rowModelsCreated: totalRows,
            metadataLookups: metadataLookups,
            uncachedMetadataCount: uncachedMetadata,
            uncachedIconCount: uncachedIcons,
            sectionCount: sections.count,
            ownedRowCount: ownedRows,
            totalRowCount: totalRows)
        MaterialStorageInstrumentation.signposter.endInterval(
            MaterialStorageInstrumentation.buildName, state)
        return MaterialStorageSnapshot(
            sections: sections, updatedAt: updatedAt, source: source, metrics: metrics)
    }

    private static func rowSnapshot(
        itemID: Int, categoryID: Int, material: AccountMaterial?, metadata: [Int: ItemMetadata],
        lookups: inout Int, uncachedMetadata: inout Int, uncachedIcons: inout Int
    ) -> MaterialRowSnapshot {
        lookups += 1
        let item = metadata[itemID]
        if item == nil { uncachedMetadata += 1 }
        let name = item?.name ?? "Item \(itemID)"
        let icon = item?.icon
        if icon == nil { uncachedIcons += 1 }
        return MaterialRowSnapshot(
            id: itemID,
            name: name,
            normalizedName: name.lowercased(),
            count: material?.count ?? 0,
            categoryID: categoryID,
            iconURL: icon,
            rarity: item?.rarity ?? "Unknown",
            metadataCached: item != nil)
    }
}

enum MaterialStoragePresentation {
    static func present(
        snapshot: MaterialStorageSnapshot, showAll: Bool, query: String
    ) -> MaterialStoragePresentedSnapshot {
        MaterialStorageInstrumentation.presentationCount.withLock { $0 += 1 }
        let signpostID = MaterialStorageInstrumentation.signposter.makeSignpostID()
        let state = MaterialStorageInstrumentation.signposter.beginInterval(
            MaterialStorageInstrumentation.presentName, id: signpostID)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var visible = 0
        let sections = snapshot.sections.compactMap { section -> MaterialSectionSnapshot? in
            let rows = section.rows.filter { row in
                if !showAll && row.count <= 0 { return false }
                if needle.isEmpty { return true }
                return row.normalizedName.contains(needle) || String(row.id) == needle
            }
            guard !rows.isEmpty else { return nil }
            visible += rows.count
            return MaterialSectionSnapshot(id: section.id, name: section.name, order: section.order, rows: rows)
        }
        MaterialStorageInstrumentation.signposter.endInterval(
            MaterialStorageInstrumentation.presentName, state)
        return MaterialStoragePresentedSnapshot(
            sections: sections, visibleRowCount: visible, ownedRowCount: snapshot.ownedRowCount,
            totalRowCount: snapshot.totalRowCount, showAll: showAll, query: query,
            source: snapshot.source, updatedAt: snapshot.updatedAt)
    }
}

enum MaterialStoragePreferences {
    static let showAllKey = "inventory.materials.showAll"

    static func showAll(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: showAllKey)
    }

    static func setShowAll(_ value: Bool, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: showAllKey)
    }
}
