import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A subcollection at the top of the grid, drawn like a folder in Finder's icon view: the
/// system folder icon over its name and how much is inside. Selected, the icon gets a soft
/// highlight and the name an accent-colored label, as in Finder.
struct FolderTile: View {
    @Environment(LibraryStore.self) private var store
    let collection: RaindropCollection
    let isSelected: Bool

    static let iconSize: CGFloat = 64
    /// The same icon Finder draws for folders, tinted by the system.
    private static let icon = NSWorkspace.shared.icon(for: .folder)

    /// Bookmarks and folders inside, counted together, as Finder counts items.
    private var itemCount: Int {
        store.count(for: .collection(collection.id)) + store.subcollections(of: collection.id).count
    }

    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: Self.icon)
                .resizable()
                .frame(width: Self.iconSize, height: Self.iconSize)
                .padding(4)
                .background(isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))

            // Two lines kept even for short names, so every tile is the same height. The space
            // is kept outside the label, so a selected one-line name gets a one-line label.
            Text(verbatim: "\n")
                .font(.callout)
                .lineLimit(2, reservesSpace: true)
                .padding(.vertical, 1)
                .hidden()
                .frame(maxWidth: .infinity)
                .overlay(alignment: .top) {
                    Text(collection.title)
                        .font(.callout)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 4))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                }
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    let store = LibraryStore.preview
    let folders = Array(store.collections.prefix(3))
    HStack(spacing: GridMetrics.rowSpacing) {
        ForEach(folders) { folder in
            FolderTile(collection: folder, isSelected: folder.id == folders.first?.id)
        }
    }
//    .frame(width: 220)
    .padding(GridMetrics.inset)
    .environment(store)
}
