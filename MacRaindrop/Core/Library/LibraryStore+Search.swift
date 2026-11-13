import Foundation

extension LibraryStore {
    /// The index over the current library, built off the main thread the first time it's asked for
    /// after a change. Every caller in the meantime waits for the same build.
    func searchIndex() async -> SearchIndex {
        if let readySearchIndex { return readySearchIndex }
        if let searchIndexTask { return await searchIndexTask.value }
        let raindrops = raindrops
        let paths = collectionPaths
        let task = Task.detached(priority: .userInitiated) {
            SearchIndex(raindrops: raindrops, collectionPaths: paths)
        }
        searchIndexTask = task
        let index = await task.value
        // Unless the library changed while it was being built.
        if searchIndexTask == task { readySearchIndex = index }
        return index
    }

    /// Each collection's name with its parents, outermost first: "Work › Design".
    var collectionPaths: [RaindropCollection.ID: String] {
        var paths: [RaindropCollection.ID: String] = [
            SystemCollectionID.unsorted: title(for: .unsorted),
            SystemCollectionID.trash: title(for: .trash),
        ]
        for collection in collections {
            let names = ancestors(of: collection.id).reversed().compactMap { self.collection(id: $0)?.title }
            paths[collection.id] = (names + [collection.title]).joined(separator: " › ")
        }
        return paths
    }
}
