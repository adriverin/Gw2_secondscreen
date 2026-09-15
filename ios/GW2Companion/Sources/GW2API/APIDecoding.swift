import Foundation

enum JSONValue: Decodable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .null
        }
    }
}

struct LossyDecodableArray<Element: Decodable & Sendable>: Decodable, Sendable {
    let values: [Element]
    let failedCount: Int
    let failures: [String]

    init(values: [Element], failedCount: Int = 0, failures: [String] = []) {
        self.values = values
        self.failedCount = failedCount
        self.failures = failures
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [Element] = []
        var failures: [String] = []
        var index = 0
        while !container.isAtEnd {
            let start = container.currentIndex
            do {
                values.append(try container.decode(Element.self))
            } catch {
                if container.currentIndex == start {
                    _ = try? container.decode(JSONValue.self)
                }
                failures.append("[\(index)] \(DecodeErrorPath.describe(error))")
            }
            index += 1
        }
        self.values = values
        self.failedCount = failures.count
        self.failures = failures
    }
}

struct SparseNullableArray<Element: Decodable & Sendable>: Decodable, Sendable {
    let values: [Element?]

    init(values: [Element?]) { self.values = values }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [Element?] = []
        while !container.isAtEnd {
            let start = container.currentIndex
            if (try? container.decodeNil()) == true {
                values.append(nil)
            } else if let value = try? container.decode(Element.self) {
                values.append(value)
            } else {
                if container.currentIndex == start {
                    _ = try? container.decode(JSONValue.self)
                }
                values.append(nil)
            }
        }
        self.values = values
    }
}

enum DecodeErrorPath {
    static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else {
            return "decode failed"
        }
        switch decoding {
        case let .typeMismatch(type, context):
            return "typeMismatch \(type) at \(codingPath(context))"
        case let .valueNotFound(type, context):
            return "valueNotFound \(type) at \(codingPath(context))"
        case let .keyNotFound(key, context):
            return "keyNotFound \(key.stringValue) at \(codingPath(context))"
        case let .dataCorrupted(context):
            return "dataCorrupted at \(codingPath(context)): \(context.debugDescription)"
        @unknown default:
            return "decode failed"
        }
    }

    static func codingPath(_ context: DecodingError.Context) -> String {
        let path = context.codingPath.map { key in
            key.intValue.map { "[\($0)]" } ?? key.stringValue
        }.joined(separator: ".")
        return path.isEmpty ? "(root)" : path
    }
}

extension KeyedDecodingContainer {
    func decodeFlexibleURL(forKey key: Key) -> URL? {
        if let url = try? decodeIfPresent(URL.self, forKey: key) { return url }
        guard let string = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        return URL(string: string)
    }

    func decodeCompactInts(forKey key: Key) -> [Int]? {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return nil }
        guard let values = try? decode([OptionalIntValue].self, forKey: key) else {
            return try? decodeIfPresent([Int].self, forKey: key)
        }
        return values.compactMap(\.value)
    }

    func decodeLossyArray<T: Decodable & Sendable>(_ type: T.Type, forKey key: Key) -> [T] {
        (try? decodeIfPresent(LossyDecodableArray<T>.self, forKey: key))?.values ?? []
    }

    func decodeDefault<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? defaultValue
    }
}

private struct OptionalIntValue: Decodable {
    let value: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else {
            value = try? container.decode(Int.self)
        }
    }
}

enum ItemPlaceholder {
    static func metadata(id: Int, name: String? = nil) -> ItemMetadata {
        ItemMetadata(
            id: id, name: name ?? "Item \(id)", icon: nil, rarity: "Unknown",
            description: "Metadata for this item has not loaded yet.", type: nil, level: nil,
            flags: nil, restrictions: nil, details: nil)
    }
}
