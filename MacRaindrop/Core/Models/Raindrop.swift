import Foundation

/// A single bookmark, as returned by `GET /rest/v1/raindrops/{collectionId}`.
nonisolated struct Raindrop: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    var link: String
    var title: String
    var excerpt: String
    var note: String
    var type: Kind
    var cover: String
    var media: [Media]
    var tags: [String]
    var highlights: [Highlight]
    var important: Bool
    var removed: Bool
    var broken: Bool
    var domain: String
    var collectionID: Int
    /// Manual ordering inside a collection.
    var sort: Int
    var cache: Cache?
    var reminder: Reminder?
    var created: Date
    var lastUpdate: Date

    var url: URL? { URL(string: link) }
    var isInTrash: Bool { removed || collectionID == SystemCollectionID.trash }
    var coverURL: URL? { cover.isEmpty ? nil : URL(string: cover) }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case collectionID = "collectionId"
        case link, title, excerpt, note, type, cover, media, tags, highlights
        case important, removed, broken, domain, sort, cache, reminder, created, lastUpdate
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        link = try c.decode(String.self, forKey: .link)
        title = try c.decode(String.self, forKey: .title)
        excerpt = try c.decodeIfPresent(String.self, forKey: .excerpt) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        type = try c.decodeIfPresent(Kind.self, forKey: .type) ?? .link
        cover = try c.decodeIfPresent(String.self, forKey: .cover) ?? ""
        media = try c.decodeIfPresent([Media].self, forKey: .media) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        highlights = try c.decodeIfPresent([Highlight].self, forKey: .highlights) ?? []
        // The API omits these flags entirely when they were never set.
        important = try c.decodeIfPresent(Bool.self, forKey: .important) ?? false
        removed = try c.decodeIfPresent(Bool.self, forKey: .removed) ?? false
        broken = try c.decodeIfPresent(Bool.self, forKey: .broken) ?? false
        domain = try c.decodeIfPresent(String.self, forKey: .domain) ?? ""
        collectionID = try c.decodeIfPresent(Int.self, forKey: .collectionID) ?? SystemCollectionID.unsorted
        sort = try c.decodeIfPresent(Int.self, forKey: .sort) ?? 0
        cache = try c.decodeIfPresent(Cache.self, forKey: .cache)
        reminder = try c.decodeIfPresent(Reminder.self, forKey: .reminder)
        created = try c.decode(Date.self, forKey: .created)
        lastUpdate = try c.decode(Date.self, forKey: .lastUpdate)
    }

    enum Kind: String, Codable, Sendable, CaseIterable {
        case link, article, image, video, document, audio

        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .link
        }
    }

    struct Media: Hashable, Codable, Sendable {
        var link: String
        var type: String
    }

    struct Highlight: Identifiable, Hashable, Codable, Sendable {
        let id: String
        var text: String
        var note: String
        var color: String
        var created: Date
        var lastUpdate: Date

        enum CodingKeys: String, CodingKey {
            case id = "_id"
            case text, note, color, created, lastUpdate
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            text = try c.decode(String.self, forKey: .text)
            note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
            // Omitted for highlights left at the default color.
            color = try c.decodeIfPresent(String.self, forKey: .color) ?? "yellow"
            created = try c.decode(Date.self, forKey: .created)
            lastUpdate = try c.decode(Date.self, forKey: .lastUpdate)
        }
    }

    struct Cache: Hashable, Codable, Sendable {
        /// `ready`, `retry`, `failed`, `invalid-origin`, `invalid-timeout`, `invalid-size`.
        var status: String
        var size: Int?
        var created: Date?
    }

    struct Reminder: Hashable, Codable, Sendable {
        var date: Date?
    }
}
