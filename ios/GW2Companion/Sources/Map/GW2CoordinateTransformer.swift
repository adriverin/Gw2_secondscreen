import Foundation

struct ContinentPoint: Equatable, Sendable {
    let x: Double
    let y: Double
}

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
    static let maximumTileZoom = 8
    let metadata: GW2MapMetadata

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

    func tilePoint(from continent: ContinentPoint, zoom: Int) -> TilePoint {
        let clampedZoom = min(max(zoom, 0), Self.maximumTileZoom)
        let scale = pow(2.0, Double(Self.maximumTileZoom - clampedZoom))
        let px = continent.x / scale
        let py = continent.y / scale
        return TilePoint(tileX: Int(floor(px / 256)), tileY: Int(floor(py / 256)),
                         pixelX: px.truncatingRemainder(dividingBy: 256),
                         pixelY: py.truncatingRemainder(dividingBy: 256))
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
