import CryptoKit
import Foundation
import os
import UIKit

actor MapTileImageCache {
    static let shared = MapTileImageCache()
    static let memoryCountLimit = 48
    static let memoryCostLimit = 32 * 1_024 * 1_024
    static let diskFileLimit = 512

    private var memory = BoundedMemoryCache<URL, UIImage>(
        countLimit: memoryCountLimit, totalCostLimit: memoryCostLimit)
    private struct Flight {
        let id: UUID
        let task: Task<UIImage?, Never>
        var consumers: Set<UUID>
    }
    private var inFlight: [URL: Flight] = [:]
    private let session: URLSession
    private let directory: URL
    private let countState = OSAllocatedUnfairLock(initialState: 0)
    nonisolated var memoryCount: Int { countState.withLock { $0 } }

    init(session: URLSession? = nil, directory: URL? = nil) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = directory ?? caches.appending(path: "GW2MapTiles-v1", directoryHint: .isDirectory)
        if let session {
            self.session = session
        } else {
            let cache = URLCache(
                memoryCapacity: 8 * 1_024 * 1_024,
                diskCapacity: 48 * 1_024 * 1_024,
                directory: self.directory.appending(path: "urlcache", directoryHint: .isDirectory))
            let configuration = URLSessionConfiguration.default
            configuration.urlCache = cache
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            self.session = URLSession(configuration: configuration)
        }
    }

    func image(for url: URL) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        if let cached = memory.value(for: url) { return cached }
        let consumer = UUID()
        let flight: Flight
        if var existing = inFlight[url] {
            existing.consumers.insert(consumer)
            inFlight[url] = existing
            flight = existing
        } else {
            flight = Flight(id: UUID(), task: Task { await download(url) }, consumers: [consumer])
            inFlight[url] = flight
        }
        let image = await withTaskCancellationHandler {
            await flight.task.value
        } onCancel: {
            Task { await self.cancelConsumer(consumer, url: url, flightID: flight.id) }
        }
        if inFlight[url]?.id == flight.id { inFlight[url] = nil }
        guard !Task.isCancelled else { return nil }
        if let image {
            memory.set(image, for: url, cost: Int(image.size.width * image.size.height * 4))
            let count = memory.count
            countState.withLock { $0 = count }
        }
        return image
    }

    private func cancelConsumer(_ consumer: UUID, url: URL, flightID: UUID) {
        guard var flight = inFlight[url], flight.id == flightID else { return }
        flight.consumers.remove(consumer)
        if flight.consumers.isEmpty {
            flight.task.cancel()
            inFlight[url] = nil
        } else { inFlight[url] = flight }
    }

    func handleMemoryPressure() {
        memory.removeAll()
        countState.withLock { $0 = 0 }
    }

    func evictOffscreen(keeping urls: Set<URL>) {
        for key in memory.keys where !urls.contains(key) {
            memory.remove(key)
        }
        let count = memory.count
        countState.withLock { $0 = count }
    }

    private func download(_ url: URL) async -> UIImage? {
        let file = directory.appending(path: Self.hash(url.absoluteString))
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            return image
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard !Task.isCancelled, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data) else { return nil }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            DiskCachePruner.prune(directory: directory, maxFiles: Self.diskFileLimit)
            return image
        } catch {
            return nil
        }
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
