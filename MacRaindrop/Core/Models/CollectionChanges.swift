import Foundation

/// Fields to change on a collection: the body of `PUT /collection/{id}`. Only the fields
/// that are set are sent.
nonisolated struct CollectionChanges: Encodable, Sendable, Equatable {
    enum Parent: Equatable, Sendable {
        /// The top level, outside any collection.
        case root
        case collection(RaindropCollection.ID)
    }

    var parent: Parent?

    enum CodingKeys: String, CodingKey {
        case parent
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch parent {
        case nil:
            break
        case .root:
            // The docs only say the parent is "empty for root collections", so `null` is a
            // best guess that still needs checking against the live API.
            try c.encodeNil(forKey: .parent)
        case .collection(let id):
            try c.encode(Ref(id: id), forKey: .parent)
        }
    }

    /// `collection` with these changes made, as the sample service stores it.
    func applied(to collection: RaindropCollection) -> RaindropCollection {
        var collection = collection
        switch parent {
        case nil: break
        case .root: collection.parent = nil
        case .collection(let id): collection.parent = Ref(id: id)
        }
        return collection
    }
}
