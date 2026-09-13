import CryptoKit
import Foundation
import SwiftUI
import UIKit

actor MapIconDataCache {
    typealias Fetcher = @Sendable (URL) async throws -> Data

    private let directory: URL
    private let fetcher: Fetcher
    private var inFlight: [URL: Task<Data, Error>] = [:]

    init(directory: URL? = nil, fetcher: @escaping Fetcher = MapIconDataCache.download) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GW2MapIcons-v1", isDirectory: true)
        self.fetcher = fetcher
    }

    func data(for url: URL) async throws -> Data {
        let file = fileURL(for: url)
        if let cached = try? Data(contentsOf: file), !cached.isEmpty { return cached }
        if let existing = inFlight[url] { return try await existing.value }

        let task = Task { try await fetcher(url) }
        inFlight[url] = task
        do {
            let data = try await task.value
            inFlight[url] = nil
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            return data
        } catch {
            inFlight[url] = nil
            throw error
        }
    }

    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined() + ".png"
        return directory.appendingPathComponent(name)
    }

    static func download(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode, !data.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

@MainActor
final class MapIconStore: ObservableObject {
    static let shared = MapIconStore()

    @Published private(set) var images: [URL: Image] = [:]
    private let cache: MapIconDataCache

    init(cache: MapIconDataCache = MapIconDataCache()) {
        self.cache = cache
    }

    func load(_ urls: Set<URL>) async {
        let missing = urls.filter { images[$0] == nil }
        guard !missing.isEmpty else { return }
        let cache = self.cache
        let decoded = await withTaskGroup(of: (URL, Data?).self, returning: [(URL, Data)].self) { group in
            for url in missing {
                group.addTask { (url, try? await cache.data(for: url)) }
            }
            var result: [(URL, Data)] = []
            for await (url, data) in group {
                if let data { result.append((url, data)) }
            }
            return result
        }

        var updated = images
        for (url, data) in decoded {
            if let image = UIImage(data: data) { updated[url] = Image(uiImage: image) }
        }
        if updated.count != images.count { images = updated }
    }
}
