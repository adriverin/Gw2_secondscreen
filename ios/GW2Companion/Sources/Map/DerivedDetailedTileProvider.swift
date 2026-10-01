import CoreGraphics
import CryptoKit
import Foundation
import UIKit

struct DerivedDetailedTileRequest: Hashable, Sendable {
    static let projectionVersion = "current-continent-z7-recursive-2x2-v3"

    let continent: Int
    let floor: Int
    let displayTile: TileIndex
    let sourceZoom: Int
    var projectionVersion: String = Self.projectionVersion

    var cacheKey: String {
        [
            "continent-\(continent)", "floor-\(floor)",
            "display-z\(displayTile.zoom)-x\(displayTile.x)-y\(displayTile.y)",
            "source-z\(sourceZoom)", "projection-\(projectionVersion)"
        ].joined(separator: "_")
    }

    var sourceTileCount: Int {
        let factor = 1 << max(0, sourceZoom - displayTile.zoom)
        return factor * factor
    }

    func sourceTiles(projection: ArenaNetTileProjection = .shared) -> [TileIndex]? {
        let delta = sourceZoom - displayTile.zoom
        guard delta > 0, delta <= 2 else { return nil }
        let factor = 1 << delta
        var result: [TileIndex] = []
        result.reserveCapacity(factor * factor)
        for row in 0..<factor {
            for column in 0..<factor {
                let child = TileIndex(
                    zoom: sourceZoom,
                    x: displayTile.x * factor + column,
                    y: displayTile.y * factor + row)
                // A partial edge tile must never cause an out-of-range source request.
                guard projection.tileWorldRect(for: child, continentID: continent) != nil else { return nil }
                result.append(child)
            }
        }
        return result
    }

    func pyramidChildren(projection: ArenaNetTileProjection = .shared) -> [TileIndex]? {
        guard (4...6).contains(displayTile.zoom), sourceZoom == 7, continent == 1 else { return nil }
        let children = (0..<4).map { index in
            TileIndex(zoom: displayTile.zoom + 1, x: displayTile.x * 2 + index % 2,
                      y: displayTile.y * 2 + index / 2)
        }
        return children.allSatisfy { projection.tileWorldRect(for: $0, continentID: continent) != nil } ? children : nil
    }
}

enum DerivedTileCacheState: String, Sendable {
    case memoryHit = "memory hit"
    case diskHit = "disk hit"
    case generated = "cache miss / generated"
}

struct DerivedTileDiagnostics: Sendable {
    let request: DerivedDetailedTileRequest
    let sourceTileCount: Int
    let cacheState: DerivedTileCacheState
    let generationMilliseconds: Int
    let imageMemoryBytes: Int
}

struct DerivedDetailedTileResult: @unchecked Sendable {
    let image: UIImage
    let diagnostics: DerivedTileDiagnostics
}

actor AsyncWorkLimiter {
    private var permits: Int
    private let limit: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
        permits = max(1, limit)
    }

    func acquire() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            permits = min(limit, permits + 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}

