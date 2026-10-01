import XCTest
import UIKit
@testable import GW2Companion

@MainActor
final class PhaseSixHMapTests: XCTestCase {
    func testExactKessexChildFormulaAndFourByFourOrder() throws {
        let request = DerivedDetailedTileRequest(continent: 1, floor: 1,
            displayTile: TileIndex(zoom: 6, x: 87, y: 61), sourceZoom: 7)
        XCTAssertEqual(request.sourceTiles(), [
            TileIndex(zoom: 7, x: 174, y: 122), TileIndex(zoom: 7, x: 175, y: 122),
            TileIndex(zoom: 7, x: 174, y: 123), TileIndex(zoom: 7, x: 175, y: 123)])
        let four = DerivedDetailedTileRequest(continent: 1, floor: 1,
            displayTile: TileIndex(zoom: 5, x: 43, y: 30), sourceZoom: 7)
        let children = try XCTUnwrap(four.sourceTiles())
        for i in 0..<16 {
            XCTAssertEqual(children[i], TileIndex(zoom: 7, x: 172 + i % 4, y: 120 + i / 4))
        }
    }

    func testTwoByTwoQuadrantsAndUprightChildContents() throws {
        let colors: [UIColor] = [.red, .green, .blue, .yellow]
        let children = colors.enumerated().map { directionalTile(color: $0.element, label: $0.offset) }
        let output = try XCTUnwrap(DerivedDetailedTileProvider.composite(children, sourceCount: 4))
        let expected = reference(children, columns: 2)
        // Every pixel, including asymmetric north/south arrows and text. A solid
        // color quadrant test alone would miss a per-child CoreGraphics Y flip.
        assertPixels(output, expected, tolerance: 3)
        for i in 0..<4 {
            assertPixel(output, x: (i % 2) * 128 + 64, y: (i / 2) * 128 + 64,
                        equals: children[i], x: 128, y: 128)
        }
    }

    func testFourByFourNumberedDirectionalPlacement() throws {
        let children = (0..<16).map {
            directionalTile(color: UIColor(hue: CGFloat($0) / 16, saturation: 0.8, brightness: 0.9, alpha: 1), label: $0)
        }
        let output = try XCTUnwrap(DerivedDetailedTileProvider.composite(children, sourceCount: 16))
        assertPixels(output, reference(children, columns: 4), tolerance: 3)
        for i in 0..<16 {
            assertPixel(output, x: (i % 4) * 64 + 32, y: (i / 4) * 64 + 32,
                        equals: children[i], x: 128, y: 128)
        }
    }

    func testFormerContextFlipReproducesInvertedChildContents() throws {
        let children = [UIColor.red, .green, .blue, .yellow].enumerated().map {
            directionalTile(color: $0.element, label: $0.offset)
        }
        let context = try XCTUnwrap(CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8,
            bytesPerRow: 1024, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: 256)
        context.scaleBy(x: 1, y: -1) // Exact former implementation.
        for (i, image) in children.enumerated() {
            context.draw(image.cgImage!, in: CGRect(x: (i % 2) * 128, y: (i / 2) * 128, width: 128, height: 128))
        }
        let old = pixels(UIImage(cgImage: try XCTUnwrap(context.makeImage())))
        let repaired = pixels(try XCTUnwrap(DerivedDetailedTileProvider.composite(children, sourceCount: 4)))
        let marker = (8 * 256 + 8) * 4
        XCTAssertEqual(Array(old[marker..<marker + 3]), [0, 0, 0], "Southern black marker is incorrectly drawn in the north")
        XCTAssertEqual(Array(repaired[marker..<marker + 3]), [255, 255, 255], "Northern white marker remains north")
    }

