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

    @ObservationIgnored let service: any RaindropService
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
    func enqueue<T>(_ operation: @escaping () async throws -> T) async throws -> T {
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

    /// Forgets the cached library. The store isn't used afterwards: the app makes a new one.
    func clearCache() {
        try? cache.removeAll()
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

    // MARK: Write primitives

    /// Marks the raindrops pending, runs `write` on the queue for those not already pending,
    /// then clears them. Returns nil when there was nothing to write.
    @discardableResult
    func writing<T>(_ ids: [Raindrop.ID], _ write: @escaping ([Raindrop]) async throws -> T) async throws -> T? {
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
    func apply(_ updated: [Raindrop]) throws {
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
    func forget(_ ids: [Raindrop.ID]) throws {
        try cache.deleteRaindrops(ids)
        try cache.save()
        raindrops.removeAll { ids.contains($0.id) }
    }

    /// Stores a collection as the server returned it, and shows it.
    func apply(_ collection: RaindropCollection) throws {
        try cache.upsertCollection(collection)
        try cache.save()
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            collections[index] = collection
        } else {
            collections.append(collection)
        }
    }

    func failIfSimulating() throws {
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
