import SwiftUI

/// A library window: sidebar, bookmarks as cards or a list, and the inspector.
struct ContentView: View {
    @Environment(LibraryStore.self) private var store
    @State private var navigation = NavigationModel()
    @State private var prompts = ActionPrompts()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    // The key keeps its old name, so the mode chosen before the rename is kept.
    @AppStorage("collectionMode") private var mode: ViewMode = .cards
    @AppStorage("raindropSort") private var sort: RaindropSort = .newest
    @AppStorage("showInspector") private var showInspector = true

    /// What the location shows, searched and sorted.
    private var raindrops: [Raindrop] {
        guard let location = navigation.location else { return [] }
        return store.raindrops(in: location, matching: navigation.searchText, sortedBy: sort)
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
            .libraryWindowBehaviors(navigation: navigation, prompts: prompts, showInspector: $showInspector)
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
                bookmarks
                    .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 440)
            } detail: {
                detail
                    .toolbar { toolbar }
            }
        case .cards:
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
            } detail: {
                bookmarks
                    // A floor for the grid, so the sidebar and inspector can't squeeze it to a
                    // sliver. The window can't shrink below it; the sidebar can still collapse.
                    .frame(minWidth: GridMetrics.minWidth)
                    .toolbar { toolbar }
            }
        }
    }

    private var toolbar: some ToolbarContent {
        ContentToolbar(navigation: navigation, mode: $mode, sort: $sort, isInspectorPresented: $showInspector)
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

    private var bookmarks: some View {
        BookmarksView(navigation: navigation, mode: mode, raindrops: raindrops)
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
                .id(selectedRaindrop.id)
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
