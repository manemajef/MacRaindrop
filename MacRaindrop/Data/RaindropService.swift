import Foundation

/// Abstraction over where library data comes from.
///
/// `SampleDataService` reads the bundled JSON snapshots; `RaindropAPIService`
/// hits `https://api.raindrop.io/rest/v1` with the same shapes.
nonisolated protocol RaindropService: Sendable {
    /// Shown in the UI so it's obvious where the data came from.
    var name: String { get }
    /// Names the on-disk cache, so sample data and the real account never mix.
    var cacheIdentifier: String { get }
    func fetchStats() async throws -> LibraryStats
    func fetchCollections() async throws -> [RaindropCollection]
    /// Pass `SystemCollectionID.all` for every raindrop outside the trash.
    ///
    /// With `changedSince`, returns only raindrops updated on or after that *day* (UTC):
    /// the API's `lastUpdate:` filter has day granularity, so callers should expect some overlap.
    func fetchRaindrops(collectionID: Int, changedSince: Date?) async throws -> [Raindrop]

    /// `GET /raindrop/{id}`: the server's current copy of one raindrop.
    func fetchRaindrop(id: Raindrop.ID) async throws -> Raindrop
    /// `PUT /raindrop/{id}`: changes one raindrop and returns the server's copy of it.
    func updateRaindrop(id: Raindrop.ID, changes: RaindropChanges) async throws -> Raindrop
    /// `PUT /raindrops/{collectionId}`: changes several raindrops that are all in `collectionID`.
    ///
    /// The server returns no items, and doesn't accept `SystemCollectionID.all` here.
    func updateRaindrops(ids: [Raindrop.ID], inCollection collectionID: Int, changes: RaindropChanges) async throws
    /// `PUT /collection/{id}`: changes one collection and returns the server's copy of it.
    func updateCollection(id: RaindropCollection.ID, changes: CollectionChanges) async throws -> RaindropCollection
    /// `DELETE /raindrops/{collectionId}`: moves raindrops in `collectionID` to the Trash, or
    /// deletes them for good when `collectionID` is the Trash.
    func removeRaindrops(ids: [Raindrop.ID], inCollection collectionID: Int) async throws
}

nonisolated extension RaindropService {
    func fetchRaindrops(collectionID: Int) async throws -> [Raindrop] {
        try await fetchRaindrops(collectionID: collectionID, changedSince: nil)
    }
}

nonisolated enum RaindropServices {
    static let tokenEnvironmentKey = "RAINDROP_TEST"

    /// The live API when a test token is in the environment, otherwise the bundled sample data.
    static func makeDefault(environment: [String: String] = ProcessInfo.processInfo.environment) -> any RaindropService {
        if let token = environment[tokenEnvironmentKey], !token.isEmpty {
            RaindropAPIService(token: token)
        } else {
            SampleDataService()
        }
    }
}

