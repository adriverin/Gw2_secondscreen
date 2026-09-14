import Foundation

struct MapPoint: Equatable, Sendable {
    let x: Double
    let y: Double
}

struct TilePoint: Equatable, Sendable {
    let tileX: Int
    let tileY: Int
    let pixelX: Double
    let pixelY: Double
}

enum CoordinateTransformError: Error { case invalidRectangle }

struct GW2CoordinateTransformer: Sendable {
    /// Tile imagery reference zoom for Tyria. Independent of `/v2/continents.max_zoom`.
    static var tileReferenceZoom: Int {
        ArenaNetTileProjection.shared.configuration(continentID: 1).referenceZoom
    }

    @available(*, deprecated, renamed: "tileReferenceZoom", message: "API continent max_zoom is not the tile projection basis.")
    static var maximumTileZoom: Int { tileReferenceZoom }

    let metadata: GW2MapMetadata
    private let projection: ArenaNetTileProjection

    init(metadata: GW2MapMetadata, projection: ArenaNetTileProjection = .shared) {
        self.metadata = metadata
        self.projection = projection
    }

    func mapPoint(from continent: ContinentPoint) throws -> MapPoint {
        let rectangles = try validatedRectangles()
        let nx = (continent.x - rectangles.c0.x) / (rectangles.c1.x - rectangles.c0.x)
        let ny = (continent.y - rectangles.c0.y) / (rectangles.c1.y - rectangles.c0.y)
        return MapPoint(
            x: rectangles.m0.x + nx * (rectangles.m1.x - rectangles.m0.x),
            y: rectangles.m0.y + (1 - ny) * (rectangles.m1.y - rectangles.m0.y))
    }

    func continentPoint(from map: MapPoint) throws -> ContinentPoint {
        let rectangles = try validatedRectangles()
        let nx = (map.x - rectangles.m0.x) / (rectangles.m1.x - rectangles.m0.x)
        let ny = 1 - (map.y - rectangles.m0.y) / (rectangles.m1.y - rectangles.m0.y)
        return ContinentPoint(
            x: rectangles.c0.x + nx * (rectangles.c1.x - rectangles.c0.x),
            y: rectangles.c0.y + ny * (rectangles.c1.y - rectangles.c0.y))
    }

    func continentPoint(worldX: Double, worldZ: Double) throws -> ContinentPoint {
        let metersToInches = 39.370_078_740_157_48
        return try continentPoint(from: MapPoint(
            x: worldX * metersToInches,
            y: -worldZ * metersToInches))
    }

    func tileWorldCoordinate(from continent: ContinentPoint) -> TileWorldCoordinate? {
        projection.tileWorldCoordinate(
            from: continent, continentID: metadata.continentId, mapFloor: metadata.defaultFloor)
    }

    func tilePoint(from continent: ContinentPoint, zoom: Int) -> TilePoint {
        guard let tileWorld = tileWorldCoordinate(from: continent),
              let index = projection.tileIndex(
                from: tileWorld, zoom: zoom, continentID: metadata.continentId),
              let pixel = projection.pixelInTile(
                from: tileWorld, zoom: zoom, continentID: metadata.continentId)
        else {
            return TilePoint(tileX: -1, tileY: -1, pixelX: 0, pixelY: 0)
        }
        return TilePoint(tileX: index.x, tileY: index.y, pixelX: pixel.x, pixelY: pixel.y)
    }

    private func validatedRectangles() throws -> (m0: MapPoint, m1: MapPoint, c0: ContinentPoint, c1: ContinentPoint) {
        guard metadata.mapRect.count == 2, metadata.continentRect.count == 2,
              metadata.mapRect.allSatisfy({ $0.count == 2 }), metadata.continentRect.allSatisfy({ $0.count == 2 }) else {
            throw CoordinateTransformError.invalidRectangle
        }
        let m0 = MapPoint(x: metadata.mapRect[0][0], y: metadata.mapRect[0][1])
        let m1 = MapPoint(x: metadata.mapRect[1][0], y: metadata.mapRect[1][1])
        let c0 = ContinentPoint(x: metadata.continentRect[0][0], y: metadata.continentRect[0][1])
        let c1 = ContinentPoint(x: metadata.continentRect[1][0], y: metadata.continentRect[1][1])
        guard m0.x != m1.x, m0.y != m1.y, c0.x != c1.x, c0.y != c1.y else {
            throw CoordinateTransformError.invalidRectangle
        }
        return (m0, m1, c0, c1)
    }
}
