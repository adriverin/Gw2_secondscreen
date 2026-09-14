import CoreGraphics
import Foundation

/// Current ArenaNet continent coordinates.
/// Mumble telemetry, official POIs, gathering, and navigation all live in this space.
/// Origin is northwest; X increases east; Y increases south.
struct ContinentCoordinate: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
}

typealias ContinentPoint = ContinentCoordinate

/// Pixel space of official tile artwork at the projection's reference zoom.
/// Distinct from `ContinentCoordinate` so current API coordinates cannot be
/// fed to the tile service without an explicit projection step.
struct TileWorldCoordinate: Hashable, Sendable {
    var x: Double
    var y: Double
}

struct TileIndex: Hashable, Sendable {
    var zoom: Int
    var x: Int
    var y: Int
}

/// Historical End of Dragons continent expansion.
/// Current Tyria X/Y = legacy X/Y + these deltas.
/// Official `tiles.guildwars2.com` Tyria imagery now uses current continent space,
/// so this shift must not be applied at the tile boundary unless a projection
/// explicitly opts into the legacy tile origin.
enum EndOfDragonsShift {
    static let deltaX = 32_768.0
    static let deltaY = 16_384.0

    static func current(fromLegacy x: Double, y: Double) -> ContinentCoordinate {
        ContinentCoordinate(x: x + deltaX, y: y + deltaY)
    }

    static func legacy(fromCurrent x: Double, y: Double) -> TileWorldCoordinate {
        TileWorldCoordinate(x: x - deltaX, y: y - deltaY)
    }
}

struct TileProjectionConfiguration: Equatable, Sendable {
    var continentID: Int
    /// Zoom at which one tile-world unit equals one tile pixel for the official imagery.
    /// This is independent of `/v2/continents.max_zoom`.
    var referenceZoom: Int
    /// Advertised continent size, used only as an upper bound on tile indices.
    var continentWidth: Double
    var continentHeight: Double
    /// When true, subtract the EoD shift to reach stale pre-expansion tile space.
    var usesLegacyTileOrigin: Bool
    /// Current-continent rectangle where official painted artwork is known to exist.
    /// Maps whose `continent_rect` does not intersect this area get a neutral background.
    var paintedContinentRect: CGRect?
    /// API-advertised maximum zoom. Diagnostic only; not the tile projection basis.
    var advertisedMaxZoom: Int
}

protocol TileCoordinateProjection: Sendable {
    func configuration(continentID: Int) -> TileProjectionConfiguration
    func tileWorldCoordinate(
        from continentCoordinate: ContinentCoordinate,
        continentID: Int,
        mapFloor: Int
    ) -> TileWorldCoordinate?
    func continentCoordinate(
        from tileWorld: TileWorldCoordinate,
        continentID: Int,
        mapFloor: Int
    ) -> ContinentCoordinate?
    func tileIndex(
        from tileWorld: TileWorldCoordinate,
        zoom: Int,
        continentID: Int
    ) -> TileIndex?
    func tileWorldRect(for index: TileIndex, continentID: Int) -> CGRect?
    func tiles(
        coveringContinentRect rect: CGRect,
        zoom: Int,
        continentID: Int,
        mapFloor: Int
    ) -> [TileIndex]
    func worldUnitsPerTilePixel(zoom: Int, continentID: Int) -> Double
    func mapHasPaintedArtwork(_ metadata: GW2MapMetadata) -> Bool
}

struct ArenaNetTileProjection: TileCoordinateProjection {
    static let shared = ArenaNetTileProjection()
    static let tileSize = 256.0

