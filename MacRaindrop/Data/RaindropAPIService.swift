import Foundation

/// Talks to the live Raindrop REST API (`https://api.raindrop.io/rest/v1`).
///
/// Authenticates with a test token (or, later, an OAuth access token) sent as a bearer header.
nonisolated struct RaindropAPIService: RaindropService {
    enum Failure: LocalizedError {
        case unauthorized
        case rateLimited
        case rejected(String?)
        case http(status: Int)
        case decoding(path: String, underlying: DecodingError)

        var errorDescription: String? {
            switch self {
            case .unauthorized: "Raindrop rejected the access token. Paste a new one in Settings."
            case .rateLimited: "Raindrop's rate limit was hit. Try again in a minute."
            case .rejected(let reason): reason ?? "Raindrop didn't accept the change."
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

    func fetchRaindrop(id: Raindrop.ID) async throws -> Raindrop {
        let response: ItemResponse<Raindrop> = try await get("raindrop/\(id)")
        return response.item
    }

    func updateRaindrop(id: Raindrop.ID, changes: RaindropChanges) async throws -> Raindrop {
        let response: ItemResponse<Raindrop> = try await send("PUT", "raindrop/\(id)", body: changes)
        guard response.result else { throw Failure.rejected(nil) }
        return response.item
    }

    func updateRaindrops(ids: [Raindrop.ID], inCollection collectionID: Int, changes: RaindropChanges) async throws {
        let response: WriteResponse = try await send("PUT", "raindrops/\(collectionID)", body: BulkChanges(ids: ids, changes: changes))
        guard response.result else { throw Failure.rejected(response.errorMessage) }
    }

    func updateCollection(id: RaindropCollection.ID, changes: CollectionChanges) async throws -> RaindropCollection {
        let response: ItemResponse<RaindropCollection> = try await send("PUT", "collection/\(id)", body: changes)
        guard response.result else { throw Failure.rejected(nil) }
        return response.item
    }

    func removeRaindrops(ids: [Raindrop.ID], inCollection collectionID: Int) async throws {
        let response: WriteResponse = try await send("DELETE", "raindrops/\(collectionID)", body: ["ids": ids])
        guard response.result else { throw Failure.rejected(response.errorMessage) }
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

    private func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        try await send("GET", path, query: query)
    }

    private func send<Response: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        retries: Int = 2
    ) async throws -> Response {
        var request = URLRequest(url: Self.baseURL.appending(path: path).appending(queryItems: query))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONEncoder.raindrop.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

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
            return try await send(method, path, query: query, body: body, retries: retries - 1)
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

/// The body of `PUT /raindrops/{collectionId}`: the changes, plus which raindrops they apply to.
private nonisolated struct BulkChanges: Encodable {
    var ids: [Raindrop.ID]
    var changes: RaindropChanges

    private enum CodingKeys: String, CodingKey { case ids }

    func encode(to encoder: any Encoder) throws {
        try changes.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ids, forKey: .ids)
    }
}
