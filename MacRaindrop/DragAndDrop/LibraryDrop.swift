import Foundation

/// The same drop actions serve the sidebar and the grid's collection chips.
struct LibraryDrop {
    enum Target {
        case item(SidebarItem)
        case topLevel
    }

    let target: Target
    let store: LibraryStore
    let prompts: ActionPrompts

    func bookmarks(_ ids: [Raindrop.ID]) async {
        guard case .item(let item) = target, store.canModify(ids) else { return }
        switch item {
        case .collection(let id):
            await store.attempt("Couldn't Move Bookmarks") { try await store.move(ids, to: id) }
        case .unsorted:
            await store.attempt("Couldn't Move Bookmarks") { try await store.move(ids, to: SystemCollectionID.unsorted) }
        case .important:
            await store.attempt("Couldn't Add to Favorites") { try await store.setImportant(ids, true) }
        case .trash:
            prompts.delete(ids.compactMap(store.raindrop(id:)), in: store)
        case .tag(let tag):
            await store.attempt("Couldn't Add Tag") { try await store.addTags([tag], to: ids) }
        case .all, .filter:
            break
        }
    }

    func collection(_ id: RaindropCollection.ID) async {
        guard store.canWrite else { return }
        switch target {
        case .item(.collection(let parent)):
            await store.attempt("Couldn't Move Collection") { try await store.moveCollection(id, into: parent) }
        case .topLevel:
            await store.attempt("Couldn't Move Collection") { try await store.moveCollection(id, into: nil) }
        case .item:
            break
        }
    }

}
