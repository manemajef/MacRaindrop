import SwiftUI

struct RaindropListView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.openURL) private var openURL
    let raindrops: [Raindrop]
    @Binding var selection: Set<Raindrop.ID>

    var body: some View {
        List(raindrops, selection: $selection) { raindrop in
            RaindropRow(raindrop: raindrop, isPending: store.pendingIDs.contains(raindrop.id))
                .draggable(containerItemID: raindrop.id)
        }
        .contextMenu(forSelectionType: Raindrop.ID.self) { ids in
            RaindropActions(raindrops: ids.compactMap(store.raindrop(id:)))
        } primaryAction: { ids in
            // Double-click (or Return) opens the page in the default browser.
            for url in ids.compactMap({ store.raindrop(id: $0)?.url }) {
                openURL(url)
            }
        }
        .raindropDragContainer(selection: selection)
    }
}

struct RaindropRow: View {
    let raindrop: Raindrop
    /// A write to this raindrop is waiting for the server.
    var isPending = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverImage(url: raindrop.coverURL, kind: raindrop.type)
                .frame(width: 72, height: 54)
                .clipShape(.rect(cornerRadius: 6))
                .overlay {
                    if isPending {
                        ProgressView()
                            .controlSize(.small)
                            .padding(6)
                            .background(.regularMaterial, in: .circle)
                    }
                }

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

/// Shared menu items for one or more raindrops, used by the list and card context menus.
struct RaindropActions: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.openURL) private var openURL
    let raindrops: [Raindrop]

    private var urls: [URL] { raindrops.compactMap(\.url) }
    private var allFavorites: Bool { raindrops.allSatisfy(\.important) }

    var body: some View {
        if !urls.isEmpty {
            Button("Open in Browser", systemImage: "safari") { urls.forEach { openURL($0) } }
            if let url = urls.first, urls.count == 1 {
                ShareLink(item: url)
            }
            Button(urls.count == 1 ? "Copy Link" : "Copy \(urls.count) Links", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(urls.map(\.absoluteString).joined(separator: "\n"), forType: .string)
            }
            Divider()
        }
        if !raindrops.isEmpty {
            Button(
                allFavorites ? "Remove from Favorites" : "Add to Favorites",
                systemImage: allFavorites ? "heart.slash" : "heart"
            ) {
                let ids = raindrops.map(\.id)
                let important = !allFavorites
                Task { await store.setImportant(ids, important) }
            }
            .disabled(!store.canModify(raindrops.map(\.id)))
        }
    }
}

#Preview {
    @Previewable @State var selection: Set<Raindrop.ID> = []
    let store = LibraryStore.preview
    RaindropListView(raindrops: store.raindrops(in: .all), selection: $selection)
        .environment(store)
}
