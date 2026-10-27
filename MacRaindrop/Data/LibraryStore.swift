import Foundation
import Network
import Observation

/// What the sidebar can point at.
enum SidebarItem: Hashable {
    case all
    case unsorted
    case important
    case trash
    case collection(RaindropCollection.ID)
    case tag(String)
}

enum RaindropSort: String, CaseIterable, Identifiable {
    case newest, oldest, title, domain

    var id: Self { self }

    var label: String {
        switch self {
        case .newest: "Newest First"
        case .oldest: "Oldest First"
        case .title: "Title"
        case .domain: "Domain"
        }
    }

    func areInIncreasingOrder(_ a: Raindrop, _ b: Raindrop) -> Bool {
        switch self {
        case .newest: a.created > b.created
        case .oldest: a.created < b.created
        case .title: a.title.localizedStandardCompare(b.title) == .orderedAscending
        case .domain: a.domain.localizedStandardCompare(b.domain) == .orderedAscending
        }
    }
}

/// A collection plus its nested children, for the sidebar outline.
struct CollectionNode: Identifiable, Hashable {
    let collection: RaindropCollection
    /// `nil` (not empty) for leaves, so `OutlineGroup` draws no disclosure triangle.
    let children: [CollectionNode]?

    var id: RaindropCollection.ID { collection.id }
}

/// The app's single source of truth for collections and raindrops.
@Observable
final class LibraryStore {
    enum Phase: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var collections: [RaindropCollection] = []
    private(set) var raindrops: [Raindrop] = []
    /// True while syncing, including when cached data is already on screen.
    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    /// Set when a sync fails while cached data is on screen; cleared by the next success.
    private(set) var syncError: String?
    /// Raindrops with a write on its way to the server. Their actions are disabled until it's answered.
    private(set) var pendingIDs: Set<Raindrop.ID> = []
    /// The last write the server didn't accept, for the UI to present. Nothing changed locally.
    var writeFailure: WriteFailure?
    /// Whether the system reports a network path. Only a hint: a write can still fail while "online".
    private(set) var isOnline = true
    #if DEBUG
    /// Makes every write fail before reaching the server, to check that nothing changes locally.
    var simulatesWriteFailures = false
    #endif

    @ObservationIgnored private let service: any RaindropService
    @ObservationIgnored private let cache: LibraryCache
    @ObservationIgnored private lazy var syncEngine = SyncEngine(service: service, cache: cache)
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    /// The end of the queue that syncs and writes run on, one at a time. A sync that started
    /// before a write can then never put the pre-write copy back over the server's answer.
    @ObservationIgnored private var lastOperation: Task<Void, Never>?

    var sourceName: String { service.name }

    /// Writes are offered only with a loaded library and a network connection.
    var canWrite: Bool { phase == .loaded && isOnline }

    init(service: any RaindropService = SampleDataService(), cache: LibraryCache? = nil) {
        self.service = service
        self.cache = cache ?? LibraryCache(identifier: service.cacheIdentifier)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isOnline = path.status == .satisfied }
        }
        pathMonitor.start(queue: .main)
    }

    deinit {
        pathMonitor.cancel()
    }

    /// Runs `operation` after every sync and write queued before it.
    private func enqueue<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        let previous = lastOperation
        let task = Task {
            await previous?.value
            return try await operation()
        }
        lastOperation = Task { _ = try? await task.value }
        return try await task.value
    }

    /// Shows the cached library immediately, then syncs in the background.
    func load() async {
        if phase == .idle { reloadFromCache() }
        await sync()
    }

    /// Syncs unless the last sync finished less than `interval` ago. Used for the automatic syncs.
    func syncIfStale(olderThan interval: Duration = .seconds(60)) async {
        if let lastSyncedAt, Date.now.timeIntervalSince(lastSyncedAt) < interval / .seconds(1) { return }
        await sync()
    }

    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        if phase != .loaded { phase = .loading }

        do {
            let report = try await enqueue { try await self.syncEngine.sync() }
            if report.kind != .upToDate || phase != .loaded {
                reloadFromCache()
            }
            lastSyncedAt = report.date
            syncError = nil
            phase = .loaded
        } catch is CancellationError {
            if phase == .loading { phase = .idle }
        } catch {
            if phase == .loaded {
                syncError = error.localizedDescription
            } else {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func reloadFromCache() {
        guard let collections = try? cache.collections(),
              let raindrops = try? cache.raindrops(),
              !(collections.isEmpty && raindrops.isEmpty)
        else { return }
        self.collections = collections
        self.raindrops = raindrops
        lastSyncedAt = cache.syncState.lastSyncedAt
        phase = .loaded
    }

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

    /// Marks the raindrops pending, runs `write` on the queue for those not already pending,
    /// then clears them. Returns nil when there was nothing to write.
    @discardableResult
    private func writing<T>(_ ids: [Raindrop.ID], _ write: @escaping ([Raindrop]) async throws -> T) async throws -> T? {
        let targets = ids.compactMap(raindrop(id:)).filter { !pendingIDs.contains($0.id) }
        guard !targets.isEmpty else { return nil }
        let targetIDs = Set(targets.map(\.id))
        pendingIDs.formUnion(targetIDs)
        defer { pendingIDs.subtract(targetIDs) }
        return try await enqueue {
            try self.failIfSimulating()
            return try await write(targets)
        }
    }

    /// Stores raindrops as the server returned (or confirmed) them, and shows them.
    private func apply(_ updated: [Raindrop]) throws {
        try cache.upsertRaindrops(updated)
        try cache.save()
        for raindrop in updated {
            if let index = raindrops.firstIndex(where: { $0.id == raindrop.id }) {
                raindrops[index] = raindrop
            } else {
                raindrops.append(raindrop)
            }
        }
    }

    /// Drops raindrops the server deleted for good.
    private func forget(_ ids: [Raindrop.ID]) throws {
        try cache.deleteRaindrops(ids)
        try cache.save()
        raindrops.removeAll { ids.contains($0.id) }
    }

    private func failIfSimulating() throws {
        #if DEBUG
        if simulatesWriteFailures { throw SimulatedWriteFailure() }
        #endif
    }
}

#if DEBUG
private struct SimulatedWriteFailure: LocalizedError {
    var errorDescription: String? { "Simulated failure (Debug › Simulate Write Failures). Nothing was sent." }
}
#endif

/// A write the server didn't accept, with a way to try it again.
struct WriteFailure: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let retry: () async -> Void
}

extension LibraryStore {
    /// A store filled synchronously from the bundled sample data, for previews.
    static var preview: LibraryStore {
        let service = SampleDataService()
        let store = LibraryStore(service: service, cache: LibraryCache(identifier: "preview", inMemory: true))
        store.collections = (try? service.loadCollections()) ?? []
        store.raindrops = (try? service.loadRaindrops()) ?? []
        store.phase = .loaded
        return store
    }
}
