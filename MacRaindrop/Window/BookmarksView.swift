import SwiftUI

/// The bookmarks at the window's location, as cards or a list, or why there are none to show:
/// still loading, failed to load, nothing selected, nothing saved, or nothing found.
struct BookmarksView: View {
    @Environment(LibraryStore.self) private var store
    /// The model itself rather than bindings made from it, as for the sidebar.
    @Bindable var navigation: NavigationModel
    let mode: ViewMode
    /// What the location shows, searched and sorted. The window works it out once, since it
    /// also needs it for the subtitle.
    let raindrops: [Raindrop]

    /// The collections the location shows, as collection chips in cards mode.
    /// Hidden while searching, since the search covers bookmarks only.
    private var collections: [RaindropCollection] {
        guard mode == .cards, navigation.searchText.isEmpty, let location = navigation.location else { return [] }
        return store.collections(in: location)
    }

    var body: some View {
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
                loaded(at: location)
            } else {
                ContentUnavailableView("Select a Collection", systemImage: "sidebar.left")
            }
        }
    }

    private func loaded(at location: SidebarItem) -> some View {
        Group {
            switch mode {
            case .list:
                ListView(raindrops: raindrops, selection: $navigation.selection,
                         showsCollectionLabel: location.showsCollectionLabel)
            case .cards:
                GridView(raindrops: raindrops, selection: $navigation.selection, collections: collections,
                         showsCollectionLabel: location.showsCollectionLabel) { id in
                    navigation.go(to: .collection(id))
                }
            }
        }
        // A fresh list per location. Diffing one AppKit outline into a completely
        // different set of rows while its selection is cleared trips a SwiftUI assertion
        // (`ViewListTree.visitItem`), which crashed both the app and the live preview.
        .id(location)
        .overlay {
            if raindrops.isEmpty, collections.isEmpty {
                if navigation.searchText.isEmpty {
                    ContentUnavailableView("No Bookmarks", systemImage: "bookmark", description: Text("Nothing saved here yet."))
                } else {
                    ContentUnavailableView.search(text: navigation.searchText)
                }
            }
        }
    }
}
