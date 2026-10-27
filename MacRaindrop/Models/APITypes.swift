import Foundation

/// A MongoDB-style reference, e.g. `{ "$ref": "collections", "$id": 123 }`.
nonisolated struct Ref: Hashable, Codable, Sendable {
    var ref: String?
    var id: Int

    enum CodingKeys: String, CodingKey {
        case ref = "$ref"
        case id = "$id"
    }
}

/// The envelope every list endpoint returns: `{ "result": true, "items": [...], "count": n }`.
nonisolated struct ItemsResponse<Item: Decodable & Sendable>: Decodable, Sendable {
    var result: Bool
    var items: [Item]
    /// Total matching items on the server; only present on paginated endpoints.
    var count: Int?
}

/// `GET /user/stats`: per-system-collection counts plus when any bookmark last changed.
nonisolated struct LibraryStats: Decodable, Sendable, Equatable {
    /// Bumped by the server whenever any bookmark is created, edited, moved or deleted.
    var changedBookmarksDate: Date?
    /// Keyed by collection id; includes `SystemCollectionID.all`, `.unsorted` and `.trash`.
    var counts: [Int: Int]

    init(changedBookmarksDate: Date?, counts: [Int: Int]) {
        self.changedBookmarksDate = changedBookmarksDate
        self.counts = counts
    }

    private struct Count: Decodable {
        var _id: Int
        var count: Int
    }

    private struct Meta: Decodable {
        var changedBookmarksDate: Date?
    }

    private enum CodingKeys: String, CodingKey {
        case items, meta
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let items = try c.decode([Count].self, forKey: .items)
        counts = Dictionary(items.map { ($0._id, $0.count) }, uniquingKeysWith: { first, _ in first })
        changedBookmarksDate = try c.decodeIfPresent(Meta.self, forKey: .meta)?.changedBookmarksDate
    }
}

nonisolated extension DecodingError {
    /// A one-line description naming the offending field, e.g. `missing “color” at items[3].highlights[0]`.
    var summary: String {
        func path(_ codingPath: [any CodingKey]) -> String {
            codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
        }
        return switch self {
        case .keyNotFound(let key, let context): "missing “\(key.stringValue)” at \(path(context.codingPath))"
        case .valueNotFound(_, let context): "null value at \(path(context.codingPath))"
        case .typeMismatch(_, let context): "wrong type at \(path(context.codingPath))"
        case .dataCorrupted(let context): "\(context.debugDescription) at \(path(context.codingPath))"
        @unknown default: localizedDescription
        }
    }
}

nonisolated extension JSONEncoder {
    /// Mirrors `JSONDecoder.raindrop`, so cached payloads round-trip with millisecond precision.
    static var raindrop: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        return encoder
    }
}

nonisolated extension JSONDecoder {
    /// A decoder configured for Raindrop's ISO 8601 timestamps (`2026-10-26T11:27:14.807Z`).
    static var raindrop: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            if let date = try? Date(string, strategy: .iso8601) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unrecognised date: \(string)"
            ))
        }
        return decoder
    }
}

/// The envelope single-item endpoints return: `{ "result": true, "item": {...} }`.
nonisolated struct ItemResponse<Item: Decodable & Sendable>: Decodable, Sendable {
    var result: Bool
    var item: Item
}

/// What write endpoints without an item return: `{ "result": true }`, or `false` with a reason.
nonisolated struct WriteResponse: Decodable, Sendable {
    var result: Bool
    var errorMessage: String?
}