    func testKessexEveryChildBoundaryAndNeighboringHorizontalVerticalEdges() throws {
        let a = try kessex(x: 174, y: 122)
        let b = try kessex(x: 176, y: 122)
        let c = try kessex(x: 174, y: 124)
        let parents = try [a, b, c].map { try XCTUnwrap(DerivedDetailedTileProvider.composite($0, sourceCount: 4)) }
        for (images, parent) in zip([a, b, c], parents) {
            let golden = reference(images, columns: 2)
            assertPixels(parent, golden, tolerance: 3)
            // Compare actual geographic pixels on BOTH sides of every seam,
            // not a mean A/B difference or an assumption that edges are identical.
            assertPixels(parent, golden, region: CGRect(x: 124, y: 0, width: 8, height: 256), tolerance: 3)
            assertPixels(parent, golden, region: CGRect(x: 0, y: 124, width: 256, height: 8), tolerance: 3)
        }
        // Each native/overzoom tile is independently filtered at its edge. Use
        // independent upright golden parents, not a larger resampling kernel
        // spanning parents (which changes legitimate border pixel colors).
        let horizontal = join(reference(a, columns: 2), reference(b, columns: 2), horizontal: true)
        let vertical = join(reference(a, columns: 2), reference(c, columns: 2), horizontal: false)
        let joinedH = join(parents[0], parents[1], horizontal: true)
        let joinedV = join(parents[0], parents[2], horizontal: false)
        for x in 252...259 {
            assertPixels(joinedH, horizontal, region: CGRect(x: x, y: 0, width: 1, height: 256), tolerance: 3)
        }
        for y in 252...259 {
            assertPixels(joinedV, vertical, region: CGRect(x: 0, y: y, width: 256, height: 1), tolerance: 3)
        }
    }

    func testNoPartialCompositeAndDirectFrameAtomicity() async throws {
        let child = directionalTile(color: .red, label: 0)
        XCTAssertNil(DerivedDetailedTileProvider.composite([child, child, child], sourceCount: 4))
        let tiles = try XCTUnwrap(DerivedDetailedTileRequest(continent: 1, floor: 1,
            displayTile: TileIndex(zoom: 6, x: 87, y: 61), sourceZoom: 7).sourceTiles())
        let request = DirectDetailedTileRequest(continent: 1, floor: 1, tiles: tiles)
        let success = DirectDetailedTileProvider(loader: { _ in child })
        let frame = await success.frame(for: request)
        XCTAssertTrue(frame?.isComplete == true)
        let failed = DirectDetailedTileProvider(loader: { url in
            url.path.contains("/175/123") ? nil : child
        })
        let missing = await failed.frame(for: request)
        XCTAssertNil(missing, "One missing child must retain the whole native frame")
        XCTAssertFalse(DirectDetailedTileFrame(request: request, images: [tiles[0]: child]).isComplete)
        let oversized = DirectDetailedTileRequest(continent: 1, floor: 1,
            tiles: (0...DirectDetailedTileProvider.maximumSourceTiles).map { TileIndex(zoom: 7, x: $0 % 200, y: $0 / 200) })
        let rejected = await success.frame(for: oversized)
        XCTAssertNil(rejected)
    }

    func testRapidPanCancellationDoesNotPublishStaleOrPartialFrame() async throws {
        let child = directionalTile(color: .red, label: 0)
        let provider = DirectDetailedTileProvider(loader: { _ in
            try? await Task.sleep(for: .milliseconds(30))
            return child
        })
        let old = DirectDetailedTileRequest(continent: 1, floor: 1,
            tiles: (0..<64).map { TileIndex(zoom: 7, x: 174 + $0 % 8, y: 122 + $0 / 8) })
        let task = Task { await provider.frame(for: old) }
        await Task.yield()
        task.cancel()
        let cancelled = await task.value
        XCTAssertNil(cancelled)
        let next = DirectDetailedTileRequest(continent: 1, floor: 1, tiles: [TileIndex(zoom: 7, x: 180, y: 124)])
        let nextFrame = await provider.frame(for: next)
        XCTAssertEqual(nextFrame?.request, next)
        XCTAssertTrue(nextFrame?.isComplete == true)
    }

