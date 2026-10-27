import Foundation

extension LibraryStore {
    // MARK: Lookups

    func collection(id: RaindropCollection.ID) -> RaindropCollection? {
        collections.first { $0.id == id }
    }

    func raindrop(id: Raindrop.ID) -> Raindrop? {
        raindrops.first { $0.id == id }
    }

    func title(for item: SidebarItem) -> String {
        switch item {
        case .all: "All Bookmarks"
        case .unsorted: "Unsorted"
        case .important: "Favorites"
        case .trash: "Trash"
        case .collection(let id): collection(id: id)?.title ?? "Collection"
        case .tag(let tag): "#\(tag)"
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

    /// Every tag in use, with how many raindrops carry it, most used first.
    var tags: [(name: String, count: Int)] {
        let counts = raindrops.filter { !$0.removed }.flatMap(\.tags).reduce(into: [:]) { $0[$1, default: 0] += 1 }
        return counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    func raindrops(in item: SidebarItem, matching query: String = "", sortedBy sort: RaindropSort = .newest) -> [Raindrop] {
        let scoped = raindrops.filter { raindrop in
            let inTrash = raindrop.isInTrash
            switch item {
            case .trash: return inTrash
            case _ where inTrash: return false
            case .all: return true
            case .unsorted: return raindrop.collectionID == SystemCollectionID.unsorted
            case .important: return raindrop.important
            case .collection(let id): return raindrop.collectionID == id
            case .tag(let tag): return raindrop.tags.contains(tag)
            }
        }
        let query = query.trimmingCharacters(in: .whitespaces)
        let matched = query.isEmpty ? scoped : scoped.filter { raindrop in
            [raindrop.title, raindrop.excerpt, raindrop.note, raindrop.domain]
                .contains { $0.localizedStandardContains(query) }
                || raindrop.tags.contains { $0.localizedStandardContains(query) }
        }
        return matched.sorted(by: sort.areInIncreasingOrder)
    }

    func count(for item: SidebarItem) -> Int {
        raindrops(in: item).count
    }

    func canModify(_ ids: some Sequence<Raindrop.ID>) -> Bool {
        canWrite && pendingIDs.isDisjoint(with: ids)
    }
}
