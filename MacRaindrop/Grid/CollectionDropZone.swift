import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Takes drops on a collection chip in AppKit, not with SwiftUI's `onDrop`, which never sees the
/// drag images: over a collection that takes the drop, the dragged cards shrink to half, as they
/// do over a sidebar row (whose outline view does this itself), and grow back off it.
struct CollectionDropZone: NSViewRepresentable {
    let collection: RaindropCollection.ID
    let canWrite: Bool
    let targetChanged: (Bool) -> Void
    let drop: (_ bookmarks: [Raindrop.ID], _ collections: [RaindropCollection.ID]) -> Void

    func makeNSView(context: Context) -> CollectionDropView { CollectionDropView() }

    func updateNSView(_ view: CollectionDropView, context: Context) {
        view.collection = collection
        view.canWrite = canWrite
        view.targetChanged = targetChanged
        view.drop = drop
    }
}

final class CollectionDropView: NSView {
    var collection: RaindropCollection.ID?
    var canWrite = false
    var targetChanged: (Bool) -> Void = { _ in }
    var drop: ([Raindrop.ID], [RaindropCollection.ID]) -> Void = { _, _ in }

    private static let bookmarkType = NSPasteboard.PasteboardType(UTType.raindropBookmark.identifier)
    private static let collectionType = NSPasteboard.PasteboardType(UTType.raindropCollection.identifier)
    private static let shrinkScale: CGFloat = 0.5
    /// Whether the dragged items are at half size.
    private var isShrunk = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([Self.bookmarkType, Self.collectionType])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Clicks, drags and menus go to the chip; only drags arriving from elsewhere come here.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ info: any NSDraggingInfo) -> NSDragOperation {
        let operation = operation(for: info)
        guard !operation.isEmpty else { return [] }
        shrink(true, info)
        targetChanged(true)
        return operation
    }

    override func draggingUpdated(_ info: any NSDraggingInfo) -> NSDragOperation { operation(for: info) }

    override func draggingExited(_ info: (any NSDraggingInfo)?) {
        if let info { shrink(false, info) }
        endTargeting()
    }

    override func performDragOperation(_ info: any NSDraggingInfo) -> Bool {
        let items = info.draggingPasteboard.pasteboardItems ?? []
        let bookmarks = decode(RaindropLink.self, Self.bookmarkType, from: items).map(\.id)
        let collections = decode(CollectionDrag.self, Self.collectionType, from: items).map(\.id)
        guard !bookmarks.isEmpty || !collections.isEmpty else { return false }
        drop(bookmarks, collections)
        return true
    }

    /// After a drop, AppKit puts back the images the drag started with.
    override func concludeDragOperation(_ info: (any NSDraggingInfo)?) { endTargeting() }
    override func draggingEnded(_ info: any NSDraggingInfo) { endTargeting() }

    private func endTargeting() {
        isShrunk = false
        targetChanged(false)
    }

    /// A move, unless the store can't write or a collection is being dropped on itself.
    private func operation(for info: any NSDraggingInfo) -> NSDragOperation {
        guard canWrite, let collection else { return [] }
        let items = info.draggingPasteboard.pasteboardItems ?? []
        let droppingOnItself = decode(CollectionDrag.self, Self.collectionType, from: items).contains { $0.id == collection }
        return droppingOnItself ? [] : .move
    }

    private func decode<Item: Decodable>(_ type: Item.Type, _ pasteboardType: NSPasteboard.PasteboardType,
                                         from items: [NSPasteboardItem]) -> [Item] {
        items.compactMap { $0.data(forType: pasteboardType).flatMap { try? JSONDecoder().decode(Item.self, from: $0) } }
    }

    /// Scales every dragged item about the pointer, so the part under it stays under it.
    private func shrink(_ shrink: Bool, _ info: any NSDraggingInfo) {
        guard shrink != isShrunk else { return }
        isShrunk = shrink
        let scale = shrink ? Self.shrinkScale : 1 / Self.shrinkScale
        let pointer = convert(info.draggingLocation, from: nil)
        info.enumerateDraggingItems(options: [], for: self, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
            let frame = item.draggingFrame
            let components = item.imageComponents ?? []
            item.draggingFrame = NSRect(x: pointer.x - (pointer.x - frame.minX) * scale,
                                        y: pointer.y - (pointer.y - frame.minY) * scale,
                                        width: frame.width * scale, height: frame.height * scale)
            item.imageComponentsProvider = {
                components.map { component in
                    let scaled = NSDraggingImageComponent(key: component.key)
                    scaled.contents = component.contents
                    scaled.frame = NSRect(x: component.frame.minX * scale, y: component.frame.minY * scale,
                                          width: component.frame.width * scale, height: component.frame.height * scale)
                    return scaled
                }
            }
        }
    }
}
