import Foundation

struct BoundedMemoryCache<Key: Hashable, Value> {
    var countLimit: Int
    var totalCostLimit: Int

    private var items: [Key: (value: Value, cost: Int)] = [:]
    private var order: [Key] = []
    private var totalCost = 0

    init(countLimit: Int, totalCostLimit: Int = .max) {
        self.countLimit = countLimit
        self.totalCostLimit = totalCostLimit
    }

    var count: Int { items.count }
    var cost: Int { totalCost }
    var keys: [Key] { order }

    subscript(key: Key) -> Value? { items[key]?.value }

    mutating func value(for key: Key) -> Value? {
        guard let item = items[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return item.value
    }

    mutating func set(_ value: Value, for key: Key, cost: Int = 1) {
        remove(key)
        items[key] = (value, cost)
        order.append(key)
        totalCost += max(0, cost)
        trim()
    }

    mutating func remove(_ key: Key) {
        guard let item = items.removeValue(forKey: key) else { return }
        order.removeAll { $0 == key }
        totalCost = max(0, totalCost - item.cost)
    }

    mutating func removeAll() {
        items.removeAll()
        order.removeAll()
        totalCost = 0
    }

    private mutating func trim() {
        while count > countLimit || totalCost > totalCostLimit, let oldest = order.first {
            remove(oldest)
        }
    }
}

enum DiskCachePruner {
    static func prune(directory: URL, maxFiles: Int, fileManager: FileManager = .default) {
        guard maxFiles > 0,
              let files = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles])
        else { return }
        guard files.count > maxFiles else { return }
        let sorted = files.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }
        for url in sorted.prefix(files.count - maxFiles) {
            try? fileManager.removeItem(at: url)
        }
    }
}
