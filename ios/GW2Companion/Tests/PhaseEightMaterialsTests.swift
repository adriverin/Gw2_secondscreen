import Foundation
import XCTest
@testable import GW2Companion

final class PhaseEightMaterialsPerformanceTests: XCTestCase {
    func testMatureAccountSnapshotAvoidsLegacyBodyScan() {
        let fixture = MaterialStorageMatureFixture.make()
        XCTAssertGreaterThanOrEqual(fixture.materials.count, 400)
        XCTAssertGreaterThanOrEqual(fixture.categories.count, 8)
        XCTAssertTrue(fixture.materials.contains(where: { $0.count > 0 }))
        XCTAssertTrue(fixture.materials.contains(where: { $0.count == 0 }))
        XCTAssertTrue(fixture.metadata.values.contains(where: { $0.icon != nil }))
        XCTAssertTrue(fixture.metadata.count < fixture.materials.count)

        let legacy = MaterialStorageLegacyProjection.project(
            materials: fixture.materials, categories: fixture.categories,
            metadata: fixture.metadata, showAll: true, search: "")
        XCTAssertGreaterThan(legacy.containsScans, 50_000)
        XCTAssertGreaterThan(legacy.nanoseconds, 0)

        let snapshot = MaterialStorageSnapshotBuilder.build(
            materials: fixture.materials, categories: fixture.categories,
            metadata: fixture.metadata, source: .live)
        XCTAssertEqual(snapshot.metrics.rowModelsCreated, snapshot.totalRowCount)
        XCTAssertEqual(snapshot.metrics.metadataLookups, snapshot.totalRowCount)
        XCTAssertGreaterThan(snapshot.metrics.uncachedMetadataCount, 0)
        XCTAssertGreaterThan(snapshot.metrics.uncachedIconCount, 0)
        XCTAssertLessThan(snapshot.metrics.generationNanoseconds, legacy.nanoseconds)
        XCTAssertLessThan(snapshot.metrics.generationNanoseconds, 50_000_000)
        print(
            "MATERIALS_PERF snapshot_ns=\(snapshot.metrics.generationNanoseconds) legacy_ns=\(legacy.nanoseconds) rows=\(snapshot.totalRowCount) owned=\(snapshot.ownedRowCount) contains_scans=\(legacy.containsScans) metadata_lookups=\(snapshot.metrics.metadataLookups)")

        MaterialStorageInstrumentation.resetPresentationCount()
        let owned = MaterialStoragePresentation.present(snapshot: snapshot, showAll: false, query: "")
        let all = MaterialStoragePresentation.present(snapshot: snapshot, showAll: true, query: "")
        let search = MaterialStoragePresentation.present(snapshot: snapshot, showAll: true, query: "Cotton")
        XCTAssertLessThan(owned.visibleRowCount, all.visibleRowCount)
        XCTAssertEqual(owned.visibleRowCount, snapshot.ownedRowCount)
        XCTAssertFalse(owned.sections.flatMap(\.rows).contains(where: { $0.count <= 0 }))
        XCTAssertTrue(all.sections.flatMap(\.rows).contains(where: { $0.count == 0 }))
        XCTAssertTrue(search.sections.flatMap(\.rows).allSatisfy { $0.normalizedName.contains("cotton") })
        XCTAssertEqual(MaterialStorageInstrumentation.currentPresentationCount(), 3)
        XCTAssertEqual(Set(owned.sections.flatMap(\.rows).map(\.id)).count, owned.visibleRowCount)
    }

    func testSearchAndOwnedToggleDoNotRescanCategoryMembership() {
        let fixture = MaterialStorageMatureFixture.make()
        let snapshot = MaterialStorageSnapshotBuilder.build(
            materials: fixture.materials, categories: fixture.categories,
            metadata: fixture.metadata, source: .cached)
        let first = MaterialStoragePresentation.present(snapshot: snapshot, showAll: false, query: "")
        let second = MaterialStoragePresentation.present(snapshot: snapshot, showAll: true, query: "ore")
        XCTAssertEqual(first.totalRowCount, second.totalRowCount)
        XCTAssertEqual(first.updatedAt, snapshot.updatedAt)
        XCTAssertLessThan(second.visibleRowCount, snapshot.totalRowCount)
        XCTAssertTrue(second.sections.allSatisfy { !$0.rows.isEmpty })
    }