    func testDirectTileScaleAndExtremeZoomFallback() {
        XCTAssertEqual(DirectDetailedTileLayout.screenSide(displayZoom: 7), 256)
        XCTAssertEqual(DirectDetailedTileLayout.screenSide(displayZoom: 6), 128)
        XCTAssertEqual(DirectDetailedTileLayout.screenSide(displayZoom: 5), 64)
        XCTAssertEqual(MapRasterDetail.renderingSource(displayZoom: 4, continentID: 1,
            mode: .detailed, visibleDisplayTileCount: 1), .native(zoom: 4))
        XCTAssertEqual(MapRasterDetail.renderingSource(displayZoom: 5, continentID: 1,
            mode: .detailed, visibleDisplayTileCount: 100), .native(zoom: 5))
    }

    func testNeighborSourceWorldPositionsTouchWithoutChangingProjection() throws {
        let projection = ArenaNetTileProjection.shared
        let a = try XCTUnwrap(projection.tileWorldRect(for: TileIndex(zoom: 7, x: 175, y: 123), continentID: 1))
        let east = try XCTUnwrap(projection.tileWorldRect(for: TileIndex(zoom: 7, x: 176, y: 123), continentID: 1))
        let south = try XCTUnwrap(projection.tileWorldRect(for: TileIndex(zoom: 7, x: 175, y: 124), continentID: 1))
        XCTAssertEqual(a.maxX, east.minX)
        XCTAssertEqual(a.maxY, south.minY)
        for zoom in [5, 6] {
            let transform = MapViewportTransform(center: ContinentPoint(x: a.midX, y: a.midY), zoom: zoom,
                magnification: 1, dragOffset: .zero, size: CGSize(width: 1024, height: 768), tileReferenceZoom: 7)
            let center = transform.screenPosition(for: ContinentPoint(x: a.midX, y: a.midY))
            let right = transform.screenPosition(for: ContinentPoint(x: east.midX, y: east.midY))
            let bottom = transform.screenPosition(for: ContinentPoint(x: south.midX, y: south.midY))
            let side = DirectDetailedTileLayout.screenSide(displayZoom: zoom)
            XCTAssertEqual(right.x - center.x, side, accuracy: 0.001)
            XCTAssertEqual(bottom.y - center.y, side, accuracy: 0.001)
        }
    }

