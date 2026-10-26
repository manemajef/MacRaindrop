import Foundation
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

    @ObservationIgnored private let service: any RaindropService
    @ObservationIgnored private let cache: LibraryCache
    @ObservationIgnored private lazy var syncEngine = SyncEngine(service: service, cache: cache)

    var sourceName: String { service.name }

    init(service: any RaindropService = SampleDataService(), cache: LibraryCache? = nil) {
        self.service = service
        self.cache = cache ?? LibraryCache(identifier: service.cacheIdentifier)
    }

    /// Shows the cached library immediately, then syncs in the background.
    func load() async {
        if phase == .idle { reloadFromCache() }
        await sync()
    }

    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        if phase != .loaded { phase = .loading }

        do {
            let report = try await syncEngine.sync()
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
            let inTrash = raindrop.removed || raindrop.collectionID == SystemCollectionID.trash
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

    // MARK: Local mutations (not yet synced; the next sync that touches the item overwrites them)

    func toggleImportant(_ id: Raindrop.ID) {
        guard let index = raindrops.firstIndex(where: { $0.id == id }) else { return }
        raindrops[index].important.toggle()
    }
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
