import Foundation

/// An edit in progress on one raindrop, shared by every screen that edits one.
///
/// Holds the version the edit started from and the edited copy, works out which fields
/// changed, and saves only those, after checking whether the bookmark changed elsewhere
/// meanwhile. The screen owns the layout; this owns the rules.
@Observable
final class RaindropDraft {
    /// The version the edit started from; changes are measured against it.
    private(set) var original: Raindrop
    /// The edited copy that fields bind to.
    var value: Raindrop
    /// A tag that's been typed but not added yet. Saving adds it.
    var pendingTag = ""
    private(set) var isSaving = false
    var errorMessage: String?
    /// Set when the server's copy changed after the edit started; the screen asks what to do.
    var showsConflict = false

    init(raindrop: Raindrop) {
        original = raindrop
        value = raindrop
    }

    var changes: RaindropChanges {
        var changes = RaindropChanges()
        if value.title != original.title { changes.title = value.title }
        if value.excerpt != original.excerpt { changes.excerpt = value.excerpt }
        if value.note != original.note { changes.note = value.note }
        if value.link != original.link { changes.link = value.link }
        if value.tags != original.tags { changes.tags = value.tags }
        if value.important != original.important { changes.important = value.important }
        if value.collectionID != original.collectionID { changes.collectionID = value.collectionID }
        return changes
    }

    var hasChanges: Bool { changes != RaindropChanges() }

    func canSave(in store: LibraryStore) -> Bool {
        hasChanges && !isSaving && !value.title.trimmingCharacters(in: .whitespaces).isEmpty
            && store.canModify([value.id])
    }

    /// Adds the typed-but-not-added tag, if any.
    func commitPendingTag() {
        value.tags.addTag(pendingTag)
        pendingTag = ""
    }

    /// Picks up the server's copy if nothing has been edited yet. Otherwise the edits stay,
    /// and saving notices the difference.
    func loadLatest(from store: LibraryStore) async {
        guard let latest = try? await store.refresh(original.id), !hasChanges else { return }
        original = latest
        value = latest
    }

    /// Whether `latest` differs from the starting version in a field this edit changes.
    /// Changes elsewhere to other fields don't matter, since saving leaves those alone,
    /// such as a tag added from the inspector while its title is being edited.
    private func changedElsewhere(in latest: Raindrop) -> Bool {
        let edited = changes
        return edited.title != nil && latest.title != original.title
            || edited.excerpt != nil && latest.excerpt != original.excerpt
            || edited.note != nil && latest.note != original.note
            || edited.link != nil && latest.link != original.link
            || edited.tags != nil && latest.tags != original.tags
            || edited.important != nil && latest.important != original.important
            || edited.collectionID != nil && latest.collectionID != original.collectionID
    }

    /// Saves the changed fields and returns whether it did. On a conflict it sets
    /// `showsConflict` instead; on a failure it sets `errorMessage` and keeps every edit.
    @discardableResult
    func save(to store: LibraryStore, checkingForConflicts: Bool) async -> Bool {
        commitPendingTag()
        guard canSave(in: store) else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            if checkingForConflicts {
                let latest = try await store.refresh(original.id)
                if changedElsewhere(in: latest) {
                    showsConflict = true
                    return false
                }
            }
            try await store.edit(original.id, with: changes)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
