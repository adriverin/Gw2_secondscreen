import CoreGraphics
import Foundation
import UIKit

/// Camera state is independent of the integer raster level. All overlays share
/// this transform; source changes must never change geographical camera state.
enum ContinuousMapCamera {
    static let sourceThreshold = 0.65
    static let crossfadeSeconds = 0.15

    static func sourceZoom(cameraZoom: Double, current: Int, maximum: Int) -> Int {
        var result = min(maximum, max(2, current))
        while result < maximum && cameraZoom >= Double(result) + sourceThreshold { result += 1 }
        while result > 2 && cameraZoom < Double(result) - sourceThreshold { result -= 1 }
        return result
    }

    static func scale(cameraZoom: Double, sourceZoom: Int) -> Double {
        pow(2, cameraZoom - Double(sourceZoom))
    }

    struct Pinch {
        let startZoom: Double
        let screenAnchor: CGPoint
        let continentAnchor: ContinentPoint

        func update(magnification: Double, size: CGSize, referenceZoom: Int, movingAnchor: CGPoint? = nil) -> (zoom: Double, center: ContinentPoint) {
            let zoom = min(Double(referenceZoom), max(2, startZoom + log2(max(0.001, magnification))))
            let units = pow(2, Double(referenceZoom) - zoom)
            let anchor = movingAnchor ?? screenAnchor
            return (zoom, ContinentPoint(
                x: continentAnchor.x - (anchor.x - size.width / 2) * units,
                y: continentAnchor.y - (anchor.y - size.height / 2) * units))
        }
    }
}

struct MapRasterLayerRequest: Hashable, Sendable {
    let continent: Int
    let floor: Int
    let tiles: [TileIndex]
    let detailed: Bool

    // Upper bound on cold leaf work. A z4 parent is always built from four
    // cached z5 parents, never from a flattened 8×8 operation.
    static let maximumColdSourceTiles = 3_072
    static let maximumParentTiles = 96
    var permitsDetailed: Bool {
        guard continent == 1, let zoom = tiles.first?.zoom, (4...6).contains(zoom) else { return false }
        return !tiles.isEmpty && tiles.count <= Self.maximumParentTiles && tiles.count * (1 << (2 * (7 - zoom))) <= Self.maximumColdSourceTiles
    }
}

struct MapRasterLayerFrame: @unchecked Sendable {
    let request: MapRasterLayerRequest
    let images: [TileIndex: UIImage]
    var isComplete: Bool {
        !request.tiles.isEmpty && images.count == request.tiles.count
            && request.tiles.allSatisfy { images[$0] != nil }
    }
}

struct MapRasterLayerHandoff {
    private(set) var active: MapRasterLayerFrame?
    private(set) var outgoing: MapRasterLayerFrame?

    mutating func accept(_ frame: MapRasterLayerFrame) -> Bool {
        guard frame.isComplete else { return false }
        outgoing = active
        active = frame
        return true
    }

    mutating func finish(_ request: MapRasterLayerRequest) {
        guard active?.request == request else { return }
        outgoing = nil
    }
}

enum MapRasterLayerLoader {
    static let maximumConcurrentParents = 2
    private static let parentLimiter = AsyncWorkLimiter(limit: maximumConcurrentParents)
    static func frame(for request: MapRasterLayerRequest,
                      nativeLoader: @escaping @Sendable (URL) async -> UIImage? = { await MapTileImageCache.shared.image(for: $0) },
                      derivedLoader: @escaping @Sendable (DerivedDetailedTileRequest) async -> UIImage? = { await DerivedDetailedTileProvider.shared.image(for: $0)?.image }) async -> MapRasterLayerFrame? {
        guard !request.tiles.isEmpty, request.tiles.count <= 96, !request.detailed || request.permitsDetailed else { return nil }
        var images: [TileIndex: UIImage] = [:]
        await withTaskGroup(of: (TileIndex, UIImage?).self) { group in
            for tile in request.tiles {
                group.addTask {
                    guard !Task.isCancelled else { return (tile, nil) }
                    if request.detailed {
                        await parentLimiter.acquire()
                        guard !Task.isCancelled else { await parentLimiter.release(); return (tile, nil) }
                        let result = await derivedLoader(DerivedDetailedTileRequest(
                            continent: request.continent, floor: request.floor, displayTile: tile, sourceZoom: 7))
                        await parentLimiter.release()
                        return (tile, Task.isCancelled ? nil : result)
                    }
                    guard let url = ArenaNetTileProvider().tileURL(
                        continent: request.continent, floor: request.floor, zoom: tile.zoom, x: tile.x, y: tile.y)
                    else { return (tile, nil) }
                    return (tile, await nativeLoader(url))
                }
            }
            for await (tile, image) in group { if let image { images[tile] = image } }
        }
        let frame = MapRasterLayerFrame(request: request, images: images)
        return !Task.isCancelled && frame.isComplete ? frame : nil
    }
}