    func configuration(continentID: Int) -> TileProjectionConfiguration {
        switch continentID {
        case 1:
            // Empirically, tiles.guildwars2.com Tyria imagery is 1:1 with current
            // continent coordinates at zoom 7. Zoom 8 URLs 404. The EoD origin
            // shift is already baked into those tiles; do not subtract it.
            return TileProjectionConfiguration(
                continentID: 1,
                referenceZoom: 7,
                continentWidth: 81_920,
                continentHeight: 114_688,
                usesLegacyTileOrigin: false,
                paintedContinentRect: CGRect(x: 28_672, y: 14_336, width: 40_960, height: 40_960),
                advertisedMaxZoom: 8)
        case 2:
            return TileProjectionConfiguration(
                continentID: 2,
                referenceZoom: 6,
                continentWidth: 16_384,
                continentHeight: 16_384,
                usesLegacyTileOrigin: false,
                paintedContinentRect: CGRect(x: 0, y: 0, width: 16_384, height: 16_384),
                advertisedMaxZoom: 6)
        default:
            return TileProjectionConfiguration(
                continentID: continentID,
                referenceZoom: 6,
                continentWidth: 32_768,
                continentHeight: 32_768,
                usesLegacyTileOrigin: false,
                paintedContinentRect: nil,
                advertisedMaxZoom: 6)
        }
    }

    func tileWorldCoordinate(
        from continentCoordinate: ContinentCoordinate,
        continentID: Int,
        mapFloor: Int
    ) -> TileWorldCoordinate? {
        let config = configuration(continentID: continentID)
        if config.usesLegacyTileOrigin {
            return EndOfDragonsShift.legacy(fromCurrent: continentCoordinate.x, y: continentCoordinate.y)
        }
        return TileWorldCoordinate(x: continentCoordinate.x, y: continentCoordinate.y)
    }

    func continentCoordinate(
        from tileWorld: TileWorldCoordinate,
        continentID: Int,
        mapFloor: Int
    ) -> ContinentCoordinate? {
        let config = configuration(continentID: continentID)
        if config.usesLegacyTileOrigin {
            return EndOfDragonsShift.current(fromLegacy: tileWorld.x, y: tileWorld.y)
        }
        return ContinentCoordinate(x: tileWorld.x, y: tileWorld.y)
    }

    func worldUnitsPerTilePixel(zoom: Int, continentID: Int) -> Double {
        let reference = configuration(continentID: continentID).referenceZoom
        let clamped = min(max(zoom, 0), reference)
        return pow(2.0, Double(reference - clamped))
    }

    func tileIndex(
        from tileWorld: TileWorldCoordinate,
        zoom: Int,
        continentID: Int
    ) -> TileIndex? {
        let config = configuration(continentID: continentID)
        guard (0...config.referenceZoom).contains(zoom),
              tileWorld.x.isFinite, tileWorld.y.isFinite else { return nil }
        let scale = worldUnitsPerTilePixel(zoom: zoom, continentID: continentID)
        let pixelX = tileWorld.x / scale
        let pixelY = tileWorld.y / scale
        let x = Int(Foundation.floor(pixelX / Self.tileSize))
        let y = Int(Foundation.floor(pixelY / Self.tileSize))
        // Never wrap. Indices outside the grid are simply absent.
        guard x >= 0, y >= 0 else { return nil }
        let grid = tileGridSize(zoom: zoom, config: config)
        guard x < grid.width, y < grid.height else { return nil }
        return TileIndex(zoom: zoom, x: x, y: y)
    }

    func tileWorldRect(for index: TileIndex, continentID: Int) -> CGRect? {
        let config = configuration(continentID: continentID)
        guard (0...config.referenceZoom).contains(index.zoom),
              index.x >= 0, index.y >= 0 else { return nil }
        let grid = tileGridSize(zoom: index.zoom, config: config)
        guard index.x < grid.width, index.y < grid.height else { return nil }
        let scale = worldUnitsPerTilePixel(zoom: index.zoom, continentID: continentID)
        let size = Self.tileSize * scale
        return CGRect(
            x: Double(index.x) * size,
            y: Double(index.y) * size,
            width: size,
            height: size)
    }

