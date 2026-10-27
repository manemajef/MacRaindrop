import SwiftUI

/// How a collection's bookmarks are shown.
enum CollectionMode: String, CaseIterable, Identifiable {
    /// Sidebar, bookmark list, and the selected page in a web view.
    case list
    /// Sidebar and a grid of cards; double-clicking a card opens it in the browser.
    case cards

    var id: Self { self }

    var label: String {
        switch self {
        case .list: "List"
        case .cards: "Cards"
        }
    }

    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .cards: "square.grid.2x2"
        }
    }
}

struct ContentView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var sidebarSelection: SidebarItem? = .all
    @State private var selection: Set<Raindrop.ID> = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchText = ""
    @AppStorage("collectionMode") private var mode: CollectionMode = .list
    @AppStorage("raindropSort") private var sort: RaindropSort = .newest
    @AppStorage("showInspector") private var showInspector = true

    private var raindrops: [Raindrop] {
        guard let sidebarSelection else { return [] }
        return store.raindrops(in: sidebarSelection, matching: searchText, sortedBy: sort)
    }

    private var selectedRaindrops: [Raindrop] {
        selection.compactMap(store.raindrop(id:))
    }

    /// The selected raindrop, when exactly one is selected.
    private var selectedRaindrop: Raindrop? {
        selection.count == 1 ? selection.first.flatMap(store.raindrop(id:)) : nil
    }

    var body: some View {
        splitView
            .navigationTitle(title)
            .navigationSubtitle(store.phase == .loaded ? "\(raindrops.count) bookmarks" : "")
            .searchable(text: $searchText, prompt: "Search \(sidebarSelection.map(store.title(for:)) ?? "Bookmarks")")
            .inspector(isPresented: $showInspector) {
                inspector
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
            }
            .onChange(of: sidebarSelection) {
                selection = []
                searchText = ""
            }
            .task {
                if store.phase == .idle { await store.load() }
            }
    }

    // MARK: Layout

    /// Three columns in list mode, two in cards mode. The inspector sits outside both.
    ///
    /// Only the sidebar and the list get column widths. The last column is whatever is left:
    /// giving it an ideal or max width too makes the split view fight the window over who
    /// gets the space, which shows up as columns jumping, especially in previews.
    ///
    /// The toolbar goes on the last column. On the split view itself every item collapses
    /// into the overflow menu; outside `.inspector`, the spacer that keeps the inspector
    /// button in its own capsule is ignored.
    @ViewBuilder
    private var splitView: some View {
        switch mode {
        case .list:
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(selection: $sidebarSelection)
            } content: {
                collection
                    .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 440)
            } detail: {
                detail
                    .toolbar { toolbar }
            }
        case .cards:
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(selection: $sidebarSelection)
            } detail: {
                collection
                    .toolbar { toolbar }
            }
        }
    }

    private var title: String {
        if mode == .list, columnVisibility == .detailOnly, let selectedRaindrop {
            selectedRaindrop.title
        } else {
            sidebarSelection.map(store.title(for:)) ?? "Raindrop"
        }
    }

    @ViewBuilder
    private var collection: some View {
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
            }
        case .loaded:
            if let sidebarSelection {
                Group {
                    switch mode {
                    case .list: RaindropListView(raindrops: raindrops, selection: $selection)
                    case .cards: RaindropGridView(raindrops: raindrops, selection: $selection)
                    }
                }
                // A fresh list per sidebar item. Diffing one AppKit outline into a completely
                // different set of rows while its selection is cleared trips a SwiftUI assertion
                // (`ViewListTree.visitItem`), which crashed both the app and the live preview.
                .id(sidebarSelection)
                .overlay {
                    if raindrops.isEmpty {
                        if searchText.isEmpty {
                            ContentUnavailableView("No Bookmarks", systemImage: "bookmark", description: Text("Nothing saved here yet."))
                        } else {
                            ContentUnavailableView.search(text: searchText)
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
        if selection.count > 1 {
            ContentUnavailableView("\(selection.count) Bookmarks Selected", systemImage: "square.stack")
        } else {
            ContentUnavailableView("No Bookmark Selected", systemImage: "bookmark")
        }
    }

    // MARK: Toolbar

    /// Laid out left to right: sync | view switch | sort | actions | inspector, then search,
    /// which macOS always puts last. Items next to each other share one glass capsule unless
    /// a fixed `ToolbarSpacer` separates them.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if store.isSyncing && store.phase == .loaded {
                ProgressView().controlSize(.small)
            } else {
                Button("Sync", systemImage: "arrow.clockwise") {
                    Task { await store.sync() }
                }
                .disabled(store.isSyncing)
            }
        }

        ToolbarItem {
            Picker("View", selection: $mode) {
                ForEach(CollectionMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("Show bookmarks as a list or as cards")
        }

        ToolbarItem {
            Menu("Sort", systemImage: "arrow.up.arrow.down") {
                Picker("Sort", selection: $sort) {
                    ForEach(RaindropSort.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            }
        }

        ToolbarSpacer(.fixed)

        ToolbarItemGroup {
            Button {
                store.setImportant(selection, !selectedRaindrops.allSatisfy(\.important))
            } label: {
                let isFavorite = !selectedRaindrops.isEmpty && selectedRaindrops.allSatisfy(\.important)
                Label("Favorite", systemImage: isFavorite ? "heart.fill" : "heart")
            }
            .disabled(selection.isEmpty)

            Button("Open in Browser", systemImage: "safari") {
                selectedRaindrops.compactMap(\.url).forEach { openURL($0) }
            }
            .disabled(selectedRaindrops.allSatisfy { $0.url == nil })

            if let url = selectedRaindrop?.url {
                ShareLink(item: url)
            }
        }

        ToolbarSpacer(.fixed)

        ToolbarItem {
            Button {
                showInspector.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help(showInspector ? "Hide Inspector" : "Show Inspector")
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