    private func directionalTile(color: UIColor, label: Int) -> UIImage {
        renderer(size: CGSize(width: 256, height: 256)).image { _ in
            color.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 256, height: 256))
            UIColor.white.setFill(); UIRectFill(CGRect(x: 8, y: 8, width: 240, height: 24))
            UIColor.black.setFill(); UIRectFill(CGRect(x: 8, y: 216, width: 80, height: 32))
            ("N ↑ \(label)" as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: [.foregroundColor: UIColor.black])
        }
    }

    private func kessex(x: Int, y: Int) throws -> [UIImage] {
        try [(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)].map { x, y in
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "kessex-z7-\(x)-\(y)", withExtension: "jpg"))
            return try XCTUnwrap(UIImage(contentsOfFile: url.path))
        }
    }

    private func renderer(size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    /// Independent top-left UIKit implementation; no CGContext transform or child row inversion.
    private func reference(_ children: [UIImage], columns: Int, rows: Int? = nil) -> UIImage {
        let rows = rows ?? columns
        let canvas = renderer(size: CGSize(width: columns * 256, height: rows * 256)).image { _ in
            for (i, child) in children.enumerated() {
                child.draw(in: CGRect(x: (i % columns) * 256, y: (i / columns) * 256, width: 256, height: 256))
            }
        }
        let outputSize = columns == rows ? CGSize(width: 256, height: 256)
            : CGSize(width: columns * 128, height: rows * 128)
        return renderer(size: outputSize).image { context in
            context.cgContext.interpolationQuality = .high
            canvas.draw(in: CGRect(origin: .zero, size: outputSize))
        }
    }

    private func join(_ a: UIImage, _ b: UIImage, horizontal: Bool) -> UIImage {
        // Copy exact parent pixels; a second UIKit draw can color-convert/filter
        // them and would test that conversion instead of geography at the seam.
        let width = horizontal ? 512 : 256, height = horizontal ? 256 : 512
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .none
        context.draw(a.cgImage!, in: CGRect(x: 0, y: horizontal ? 0 : 256, width: 256, height: 256))
        context.draw(b.cgImage!, in: CGRect(x: horizontal ? 256 : 0, y: 0, width: 256, height: 256))
        return UIImage(cgImage: context.makeImage()!)
    }

    private func pixels(_ image: UIImage) -> [UInt8] {
        let cg = image.cgImage!
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        return bytes
    }

    private func assertPixels(_ actual: UIImage, _ expected: UIImage, region: CGRect? = nil, tolerance: Int,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.size, expected.size, file: file, line: line)
        let a = pixels(actual), b = pixels(expected), width = actual.cgImage!.width
        guard a.count == b.count else { return }
        let r = region ?? CGRect(origin: .zero, size: actual.size)
        for y in Int(r.minY)..<Int(r.maxY) {
            for x in Int(r.minX)..<Int(r.maxX) {
                for channel in 0..<3 {
                    let i = (y * width + x) * 4 + channel
                    if abs(Int(a[i]) - Int(b[i])) > tolerance {
                        XCTFail("Geographic pixel mismatch at (\(x),\(y)) channel \(channel): \(a[i]) vs \(b[i])", file: file, line: line)
                        return
                    }
                }
            }
        }
    }

    private func assertPixel(_ a: UIImage, x: Int, y: Int, equals b: UIImage, x bx: Int, y by: Int) {
        let pa = pixels(a), pb = pixels(b)
        for c in 0..<3 { XCTAssertEqual(pa[(y * a.cgImage!.width + x) * 4 + c], pb[(by * b.cgImage!.width + bx) * 4 + c]) }
    }
}

final class PhaseSixHStatTests: XCTestCase {
    let warrior = GW2Character(name: "Flashonder", race: "Human", gender: "Male", profession: "Warrior", level: 80, age: 1)

