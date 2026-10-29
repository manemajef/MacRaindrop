import SwiftUI

/// SwiftUI owns the content and actions; AppKit owns collection layout and selection.
struct RaindropGridView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(ActionPrompts.self) private var prompts
    @Environment(\.openURL) private var openURL
    let raindrops: [Raindrop]
    @Binding var selection: Set<Raindrop.ID>
    var folders: [RaindropCollection] = []
    var openFolder: (RaindropCollection.ID) -> Void = { _ in }

    var body: some View {
        RaindropCollectionView(
            raindrops: raindrops,
            folders: folders,
            selection: $selection,
            store: store,
            prompts: prompts,
            openFolder: openFolder,
            open: { openURL($0) }
        )
    }
}

/// A subcollection at the top of the grid: its name, and what's inside.
struct FolderTile: View {
    @Environment(LibraryStore.self) private var store
    let collection: RaindropCollection
    let isSelected: Bool

    private var summary: String {
        let bookmarks = store.count(for: .collection(collection.id))
        let folders = store.subcollections(of: collection.id).count
        var parts = ["\(bookmarks) bookmark\(bookmarks == 1 ? "" : "s")"]
        if folders > 0 { parts.append("\(folders) folder\(folders == 1 ? "" : "s")") }
        return parts.formatted(.list(type: .and, width: .narrow))
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12).strokeBorder(.tint, lineWidth: 3)
            }
        }
        .contentShape(.rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A card in the style of Raindrop's iOS grid: cover, title, excerpt, tags, then source and date.
struct RaindropCard: View {
    let raindrop: Raindrop
    let isSelected: Bool
    /// A write to this raindrop is waiting for the server.
    var isPending = false

    @State private var isHovered = false

    /// About 16:10 at a typical card width. Fixed rather than a ratio of the width: then a
    /// card's height never changes as the grid resizes, and neither do the rows above the
    /// viewport. With a ratio, every row above grew or shrank on each frame of a sidebar
    /// animation, pushing the visible cards further the further down the grid was scrolled.
    private static let coverHeight: CGFloat = 125

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: Self.coverHeight)
                .overlay { CoverImage(url: raindrop.coverURL, kind: raindrop.type) }
                // Only trims the filled image to its frame; the card's shape rounds the top corners.
                .clipped()

            VStack(alignment: .leading, spacing: 5) {
                // Every line is reserved even when empty, so all cards are the same height.
                // The grid then needs no measuring pass to line rows up, and a card keeps
                // its identity (and its loaded cover) when the column count changes.
                Text(raindrop.title)
                    .font(.headline)
                    .lineLimit(2, reservesSpace: true)

                // An empty string reserves nothing, so a space stands in for a missing excerpt.
                Text(raindrop.excerpt.isEmpty ? " " : raindrop.excerpt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3, reservesSpace: true)

                // A tag's height, with or without tags.
                Text(verbatim: "#")
                    .font(.caption)
                    .padding(.vertical, 2)
                    .hidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) {
                        TagList(tags: raindrop.tags)
                            .fixedSize()
                    }
                    .clipped()

                footer
                    .padding(.top, 2)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(.background.secondary)
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12).strokeBorder(.tint, lineWidth: 3)
            } else if isHovered {
                RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 1)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isPending {
                ProgressView()
                    .controlSize(.small)
                    .padding(6)
                    .background(.regularMaterial, in: .circle)
                    .padding(8)
            }
        }
        .contentShape(.rect(cornerRadius: 12))
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: raindrop.type.systemImage)
                .accessibilityLabel(raindrop.type.label)
            Text(raindrop.domain)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if raindrop.broken {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Broken link")
            }
            if raindrop.important {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                    .accessibilityLabel("Favorite")
            }
            Text(raindrop.created, format: .dateTime.day().month(.abbreviated))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

extension View {
    /// Lets the raindrops inside drag out as URLs, all of the selection at once when a selected one is dragged.
    func raindropDragContainer(selection: Set<Raindrop.ID>) -> some View {
        modifier(RaindropDragContainer(selection: selection))
    }
}

private struct RaindropDragContainer: ViewModifier {
    @Environment(LibraryStore.self) private var store
    let selection: Set<Raindrop.ID>

    func body(content: Content) -> some View {
        content
            .dragContainer(for: RaindropLink.self) { ids in
                ids.compactMap { id in
                    store.raindrop(id: id)?.url.map { RaindropLink(id: id, url: $0) }
                }
            }
            .dragContainerSelection(Array(selection))
    }
}

#Preview {
    @Previewable @State var selection: Set<Raindrop.ID> = []
    let store = LibraryStore.preview
    RaindropGridView(raindrops: store.raindrops(in: .all), selection: $selection)
        .frame(width: 800, height: 600)
        .environment(store)
        .environment(ActionPrompts())
}
