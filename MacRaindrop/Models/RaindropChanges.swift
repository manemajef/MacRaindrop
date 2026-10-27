import Foundation

/// Fields to change on one or more raindrops: the body of `PUT /raindrop/{id}` and `PUT /raindrops/{collectionId}`.
///
/// Only the fields that are set are sent, so saving one field never overwrites another
/// that was changed elsewhere in the meantime.
nonisolated struct RaindropChanges: Encodable, Sendable, Equatable {
    var title: String?
    var excerpt: String?
    var note: String?
    var link: String?
    /// Replaces the tags on a single update, but the bulk endpoint *appends* them.
    var tags: [String]?
    var important: Bool?
    var collectionID: RaindropCollection.ID?

    enum CodingKeys: String, CodingKey {
        case title, excerpt, note, link, tags, important, collection
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(excerpt, forKey: .excerpt)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(link, forKey: .link)
        try c.encodeIfPresent(tags, forKey: .tags)
        try c.encodeIfPresent(important, forKey: .important)
        try c.encodeIfPresent(collectionID.map { Ref(id: $0) }, forKey: .collection)
    }

    /// `raindrop` with these changes made, for when the server confirms a write without
    /// returning the item. Tags are left alone, since the bulk endpoint appends them.
    func applied(to raindrop: Raindrop) -> Raindrop {
        var raindrop = raindrop
        if let title { raindrop.title = title }
        if let excerpt { raindrop.excerpt = excerpt }
        if let note { raindrop.note = note }
        if let link { raindrop.link = link }
        if let important { raindrop.important = important }
        if let collectionID { raindrop.collectionID = collectionID }
        return raindrop
    }
}
