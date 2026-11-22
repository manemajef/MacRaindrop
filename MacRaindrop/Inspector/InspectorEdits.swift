import Foundation
import Observation

/// The inspector's edits to one raindrop that haven't reached the server yet.
///
/// Every field in the inspector saves on its own, as soon as it's committed. The store takes
/// one write per raindrop at a time and drops any sent while one is pending, so changes made
/// during a save collect here and go out together as soon as it finishes. Until then the
/// inspector shows them, so nothing typed flickers back to the old value.
///
/// There's one per raindrop, from `edits(for:)`, so a change undone after another bookmark
/// was selected still joins the same queue.
@Observable
final class InspectorEdits {
    let raindropID: Raindrop.ID
    private(set) var unsaved = RaindropChanges()
    private(set) var isSaving = false
    /// Whether a save is waiting for another write to this raindrop to finish.
    private var isWaiting = false

    private static var all: [Raindrop.ID: InspectorEdits] = [:]

    static func edits(for id: Raindrop.ID) -> InspectorEdits {
        if let edits = all[id] { return edits }
        let edits = InspectorEdits(raindropID: id)
        all[id] = edits
        return edits
    }

    private init(raindropID: Raindrop.ID) {
        self.raindropID = raindropID
    }

    /// Whether anything is waiting for, or on its way to, the server.
    var isBusy: Bool { isSaving || unsaved != RaindropChanges() }

    /// `raindrop` as the inspector should show it: the server's copy with the unsaved edits on top.
    func displayed(_ raindrop: Raindrop) -> Raindrop {
        var raindrop = unsaved.applied(to: raindrop)
        if let tags = unsaved.tags { raindrop.tags = tags }
        return raindrop
    }

    /// Records a change, sends it now or once the current write finishes, and registers its
    /// undo: a change back to the values it replaced, which can itself be redone.
    func change(_ changes: RaindropChanges, in store: LibraryStore, undoManager: UndoManager?) {
        guard let current = store.raindrop(id: raindropID).map(displayed) else { return }
        let inverse = changes.inverse(of: current)
        guard inverse != changes else { return }
        unsaved.merge(changes)
        save(in: store)

        undoManager?.registerUndo(withTarget: self) { edits in
            MainActor.assumeIsolated {
                edits.change(inverse, in: store, undoManager: undoManager)
            }
        }
        undoManager?.setActionName(changes.actionName)
    }

    /// Sends the unsaved changes, unless a save is already running here. While another write
    /// to this raindrop is pending, waits for it and tries again.
    private func save(in store: LibraryStore) {
        guard !isSaving, !isWaiting, unsaved != RaindropChanges() else { return }
        guard store.canModify([raindropID]) else {
            waitUntilWritable(in: store)
            return
        }
        let sent = unsaved
        isSaving = true
        Task {
            await store.attempt("Couldn’t Save Changes") {
                try await store.edit(self.raindropID, with: sent)
            }
            isSaving = false
            // Saved, or failed and the store is showing why: either way the server's copy is the
            // truth for what was sent. Anything changed meanwhile goes out next.
            unsaved.remove(sent)
            save(in: store)
        }
    }

    private func waitUntilWritable(in store: LibraryStore) {
        isWaiting = true
        withObservationTracking {
            _ = store.canModify([raindropID])
        } onChange: {
            // Edits live as long as the app, in `all`, so holding on to self is fine.
            Task { @MainActor in
                self.isWaiting = false
                self.save(in: store)
            }
        }
    }
}

private extension RaindropChanges {
    /// Changes back to `raindrop`'s values for the fields this sets.
    func inverse(of raindrop: Raindrop) -> RaindropChanges {
        var inverse = RaindropChanges()
        if title != nil { inverse.title = raindrop.title }
        if excerpt != nil { inverse.excerpt = raindrop.excerpt }
        if note != nil { inverse.note = raindrop.note }
        if link != nil { inverse.link = raindrop.link }
        if tags != nil { inverse.tags = raindrop.tags }
        if important != nil { inverse.important = raindrop.important }
        if collectionID != nil { inverse.collectionID = raindrop.collectionID }
        return inverse
    }

    mutating func merge(_ other: RaindropChanges) {
        if let title = other.title { self.title = title }
        if let excerpt = other.excerpt { self.excerpt = excerpt }
        if let note = other.note { self.note = note }
        if let link = other.link { self.link = link }
        if let tags = other.tags { self.tags = tags }
        if let important = other.important { self.important = important }
        if let collectionID = other.collectionID { self.collectionID = collectionID }
    }

    /// Clears each field that still holds the value `sent` carried.
    mutating func remove(_ sent: RaindropChanges) {
        if title == sent.title { title = nil }
        if excerpt == sent.excerpt { excerpt = nil }
        if note == sent.note { note = nil }
        if link == sent.link { link = nil }
        if tags == sent.tags { tags = nil }
        if important == sent.important { important = nil }
        if collectionID == sent.collectionID { collectionID = nil }
    }

    /// The Edit menu's "Undo …" name.
    var actionName: String {
        if title != nil { return "Title" }
        if excerpt != nil { return "Description" }
        if note != nil { return "Note" }
        if link != nil { return "URL" }
        if tags != nil { return "Tags" }
        if important != nil { return "Favorite" }
        if collectionID != nil { return "Move" }
        return ""
    }
}
