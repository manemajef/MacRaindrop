import SwiftUI

struct SidebarView: View {
    @Environment(LibraryStore.self) private var store
    @Binding var selection: SidebarItem?
    @Binding var expandedCollections: Set<RaindropCollection.ID>

    var body: some View {
        List(selection: $selection) {
            Section {
                row(.all, systemImage: "tray.full")
                row(.unsorted, systemImage: "tray")
                row(.important, systemImage: "heart")
                row(.trash, systemImage: "trash")
            }

            Section("Collections") {
                ForEach(store.collectionTree) { node in
                    CollectionRow(node: node, expandedCollections: $expandedCollections)
                }
            }

            if !store.tags.isEmpty {
                Section("Tags") {
                    ForEach(store.tags, id: \.name) { tag in
                        Label(tag.name, systemImage: "number")
                            .badge(tag.count)
                            .tag(SidebarItem.tag(tag.name))
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showsSyncStatus {
                SyncStatusView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
        }
        .navigationTitle("Raindrop")
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
    }

    /// Sync details are for debugging. Release builds only mention it when something is wrong.
    private var showsSyncStatus: Bool {
        #if DEBUG
        true
        #else
        !store.isOnline || store.syncError != nil
        #endif
    }

    private func row(_ item: SidebarItem, systemImage: String) -> some View {
        Label(store.title(for: item), systemImage: systemImage)
            .badge(store.count(for: item))
            .tag(item)
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
        Label(node.collection.title, systemImage: node.children == nil ? "folder" : "folder.fill")
            .badge(store.count(for: .collection(node.id)))
            .tag(SidebarItem.collection(node.id))
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

private struct SyncStatusView: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(store.sourceName, systemImage: store.sourceName == "Sample Data" ? "shippingbox" : "cloud")
            Group {
                if !store.isOnline {
                    Label("Offline. Changes are turned off.", systemImage: "wifi.slash")
                        .foregroundStyle(.orange)
                } else if let error = store.syncError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                } else if store.isSyncing {
                    Text("Syncing…")
                } else if let date = store.lastSyncedAt {
                    Text("Synced \(Text(date, style: .relative)) ago")
                }
            }
            .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

#Preview {
    NavigationSplitView {
        SidebarView(selection: .constant(.all), expandedCollections: .constant([]))
    } detail: {
        Text("Detail")
    }
    .environment(LibraryStore.preview)
}