    func testRealDefaultAPIEmptySuffixDoesNotDiscardInfixOrDefense() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "phase6h-items-default", withExtension: "json"))
        let items = try JSONDecoder().decode([ItemMetadata].self, from: Data(contentsOf: url))
        let coat = try XCTUnwrap(items.first { $0.id == 48199 })
        XCTAssertEqual(coat.name, "Wei Qi's Breastplate")
        XCTAssertEqual(coat.details?.defense, 381)
        XCTAssertNil(coat.details?.secondarySuffixItemID)
        let stats = CharacterStatEngine.calculate(character: warrior,
            equipment: [CharacterEquipment(itemID: coat.id, slot: "Coat")], items: [coat.id: coat])
        XCTAssertEqual(stats.total(for: "Power"), 1101)
        XCTAssertEqual(stats.total(for: "Toughness"), 1101)
        XCTAssertEqual(stats.total(for: "Vitality"), 1141)
        XCTAssertEqual(stats.defense.total, 381)
        XCTAssertEqual(stats.equipmentSources[0].sources[1].state, .fallback)
        XCTAssertNotNil(items.first { $0.id == 30704 }?.details?.statChoices)
    }

    func testAllEquipmentKindsSelectedAuthoritativeWithoutDoubleCounting() {
        let slots = ["Coat", "Helm", "Backpack", "Amulet", "WeaponA1", "Ring1"]
        let types = ["Armor", "Armor", "Back", "Trinket", "Weapon", "Trinket"]
        var items: [Int: ItemMetadata] = [:]
        let equipment = slots.enumerated().map { i, slot in
            items[i] = ItemMetadata(id: i, name: "Fixture \(slot)", icon: nil,
                rarity: i == 1 ? "Legendary" : "Ascended", type: types[i],
                details: ItemDetails(defense: i < 2 ? 100 : nil,
                    infixUpgrade: InfixUpgrade(id: 1, attributes: [ItemAttribute(attribute: "Power", modifier: 999)], buff: nil),
                    statChoices: [1, 2]))
            return CharacterEquipment(itemID: i, slot: slot, stats: SelectedItemStats(id: 2, attributes: ["Power": 10 + i]))
        }
        let stats = CharacterStatEngine.calculate(character: warrior, equipment: equipment, items: items)
        XCTAssertEqual(stats.total(for: "Power"), 1075)
        XCTAssertTrue(stats.equipmentSources.allSatisfy { $0.sources[0].state == .used && $0.sources[1].state == .ignored })
    }

    func testCentralizedArenaNetAttributeNormalization() {
        for (api, canonical) in ["Power": "Power", "Precision": "Precision", "Toughness": "Toughness",
            "Vitality": "Vitality", "CritDamage": "Ferocity", "ConditionDamage": "ConditionDamage",
            "Condition Damage": "ConditionDamage", "ConditionDuration": "Expertise",
            "BoonDuration": "Concentration", "Healing": "HealingPower"] {
            XCTAssertEqual(CharacterStatEngine.canonicalAttribute(api), canonical)
        }
    }

    func testTabScopedHydrationCannotCopyAnotherLegendaryPrefix() {
        let empty = CharacterEquipment(itemID: 30704, slot: "WeaponA1", stats: SelectedItemStats(id: 1, attributes: nil))
        var one = CharacterEquipment(itemID: 30704, slot: "WeaponA1", stats: SelectedItemStats(id: 1, attributes: ["Power": 100]))
        one.tabs = [1]
        var two = CharacterEquipment(itemID: 30704, slot: "WeaponA1", stats: SelectedItemStats(id: 2, attributes: ["Vitality": 200]))
        two.tabs = [2]
        let tabs = EquipmentStatInputResolver.hydratedTabs([
            EquipmentTab(tab: 1, name: "One", isActive: true, equipment: [empty]),
            EquipmentTab(tab: 2, name: "Two", isActive: false, equipment: [empty])],
            from: CharacterEquipmentResponse(equipment: [one, two]))
        XCTAssertEqual(tabs[0].equipment[0].stats?.attributes, ["Power": 100])
        XCTAssertNil(tabs[1].equipment[0].stats?.attributes)
        let stats = CharacterStatEngine.calculate(character: warrior, equipment: tabs[0].equipment, items: [:])
        XCTAssertEqual(stats.total(for: "Power"), 1100)
        XCTAssertEqual(stats.total(for: "Vitality"), 1000)
    }

    func testTerrestrialOnlySixRunesAlternateWeaponsAndDuplicateSlotsIgnored() {
        let slots = ["Helm", "Shoulders", "Coat", "Gloves", "Leggings", "Boots", "HelmAquatic", "WeaponB1", "Unknown", "Helm"]
        let equipment = slots.enumerated().map { i, slot in
            CharacterEquipment(itemID: i, slot: slot, upgrades: [24836], stats: SelectedItemStats(id: 1, attributes: ["Power": 10]))
        }
        let rune = ItemMetadata(id: 24836, name: "Superior Rune of the Scholar", icon: nil, rarity: "Exotic",
            type: "UpgradeComponent", details: ItemDetails(type: "Rune"))
        let stats = CharacterStatEngine.calculate(character: warrior, equipment: equipment, items: [rune.id: rune])
        XCTAssertEqual(stats.attributes["Power"]?.equipment, 60)
        XCTAssertEqual(stats.attributes["Power"]?.runes, 175)
        XCTAssertEqual(stats.equipmentSources.filter(\.included).count, 6)
        XCTAssertTrue(stats.equipmentSources.suffix(4).allSatisfy { $0.sources.allSatisfy { $0.state == .ignored } })
    }

    func testFlashonderObservedInputRegressionTotalsAndDerivedFormulas() {
        // Reconstructed regression input, NOT an account equipment dump. The
        // physical recording supplies totals, not the character's item records.
        let selected = ["Power": 873, "Precision": 170, "Toughness": 868, "Vitality": 1051,
                        "CritDamage": 260, "ConditionDamage": 73, "ConditionDuration": 49,
                        "BoonDuration": 49, "Healing": 133]
        let slots = ["Helm", "Shoulders", "Coat", "Gloves", "Leggings", "Boots"]
        let defenses = [127, 127, 381, 127, 254, 127] // 1143 armor + 116 shield = 1259
        var items: [Int: ItemMetadata] = [:]
        var equipment = slots.enumerated().map { i, slot in
            items[i] = ItemMetadata(id: i, name: "Regression \(slot)", icon: nil, rarity: "Ascended", type: "Armor",
                details: ItemDetails(type: slot, weightClass: "Heavy", defense: defenses[i]))
            return CharacterEquipment(itemID: i, slot: slot,
                stats: SelectedItemStats(id: 1, attributes: i == 2 ? selected : ["Power": 0]))
        }
        items[6] = ItemMetadata(id: 6, name: "Regression Shield", icon: nil, rarity: "Ascended", type: "Weapon",
                               details: ItemDetails(type: "Shield", defense: 116))
        equipment.append(CharacterEquipment(itemID: 6, slot: "WeaponA2", stats: SelectedItemStats(id: 1, attributes: ["Power": 0])))
        let result = CharacterStatEngine.calculate(character: warrior, equipment: equipment, items: items)
        for (key, expected) in ["Power": 1873, "Precision": 1170, "Toughness": 1868, "Vitality": 2051,
                                "Ferocity": 260, "ConditionDamage": 73, "Expertise": 49, "Concentration": 49, "HealingPower": 133] {
            XCTAssertEqual(result.total(for: key), expected, key)
        }
        XCTAssertEqual(result.defense.armorPieces, 1143)
        XCTAssertEqual(result.defense.shield, 116)
        XCTAssertEqual(result.defense.total, 1259)
        XCTAssertEqual(result.derived.armor, 3127)
        XCTAssertEqual(result.derived.health, 29722)
        XCTAssertEqual(result.derived.criticalDamagePercent!, 167.333333, accuracy: 0.0001)
        XCTAssertEqual(result.derived.boonDurationPercent!, 3.266666, accuracy: 0.0001)
        XCTAssertEqual(result.derived.conditionDurationPercent!, 3.266666, accuracy: 0.0001)
        XCTAssertEqual(result.derived.criticalChanceFromPrecision!, 13.095238, accuracy: 0.0001)
        XCTAssertEqual(18.09 - result.derived.criticalChancePercent!, 4.994762, accuracy: 0.0001)
        XCTAssertEqual(result.derived.criticalChanceBuildModifier, 0, "Do not fabricate the unexplained approximately 5%")
        XCTAssertEqual(result.coverage, .partial)
    }

    func testDifferenceParsingAndEditableRoundTripForEveryStatRow() throws {
        XCTAssertEqual(StatAuditNumber.difference(calculated: 1024, observed: 1873), -849)
        let german = Locale(identifier: "de_DE")
        XCTAssertEqual(StatAuditNumber.parse("1.873", fractional: false, locale: german), 1873)
        for locale in [german, Locale(identifier: "en_US"), Locale(identifier: "de_CH")] {
            for value in [1873.0, 29722, 18.09, 3.26] {
                let editable = StatAuditNumber.editable(value, locale: locale)
                XCTAssertEqual(try XCTUnwrap(StatAuditNumber.parse(editable, fractional: true, locale: locale)), value, accuracy: 0.0001)
            }
        }
        XCTAssertNil(StatAuditNumber.parse("1.873", fractional: false, locale: Locale(identifier: "en_US")), "Do not silently treat a whole attribute as 1.873")
        for (calculated, observed) in [(1024.0, 1873.0), (1024, 1170), (19452, 29722), (6.1, 18.09), (0, 3.26)] {
            XCTAssertEqual(StatAuditNumber.difference(calculated: calculated, observed: observed), calculated - observed)
        }
    }

    func testPriceArrivesBeforeMetadataNeverLeaksRawItemID() {
        let placeholder = ItemPlaceholder.metadata(id: 29185)
        XCTAssertEqual(PriceItemHeader.title(item: placeholder, loading: true), "Loading item details…")
        XCTAssertEqual(PriceItemHeader.title(item: placeholder, loading: false), "Item details unavailable")
        let dusk = ItemMetadata(id: 29185, name: "Dusk", icon: nil, rarity: "Exotic", type: "Weapon")
        XCTAssertEqual(PriceItemHeader.title(item: dusk, loading: false), "Dusk")
    }

    func testLegacyDiskMetadataIsRefetchedRatherThanPermanentlyMissingStats() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "phase6h-cache-\(UUID().uuidString)")
        let cache = MetadataDiskCache(directory: directory)
        await cache.save([48199: ItemMetadata(id: 48199, name: "Wei Qi's Breastplate", icon: nil,
            rarity: "Ascended", type: "Armor", details: nil)], named: "items")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PhaseSixHItemProtocol.self]
        let api = GW2APIClient(session: URLSession(configuration: configuration),
            credentials: CredentialStore(secureStore: InMemorySecureStore()), diskCache: cache)
        let restored = try await api.items(ids: [48199], priority: .high)
        XCTAssertEqual(restored[48199]?.details?.defense, 381)
        XCTAssertEqual(restored[48199]?.details?.infixUpgrade?.attributes.count, 3)
        let persisted = await cache.load([Int: ItemMetadata].self, named: "items")
        XCTAssertEqual(persisted?[48199]?.details?.defense, 381)
    }

    func testFullEndpointSelectedAttributesHydrateMissingTemplateStatsButNeverOverrideThem() throws {
        let json = Data(#"{"equipment":[{"id":30704,"slot":"WeaponA1","tabs":[1],"location":"EquippedFromLegendaryArmory","stats":{"id":161,"attributes":{"Power":239,"CritDamage":171}}}]}"#.utf8)
        let response = try JSONDecoder().decode(CharacterEquipmentResponse.self, from: json)
        let empty = CharacterEquipment(itemID: 30704, slot: "WeaponA1", stats: SelectedItemStats(id: 161, attributes: nil))
        let selected = CharacterEquipment(itemID: 30704, slot: "WeaponA1", stats: SelectedItemStats(id: 161, attributes: ["Vitality": 300]))
        let hydrated = EquipmentStatInputResolver.hydratedTabs([
            EquipmentTab(tab: 1, name: "One", isActive: true, equipment: [empty]),
            EquipmentTab(tab: 2, name: "Two", isActive: false, equipment: [selected])], from: response)
        XCTAssertEqual(hydrated[0].equipment[0].stats?.attributes, ["Power": 239, "CritDamage": 171])
        XCTAssertEqual(hydrated[1].equipment[0].stats?.attributes, ["Vitality": 300])
        let stats = CharacterStatEngine.calculate(character: warrior, equipment: hydrated[0].equipment, items: [:])
        XCTAssertEqual(stats.total(for: "Power"), 1239)
        XCTAssertEqual(stats.total(for: "Ferocity"), 171)
        XCTAssertEqual(stats.equipmentSources[0].sources[0].state, .used)
    }
}

private final class PhaseSixHItemProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
              let fixture = Bundle(for: PhaseSixHStatTests.self).url(forResource: "phase6h-items-default", withExtension: "json"),
              let data = try? Data(contentsOf: fixture) else { return }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
