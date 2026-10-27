import Foundation

extension LibraryStore {
    // MARK: Writes
    //
    // Every write goes to the server first. Only the server's answer changes the cache and
    // what's on screen, so nothing ever looks saved that wasn't. A failed write throws and
    // changes nothing; `attempt` turns that into `writeFailure` for buttons and menus.

    /// Runs a write started from a button or menu. A failure becomes `writeFailure`, with Try Again.
    func attempt(_ failureTitle: String, _ write: @escaping () async throws -> Void) async {
        do {
            try await write()
        } catch {
            writeFailure = WriteFailure(title: failureTitle, message: error.localizedDescription) { [weak self] in
                await self?.attempt(failureTitle, write)
            }
        }
    }

    /// Fetches the server's current copy of a raindrop, stores it, and returns it.
    func refresh(_ id: Raindrop.ID) async throws -> Raindrop {
        try await enqueue {
            let latest = try await self.service.fetchRaindrop(id: id)
            try self.apply([latest])
            return latest
        }
    }

    /// Saves edits to one raindrop. Only the fields set in `changes` are sent.
    func edit(_ id: Raindrop.ID, with changes: RaindropChanges) async throws {
        try await update([id], with: changes)
    }

    func setImportant(_ ids: some Sequence<Raindrop.ID>, _ important: Bool) async throws {
        try await update(Array(ids), with: RaindropChanges(important: important))
    }

    /// Moves raindrops into a collection. Moving them out of the Trash restores them.
    func move(_ ids: some Sequence<Raindrop.ID>, to collectionID: RaindropCollection.ID) async throws {
        let ids = ids.filter { raindrop(id: $0)?.collectionID != collectionID }
        try await update(ids, with: RaindropChanges(collectionID: collectionID))
    }

    func addTags(_ tags: [String], to ids: some Sequence<Raindrop.ID>) async throws {
        let ids = Array(ids)
        // A single update replaces the tag list, while the bulk endpoint appends to it.
        if ids.count == 1, let raindrop = raindrop(id: ids[0]) {
            try await update(ids, with: RaindropChanges(tags: raindrop.tags + tags.filter { !raindrop.tags.contains($0) }))
        } else {
            try await update(ids, with: RaindropChanges(tags: tags))
        }
    }

    /// Moves raindrops to the Trash, and deletes the ones already there for good.
    /// The UI asks before deleting anything from the Trash.
    func delete(_ ids: some Sequence<Raindrop.ID>) async throws {
        try await writing(Array(ids)) { targets in
            for (inTrash, group) in Dictionary(grouping: targets, by: \.isInTrash) {
                let collections = inTrash
                    ? [SystemCollectionID.trash: group]
                    : Dictionary(grouping: group, by: \.collectionID)
                for (collectionID, raindrops) in collections {
                    try await self.service.removeRaindrops(ids: raindrops.map(\.id), inCollection: collectionID)
                    if inTrash {
                        try self.forget(raindrops.map(\.id))
                    } else {
                        try self.apply(raindrops.map(RaindropChanges(collectionID: SystemCollectionID.trash).applied(to:)))
                    }
                }
            }
        }
        await sync()
    }

    /// Sends `changes` for one raindrop with `PUT /raindrop/{id}`, or for several with the bulk
    /// endpoint, once per collection since it can't span them.
    private func update(_ ids: [Raindrop.ID], with changes: RaindropChanges) async throws {
        let usedBulk = try await writing(ids) { targets in
            if ids.count == 1 {
                let updated = try await self.service.updateRaindrop(id: targets[0].id, changes: changes)
                try self.apply([updated])
                return false
            }
            // Each confirmed group is applied right away, so a later group failing doesn't hide it.
            for (collectionID, group) in Dictionary(grouping: targets, by: \.collectionID) {
                try await self.service.updateRaindrops(ids: group.map(\.id), inCollection: collectionID, changes: changes)
                try self.apply(group.map(changes.applied(to:)))
            }
            return true
        }
        // The bulk endpoint only confirms the change, so fetch the server's copies (tags, `lastUpdate`).
        if usedBulk == true { await sync() }
    }
}

/// A write the server didn't accept, with a way to try it again.
struct WriteFailure: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let retry: () async -> Void
}
