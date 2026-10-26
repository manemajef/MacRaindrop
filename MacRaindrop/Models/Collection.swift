import Foundation

/// A Raindrop collection, as returned by `GET /rest/v1/collections` and `/collections/childrens`.
///
/// Named `RaindropCollection` to avoid shadowing Swift's `Collection` protocol.
nonisolated struct RaindropCollection: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    var title: String
    var description: String
    var isPublic: Bool
    var view: ViewStyle
    /// Server-side number of raindrops in this collection (not just the ones loaded locally).
    var count: Int
    var cover: [String]
    var color: String?
    /// Manual ordering among siblings.
    var sort: Int
    var expanded: Bool
    var parent: Ref?
    var slug: String
    var access: Access
    var created: Date
    var lastUpdate: Date
    var lastAction: Date?

    var parentID: Int? { parent?.id }
    var coverURL: URL? { cover.first.flatMap(URL.init(string:)) }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case title, description, view, count, cover, color, sort, expanded, parent, slug, access
        case created, lastUpdate, lastAction
        case isPublic = "public"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        isPublic = try c.decodeIfPresent(Bool.self, forKey: .isPublic) ?? false
        view = try c.decodeIfPresent(ViewStyle.self, forKey: .view) ?? .list
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        cover = try c.decodeIfPresent([String].self, forKey: .cover) ?? []
        color = try c.decodeIfPresent(String.self, forKey: .color)
        // `sort` comes back as null for collections that were never manually reordered.
        sort = try c.decodeIfPresent(Int.self, forKey: .sort) ?? .max
        expanded = try c.decodeIfPresent(Bool.self, forKey: .expanded) ?? false
        parent = try c.decodeIfPresent(Ref.self, forKey: .parent)
        slug = try c.decodeIfPresent(String.self, forKey: .slug) ?? ""
        access = try c.decodeIfPresent(Access.self, forKey: .access) ?? Access(level: 4, draggable: true)
        created = try c.decode(Date.self, forKey: .created)
        lastUpdate = try c.decode(Date.self, forKey: .lastUpdate)
        lastAction = try c.decodeIfPresent(Date.self, forKey: .lastAction)
    }

    enum ViewStyle: String, Codable, Sendable {
        case list, simple, grid, masonry

        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = ViewStyle(rawValue: raw) ?? .list
        }
    }

    struct Access: Hashable, Codable, Sendable {
        /// 1 = read only, 2 = collaborator (read), 3 = collaborator (write), 4 = owner.
        var level: Int
        var draggable: Bool
    }
}

/// Pseudo-collections that exist on the server but are not returned by `/collections`.
nonisolated enum SystemCollectionID {
    static let all = 0
    static let unsorted = -1
    static let trash = -99
}