    func testShowAllPreferenceDefaultsToOwnedOnly() {
        let defaults = UserDefaults(suiteName: "materials-pref-\(UUID().uuidString)")!
        XCTAssertFalse(MaterialStoragePreferences.showAll(defaults: defaults))
        MaterialStoragePreferences.setShowAll(true, defaults: defaults)
        XCTAssertTrue(MaterialStoragePreferences.showAll(defaults: defaults))
        MaterialStoragePreferences.setShowAll(false, defaults: defaults)
        XCTAssertFalse(MaterialStoragePreferences.showAll(defaults: defaults))
    }
}

enum MaterialStorageMatureFixture {
    static func make() -> (
        materials: [AccountMaterial],
        categories: [Int: MaterialCategoryMetadata],
        metadata: [Int: ItemMetadata]
    ) {
        let names = [
            "Basic Crafting Materials", "Fine Crafting Materials", "Rare Crafting Materials",
            "Ascended Materials", "Cooking Materials", "Scribing Materials", "Festive Materials",
            "Gemstones", "Boss Materials", "Dungeon Materials", "PvP Materials",
            "Fractal Materials", "Raid Materials", "Expansion Materials", "Legendary Components"
        ]
        var categories: [Int: MaterialCategoryMetadata] = [:]
        var materials: [AccountMaterial] = []
        var metadata: [Int: ItemMetadata] = [:]
        var nextID = 10_000
        for (index, name) in names.enumerated() {
            let categoryID = index + 1
            let count = index == 0 ? 120 : 48
            var itemIDs: [Int] = []
            itemIDs.reserveCapacity(count)
            for slot in 0..<count {
                let id = nextID
                nextID += 1
                itemIDs.append(id)
                let owned = slot % 3 != 0
                materials.append(AccountMaterial(id: id, category: categoryID, count: owned ? (slot + 1) * 3 : 0))
                let cached = slot % 4 != 0
                if cached {
                    let itemName = slot % 11 == 0 ? "Cotton Scrap \(id)" : "\(name) Sample \(slot)"
                    metadata[id] = ItemMetadata(
                        id: id, name: itemName,
                        icon: slot % 5 == 0 ? URL(string: "https://render.guildwars2.com/file/fixture/\(id).png") : nil,
                        rarity: slot % 7 == 0 ? "Rare" : "Basic")
                }
            }
            categories[categoryID] = MaterialCategoryMetadata(
                id: categoryID, name: name, items: itemIDs, order: index)
        }
        materials.append(AccountMaterial(id: 99_991, category: 99, count: 12))
        return (materials, categories, metadata)
    }
}

/// Mirrors the previous Materials `body` work so regressions can compare before/after cost.
enum MaterialStorageLegacyProjection {
    struct Result {
        var rowCount: Int
        var metadataLookups: Int
        var containsScans: Int
        var nanoseconds: Int64
    }

    static func project(
        materials: [AccountMaterial],
        categories: [Int: MaterialCategoryMetadata],
        metadata: [Int: ItemMetadata],
        showAll: Bool,
        search: String
    ) -> Result {
        let clock = ContinuousClock.now
        var lookups = 0
        var containsScans = 0
        let sorted = categories.values.sorted { $0.order < $1.order }
        let materialsByID = Dictionary(uniqueKeysWithValues: materials.map { ($0.id, $0) })
        let uncategorized = materials.filter { material in
            !sorted.contains { category in
                containsScans += category.items.count
                return category.items.contains(material.id)
            } && (showAll || material.count > 0)
        }
        var rows = 0
        for category in sorted {
            for itemID in category.items {
                guard let material = materialsByID[itemID] else { continue }
                if !showAll && material.count <= 0 { continue }
                lookups += 1
                let item = metadata[itemID] ?? ItemPlaceholder.metadata(id: itemID)
                if !search.isEmpty && !item.name.localizedCaseInsensitiveContains(search) { continue }
                rows += 1
            }
        }
        rows += uncategorized.count
        let elapsed = ContinuousClock.now - clock
        let nanoseconds = elapsed.components.seconds * 1_000_000_000
            + elapsed.components.attoseconds / 1_000_000_000
        return Result(
            rowCount: rows, metadataLookups: lookups, containsScans: containsScans, nanoseconds: nanoseconds)
    }
}
