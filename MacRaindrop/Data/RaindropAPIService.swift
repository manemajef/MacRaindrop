import Foundation

/// Talks to the live Raindrop REST API (`https://api.raindrop.io/rest/v1`).
///
/// Authenticates with a test token (or, later, an OAuth access token) sent as a bearer header.
nonisolated struct RaindropAPIService: RaindropService {
    enum Failure: LocalizedError {
        case unauthorized
        case rateLimited
        case http(status: Int)
        case decoding(path: String, underlying: DecodingError)

        var errorDescription: String? {
            switch self {
            case .unauthorized: "Raindrop rejected the access token. Check RAINDROP_TEST."
            case .rateLimited: "Raindrop's rate limit was hit. Try again in a minute."
            case .http(let status): "Raindrop returned HTTP \(status)."
            case .decoding(let path, let underlying): "Unexpected response from \(path): \(underlying.summary)"
            }
        }
    }

    static let baseURL = URL(string: "https://api.raindrop.io/rest/v1/")!
    /// The API's maximum page size.
    static let pageSize = 50

    let token: String
    var session: URLSession = .shared

    var name: String { "raindrop.io" }
    var cacheIdentifier: String { "raindrop-api" }

    func fetchStats() async throws -> LibraryStats {
        try await get("user/stats")
    }

    func fetchCollections() async throws -> [RaindropCollection] {
        async let roots: ItemsResponse<RaindropCollection> = get("collections")
        async let children: ItemsResponse<RaindropCollection> = get("collections/childrens")
        // `/childrens` also returns root collections, so de-duplicate by id.
        var seen = Set<RaindropCollection.ID>()
        return try await (roots.items + children.items).filter { seen.insert($0.id).inserted }
    }

    func fetchRaindrops(collectionID: Int, changedSince: Date?) async throws -> [Raindrop] {
        // `lastUpdate:>` only understands whole days and is inclusive of that day.
        let search = changedSince.map { "lastUpdate:>\($0.formatted(.iso8601.year().month().day()))" }

        // The first page tells us the total, then the rest are fetched concurrently.
        let first = try await page(0, of: collectionID, search: search)
        let pageCount = ((first.count ?? 0) + Self.pageSize - 1) / Self.pageSize
        guard pageCount > 1 else { return first.items }

        let remaining = try await withThrowingTaskGroup(of: (Int, [Raindrop]).self) { group in
            for index in 1..<pageCount {
                group.addTask { (index, try await page(index, of: collectionID, search: search).items) }
            }
            var pages: [Int: [Raindrop]] = [:]
            for try await (index, items) in group {
                pages[index] = items
            }
            return pages.sorted { $0.key < $1.key }.flatMap(\.value)
        }

        // Items can shift across page boundaries if the library changes mid-fetch.
        var seen = Set<Raindrop.ID>()
        return (first.items + remaining).filter { seen.insert($0.id).inserted }
    }

    private func page(_ index: Int, of collectionID: Int, search: String?) async throws -> ItemsResponse<Raindrop> {
        var query = [
            URLQueryItem(name: "page", value: String(index)),
            URLQueryItem(name: "perpage", value: String(Self.pageSize)),
            // An explicit sort keeps page contents stable between requests.
            URLQueryItem(name: "sort", value: "-created"),
        ]
        if let search {
            query.append(URLQueryItem(name: "search", value: search))
        }
        return try await get("raindrops/\(collectionID)", query: query)
    }

    private func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = [], retries: Int = 2) async throws -> Response {
        var request = URLRequest(url: Self.baseURL.appending(path: path).appending(queryItems: query))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        switch status {
        case 200..<300:
            do {
                return try JSONDecoder.raindrop.decode(Response.self, from: data)
            } catch let error as DecodingError {
                throw Failure.decoding(path: path, underlying: error)
            }
        case 401, 403:
            throw Failure.unauthorized
        case 429 where retries > 0:
            try await Task.sleep(for: retryDelay(for: response))
            return try await get(path, query: query, retries: retries - 1)
        case 429:
            throw Failure.rateLimited
        default:
            throw Failure.http(status: status)
        }
    }

    /// How long to wait after a 429, from `Retry-After` or `X-RateLimit-Reset` (epoch seconds).
    private func retryDelay(for response: URLResponse) -> Duration {
        let http = response as? HTTPURLResponse
        if let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) {
            return .seconds(min(retryAfter, 60))
        }
        if let reset = http?.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init) {
            return .seconds(min(max(reset - Date.now.timeIntervalSince1970, 1), 60))
        }
        return .seconds(5)
    }
}
