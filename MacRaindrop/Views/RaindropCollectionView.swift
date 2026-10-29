import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The desktop collection control. Bookmark content, menus, and writes stay in SwiftUI.
struct RaindropCollectionView: NSViewRepresentable {
    let raindrops: [Raindrop]
    let folders: [RaindropCollection]
    @Binding var selection: Set<Raindrop.ID>
    let store: LibraryStore
    let prompts: ActionPrompts
    let openFolder: (RaindropCollection.ID) -> Void
    let open: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        let collection = BookmarkCollectionView()
        collection.collectionViewLayout = NSCollectionViewFlowLayout()
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.allowsEmptySelection = true
        collection.backgroundColors = [.clear]
        collection.autoresizingMask = [.width]
        collection.register(CollectionItem.self, forItemWithIdentifier: CollectionItem.identifier)
        collection.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        collection.setDraggingSourceOperationMask(.copy, forLocal: false)
        collection.registerForDraggedTypes([
            NSPasteboard.PasteboardType(UTType.raindropBookmark.identifier),
            NSPasteboard.PasteboardType(UTType.raindropCollection.identifier)
        ])
        scrollView.documentView = collection
        context.coordinator.attach(to: collection)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(self)
    }

    final class Coordinator: NSObject, NSCollectionViewDelegateFlowLayout {
        private var parent: RaindropCollectionView
        private weak var collection: BookmarkCollectionView?
        private var dataSource: NSCollectionViewDiffableDataSource<Int, Entry>!
        private var content: [Entry: TileContent] = [:]
        private var bookmarkHeight: CGFloat = 0
        private var folderHeight: CGFloat = 0

        init(_ parent: RaindropCollectionView) { self.parent = parent }

        fileprivate func attach(to collection: BookmarkCollectionView) {
            self.collection = collection
            collection.delegate = self
            collection.activate = { [weak self] in self?.activateSelection() }
            collection.deleteSelection = { [weak self] in self?.deleteSelection() }
            collection.copySelection = { [weak self] in self?.copySelection() }
            collection.selectBookmarks = { [weak self] in self?.selectAllBookmarks() }
            collection.selectionChanged = { [weak self] in self?.publishSelection() }
            collection.contextMenu = { [weak self] path in self?.menu(at: path) }
            dataSource = NSCollectionViewDiffableDataSource(collectionView: collection) { [weak self] collection, path, entry in
                guard let self, let content = self.content[entry] else { return nil }
                let item = collection.makeItem(withIdentifier: CollectionItem.identifier, for: path) as! CollectionItem
                item.configure(content, store: self.parent.store)
                return item
            }
        }

        fileprivate func update(_ parent: RaindropCollectionView) {
            let changed = content.isEmpty || self.parent.raindrops != parent.raindrops || self.parent.folders != parent.folders
            self.parent = parent
            guard let collection else { return }
            if changed {
                content = Dictionary(uniqueKeysWithValues:
                    parent.folders.map { (Entry.folder($0.id), TileContent.folder($0)) }
                    + parent.raindrops.map { (Entry.bookmark($0.id), TileContent.bookmark($0)) }
                )
                measureTilesIfNeeded()
                var snapshot = NSDiffableDataSourceSnapshot<Int, Entry>()
                snapshot.appendSections([0, 1])
                snapshot.appendItems(parent.folders.map { .folder($0.id) }, toSection: 0)
                snapshot.appendItems(parent.raindrops.map { .bookmark($0.id) }, toSection: 1)
                if snapshot.itemIdentifiers != dataSource.snapshot().itemIdentifiers {
                    dataSource.apply(snapshot, animatingDifferences: false)
                }
                for path in collection.indexPathsForVisibleItems() {
                    if let entry = dataSource.itemIdentifier(for: path), let content = content[entry],
                       let item = collection.item(at: path) as? CollectionItem {
                        item.configure(content, store: parent.store)
                    }
                }
            }
            let nativeSelection = Set(collection.selectionIndexPaths.compactMap { path -> Raindrop.ID? in
                if case .bookmark(let id) = dataSource.itemIdentifier(for: path) { return id }
                return nil
            })
            if nativeSelection != parent.selection {
                collection.selectionIndexPaths = Set(parent.selection.compactMap { dataSource.indexPath(for: .bookmark($0)) })
            }
        }

        private func measureTilesIfNeeded() {
            if bookmarkHeight == 0, let raindrop = parent.raindrops.first {
                let view = NSHostingView(rootView: RaindropCard(raindrop: raindrop, isSelected: false).frame(width: 200))
                bookmarkHeight = ceil(view.fittingSize.height)
            }
            if folderHeight == 0, let folder = parent.folders.first {
                let view = NSHostingView(rootView: FolderTile(collection: folder, isSelected: false)
                    .frame(width: 200).environment(parent.store))
                folderHeight = ceil(view.fittingSize.height)
            }
        }

        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> NSSize {
            let available = max(1, collectionView.bounds.width - 32)
            let minimum: CGFloat = indexPath.section == 0 ? 170 : 180
            let columns = max(1, floor((available + 8) / (minimum + 8)))
            return NSSize(width: floor((available - (columns - 1) * 8) / columns),
                          height: indexPath.section == 0 ? folderHeight : bookmarkHeight)
        }

        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                            insetForSectionAt section: Int) -> NSEdgeInsets {
            guard collectionView.numberOfItems(inSection: section) > 0 else { return NSEdgeInsets() }
            return NSEdgeInsets(top: section == 1 && !parent.folders.isEmpty ? 0 : 16, left: 16, bottom: 16, right: 16)
        }

        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                            minimumInteritemSpacingForSectionAt section: Int) -> CGFloat { 8 }

        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                            minimumLineSpacingForSectionAt section: Int) -> CGFloat { 8 }

        func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {
            // Folder selection is singular and never mixed with bookmark selection.
            if let bookmark = indexPaths.first(where: { $0.section == 1 }) {
                return Set(indexPaths.filter { $0.section == bookmark.section })
            }
            return Set(indexPaths.sorted().prefix(1))
        }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            if let path = indexPaths.sorted().first {
                let allowed: Set<IndexPath> = path.section == 0 ? [path]
                    : Set(collectionView.selectionIndexPaths.filter { $0.section == path.section })
                if collectionView.selectionIndexPaths != allowed { collectionView.selectionIndexPaths = allowed }
                collection?.preferredAnchor = path
            }
            publishSelection()
        }

        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            publishSelection()
        }

        private func publishSelection() {
            guard let collection else { return }
            let ids = Set(collection.selectionIndexPaths.compactMap { path -> Raindrop.ID? in
                if case .bookmark(let id) = dataSource.itemIdentifier(for: path) { return id }
                return nil
            })
            if parent.selection != ids { parent.selection = ids }
        }

        private func activateSelection() {
            guard let collection else { return }
            for path in collection.selectionIndexPaths.sorted() {
                switch dataSource.itemIdentifier(for: path) {
                case .folder(let id): parent.openFolder(id)
                case .bookmark(let id):
                    if let url = parent.store.raindrop(id: id)?.url { parent.open(url) }
                case nil: break
                }
            }
        }

        private func deleteSelection() {
            parent.prompts.delete(parent.selection.compactMap(parent.store.raindrop(id:)), in: parent.store)
        }

        private func copySelection() {
            let urls = parent.raindrops.filter { parent.selection.contains($0.id) }.compactMap(\.url)
            guard !urls.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(urls as [NSURL])
        }

        private func selectAllBookmarks() {
            guard let collection else { return }
            collection.selectionIndexPaths = Set(parent.raindrops.indices.map { IndexPath(item: $0, section: 1) })
            publishSelection()
        }

        private func menu(at path: IndexPath) -> NSMenu? {
            switch dataSource.itemIdentifier(for: path) {
            case .bookmark(let id):
                let ids = parent.selection.contains(id) ? parent.selection : [id]
                return NSHostingMenu(rootView: RaindropActions(raindrops: ids.compactMap(parent.store.raindrop(id:)))
                    .environment(parent.store).environment(parent.prompts))
            case .folder(let id):
                let openFolder = parent.openFolder
                return NSHostingMenu(rootView: Button("Open", systemImage: "folder") { openFolder(id) })
            case nil: return nil
            }
        }

        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
            let item = NSPasteboardItem()
            switch dataSource.itemIdentifier(for: indexPath) {
            case .bookmark(let id):
                guard let url = parent.store.raindrop(id: id)?.url,
                      let data = try? JSONEncoder().encode(RaindropLink(id: id, url: url)) else { return nil }
                item.setData(data, forType: NSPasteboard.PasteboardType(UTType.raindropBookmark.identifier))
                item.setString(url.absoluteString, forType: .URL)
                item.setString(url.absoluteString, forType: .string)
            case .folder(let id):
                guard let data = try? JSONEncoder().encode(CollectionDrag(id: id)) else { return nil }
                item.setData(data, forType: NSPasteboard.PasteboardType(UTType.raindropCollection.identifier))
            case nil: return nil
            }
            return item
        }

        func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: any NSDraggingInfo,
                            proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                            dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
            guard let path = collectionView.indexPathForItem(at: collectionView.convert(draggingInfo.draggingLocation, from: nil)),
                  case .folder(let id) = dataSource.itemIdentifier(for: path), parent.store.canWrite,
                  !(draggingInfo.draggingPasteboard.pasteboardItems ?? []).contains(where: {
                      $0.data(forType: NSPasteboard.PasteboardType(UTType.raindropCollection.identifier))
                          .flatMap { try? JSONDecoder().decode(CollectionDrag.self, from: $0) }?.id == id
                  }) else { return [] }
            proposedDropIndexPath.pointee = path as NSIndexPath
            proposedDropOperation.pointee = .on
            return .move
        }

        func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: any NSDraggingInfo,
                            indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
            guard case .folder(let id) = dataSource.itemIdentifier(for: indexPath) else { return false }
            let items = draggingInfo.draggingPasteboard.pasteboardItems ?? []
            let bookmarks = items.compactMap {
                $0.data(forType: NSPasteboard.PasteboardType(UTType.raindropBookmark.identifier))
                    .flatMap { try? JSONDecoder().decode(RaindropLink.self, from: $0) }?.id
            }
            let folders = items.compactMap {
                $0.data(forType: NSPasteboard.PasteboardType(UTType.raindropCollection.identifier))
                    .flatMap { try? JSONDecoder().decode(CollectionDrag.self, from: $0) }?.id
            }
            guard !bookmarks.isEmpty || !folders.isEmpty else { return false }
            let action = LibraryDrop(target: .item(.collection(id)), store: parent.store, prompts: parent.prompts)
            Task {
                if !bookmarks.isEmpty { await action.bookmarks(bookmarks) }
                for folder in folders { await action.collection(folder) }
            }
            return true
        }
    }
}

