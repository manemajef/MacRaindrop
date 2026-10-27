import Foundation
import Observation

/// Which library the app shows. Without a token there's no store, and the window asks for one.
@Observable
final class AppSession {
    private(set) var store: LibraryStore?

    /// Whether `RAINDROP_TEST` is set. It then wins over the saved token at every launch.
    let usesEnvironmentToken = ProcessInfo.processInfo.environment[RaindropServices.tokenEnvironmentKey]?.isEmpty == false

    init() {
        store = RaindropServices.makeDefault().map { LibraryStore(service: $0) }
    }

    var savedToken: String? {
        UserDefaults.standard.string(forKey: RaindropServices.tokenDefaultsKey)
    }

    /// Checks the token with Raindrop, then saves it and switches to that library.
    func connect(token: String) async throws {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let service = RaindropAPIService(token: token)
        _ = try await service.fetchStats()
        UserDefaults.standard.set(token, forKey: RaindropServices.tokenDefaultsKey)
        replaceStore(with: LibraryStore(service: service))
    }

    /// Forgets the saved token and the cached library, and goes back to asking for a token.
    func disconnect() {
        UserDefaults.standard.removeObject(forKey: RaindropServices.tokenDefaultsKey)
        replaceStore(with: nil)
    }

    #if DEBUG
    /// Shows the bundled sample data until the next launch.
    func useSampleData() {
        replaceStore(with: LibraryStore(service: SampleDataService()))
    }
    #endif

    /// A new token may be for another account, so the old account's cache goes first.
    private func replaceStore(with newStore: LibraryStore?) {
        if let store, store.service is RaindropAPIService {
            store.clearCache()
        }
        store = newStore
    }
}
