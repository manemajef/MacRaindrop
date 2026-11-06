import AppKit
import SwiftUI

/// A subcollection at the top of the grid, drawn as a chip like Raindrop's iOS app: a folder
/// glyph and the name on one line, in a rounded, softly filled rectangle. Each chip is as wide as
/// its name, up to `maxWidth`. Selected, it fills with the accent color.
struct CollectionTile: View {
    @Environment(LibraryStore.self) private var store
    let collection: RaindropCollection
    let isSelected: Bool
    /// Bookmarks or a collection are being dragged over it.
    var isDropTarget = false
    
    /// Longer names are truncated, so one long name can't take a whole row.
    static let maxWidth: CGFloat = 260
    static let cornerRadius: CGFloat = 15

    /// Bookmarks and collections inside, counted together, as Finder counts items.
    private var itemCount: Int {
        store.count(for: .collection(collection.id)) + store.subcollections(of: collection.id).count
    }

    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.fill.tertiary) }
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
            if isDropTarget || isSelected {
                RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(.tint, lineWidth: 2)
            }
        }
        .contentShape(.rect(cornerRadius: Self.cornerRadius))
//        .glassEffect(in: .rect(cornerRadius: Self.cornerRadius))
        
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("^[\(itemCount) item](inflect: true)"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    let store = LibraryStore.preview
    let collections = Array(store.collections.prefix(4))
    HStack(spacing: GridMetrics.columnSpacing) {
        ForEach(collections) { collection in
            CollectionTile(collection: collection, isSelected: collection.id == collections.first?.id)
                .fixedSize()
        }
    }
    .padding(GridMetrics.inset)
    .previewEnvironment(store)
}
