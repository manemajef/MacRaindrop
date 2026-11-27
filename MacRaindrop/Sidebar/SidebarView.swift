import SwiftUI

struct SidebarView: View {
    @Environment(LibraryStore.self) private var store
    @Bindable var navigation: NavigationModel
    /// Collapsed or not, kept across launches. The chevron shows when hovering a heading.
    @AppStorage("sidebarShowsCollections") private var showsCollections = true
    @AppStorage("sidebarShowsFilters") private var showsFilters = true
    @AppStorage("sidebarShowsTags") private var showsTags = true
    /// Whether there's a Filters section at all (View › Show Filters in Sidebar).
    @AppStorage("sidebarFiltersEnabled") private var filtersEnabled = true

    /// The filters that match something, as in Raindrop, plus the one on screen even if it
    /// stopped matching, so its row doesn't vanish while selected.
    private var visibleFilters: [SidebarItem.Filter] {
        SidebarItem.Filter.allCases.filter { filter in
            store.count(for: .filter(filter)) > 0 || navigation.location == .filter(filter)
        }
    }

    private var selection: Binding<SidebarItem?> {
        Binding { navigation.location } set: { navigation.go(to: $0) }
    }

    var body: some View {
        // The footer floats over the bottom of the list on glass, like Xcode's navigator. The hard
        // edge cuts rows off cleanly behind it rather than fading them.
        list
            .safeAreaBar(edge: .bottom) { SidebarFooterView() }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .navigationTitle("Raindrop")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
    }

    private var list: some View {
        List(selection: selection) {
            Section {
                row(.all)
                row(.important)

            }
            
           

            Section(isExpanded: $showsCollections) {
                ForEach(store.collectionTree) { node in
                    CollectionRow(node: node, expandedCollections: $navigation.expandedCollections)
                }
            } header: {
                Text("Collections")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .topLevelCollectionsDropTarget()
                    .help("Drop a collection here to move it to the top level")
            }
            Section {
                row(.unsorted)

                row(.trash)
            }

            if filtersEnabled, !visibleFilters.isEmpty {
                Section(isExpanded: $showsFilters) {
                    ForEach(visibleFilters, id: \.self) { filter in
                        filterRow(filter)
                    }
                } header: {
                    Text("Filters")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                        .contextMenu {
                            Button("Hide Filters") { filtersEnabled = false }
                        }
                }
            }

            if !store.tags.isEmpty {
                Section("Tags", isExpanded: $showsTags) {
                    ForEach(store.tags, id: \.name) { tag in
                        Label(tag.name, systemImage: SidebarItem.tag(tag.name).systemImage)
                            .badge(tag.count)
                            .tag(SidebarItem.tag(tag.name))
                            .dropTarget(for: .tag(tag.name), highlights: false)
                    }
                }
            }
        }
    }

    /// A row with a filled, colored icon, as Raindrop draws its filters.
    private func filterRow(_ filter: SidebarItem.Filter) -> some View {
        let item = SidebarItem.filter(filter)
        return Label {
            Text(store.title(for: item))
        } icon: {
            FilterIcon(systemImage: item.systemImage, tint: filter.tint)
        }
        .badge(store.count(for: item))
        .tag(item)
        .dropTarget(for: item, highlights: false)
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(store.title(for: item), systemImage: item.systemImage)
            .badge(store.count(for: item))
            .tag(item)
            .dropTarget(for: item, highlights: false)
    }
}

/// A filter's filled icon, in its color while the window is active and gray otherwise. The
/// system grays the sidebar's other icons in an inactive window, but not a custom color.
/// Its own view, so only the icons redraw when the window becomes active or inactive.
private struct FilterIcon: View {
    @Environment(\.appearsActive) private var appearsActive
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .symbolVariant(.fill)
            .foregroundStyle(appearsActive ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
    }
}

private extension SidebarItem.Filter {
    /// Raindrop's colors for its filter icons.
    var tint: Color {
        switch self {
        case .highlights: .pink
        case .articles: .orange
        case .videos: .purple
        case .images: .green
        case .documents, .files: .cyan
        case .audio: .indigo
        case .broken: .red
        case .duplicates: .mint
        }
    }
}

/// A collection and, inside a disclosure group the app opens and closes, its subcollections.
/// Unlike `OutlineGroup`, this lets `NavigationModel` keep and set which ones are open.
private struct CollectionRow: View {
    @Environment(LibraryStore.self) private var store
    let node: CollectionNode
    @Binding var expandedCollections: Set<RaindropCollection.ID>

    var body: some View {
        if let children = node.children {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(children) { CollectionRow(node: $0, expandedCollections: $expandedCollections) }
            } label: {
                label
            }
        } else {
            label
        }
    }

    private var label: some View {
        Label(node.collection.title, systemImage: SidebarItem.collection(node.id).systemImage)
            .badge(store.count(for: .collection(node.id)))
            .tag(SidebarItem.collection(node.id))
            .draggable(CollectionDrag(id: node.id))
            .dropTarget(for: .collection(node.id), highlights: false)
    }

    private var isExpanded: Binding<Bool> {
        Binding {
            expandedCollections.contains(node.id)
        } set: { isExpanded in
            if isExpanded {
                expandedCollections.insert(node.id)
            } else {
                expandedCollections.remove(node.id)
            }
        }
    }
}

private struct SidebarFooterView: View {
    var body: some View {
        HStack(spacing: 0) {
            Menu {
                Button("New Bookmark…", systemImage: "bookmark") {}
                Button("New Collection…", systemImage: "folder.badge.plus") {}
                Divider()
                Button("Upload Image…", systemImage: "photo") {}
                Button("Upload File…", systemImage: "doc") {}
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .regular))
//                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(.circle)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .glassEffect(.regular.interactive(), in: .circle)
            .fixedSize()
            .help("Add")

            Spacer()
        }
        // Tucked into the sidebar's corner.
        .padding(8)
    }
}

/// One icon for the connection and sync state. Hover it for the details.
private struct SyncStatusIcon: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        Image(systemName: systemImage)
            .foregroundStyle(isProblem ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            .symbolEffect(.rotate, isActive: store.isSyncing && !isProblem)
            .frame(width: 22, height: 22)
            .contentShape(.rect)
            .help(details)
            .accessibilityLabel(details)
    }

    private var isProblem: Bool { !store.isOnline || store.syncError != nil }

    private var systemImage: String {
        if !store.isOnline { return "wifi.slash" }
        if store.syncError != nil { return "exclamationmark.icloud" }
        if store.isSyncing { return "arrow.triangle.2.circlepath" }
        return "checkmark.icloud"
    }

    private var details: String {
        let status: String
        if !store.isOnline {
            status = "Offline. Changes are turned off."
        } else if let error = store.syncError {
            status = error
        } else if store.isSyncing {
            status = "Syncing…"
        } else if let date = store.lastSyncedAt {
            status = "Synced \(date.formatted(.relativeNamed))"
        } else {
            status = "Not synced yet"
        }
        return "\(store.sourceName): \(status)"
    }
}