actor DerivedDetailedTileProvider {
    typealias SourceLoader = @Sendable (URL) async -> UIImage?

    static let shared = DerivedDetailedTileProvider()
    static let maximumSimultaneousSourceFetches = 6
    static let maximumDerivedGenerationTasks = 2
    static let memoryCountLimit = 32
    static let memoryCostLimit = 12 * 1_024 * 1_024
    // A 48-parent z4 viewport needs up to 48 × (1 + 4 + 16) =
    // 1008 derived nodes. Preserve that reusable pyramid, not just its leaves.
    static let diskFileLimit = 1_024

    private var memory = BoundedMemoryCache<DerivedDetailedTileRequest, UIImage>(
        countLimit: memoryCountLimit, totalCostLimit: memoryCostLimit)
    private var inFlight: [DerivedDetailedTileRequest: Task<DerivedDetailedTileResult?, Never>] = [:]
    private var consumers: [DerivedDetailedTileRequest: Set<UUID>] = [:]
    private let sourceLoader: SourceLoader
    private let tileProvider: MapTileProvider
    private let projection: ArenaNetTileProjection
    private let directory: URL
    private let sourceLimiter = AsyncWorkLimiter(limit: maximumSimultaneousSourceFetches)
    private let generationLimiter = AsyncWorkLimiter(limit: maximumDerivedGenerationTasks)

    init(
        directory: URL? = nil,
        projection: ArenaNetTileProjection = .shared,
        tileProvider: MapTileProvider = ArenaNetTileProvider(),
        sourceLoader: SourceLoader? = nil
    ) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = directory
            ?? caches.appending(path: "GW2DerivedMapTiles-v3", directoryHint: .isDirectory)
        self.projection = projection
        self.tileProvider = tileProvider
        self.sourceLoader = sourceLoader ?? { url in
            await MapTileImageCache.shared.image(for: url)
        }
    }

    func image(for request: DerivedDetailedTileRequest) async -> DerivedDetailedTileResult? {
        guard !Task.isCancelled, (4...6).contains(request.displayTile.zoom),
              request.sourceZoom == projection.configuration(continentID: request.continent).referenceZoom,
              let sourceTiles = request.pyramidChildren(projection: projection)
        else { return nil }

        let byteCost = Int(ArenaNetTileProjection.tileSize * ArenaNetTileProjection.tileSize * 4)
        if let cached = memory.value(for: request) {
            return DerivedDetailedTileResult(
                image: cached,
                diagnostics: DerivedTileDiagnostics(
                    request: request, sourceTileCount: sourceTiles.count, cacheState: .memoryHit,
                    generationMilliseconds: 0, imageMemoryBytes: byteCost))
        }
        if let cached = diskImage(for: request) {
            memory.set(cached, for: request, cost: byteCost)
            return DerivedDetailedTileResult(
                image: cached,
                diagnostics: DerivedTileDiagnostics(
                    request: request, sourceTileCount: sourceTiles.count, cacheState: .diskHit,
                    generationMilliseconds: 0, imageMemoryBytes: byteCost))
        }
        let consumer = UUID()
        consumers[request, default: []].insert(consumer)
        let task: Task<DerivedDetailedTileResult?, Never>
        if let existing = inFlight[request] { task = existing }
        else {
            task = Task { await self.generate(request, sourceTiles: sourceTiles, byteCost: byteCost) }
            inFlight[request] = task
        }
        let result = await withTaskCancellationHandler { await task.value } onCancel: {
            Task { await self.releaseConsumer(consumer, request: request) }
        }
        releaseConsumer(consumer, request: request)
        if let result, !Task.isCancelled {
            memory.set(result.image, for: request, cost: byteCost)
        }
        return Task.isCancelled ? nil : result
    }

    private func releaseConsumer(_ consumer: UUID, request: DerivedDetailedTileRequest) {
        guard consumers[request]?.remove(consumer) != nil else { return }
        if consumers[request]?.isEmpty == true {
            inFlight[request]?.cancel()
            inFlight[request] = nil
            consumers[request] = nil
        }
    }

    func cancel(_ request: DerivedDetailedTileRequest) {
        inFlight[request]?.cancel()
        inFlight[request] = nil
    }

    func handleMemoryPressure() {
        memory.removeAll()
    }

    private func generate(
        _ request: DerivedDetailedTileRequest,
        sourceTiles: [TileIndex],
        byteCost: Int
    ) async -> DerivedDetailedTileResult? {
        guard !Task.isCancelled else { return nil }
        let started = ContinuousClock.now
        let urls = sourceTiles.compactMap { tile in
            tileProvider.tileURL(
                continent: request.continent, floor: request.floor,
                zoom: tile.zoom, x: tile.x, y: tile.y)
        }
        guard urls.count == sourceTiles.count else {
            return nil
        }

        let loader = sourceLoader
        let limiter = sourceLimiter
        var loaded = Array<UIImage?>(repeating: nil, count: urls.count)
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    if sourceTiles[index].zoom < request.sourceZoom {
                        let child = DerivedDetailedTileRequest(continent: request.continent, floor: request.floor,
                                                               displayTile: sourceTiles[index], sourceZoom: request.sourceZoom,
                                                               projectionVersion: request.projectionVersion)
                        return (index, await self.image(for: child)?.image)
                    }
                    await limiter.acquire()
                    if Task.isCancelled {
                        await limiter.release()
                        return (index, nil)
                    }
                    let image = await loader(url)
                    await limiter.release()
                    return (index, Task.isCancelled ? nil : image)
                }
            }
            for await (index, image) in group {
                loaded[index] = image
            }
        }
        guard !Task.isCancelled, loaded.allSatisfy({ $0 != nil }) else { return nil }
        // Never hold a generation permit while awaiting recursively generated
        // children: doing so would deadlock the two-permit pyramid.
        await generationLimiter.acquire()
        guard !Task.isCancelled,
              let image = Self.composite(loaded.compactMap { $0 }, sourceCount: 4)
        else {
            await generationLimiter.release()
            return nil
        }

        let elapsed = started.duration(to: .now)
        let components = elapsed.components
        let milliseconds = max(0, Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000))
        persist(image, for: request)
        await generationLimiter.release()
        return DerivedDetailedTileResult(
            image: image,
            diagnostics: DerivedTileDiagnostics(
                request: request, sourceTileCount: sourceTiles.count, cacheState: .generated,
                generationMilliseconds: milliseconds, imageMemoryBytes: byteCost))
    }

    /// Every live pyramid level uses four immediate children. Child rows have a
    /// top-left origin, while an untransformed CGContext has a bottom-left origin.
    /// Position rows explicitly, keeping each CGImage upright, then resize once.
    static func composite(_ images: [UIImage], sourceCount: Int) -> UIImage? {
        let factor = Int(Double(sourceCount).squareRoot())
        guard [2, 4].contains(factor), factor * factor == sourceCount,
              images.count == sourceCount,
              images.allSatisfy({ $0.cgImage?.width == 256 && $0.cgImage?.height == 256 }),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: factor * 256, height: factor * 256, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .none
        for (index, image) in images.enumerated() {
            guard let cgImage = image.cgImage else { return nil }
            let column = index % factor
            let row = index / factor
            context.draw(cgImage, in: CGRect(
                x: column * 256, y: (factor - 1 - row) * 256,
                width: 256, height: 256))
        }
        guard let canvas = context.makeImage(), let resized = CGContext(
            data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        resized.interpolationQuality = .high
        resized.draw(canvas, in: CGRect(x: 0, y: 0, width: 256, height: 256))
        guard let output = resized.makeImage() else { return nil }
        return UIImage(cgImage: output, scale: 1, orientation: .up)
    }

    private func diskImage(for request: DerivedDetailedTileRequest) -> UIImage? {
        let file = diskURL(for: request)
        guard let data = try? Data(contentsOf: file), let image = UIImage(data: data) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return image
    }

    private func persist(_ image: UIImage, for request: DerivedDetailedTileRequest) {
        guard let data = image.pngData() else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: diskURL(for: request), options: .atomic)
        DiskCachePruner.prune(directory: directory, maxFiles: Self.diskFileLimit)
    }

    private func diskURL(for request: DerivedDetailedTileRequest) -> URL {
        let digest = SHA256.hash(data: Data(request.cacheKey.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: digest + ".png")
    }
}

enum MapImageDifference {
    /// A small QA-only metric. Zero means pixel-identical; larger values mean the
    /// native lower-zoom artwork and the derived source are measurably different.
    static func meanAbsoluteRGBDelta(_ lhs: UIImage, _ rhs: UIImage) -> Double? {
        guard let left = rgba64(lhs), let right = rgba64(rhs), left.count == right.count else { return nil }
        var total: UInt64 = 0
        var samples: UInt64 = 0
        for index in stride(from: 0, to: left.count, by: 4) {
            total += UInt64(abs(Int(left[index]) - Int(right[index])))
            total += UInt64(abs(Int(left[index + 1]) - Int(right[index + 1])))
            total += UInt64(abs(Int(left[index + 2]) - Int(right[index + 2])))
            samples += 3
        }
        guard samples > 0 else { return nil }
        return Double(total) / Double(samples) / 255.0 * 100.0
    }

    private static func rgba64(_ image: UIImage) -> [UInt8]? {
        guard let cgImage = image.cgImage,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 64 * 64 * 4)
        let created = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 64, height: 64, bitsPerComponent: 8,
                bytesPerRow: 64 * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 64, height: 64))
            return true
        }
        return created ? bytes : nil
    }
}
