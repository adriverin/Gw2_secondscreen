import Foundation
import UIKit

struct DirectDetailedTileRequest: Hashable, Sendable {
    let continent: Int
    let floor: Int
    let tiles: [TileIndex]
}

struct DirectDetailedTileFrame: @unchecked Sendable {
    let request: DirectDetailedTileRequest
    let images: [TileIndex: UIImage]

    var isComplete: Bool {
        images.count == request.tiles.count && request.tiles.allSatisfy { images[$0] != nil }
    }
}

/// Loads a complete visible z7 grid. The live renderer draws the original source
/// images at their world positions; no CoreGraphics mosaic enters the map.
actor DirectDetailedTileProvider {
    static let shared = DirectDetailedTileProvider()
    static let maximumSourceTiles = 384
    static let maximumSimultaneousFetches = 6
    private let limiter = AsyncWorkLimiter(limit: maximumSimultaneousFetches)
    private let loader: @Sendable (URL) async -> UIImage?

    init(loader: @escaping @Sendable (URL) async -> UIImage? = { url in
        await MapTileImageCache.shared.image(for: url)
    }) {
        self.loader = loader
    }

    func frame(for request: DirectDetailedTileRequest) async -> DirectDetailedTileFrame? {
        let projection = ArenaNetTileProjection.shared
        let provider = ArenaNetTileProvider()
        guard !Task.isCancelled, !request.tiles.isEmpty,
              request.tiles.count <= Self.maximumSourceTiles,
              Set(request.tiles).count == request.tiles.count,
              request.tiles.allSatisfy({
                  $0.zoom == 7 && projection.tileWorldRect(for: $0, continentID: request.continent) != nil
              }) else { return nil }
        let loader = loader
        let limiter = limiter
        var images: [TileIndex: UIImage] = [:]
        await withTaskGroup(of: LoadedTile.self) { group in
            for tile in request.tiles {
                guard let url = provider.tileURL(
                    continent: request.continent, floor: request.floor,
                    zoom: tile.zoom, x: tile.x, y: tile.y) else { return }
                group.addTask {
                    await limiter.acquire()
                    guard !Task.isCancelled else {
                        await limiter.release()
                        return LoadedTile(tile: tile, image: nil)
                    }
                    let image = await loader(url)
                    await limiter.release()
                    let valid = image?.cgImage?.width == 256 && image?.cgImage?.height == 256
                    return LoadedTile(tile: tile, image: Task.isCancelled || !valid ? nil : image)
                }
            }
            for await tile in group {
                if let image = tile.image { images[tile.tile] = image }
                else { group.cancelAll() }
            }
        }
        let frame = DirectDetailedTileFrame(request: request, images: images)
        return !Task.isCancelled && frame.isComplete ? frame : nil
    }

    private struct LoadedTile: @unchecked Sendable {
        let tile: TileIndex
        let image: UIImage?
    }
}

enum DirectDetailedTileLayout {
    static func screenSide(displayZoom: Int, magnification: Double = 1) -> Double {
        256 / pow(2, Double(7 - displayZoom)) * magnification
    }
}
