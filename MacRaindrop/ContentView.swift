import SwiftUI

struct ContentView: View {
    @Environment(LibraryStore.self) private var store
    @State private var sidebarSelection: SidebarItem? = .all
    @State private var raindropSelection: Raindrop.ID?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
        } content: {
            switch store.phase {
            case .idle, .loading:
                ProgressView()
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
        } detail: {
            if let id = raindropSelection, let raindrop = store.raindrop(id: id) {
                RaindropDetailView(raindrop: raindrop)
            } else {
                ContentUnavailableView("No Bookmark Selected", systemImage: "bookmark")
            }
        }
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
}

#Preview {
    ContentView()
        .environment(LibraryStore.preview)
}
