import SwiftUI

struct RaindropListView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.openURL) private var openURL
    let source: SidebarItem
    @Binding var selection: Raindrop.ID?

    @State private var searchText = ""
    @AppStorage("raindropSort") private var sort: RaindropSort = .newest

    private var raindrops: [Raindrop] {
        store.raindrops(in: source, matching: searchText, sortedBy: sort)
    }

    var body: some View {
        List(raindrops, selection: $selection) { raindrop in
            RaindropRow(raindrop: raindrop)
        }
        .contextMenu(forSelectionType: Raindrop.ID.self) { ids in
            if let id = ids.first, let raindrop = store.raindrop(id: id) {
                RaindropActions(raindrop: raindrop)
            }
        } primaryAction: { ids in
            // Double-click (or Return) opens the page in the default browser.
            for url in ids.compactMap({ store.raindrop(id: $0)?.url }) {
                openURL(url)
            }
        }
        .overlay {
            if raindrops.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView("No Bookmarks", systemImage: "bookmark", description: Text("Nothing saved here yet."))
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search \(store.title(for: source))")
        #if os(macOS)
        .navigationSubtitle("\(raindrops.count) bookmarks")
        #endif
        .toolbar {
            ToolbarItem {
                Menu("Sort", systemImage: "arrow.up.arrow.down") {
                    Picker("Sort", selection: $sort) {
                        ForEach(RaindropSort.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
            }
        }
        .onChange(of: source) { searchText = "" }
    }
}

struct RaindropRow: View {
    let raindrop: Raindrop

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverImage(url: raindrop.coverURL, kind: raindrop.type)
                .frame(width: 72, height: 54)
                .clipShape(.rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(raindrop.title)
                        .font(.headline)
                        .lineLimit(2)
                    if raindrop.important {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                            .imageScale(.small)
                            .accessibilityLabel("Favorite")
                    }
                }

                if !raindrop.excerpt.isEmpty {
                    Text(raindrop.excerpt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Label(raindrop.type.label, systemImage: raindrop.type.systemImage)
                        .labelStyle(.iconOnly)
                    Text(raindrop.domain)
                    Text("·")
                    Text(raindrop.created, format: .relative(presentation: .named))
                    if raindrop.broken {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Broken link")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)

                if !raindrop.tags.isEmpty {
                    TagList(tags: raindrop.tags)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Shared menu items for a raindrop, used by the context menu and the detail toolbar.
struct RaindropActions: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.openURL) private var openURL
    let raindrop: Raindrop

    var body: some View {
        if let url = raindrop.url {
            Button("Open in Browser", systemImage: "safari") { openURL(url) }
            ShareLink(item: url)
            #if os(macOS)
            Button("Copy Link", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
            #endif
            Divider()
        }
        Button(
            raindrop.important ? "Remove from Favorites" : "Add to Favorites",
            systemImage: raindrop.important ? "heart.slash" : "heart"
        ) {
            store.toggleImportant(raindrop.id)
        }
    }
}

#Preview {
    @Previewable @State var selection: Raindrop.ID?
    NavigationStack {
        RaindropListView(source: .all, selection: $selection)
    }
    .environment(LibraryStore.preview)
}
