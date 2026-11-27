import Foundation

extension LibraryStore {
    // MARK: Lookups

    func collection(id: RaindropCollection.ID) -> RaindropCollection? {
        // Reads `collections` itself, so the caller observes it.
        collectionIndexByID[id].map { collections[$0] }
    }

    func raindrop(id: Raindrop.ID) -> Raindrop? {
        indexByID[id].map { raindrops[$0] }
    }

    func title(for item: SidebarItem) -> String {
        switch item {
        case .all: "All Bookmarks"
        case .unsorted: "Unsorted"
        case .important: "Favorites"
        case .trash: "Trash"
        case .collection(let id): collection(id: id)?.title ?? "Collection"
        case .tag(let tag): "#\(tag)"
        case .filter(let filter): filter.title
        }
    }

    /// The name to show for the collection a raindrop is in, including the system ones.
    func collectionTitle(for id: RaindropCollection.ID) -> String {
        switch id {
        case SystemCollectionID.unsorted: "Unsorted"
        case SystemCollectionID.trash: "Trash"
        default: collection(id: id)?.title ?? "Unknown"
        }
    }

    var collectionTree: [CollectionNode] {
        let byParent = Dictionary(grouping: collections, by: \.parentID)
        func nodes(under parent: Int?) -> [CollectionNode] {
            (byParent[parent] ?? [])
                .sorted { ($0.sort, $0.title) < ($1.sort, $1.title) }
                .map { collection in
                    let children = nodes(under: collection.id)
                    return CollectionNode(collection: collection, children: children.isEmpty ? nil : children)
                }
        }
        return nodes(under: nil)
    }

    /// The collections directly inside `id`, in sidebar order.
    func subcollections(of id: RaindropCollection.ID) -> [RaindropCollection] {
        collections
            .filter { $0.parentID == id }
            .sorted { ($0.sort, $0.title) < ($1.sort, $1.title) }
    }

    /// The collections that contain `id`, innermost first.
    func ancestors(of id: RaindropCollection.ID) -> [RaindropCollection.ID] {
        var ancestors: [RaindropCollection.ID] = []
        var parent = collection(id: id)?.parentID
        while let id = parent, !ancestors.contains(id) {
            ancestors.append(id)
            parent = collection(id: id)?.parentID
        }
        return ancestors
    }

    /// The raindrops `item` shows, narrowed by the search field's `text`.
    func raindrops(in item: SidebarItem, matching text: String = "", sortedBy sort: RaindropSort = .newest) -> [Raindrop] {
        raindrops(matching: item.query.searching(text), sortedBy: sort)
    }

    /// Remembered until `raindrops` changes, so asking again is free.
    func raindrops(matching query: LibraryQuery, sortedBy sort: RaindropSort = .newest) -> [Raindrop] {
        // Read `raindrops` even when the answer is remembered, so the caller still observes it.
        let all = raindrops
        let key = RaindropQuery(query: query, sort: sort)
        if let remembered = queryResults[key] { return remembered }

        let context = queryContext
        let result = all.filter { query.matches($0, in: context) }.sorted(by: sort.areInIncreasingOrder)
        // Each search keystroke is a new query; don't keep them all.
        if queryResults.count >= 16 { queryResults.removeAll() }
        queryResults[key] = result
        return result
    }

    /// The collections `item` shows along with its raindrops: a collection's subcollections.
    /// Nothing else shows collections.
    func collections(in item: SidebarItem) -> [RaindropCollection] {
        guard case .collection(let id) = item else { return [] }
        return subcollections(of: id)
    }

    /// How many raindrops `item` shows, without a search. Remembered until `raindrops` changes.
    func count(for item: SidebarItem) -> Int {
        let all = raindrops
        let query = item.query
        if let remembered = countResults[query] { return remembered }
        let context = queryContext
        let count = all.count { query.matches($0, in: context) }
        countResults[query] = count
        return count
    }

    func canModify(_ ids: some Sequence<Raindrop.ID>) -> Bool {
        canWrite && pendingIDs.isDisjoint(with: ids)
    }
}
