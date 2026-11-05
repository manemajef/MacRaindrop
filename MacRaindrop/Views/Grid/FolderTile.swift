import AppKit
import SwiftUI

/// A subcollection at the top of the grid, drawn as a chip like Raindrop's iOS app: a folder
/// glyph and the name on one line, in a rounded, softly filled rectangle. Each chip is as wide as
/// its name, up to `maxWidth`. Selected, it fills with the accent color.
struct FolderTile: View {
    @Environment(LibraryStore.self) private var store
    let collection: RaindropCollection
    let isSelected: Bool
    /// Bookmarks or a collection are being dragged over it.
    var isDropTarget = false

    /// Longer names are truncated, so one long name can't take a whole row.
    static let maxWidth: CGFloat = 260
    static let cornerRadius: CGFloat = 10

    /// Bookmarks and folders inside, counted together, as Finder counts items.
    private var itemCount: Int {
        store.count(for: .collection(collection.id)) + store.subcollections(of: collection.id).count
    }

    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.tint) }
        if isDropTarget { return AnyShapeStyle(.tint.opacity(0.25)) }
        return AnyShapeStyle(.fill.tertiary)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            Text(collection.title)
                .lineLimit(1)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .font(.body)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Filling the width the grid gives it, so a truncated name still gets the whole chip.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: .rect(cornerRadius: Self.cornerRadius))
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(.tint, lineWidth: 2)
            }
        }
        .contentShape(.rect(cornerRadius: Self.cornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("^[\(itemCount) item](inflect: true)"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    let store = LibraryStore.preview
    let folders = Array(store.collections.prefix(4))
    HStack(spacing: GridMetrics.columnSpacing) {
        ForEach(folders) { folder in
            FolderTile(collection: folder, isSelected: folder.id == folders.first?.id)
                .fixedSize()
        }
    }
    .padding(GridMetrics.inset)
    .environment(store)
}
