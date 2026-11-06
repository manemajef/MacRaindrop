import SwiftUI

/// A library window: sidebar, bookmarks as cards or a list, and the inspector.
struct ContentView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppSession.self) private var session
    @Environment(\.appearsActive) private var appearsActive
    @State private var navigation = NavigationModel()
    @State private var prompts = ActionPrompts()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("collectionMode") private var mode: CollectionMode = .cards
    @AppStorage("raindropSort") private var sort: RaindropSort = .newest
    @AppStorage("showInspector") private var showInspector = true

    private var raindrops: [Raindrop] {
        guard let location = navigation.location else { return [] }
        return store.raindrops(in: location, matching: navigation.searchText, sortedBy: sort)
    }

    /// Subcollections of the current collection, shown as collection chips in cards mode.
    /// Hidden while searching, since the search covers bookmarks only.
    private var subcollections: [RaindropCollection] {
        guard mode == .cards, navigation.searchText.isEmpty, case .collection(let id) = navigation.location else { return [] }
        return store.subcollections(of: id)
    }

    private var selectedRaindrops: [Raindrop] {
        navigation.selection.compactMap(store.raindrop(id:))
    }

    /// The selected raindrop, when exactly one is selected.
    private var selectedRaindrop: Raindrop? {
        navigation.selection.count == 1 ? navigation.selection.first.flatMap(store.raindrop(id:)) : nil
    }

    var body: some View {
        @Bindable var navigation = navigation
        splitView
            .navigationTitle(title)
            .navigationSubtitle(store.phase == .loaded ? "\(raindrops.count) bookmarks" : "")
            .searchable(text: $navigation.searchText, prompt: "Search \(navigation.location.map(store.title(for:)) ?? "Bookmarks")")
            .inspector(isPresented: $showInspector) {
                inspector
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
            }
            // Bookmarks that leave the list (trashed, moved elsewhere) leave the selection too.
            .onChange(of: raindrops.map(\.id)) { _, visible in
                navigation.selection.formIntersection(visible)
            }
            .onChange(of: navigation.location, initial: true) {
                navigation.revealLocation(in: store)
            }
            .focusedSceneValue(\.bookmarkContext, BookmarkContext(raindrops: selectedRaindrops, prompts: prompts))
            .focusedSceneValue(\.navigation, navigation)
            .presentsPrompts(prompts)
            .syncsAutomatically()
            .environment(prompts)
            // Until the app has a delegate, the first window sets up Quick Search.
            .task { QuickSearchController.install(session: session) }
            .onChange(of: session.revealRequest) { takeRevealRequest() }
            .onChange(of: appearsActive) { takeRevealRequest() }
    }

    /// Shows the bookmark Quick Search asked for, if this is the window in front.
    private func takeRevealRequest() {
        guard appearsActive, let id = session.revealRequest else { return }
        session.revealRequest = nil
        guard let raindrop = store.raindrop(id: id) else { return }
        navigation.reveal(raindrop)
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
                    // A floor for the grid, so the sidebar and inspector can't squeeze it to a
                    // sliver. The window can't shrink below it; the sidebar can still collapse.
                    .frame(minWidth: GridMetrics.minWidth)
                    .toolbar { toolbar }
            }
        }
    }

    private var toolbar: some ToolbarContent {
        ContentToolbar(navigation: navigation, mode: $mode, sort: $sort,
                       selection: selectedRaindrops, isInspectorPresented: $showInspector)
    }

    /// Gets the model itself rather than bindings made here: a binding built from closures
    /// never compares equal, so the sidebar would redraw (and recount) on every click.
    private var sidebar: some View {
        SidebarView(navigation: navigation)
    }

    private var title: String {
        if mode == .list, columnVisibility == .detailOnly, let selectedRaindrop {
            selectedRaindrop.title
        } else {
            navigation.location.map(store.title(for:)) ?? "Raindrop"
        }
    }

    @ViewBuilder
    private var collection: some View {
        @Bindable var navigation = navigation
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
            if let location = navigation.location {
                Group {
                    switch mode {
                    case .list: ListView(raindrops: raindrops, selection: $navigation.selection)
                    case .cards:
                        GridView(raindrops: raindrops, selection: $navigation.selection, collections: subcollections) { id in
                            navigation.go(to: .collection(id))
                        }
                    }
                }
                // A fresh list per location. Diffing one AppKit outline into a completely
                // different set of rows while its selection is cleared trips a SwiftUI assertion
                // (`ViewListTree.visitItem`), which crashed both the app and the live preview.
                .id(location)
                .overlay {
                    if raindrops.isEmpty, subcollections.isEmpty {
                        if navigation.searchText.isEmpty {
                            ContentUnavailableView("No Bookmarks", systemImage: "bookmark", description: Text("Nothing saved here yet."))
                        } else {
                            ContentUnavailableView.search(text: navigation.searchText)
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
            PageView(raindrop: selectedRaindrop)
        } else {
            noSelection
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let selectedRaindrop {
            InspectorView(raindrop: selectedRaindrop)
        } else {
            noSelection
        }
    }

    @ViewBuilder
    private var noSelection: some View {
        if navigation.selection.count > 1 {
            ContentUnavailableView("\(navigation.selection.count) Bookmarks Selected", systemImage: "square.stack")
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
        .previewEnvironment()
        .environment(AppSession())
}
