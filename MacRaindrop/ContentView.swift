import SwiftUI

struct ContentView: View {
    @Environment(LibraryStore.self) private var store
    @State private var sidebarSelection: SidebarItem? = .all
    @State private var raindropSelection: Raindrop.ID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// The bookmark list follows the sidebar: hiding the sidebar leaves just the page.
    private var showsList: Bool { columnVisibility != .detailOnly }

    /// Drives the inner list/page split from the outer sidebar's visibility.
    private var listVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(get: { showsList ? .all : .detailOnly }, set: { _ in })
    }

    private var selectedRaindrop: Raindrop? {
        raindropSelection.flatMap(store.raindrop(id:))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $sidebarSelection)
        } detail: {
            // A nested split gives the list a real column that collapses with the sidebar,
            // each animated by its own split view.
            NavigationSplitView(columnVisibility: listVisibility) {
                list
                    .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 560)
            } detail: {
                detail
            }
        }
        .navigationTitle(title)
        .onChange(of: sidebarSelection) { raindropSelection = nil }
        .toolbar {
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
        }
        .task {
            if store.phase == .idle { await store.load() }
        }
    }

    private var title: String {
        if !showsList, let selectedRaindrop {
            selectedRaindrop.title
        } else {
            sidebarSelection.map(store.title(for:)) ?? "Raindrop"
        }
    }

    @ViewBuilder
    private var list: some View {
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
                RaindropListView(source: sidebarSelection, selection: $raindropSelection)
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
            ContentUnavailableView("No Bookmark Selected", systemImage: "bookmark")
        }
    }
}

#Preview {
    ContentView()
        .environment(LibraryStore.preview)
}
