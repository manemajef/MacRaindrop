import SwiftUI

/// How a collection's bookmarks are shown.
enum CollectionMode: String, CaseIterable, Identifiable {
    /// Sidebar and a grid of cards; double-clicking a card opens it in the browser.
    case cards
    
    /// Sidebar, bookmark list, and the selected page in a web view.
    case list

    var id: Self { self }

    var label: String {
        switch self {
        case .cards: "Cards"
        case .list: "List"
        }
    }

    var systemImage: String {
        switch self {
        case .cards: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}

struct ContentView: View {
    @Environment(LibraryStore.self) private var store
    @State private var browser = BrowserModel()
    @State private var prompts = ActionPrompts()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("collectionMode") private var mode: CollectionMode = .cards
    @AppStorage("raindropSort") private var sort: RaindropSort = .newest
    @AppStorage("showInspector") private var showInspector = true

    private var raindrops: [Raindrop] {
        guard let location = browser.location else { return [] }
        return store.raindrops(in: location, matching: browser.searchText, sortedBy: sort)
    }

    /// Subcollections of the current collection, shown as folder tiles in cards mode.
    /// Hidden while searching, since the search covers bookmarks only.
    private var folders: [RaindropCollection] {
        guard mode == .cards, browser.searchText.isEmpty, case .collection(let id) = browser.location else { return [] }
        return store.subcollections(of: id)
    }

    private var selectedRaindrops: [Raindrop] {
        browser.selection.compactMap(store.raindrop(id:))
    }

    /// The selected raindrop, when exactly one is selected.
    private var selectedRaindrop: Raindrop? {
        browser.selection.count == 1 ? browser.selection.first.flatMap(store.raindrop(id:)) : nil
    }

    var body: some View {
        @Bindable var browser = browser
        splitView
            .navigationTitle(title)
            .navigationSubtitle(store.phase == .loaded ? "\(raindrops.count) bookmarks" : "")
            .searchable(text: $browser.searchText, prompt: "Search \(browser.location.map(store.title(for:)) ?? "Bookmarks")")
            .inspector(isPresented: $showInspector) {
                inspector
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
            }
            // Bookmarks that leave the list (trashed, moved elsewhere) leave the selection too.
            .onChange(of: raindrops.map(\.id)) { _, visible in
                browser.selection.formIntersection(visible)
            }
            .onChange(of: browser.location, initial: true) {
                browser.revealLocation(in: store)
            }
            .focusedSceneValue(\.bookmarkContext, BookmarkContext(raindrops: selectedRaindrops, prompts: prompts))
            .focusedSceneValue(\.browser, browser)
            .presentsPrompts(prompts)
            .syncsAutomatically()
            .environment(prompts)
    }

    // MARK: Layout

    /// Three columns in list mode, two in cards mode. The inspector sits outside both.
    ///
    /// Only the sidebar and the list get column widths. The last column is whatever is left:
    /// giving it an ideal or max width too makes the split view fight the window over who
    /// gets the space, which shows up as columns jumping, especially in previews.
    ///
    /// The toolbar goes on the last column. On the split view itself every item collapses
    /// into the overflow menu; outside `.inspector`, the spacers between groups are ignored.
    @ViewBuilder
    private var splitView: some View {
        switch mode {
        case .list:
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
            } content: {
                collection
                    .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 440)
            } detail: {
                detail
                    .toolbar { toolbar }
            }
        case .cards:
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
            } detail: {
                collection
                    .toolbar { toolbar }
            }
        }
    }

    /// The same in both modes: ‹ › | view, sort | edit, inspector | search.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        HistoryToolbar(browser: browser)
        ViewOptionsToolbar(mode: $mode, sort: $sort)
        ToolbarSpacer(.fixed)
        EditAndInspectorToolbar(selection: selectedRaindrops, isInspectorPresented: $showInspector)
    }

    private var sidebar: some View {
        @Bindable var browser = browser
        return SidebarView(
            selection: Binding { browser.location } set: { browser.go(to: $0) },
            expandedCollections: $browser.expandedCollections
        )
    }

    private var title: String {
        if mode == .list, columnVisibility == .detailOnly, let selectedRaindrop {
            selectedRaindrop.title
        } else {
            browser.location.map(store.title(for:)) ?? "Raindrop"
        }
    }

    @ViewBuilder
    private var collection: some View {
        @Bindable var browser = browser
        switch store.phase {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Load Library", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await store.load() } }
                if store.service is RaindropAPIService {
                    SettingsLink { Text("Change Token…") }
                }
            }
        case .loaded:
            if let location = browser.location {
                Group {
                    switch mode {
                    case .list: RaindropListView(raindrops: raindrops, selection: $browser.selection)
                    case .cards:
                        RaindropGridView(raindrops: raindrops, selection: $browser.selection, folders: folders) { id in
                            browser.go(to: .collection(id))
                        }
                    }
                }
                // A fresh list per location. Diffing one AppKit outline into a completely
                // different set of rows while its selection is cleared trips a SwiftUI assertion
                // (`ViewListTree.visitItem`), which crashed both the app and the live preview.
                .id(location)
                .overlay {
                    if raindrops.isEmpty, folders.isEmpty {
                        if browser.searchText.isEmpty {
                            ContentUnavailableView("No Bookmarks", systemImage: "bookmark", description: Text("Nothing saved here yet."))
                        } else {
                            ContentUnavailableView.search(text: browser.searchText)
                        }
                    }
                }
            } else {
                ContentUnavailableView("Select a Collection", systemImage: "sidebar.left")
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedRaindrop {
            RaindropDetailView(raindrop: selectedRaindrop)
        } else {
            noSelection
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let selectedRaindrop {
            RaindropInfoView(raindrop: selectedRaindrop)
        } else {
            noSelection
        }
    }

    @ViewBuilder
    private var noSelection: some View {
        if browser.selection.count > 1 {
            ContentUnavailableView("\(browser.selection.count) Bookmarks Selected", systemImage: "square.stack")
        } else {
            ContentUnavailableView("No Bookmark Selected", systemImage: "bookmark")
        }
    }
}

#Preview {
    ContentView()
        // A real window size: without one the canvas sizes the split view to fit its content,
        // and the columns come out squeezed or jumping.
        .frame(width: 1200, height: 760)
        .environment(LibraryStore.preview)
}