private enum Entry: Hashable {
    case folder(RaindropCollection.ID)
    case bookmark(Raindrop.ID)
}

private enum TileContent: Equatable {
    case folder(RaindropCollection)
    case bookmark(Raindrop)

    var id: Entry {
        switch self {
        case .folder(let folder): .folder(folder.id)
        case .bookmark(let raindrop): .bookmark(raindrop.id)
        }
    }
}

private struct CollectionTile: View {
    @Environment(LibraryStore.self) private var store
    let content: TileContent
    let isSelected: Bool

    var body: some View {
        Group {
            switch content {
            case .bookmark(let raindrop):
                RaindropCard(raindrop: raindrop, isSelected: isSelected, isPending: store.pendingIDs.contains(raindrop.id))
            case .folder(let folder):
                FolderTile(collection: folder, isSelected: isSelected)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private final class CollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("RaindropTile")
    private var content: TileContent?
    private var store: LibraryStore?
    private let hostingView = TileHostingView(rootView: AnyView(EmptyView()))

    override var isSelected: Bool {
        didSet { if oldValue != isSelected { render() } }
    }

    override func loadView() {
        hostingView.sizingOptions = []
        // The native item must remain hittable when its SwiftUI content passes mouse events through.
        let container = NSView()
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        view = container
    }

    func configure(_ content: TileContent, store: LibraryStore) {
        guard self.content != content || self.store !== store else { return }
        self.content = content
        self.store = store
        render()
    }

    private func render() {
        guard let content, let store else { return }
        hostingView.rootView = AnyView(CollectionTile(content: content, isSelected: isSelected)
            .environment(store).id(content.id))
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        content = nil
        store = nil
        hostingView.rootView = AnyView(EmptyView())
    }
}

/// Mouse selection, dragging, and menus belong to the collection rather than the hosted card.
private final class TileHostingView: NSHostingView<AnyView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class BookmarkCollectionView: NSCollectionView {
    var activate: (() -> Void)?
    var deleteSelection: (() -> Void)?
    var copySelection: (() -> Void)?
    var selectBookmarks: (() -> Void)?
    var selectionChanged: (() -> Void)?
    var contextMenu: ((IndexPath) -> NSMenu?)?
    var preferredAnchor: IndexPath?
    private var isReflowing = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window, window.firstResponder == nil || window.firstResponder === window {
            window.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
        if event.clickCount == 2, indexPathForItem(at: convert(event.locationInWindow, from: nil)) != nil {
            activate?()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let path = indexPathForItem(at: convert(event.locationInWindow, from: nil)) else { return nil }
        return contextMenu?(path)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: activate?()
        case 51, 117: deleteSelection?()
        case 53:
            selectionIndexPaths = []
            selectionChanged?()
        default: super.keyDown(with: event)
        }
    }

    override func selectAll(_ sender: Any?) { selectBookmarks?() }
    @objc func copy(_ sender: Any?) { copySelection?() }

    override func setFrameSize(_ newSize: NSSize) {
        guard newSize.width != frame.width, !isReflowing, let scrollView = enclosingScrollView else {
            super.setFrameSize(newSize)
            return
        }
        isReflowing = true
        defer { isReflowing = false }

        let viewport = visibleRect
        let visible = indexPathsForVisibleItems().compactMap { path -> (IndexPath, NSRect)? in
            guard let rect = layoutAttributesForItem(at: path)?.frame, rect.intersects(viewport) else { return nil }
            return (path, rect)
        }.sorted { ($0.1.minY, $0.1.minX) < ($1.1.minY, $1.1.minX) }
        let selected = visible.first { $0.0 == preferredAnchor && selectionIndexPaths.contains($0.0) }
            ?? visible.first { selectionIndexPaths.contains($0.0) }
        // At the top, keep the folders visible unless a visible selection is the anchor.
        let anchor = selected ?? (viewport.minY > 0 ? visible.first : nil)

        super.setFrameSize(newSize)
        collectionViewLayout?.invalidateLayout()
        layoutSubtreeIfNeeded()

        if let (path, oldFrame) = anchor, let newFrame = layoutAttributesForItem(at: path)?.frame {
            let clip = scrollView.contentView
            let maximum = max(0, (collectionViewLayout?.collectionViewContentSize.height ?? frame.height) - clip.bounds.height)
            let y = min(maximum, max(0, newFrame.minY - (oldFrame.minY - viewport.minY)))
            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
            scrollView.reflectScrolledClipView(clip)
        }
    }
}
