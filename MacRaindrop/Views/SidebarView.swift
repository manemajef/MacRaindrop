import SwiftUI

struct SidebarView: View {
    @Environment(LibraryStore.self) private var store
    @Bindable var browser: BrowserModel
    /// Collapsed or not, kept across launches. The chevron shows when hovering a heading.
    @AppStorage("sidebarShowsCollections") private var showsCollections = true
    @AppStorage("sidebarShowsTags") private var showsTags = true

    private var selection: Binding<SidebarItem?> {
        Binding { browser.location } set: { browser.go(to: $0) }
    }

    var body: some View {
        // The footer floats over the bottom of the list on glass, like Xcode's navigator. The hard
        // edge cuts rows off cleanly behind it rather than fading them.
        list
            .safeAreaBar(edge: .bottom) { SidebarFooterView() }
            .scrollEdgeEffectStyle(.hard, for: .bottom)
            .navigationTitle("Raindrop")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
    }

    private var list: some View {
        List(selection: selection) {
            Section {
                row(.all, systemImage: "tray.full")
                row(.unsorted, systemImage: "tray")
                row(.important, systemImage: "heart")
                row(.trash, systemImage: "trash")
            }

            Section(isExpanded: $showsCollections) {
                ForEach(store.collectionTree) { node in
                    CollectionRow(node: node, expandedCollections: $browser.expandedCollections)
                }
            } header: {
                Text("Collections")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .topLevelCollectionsDropTarget()
                    .help("Drop a collection here to move it to the top level")
            }

            if !store.tags.isEmpty {
                Section("Tags", isExpanded: $showsTags) {
                    ForEach(store.tags, id: \.name) { tag in
                        Label(tag.name, systemImage: "number")
                            .badge(tag.count)
                            .tag(SidebarItem.tag(tag.name))
                            .dropTarget(for: .tag(tag.name))
                    }
                }
            }
        }
    }

    private func row(_ item: SidebarItem, systemImage: String) -> some View {
        Label(store.title(for: item), systemImage: systemImage)
            .badge(store.count(for: item))
            .tag(item)
            .dropTarget(for: item)
    }
}

/// A collection and, inside a disclosure group the app opens and closes, its subcollections.
/// Unlike `OutlineGroup`, this lets `BrowserModel` keep and set which ones are open.
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
        Label(node.collection.title, systemImage: node.children == nil ? "folder" : "folder")
            .badge(store.count(for: .collection(node.id)))
            .tag(SidebarItem.collection(node.id))
            .draggable(CollectionDrag(id: node.id))
            .dropTarget(for: .collection(node.id))
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
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
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
            status = "Synced \(date.formatted(.relative(presentation: .named)))"
        } else {
            status = "Not synced yet"
        }
        return "\(store.sourceName): \(status)"
    }
}
