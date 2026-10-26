import Foundation
import OSLog

struct SyncReport: Equatable {
    enum Kind: Equatable {
        /// `changedBookmarksDate` hadn't moved, so no raindrops were fetched.
        case upToDate
        /// Only raindrops updated since the last sync were fetched and merged.
        case incremental(changed: Int)
        /// Everything was refetched: first sync, or the delta couldn't account for a deletion.
        case full(total: Int)
    }

    var kind: Kind
    var date: Date
}

/// Brings a `LibraryCache` up to date with a `RaindropService`, fetching as little as possible.
///
/// 1. `GET /user/stats`. If `changedBookmarksDate` matches the cursor, bookmarks are untouched.
/// 2. Otherwise fetch raindrops (library and trash) changed since the cursor and upsert them.
///    Moves to and from the trash show up here, because they bump `lastUpdate`.
/// 3. Permanent deletions leave no trace in a delta, so if local counts no longer match the
///    server's, fall back to a full refetch.
///
/// Collections are always refetched; it's two small requests.
@MainActor
final class SyncEngine {
    private let service: any RaindropService
    private let cache: LibraryCache
    private let logger = Logger(subsystem: "MacRaindrop", category: "sync")

    init(service: any RaindropService, cache: LibraryCache) {
        self.service = service
        self.cache = cache
    }

    func sync() async throws -> SyncReport {
        async let fetchedStats = service.fetchStats()
        async let fetchedCollections = service.fetchCollections()
        let (stats, collections) = try await (fetchedStats, fetchedCollections)

        do {
            let state = cache.syncState
            try cache.replaceCollections(collections)

            let kind: SyncReport.Kind
            if let cursor = state.changedBookmarksDate, cursor == stats.changedBookmarksDate {
                kind = .upToDate
            } else if let cursor = state.changedBookmarksDate {
                kind = try await incrementalSync(since: cursor, stats: stats)
            } else {
                kind = try await fullSync()
            }

            state.changedBookmarksDate = stats.changedBookmarksDate
            state.lastSyncedAt = .now
            try cache.save()

            logger.notice("Sync finished: \(String(describing: kind), privacy: .public)")
            return SyncReport(kind: kind, date: .now)
        } catch {
            cache.rollback()
            throw error
        }
    }

    private func incrementalSync(since cursor: Date, stats: LibraryStats) async throws -> SyncReport.Kind {
        // The server filters by whole UTC days, so step back one to cover the cursor's day.
        let since = cursor.addingTimeInterval(-24 * 60 * 60)
        async let library = service.fetchRaindrops(collectionID: SystemCollectionID.all, changedSince: since)
        async let trash = service.fetchRaindrops(collectionID: SystemCollectionID.trash, changedSince: since)
        let changed = try await library + trash
        try cache.upsertRaindrops(changed)

        guard try countsMatch(stats) else {
            logger.notice("Counts diverged after delta of \(changed.count); falling back to a full sync")
            return try await fullSync()
        }
        return .incremental(changed: changed.count)
    }

    private func fullSync() async throws -> SyncReport.Kind {
        async let library = service.fetchRaindrops(collectionID: SystemCollectionID.all)
        async let trash = service.fetchRaindrops(collectionID: SystemCollectionID.trash)
        let all = try await library + trash
        try cache.replaceRaindrops(all)
        return .full(total: all.count)
    }

    private func countsMatch(_ stats: LibraryStats) throws -> Bool {
        let trash = SystemCollectionID.trash
        let localLibrary = try cache.count(where: #Predicate { $0.collectionID != trash })
        let localTrash = try cache.count(where: #Predicate { $0.collectionID == trash })
        return localLibrary == stats.counts[SystemCollectionID.all]
            && localTrash == stats.counts[SystemCollectionID.trash]
    }
}
