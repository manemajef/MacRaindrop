import Foundation
import Observation

/// Actions that need to ask something first. Each window has one; `ContentView` presents them.
@Observable
final class ActionPrompts {
    var editing: Raindrop?
    var tagging: TagRequest?
    var deletion: DeletionRequest?

    /// Moves raindrops to the Trash right away, since that can be undone from there. If any are
    /// already in the Trash, asks first, because deleting those is permanent.
    func delete(_ raindrops: [Raindrop], in store: LibraryStore) {
        guard !raindrops.isEmpty else { return }
        let ids = raindrops.map(\.id)
        if raindrops.contains(where: \.isInTrash) {
            deletion = DeletionRequest(ids: ids, includesOthers: !raindrops.allSatisfy(\.isInTrash))
        } else {
            Task {
                await store.attempt("Couldn't Move to Trash") { try await store.delete(ids) }
            }
        }
    }
}

struct TagRequest: Identifiable {
    let id = UUID()
    let ids: [Raindrop.ID]
}

struct DeletionRequest: Identifiable {
    let id = UUID()
    let ids: [Raindrop.ID]
    /// Some of the raindrops aren't in the Trash yet, so they'll move there instead.
    let includesOthers: Bool
}