    func tiles(
        coveringContinentRect rect: CGRect,
        zoom: Int,
        continentID: Int,
        mapFloor: Int
    ) -> [TileIndex] {
        let config = configuration(continentID: continentID)
        guard (0...config.referenceZoom).contains(zoom),
              rect.width >= 0, rect.height >= 0,
              let northWest = tileWorldCoordinate(
                from: ContinentCoordinate(x: rect.minX, y: rect.minY),
                continentID: continentID, mapFloor: mapFloor),
              let southEast = tileWorldCoordinate(
                from: ContinentCoordinate(x: rect.maxX, y: rect.maxY),
                continentID: continentID, mapFloor: mapFloor)
        else { return [] }

        let scale = worldUnitsPerTilePixel(zoom: zoom, continentID: continentID)
        let minTileX = Int(Foundation.floor(northWest.x / scale / Self.tileSize))
        let maxTileX = Int(Foundation.floor((southEast.x - .ulpOfOne) / scale / Self.tileSize))
        let minTileY = Int(Foundation.floor(northWest.y / scale / Self.tileSize))
        let maxTileY = Int(Foundation.floor((southEast.y - .ulpOfOne) / scale / Self.tileSize))
        let grid = tileGridSize(zoom: zoom, config: config)
        let xStart = max(0, minTileX)
        let xEnd = min(grid.width - 1, maxTileX)
        let yStart = max(0, minTileY)
        let yEnd = min(grid.height - 1, maxTileY)
        guard xStart <= xEnd, yStart <= yEnd else { return [] }

        var result: [TileIndex] = []
        result.reserveCapacity((xEnd - xStart + 1) * (yEnd - yStart + 1))
        for y in yStart...yEnd {
            for x in xStart...xEnd {
                result.append(TileIndex(zoom: zoom, x: x, y: y))
            }
        }
        return result
    }

    func mapHasPaintedArtwork(_ metadata: GW2MapMetadata) -> Bool {
        let config = configuration(continentID: metadata.continentId)
        guard let painted = config.paintedContinentRect else { return true }
        guard let mapRect = metadata.continentBounds else { return false }
        return mapRect.intersects(painted)
    }

    func pixelInTile(from tileWorld: TileWorldCoordinate, zoom: Int, continentID: Int) -> CGPoint? {
        guard tileIndex(from: tileWorld, zoom: zoom, continentID: continentID) != nil else { return nil }
        let scale = worldUnitsPerTilePixel(zoom: zoom, continentID: continentID)
        let pixelX = tileWorld.x / scale
        let pixelY = tileWorld.y / scale
        return CGPoint(
            x: pixelX - Foundation.floor(pixelX / Self.tileSize) * Self.tileSize,
            y: pixelY - Foundation.floor(pixelY / Self.tileSize) * Self.tileSize)
    }

    private func tileGridSize(zoom: Int, config: TileProjectionConfiguration) -> (width: Int, height: Int) {
        let scale = pow(2.0, Double(config.referenceZoom - zoom))
        return (
            max(0, Int(ceil(config.continentWidth / Self.tileSize / scale))),
            max(0, Int(ceil(config.continentHeight / Self.tileSize / scale))))
    }
}

extension GW2MapMetadata {
    var continentBounds: CGRect? {
        guard continentRect.count == 2, continentRect.allSatisfy({ $0.count == 2 }) else { return nil }
        let minX = min(continentRect[0][0], continentRect[1][0])
        let minY = min(continentRect[0][1], continentRect[1][1])
        return CGRect(
            x: minX, y: minY,
            width: abs(continentRect[1][0] - continentRect[0][0]),
            height: abs(continentRect[1][1] - continentRect[0][1]))
    }

    var continentCenter: ContinentCoordinate? {
        guard let bounds = continentBounds else { return nil }
        return ContinentCoordinate(x: bounds.midX, y: bounds.midY)
    }
}
