import Foundation
import SwiftData

// The cache stores each item's API JSON as an opaque payload next to a few indexed columns.
// The value types in Models/ stay the single definition of a raindrop, and adding a field
// to them never needs a SwiftData schema migration.

@Model
final class CachedRaindrop {
    #Index<CachedRaindrop>([\.collectionID])

    @Attribute(.unique) var id: Int
    var collectionID: Int
    var lastUpdate: Date
    var payload: Data

    init(id: Int, collectionID: Int, lastUpdate: Date, payload: Data) {
        self.id = id
        self.collectionID = collectionID
        self.lastUpdate = lastUpdate
        self.payload = payload
    }
}

@Model
final class CachedCollection {
    @Attribute(.unique) var id: Int
    var payload: Data

    init(id: Int, payload: Data) {
        self.id = id
        self.payload = payload
    }
}

/// The sync cursor. There is at most one row.
@Model
final class SyncState {
    /// The server's `changedBookmarksDate` as of the last successful sync.
    var changedBookmarksDate: Date?
    var lastSyncedAt: Date?

    init() {}
}

/// Reads and writes the on-disk library. Lives on the main actor and uses the main context;
/// a library of a few thousand items decodes in milliseconds.
@MainActor
final class LibraryCache {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let encoder = JSONEncoder.raindrop
    private let decoder = JSONDecoder.raindrop

    static let schema = Schema([CachedRaindrop.self, CachedCollection.self, SyncState.self])

    /// Opens (or creates) `Application Support/<identifier>.store`, falling back to memory if that fails.
    init(identifier: String, inMemory: Bool = false) {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            let directory = URL.applicationSupportDirectory
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            configuration = ModelConfiguration(url: directory.appending(path: "\(identifier).store"))
        }
        do {
            container = try ModelContainer(for: Self.schema, configurations: configuration)
        } catch {
            // A corrupt or incompatible cache is disposable: the server is the source of truth.
            container = try! ModelContainer(for: Self.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }

    // MARK: Reading

    func collections() throws -> [RaindropCollection] {
        try context.fetch(FetchDescriptor<CachedCollection>()).map {
            try decoder.decode(RaindropCollection.self, from: $0.payload)
        }
    }

    func raindrops() throws -> [Raindrop] {
        try context.fetch(FetchDescriptor<CachedRaindrop>()).map {
            try decoder.decode(Raindrop.self, from: $0.payload)
        }
    }

    func count(where predicate: Predicate<CachedRaindrop>) throws -> Int {
        try context.fetchCount(FetchDescriptor(predicate: predicate))
    }

    var syncState: SyncState {
        if let existing = try? context.fetch(FetchDescriptor<SyncState>()).first {
            return existing
        }
        let state = SyncState()
        context.insert(state)
        return state
    }

    // MARK: Writing

    /// Empties the cache, for when the token (and so maybe the account) changes.
    func removeAll() throws {
        try context.delete(model: CachedRaindrop.self)
        try context.delete(model: CachedCollection.self)
        try context.delete(model: SyncState.self)
        try context.save()
    }

    func replaceCollections(_ collections: [RaindropCollection]) throws {
        try context.delete(model: CachedCollection.self)
        for collection in collections {
            context.insert(CachedCollection(id: collection.id, payload: try encoder.encode(collection)))
        }
    }

    func upsertCollection(_ collection: RaindropCollection) throws {
        let id = collection.id
        if let record = try context.fetch(FetchDescriptor<CachedCollection>(predicate: #Predicate { $0.id == id })).first {
            record.payload = try encoder.encode(collection)
        } else {
            context.insert(CachedCollection(id: id, payload: try encoder.encode(collection)))
        }
    }

    func replaceRaindrops(_ raindrops: [Raindrop]) throws {
        try context.delete(model: CachedRaindrop.self)
        for raindrop in raindrops {
            context.insert(try makeRecord(raindrop))
        }
    }

    /// Inserts new raindrops and overwrites existing ones with the same id.
    func upsertRaindrops(_ raindrops: [Raindrop]) throws {
        let ids = raindrops.map(\.id)
        let existing = try context.fetch(FetchDescriptor<CachedRaindrop>(predicate: #Predicate { ids.contains($0.id) }))
        let recordsByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for raindrop in raindrops {
            if let record = recordsByID[raindrop.id] {
                record.collectionID = raindrop.collectionID
                record.lastUpdate = raindrop.lastUpdate
                record.payload = try encoder.encode(raindrop)
            } else {
                context.insert(try makeRecord(raindrop))
            }
        }
    }

    func deleteRaindrops(_ ids: [Raindrop.ID]) throws {
        try context.delete(model: CachedRaindrop.self, where: #Predicate { ids.contains($0.id) })
    }

    func save() throws {
        try context.save()
    }

    func rollback() {
        context.rollback()
    }

    private func makeRecord(_ raindrop: Raindrop) throws -> CachedRaindrop {
        CachedRaindrop(
            id: raindrop.id,
            collectionID: raindrop.collectionID,
            lastUpdate: raindrop.lastUpdate,
            payload: try encoder.encode(raindrop)
        )
    }
}
