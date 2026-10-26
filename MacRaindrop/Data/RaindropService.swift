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

    var name: String { "Sample Data" }
    var cacheIdentifier: String { "sample" }

    func fetchStats() async throws -> LibraryStats {
        let raindrops = try loadRaindrops()
        return LibraryStats(
            changedBookmarksDate: raindrops.map(\.lastUpdate).max(),
            counts: [
                SystemCollectionID.all: raindrops.count { $0.collectionID != SystemCollectionID.trash },
                SystemCollectionID.trash: raindrops.count { $0.collectionID == SystemCollectionID.trash },
            ]
        )
    }

    func fetchCollections() async throws -> [RaindropCollection] {
        try loadCollections()
    }

    func fetchRaindrops(collectionID: Int, changedSince: Date?) async throws -> [Raindrop] {
        let startOfDay = changedSince.map { Calendar.utc.startOfDay(for: $0) }
        return try loadRaindrops().filter { raindrop in
            let inCollection = switch collectionID {
            case SystemCollectionID.all: raindrop.collectionID != SystemCollectionID.trash
            default: raindrop.collectionID == collectionID
            }
            return inCollection && startOfDay.map { raindrop.lastUpdate >= $0 } ?? true
        }
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

nonisolated extension Calendar {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
}
