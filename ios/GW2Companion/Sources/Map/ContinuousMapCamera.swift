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

/// Scheduling only: this never changes the camera, raster selection or handoff.
struct MapSourcePrefetchPolicy {
    static let prefetchThreshold = 0.10
    static let reversalThreshold = 0.08
    private(set) var direction = 0
    private var extreme: Double?
    private var requestedFrom: Int?
    private(set) var nextSource: Int?

    mutating func reset() { self = Self() }

    mutating func update(from previous: Double, to camera: Double, currentSource: Int) {
        if extreme == nil { extreme = previous }
        let anchor = extreme ?? previous
        if direction == 0 {
            if abs(camera - anchor) >= 0.04 { direction = camera > anchor ? 1 : -1; extreme = camera }
        } else if Double(direction) * (camera - anchor) >= 0 {
            extreme = camera
        } else if abs(camera - anchor) >= Self.reversalThreshold {
            direction = -direction
            extreme = camera
            nextSource = nil
            requestedFrom = nil
        }
        if requestedFrom != currentSource { nextSource = nil; requestedFrom = currentSource }
        // Once latched, threshold jitter doesn't repeatedly restart requests.
        if nextSource == nil, direction != 0,
           Double(direction) * (camera - Double(currentSource)) >= Self.prefetchThreshold - 0.000001 {
            let target = currentSource + direction
            if (4...6).contains(target) { nextSource = target }
        }
    }

    func request(transform: MapViewportTransform, currentSource: Int, continent: Int, floor: Int) -> MapRasterLayerRequest? {
        guard let nextSource, abs(nextSource - currentSource) == 1 else { return nil }
        var predicted = transform
        // Warm coverage at the unchanged promotion boundary, not merely the
        // smaller viewport at prefetch start. Outward promotion is strict <.
        predicted.cameraZoom = Double(currentSource) + Double(direction) * (ContinuousMapCamera.sourceThreshold + 0.001)
        let tiles = ArenaNetTileProjection.shared.tiles(coveringContinentRect: predicted.visibleContinentRect(),
                                                       zoom: nextSource, continentID: continent, mapFloor: floor)
        let request = MapRasterLayerRequest(continent: continent, floor: floor, tiles: tiles, detailed: true)
        return request.permitsDetailed ? request : nil
    }
}

struct MapRasterLayerRequest: Hashable, Sendable {
    let continent: Int
    let floor: Int
    let tiles: [TileIndex]
    let detailed: Bool

    /// Small, retained native mosaic beneath viewport frames. Unlike an old
    /// viewport crop it still covers newly exposed geography during a pinch.
    static func backing(continent: Int, floor: Int) -> Self {
        let projection = ArenaNetTileProjection.shared
        let config = projection.configuration(continentID: continent)
        let rect = config.paintedContinentRect
            ?? CGRect(x: 0, y: 0, width: config.continentWidth, height: config.continentHeight)
        return Self(continent: continent, floor: floor,
                    tiles: projection.tiles(coveringContinentRect: rect, zoom: 0, continentID: continent, mapFloor: floor),
                    detailed: false)
    }

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
    private(set) var pending: MapRasterLayerRequest?

    func activeOpacity(progress: Double) -> Double { outgoing == nil ? 1 : min(1, max(0, progress)) }
    func outgoingOpacity(progress: Double) -> Double { 1 - min(1, max(0, progress)) }

    mutating func begin(_ request: MapRasterLayerRequest) {
        pending = request
        // An interrupted fade's incoming frame is already complete. Retain it
        // at full opacity, not the half-faded composition of two old viewports.
        outgoing = nil
    }

    mutating func accept(_ frame: MapRasterLayerFrame, for target: MapRasterLayerRequest? = nil) -> Bool {
        guard frame.isComplete else { return false }
        if let pending {
            guard (target ?? frame.request) == pending,
                  frame.request.continent == pending.continent, frame.request.floor == pending.floor,
                  frame.request.tiles == pending.tiles else { return false }
        }
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
    private static let speculativeLimiter = AsyncWorkLimiter(limit: 1)

    /// Cache-only, one parent at a time. No visual frame is published; foreground
    /// requests keep the other parent permit and take precedence over warm work.
    static func prefetch(_ request: MapRasterLayerRequest,
                         nativeLoader: @escaping @Sendable (URL) async -> UIImage? = { await MapTileImageCache.shared.image(for: $0) },
                         derivedLoader: @escaping @Sendable (DerivedDetailedTileRequest) async -> UIImage? = { await DerivedDetailedTileProvider.shared.image(for: $0)?.image }) async {
#if DEBUG
        // The handoff stress fixture paints synthetic frames; speculative work
        // must not escape that fixture and issue real artwork requests.
        if ProcessInfo.processInfo.arguments.contains("--map-handoff-regression") { return }
#endif
        guard !Task.isCancelled, !request.tiles.isEmpty, request.tiles.count <= MapRasterLayerRequest.maximumParentTiles,
              !request.detailed || request.permitsDetailed,
              await speculativeLimiter.tryAcquire() else { return }
        for tile in request.tiles {
            guard !Task.isCancelled, await parentLimiter.tryAcquire() else { break }
            if request.detailed {
                _ = await derivedLoader(DerivedDetailedTileRequest(continent: request.continent, floor: request.floor, displayTile: tile, sourceZoom: 7))
            } else if let url = ArenaNetTileProvider().tileURL(continent: request.continent, floor: request.floor, zoom: tile.zoom, x: tile.x, y: tile.y) {
                _ = await nativeLoader(url)
            }
            await parentLimiter.release()
        }
        await speculativeLimiter.release()
    }
    static func retryingNativeFrame(for request: MapRasterLayerRequest) async -> MapRasterLayerFrame? {
        while !Task.isCancelled {
            if let frame = await frame(for: request) { return frame }
            do { try await Task.sleep(for: .seconds(1)) } catch { return nil }
        }
        return nil
    }
    static func frame(for request: MapRasterLayerRequest,
                      nativeLoader: @escaping @Sendable (URL) async -> UIImage? = { await MapTileImageCache.shared.image(for: $0) },
                      derivedLoader: @escaping @Sendable (DerivedDetailedTileRequest) async -> UIImage? = { await DerivedDetailedTileProvider.shared.image(for: $0)?.image }) async -> MapRasterLayerFrame? {
        guard !request.tiles.isEmpty, request.tiles.count <= 96, !request.detailed || request.permitsDetailed else { return nil }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--map-handoff-regression") {
            // Deterministic UI stress fixture: slow incoming frames and a failed
            // z4 Detailed build. Production always uses the real loaders below.
            do { try await Task.sleep(for: .milliseconds(request.detailed ? 450 : 180)) } catch { return nil }
            if request.detailed && request.tiles.first?.zoom == 4 { return nil }
            let image = await MainActor.run {
                let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).image { context in
                    (request.detailed ? UIColor.systemMint : UIColor.systemCyan).setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
                }
            }
            guard !Task.isCancelled else { return nil }
            return MapRasterLayerFrame(request: request, images: Dictionary(uniqueKeysWithValues: request.tiles.map { ($0, image) }))
        }
#endif
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
