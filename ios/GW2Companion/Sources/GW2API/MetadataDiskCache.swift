import Foundation

actor MetadataDiskCache {
    private let directory: URL

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.directory = directory ?? base.appending(path: "GW2CompanionMetadata", directoryHint: .isDirectory)
    }

    func load<Value: Decodable & Sendable>(_ type: Value.Type, named name: String) -> Value? {
        let url = directory.appending(path: safeName(name))
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func save<Value: Encodable & Sendable>(_ value: Value, named name: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(value)
            try data.write(to: directory.appending(path: safeName(name)), options: .atomic)
        } catch {
            // A cache miss is harmless; callers still retain their in-memory value.
        }
    }

    private func safeName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "_").appending(".json")
    }
}
