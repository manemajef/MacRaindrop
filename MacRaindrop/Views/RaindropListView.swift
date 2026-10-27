import SwiftUI

struct RaindropListView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(ActionPrompts.self) private var prompts
    @Environment(\.openURL) private var openURL
    let raindrops: [Raindrop]
    @Binding var selection: Set<Raindrop.ID>

    private var selected: [Raindrop] { raindrops.filter { selection.contains($0.id) } }

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
        .copyable(selected.compactMap(\.url))
        .onDeleteCommand { prompts.delete(selected, in: store) }
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

#Preview {
    @Previewable @State var selection: Set<Raindrop.ID> = []
    let store = LibraryStore.preview
    RaindropListView(raindrops: store.raindrops(in: .all), selection: $selection)
        .environment(store)
        .environment(ActionPrompts())
}
