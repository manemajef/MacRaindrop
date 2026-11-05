import AppKit
import Observation

/// What the Quick Search panel shows: the query, its results and which one is selected.
@Observable
final class QuickSearchModel {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            limit = Self.pageSize
            search()
        }
    }
    private(set) var results: [Raindrop] = []
    private(set) var selectedID: Raindrop.ID?
    /// Goes up when the keyboard moves the selection. Only then does the list scroll to it.
    private(set) var keyboardMoves = 0
    /// Whether `results` answer the current query yet, so "No Results" doesn't flash while typing.
    private(set) var isSearching = false
    /// Goes up each time the panel is shown, so the view can focus the field again.
    private(set) var presentation = 0

    @ObservationIgnored private let session: AppSession
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    /// How many results are shown. Scrolling near the end raises it a page at a time.
    @ObservationIgnored private var limit = pageSize
    /// Whether the index had more matches than `limit` allowed.
    @ObservationIgnored private var hasMore = false
    @ObservationIgnored private var collectionPaths: [RaindropCollection.ID: String] = [:]
    /// Where the pointer was at the last hover that counted.
    @ObservationIgnored private var lastHoverLocation: NSPoint?
    /// Called once the panel should close. True when focus should go back to the app that had it,
    /// false when an action is about to bring another app (or this one) forward anyway.
    @ObservationIgnored var dismiss: (_ restoresFocus: Bool) -> Void = { _ in }

    static let pageSize = 50

    init(session: AppSession) {
        self.session = session
    }

    var store: LibraryStore? { session.store }

    var selectedRaindrop: Raindrop? {
        results.first { $0.id == selectedID } ?? results.first
    }

    func collectionPath(for raindrop: Raindrop) -> String? {
        collectionPaths[raindrop.collectionID]
    }

    // MARK: Presentation

    /// Shows cached results at once, then syncs in the background if the library is stale.
    func willPresent() {
        presentation += 1
        // The pointer may be resting where the panel appears; that isn't a hover.
        lastHoverLocation = NSEvent.mouseLocation
        limit = Self.pageSize
        search()
        guard let store else { return }
        Task {
            if store.phase == .idle { await store.load() } else { await store.syncIfStale() }
        }
    }

    // MARK: Searching

    /// Runs the query against the index. Once the index is built this answers in the same frame
    /// as the keystroke (a scan takes a few milliseconds), so results never lag behind the field
    /// or flash empty. Until then it waits for the build in the background.
    func search() {
        searchTask?.cancel()
        guard let store else {
            results = []
            return
        }
        if let index = store.readySearchIndex {
            show(index.search(query, limit: limit), from: store)
            return
        }
        isSearching = true
        searchTask = Task {
            let index = await store.searchIndex()
            guard !Task.isCancelled else { return }
            show(index.search(query, limit: limit), from: store)
        }
    }

    private func show(_ matches: [SearchIndex.Match], from store: LibraryStore, keepingSelection: Bool = false) {
        let previous = selectedID
        collectionPaths = store.collectionPaths
        results = matches.compactMap { store.raindrop(id: $0.id) }
        hasMore = matches.count == limit
        // Keep the selection on the same bookmark when results refresh after a sync, or grow by a page.
        let keeps = !query.isEmpty || keepingSelection
        selectedID = keeps && results.contains { $0.id == previous } ? previous : results.first?.id
        isSearching = false
    }

    /// Adds the next page of results, if there are more. A rescan takes a few milliseconds,
    /// so this reruns the query with a higher limit rather than keeping a cursor.
    func loadMore() {
        guard hasMore, let store, let index = store.readySearchIndex else { return }
        limit += Self.pageSize
        show(index.search(query, limit: limit), from: store, keepingSelection: true)
    }

    /// A row scrolled into view. Near the end of the list, the next page loads.
    func rowAppeared(_ id: Raindrop.ID) {
        if results.suffix(10).contains(where: { $0.id == id }) { loadMore() }
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? 0
        if current + offset >= results.count { loadMore() }
        let next = min(max(current + offset, 0), results.count - 1)
        selectedID = results[next].id
        keyboardMoves += 1
    }

    /// The pointer entered a row. Ignored unless the mouse itself moved: rows also slide under
    /// a still pointer when the keyboard scrolls the list, and that shouldn't take the selection.
    func hover(_ id: Raindrop.ID) {
        let location = NSEvent.mouseLocation
        guard location != lastHoverLocation else { return }
        lastHoverLocation = location
        selectedID = id
    }

    /// A click on a row opens it.
    func open(_ id: Raindrop.ID) {
        selectedID = id
        openSelected()
    }

    // MARK: Actions

    /// Return: opens the bookmark's page in the default browser.
    func openSelected() {
        guard let url = selectedRaindrop?.url else { return }
        dismiss(false)
        NSWorkspace.shared.open(url)
    }

    /// Command-Return: brings the app forward with the bookmark selected in its window.
    func revealSelected() {
        guard let raindrop = selectedRaindrop else { return }
        dismiss(false)
        session.revealRequest = raindrop.id
        AppDelegate.showMainWindow()
    }

    /// Escape: clears the query first, then closes.
    func cancel() {
        if query.isEmpty { dismiss(true) } else { query = "" }
    }
}