nonisolated struct SampleDataService: RaindropService {
    enum Failure: LocalizedError {
        case missingResource(String)

        var errorDescription: String? {
            switch self {
            case .missingResource(let name): "Sample data file “\(name).json” is missing from the app bundle."
            }
        }
    }

    var bundle: Bundle = .main
    /// The sample library as edited so far. Writes change it, and fetches read from it, so a
    /// sync picks edits up the same way it would from the server.
    private let library = SampleLibrary()

    var name: String { "Sample Data" }
    var cacheIdentifier: String { "sample" }

    func fetchStats() async throws -> LibraryStats {
        let raindrops = try await library.raindrops(from: self)
        return LibraryStats(
            changedBookmarksDate: raindrops.map(\.lastUpdate).max(),
            counts: [
                SystemCollectionID.all: raindrops.count { $0.collectionID != SystemCollectionID.trash },
                SystemCollectionID.trash: raindrops.count { $0.collectionID == SystemCollectionID.trash },
            ]
        )
    }

    func fetchCollections() async throws -> [RaindropCollection] {
        try await library.collections(from: self)
    }

    func updateCollection(id: RaindropCollection.ID, changes: CollectionChanges) async throws -> RaindropCollection {
        try await library.update(collection: id, changes: changes, from: self)
    }

    func fetchRaindrops(collectionID: Int, changedSince: Date?) async throws -> [Raindrop] {
        let startOfDay = changedSince.map { Calendar.utc.startOfDay(for: $0) }
        return try await library.raindrops(from: self).filter { raindrop in
            let inCollection = switch collectionID {
            case SystemCollectionID.all: raindrop.collectionID != SystemCollectionID.trash
            default: raindrop.collectionID == collectionID
            }
            return inCollection && startOfDay.map { raindrop.lastUpdate >= $0 } ?? true
        }
    }

    func fetchRaindrop(id: Raindrop.ID) async throws -> Raindrop {
        guard let raindrop = try await library.raindrops(from: self).first(where: { $0.id == id }) else {
            throw URLError(.fileDoesNotExist)
        }
        return raindrop
    }

    func updateRaindrop(id: Raindrop.ID, changes: RaindropChanges) async throws -> Raindrop {
        try await library.update([id], changes: changes, from: self)[0]
    }

    func updateRaindrops(ids: [Raindrop.ID], inCollection collectionID: Int, changes: RaindropChanges) async throws {
        _ = try await library.update(ids, changes: changes, from: self)
    }

    func removeRaindrops(ids: [Raindrop.ID], inCollection collectionID: Int) async throws {
        try await library.remove(ids, inTrash: collectionID == SystemCollectionID.trash, from: self)
    }

    // Synchronous variants, used for SwiftUI previews.

    func loadCollections() throws -> [RaindropCollection] {
        try decode("collections")
    }

    func loadRaindrops() throws -> [Raindrop] {
        try decode("raindrops")
    }

    private func decode<Item: Decodable & Sendable>(_ name: String) throws -> [Item] {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw Failure.missingResource(name)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.raindrop.decode(ItemsResponse<Item>.self, from: data).items
    }
}

/// The sample raindrops in memory, loaded from the bundle on first use.
private actor SampleLibrary {
    private var raindrops: [Raindrop]?
    private var collections: [RaindropCollection]?

    func collections(from service: SampleDataService) throws -> [RaindropCollection] {
        if let collections { return collections }
        let loaded = try service.loadCollections()
        collections = loaded
        return loaded
    }

    func update(collection id: RaindropCollection.ID, changes: CollectionChanges, from service: SampleDataService) throws -> RaindropCollection {
        var all = try collections(from: service)
        guard let index = all.firstIndex(where: { $0.id == id }) else { throw URLError(.fileDoesNotExist) }
        all[index] = changes.applied(to: all[index])
        all[index].lastUpdate = .now
        collections = all
        return all[index]
    }

    func raindrops(from service: SampleDataService) throws -> [Raindrop] {
        if let raindrops { return raindrops }
        let loaded = try service.loadRaindrops()
        raindrops = loaded
        return loaded
    }

    /// Mimics the server: applies the changes and bumps `lastUpdate`.
    func update(_ ids: [Raindrop.ID], changes: RaindropChanges, from service: SampleDataService) throws -> [Raindrop] {
        var all = try raindrops(from: service)
        var updated: [Raindrop] = []
        for index in all.indices where ids.contains(all[index].id) {
            all[index] = changes.applied(to: all[index])
            if let tags = changes.tags { all[index].tags = tags }
            all[index].lastUpdate = .now
            updated.append(all[index])
        }
        guard !updated.isEmpty else { throw URLError(.fileDoesNotExist) }
        raindrops = all
        return updated
    }

    /// Mimics the server: moves raindrops to the Trash, or deletes those already there.
    func remove(_ ids: [Raindrop.ID], inTrash: Bool, from service: SampleDataService) throws {
        var all = try raindrops(from: service)
        if inTrash {
            all.removeAll { ids.contains($0.id) }
        } else {
            for index in all.indices where ids.contains(all[index].id) {
                all[index].collectionID = SystemCollectionID.trash
                all[index].removed = true
                all[index].lastUpdate = .now
            }
        }
        raindrops = all
    }
}

nonisolated extension Calendar {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
}
