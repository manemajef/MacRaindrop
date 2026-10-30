import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The grid's layout, in points. Card height isn't set here: it comes from the card's contents
/// (see the Height section of `RaindropCard`), measured once in `measureTilesIfNeeded()`.
enum GridMetrics {
    /// Space between the grid and the edges of its column.
    static let inset: CGFloat = 16
    /// Gap between tiles side by side.
    static let columnSpacing: CGFloat = 16
    /// Gap between rows.
    static let rowSpacing: CGFloat = 16
    /// The narrowest a bookmark card gets. Below it, the grid drops a column and cards widen
    /// to fill the row, up to the width at which another column fits.
    static let minCardWidth: CGFloat = 210
    /// Folder tiles, in their own rows above the bookmarks, don't stretch: what a row doesn't
    /// use is left at its end, so folders stay put while the grid resizes.
    static let folderWidth: CGFloat = 104
    /// The narrowest the grid gets, between the sidebar and the inspector: about a third of a
    /// 14-inch MacBook Pro's 1512-point screen, room for two cards.
    static let minWidth: CGFloat = 440
    /// The "Collections" and "Bookmarks" headings, shown when a page has both.
    static let headerHeight: CGFloat = 40

    /// How many tiles at least `minimum` wide fit across `width`.
    static func columns(across width: CGFloat, minimum: CGFloat) -> Int {
        let available = max(1, width - 2 * inset)
        return max(1, Int((available + columnSpacing) / (minimum + columnSpacing)))
    }
}

/// What bookmark cards do with the space a row doesn't use. Except for `stretch`, cards keep
/// `GridMetrics.minCardWidth`, and the names follow CSS's `justify-content`. Chosen from the
/// Debug menu, to compare how each looks and animates while the grid resizes.
enum CardSpacing: String, CaseIterable, Identifiable {
    /// Cards widen to fill the row.
    case stretch
    /// Cards stay put from the left, and the space is left at the row's end, like the folders.
    case leading
    case spaceBetween
    case spaceAround
    case spaceEvenly

    static let storageKey = "gridCardSpacing"

    var id: Self { self }

    var title: String {
        switch self {
        case .stretch: "Stretch"
        case .leading: "Leading"
        case .spaceBetween: "Space Between"
        case .spaceAround: "Space Around"
        case .spaceEvenly: "Space Evenly"
        }
    }

    /// The space before the first column and between columns, for `columns` tiles `width` wide
    /// across `available`, at least `spacing` apart.
    func placement(columns: Int, width: CGFloat, spacing: CGFloat, available: CGFloat) -> (lead: CGFloat, gap: CGFloat) {
        let n = CGFloat(columns)
        let extra = max(0, available - n * width - (n - 1) * spacing)
        switch self {
        case .stretch, .leading: return (0, spacing)
        case .spaceBetween: return columns > 1 ? (0, spacing + extra / (n - 1)) : (extra / 2, spacing)
        case .spaceAround: return (extra / (2 * n), spacing + extra / n)
        case .spaceEvenly: return (extra / (n + 1), spacing + extra / (n + 1))
        }
    }
}

/// The desktop collection control. Bookmark content, menus, and writes stay in SwiftUI.
struct GridCollectionView: NSViewRepresentable {
    let raindrops: [Raindrop]
    let folders: [RaindropCollection]
    @Binding var selection: Set<Raindrop.ID>
    let store: LibraryStore
    let prompts: ActionPrompts
    let openFolder: (RaindropCollection.ID) -> Void
    let open: (URL) -> Void
    var cardSpacing: CardSpacing = .stretch

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        // The view extends under the toolbar (see `RaindropGridView`); these insets start the
        // content below it, and let it scroll up underneath, like a SwiftUI `ScrollView`.
        scrollView.automaticallyAdjustsContentInsets = true
        let collection = BookmarkCollectionView()
        collection.collectionViewLayout = GridLayout()
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.allowsEmptySelection = true
        collection.backgroundColors = [.clear]
        collection.autoresizingMask = [.width]
        collection.register(CollectionItem.self, forItemWithIdentifier: CollectionItem.identifier)
        collection.register(SectionHeaderView.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                            withIdentifier: SectionHeaderView.identifier)
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

    final class Coordinator: NSObject, NSCollectionViewDelegateFlowLayout, NSCollectionViewPrefetching {
        private var parent: GridCollectionView
        private weak var collection: BookmarkCollectionView?
        private var dataSource: NSCollectionViewDiffableDataSource<Int, Entry>!
        private var content: [Entry: TileContent] = [:]
        private var bookmarkHeight: CGFloat = 0
        private var folderHeight: CGFloat = 0

        init(_ parent: GridCollectionView) { self.parent = parent }

        fileprivate func attach(to collection: BookmarkCollectionView) {
            self.collection = collection
            collection.delegate = self
            collection.prefetchDataSource = self
            collection.activate = { [weak self] in self?.activateSelection() }
            collection.deleteSelection = { [weak self] in self?.deleteSelection() }
            collection.copySelection = { [weak self] in self?.copySelection() }
            collection.selectBookmarks = { [weak self] in self?.selectAllBookmarks() }
            collection.selectionChanged = { [weak self] in self?.publishSelection() }
            collection.contextMenu = { [weak self] path in self?.menu(at: path) }
            collection.reflowed = { [weak self] in self?.refreshHeaders() }
            dataSource = NSCollectionViewDiffableDataSource(collectionView: collection) { [weak self] collection, path, entry in
                guard let self, let content = self.content[entry] else { return nil }
                let item = collection.makeItem(withIdentifier: CollectionItem.identifier, for: path) as! CollectionItem
                item.configure(content, store: self.parent.store, actions: self.actions(for: entry))
                return item
            }
            dataSource.supplementaryViewProvider = { [weak self] collection, kind, path in
                let header = collection.makeSupplementaryView(ofKind: kind, withIdentifier: SectionHeaderView.identifier,
                                                              for: path) as! SectionHeaderView
                header.collapseButton.target = self
                header.collapseButton.action = #selector(Coordinator.toggleFolders(_:))
                self?.configure(header, section: path.section)
                return header
            }
        }

        // MARK: Folders section

        // Collapsed, the folders section shows the first row, like Finder's "Show More". Not
        // `NSCollectionViewFlowLayout.collapseSection(at:)`: instead of the horizontally scrolling
        // row it's documented to give, it squeezed every folder into the width, overlapping.
        //
        // Every folder stays in the data; collapsed, those past the first row are laid out with
        // no height. So collapsing, and a new width changing how many fit, are layout changes
        // only. (Changing the data during a resize scrolled the grid after the reflow anchoring.)

        /// Whether every folder shows, rather than just the first row. One row by default; the
        /// choice is kept across pages and launches.
        private static let showsAllFoldersKey = "gridShowsAllFolders"
        private var showsAllFolders = UserDefaults.standard.bool(forKey: showsAllFoldersKey)

        /// Whether the folder at `index` is past the first row of a collapsed section.
        private func isHiddenFolder(_ index: Int, width: CGFloat) -> Bool {
            !showsAllFolders && index >= GridMetrics.columns(across: width, minimum: GridMetrics.folderWidth)
        }

        @objc fileprivate func toggleFolders(_ sender: Any?) {
            showsAllFolders.toggle()
            UserDefaults.standard.set(showsAllFolders, forKey: Self.showsAllFoldersKey)
            collection?.collectionViewLayout?.invalidateLayout()
            refreshHeaders()
        }

        /// Folders, then bookmarks. Applied only when something changed.
        private func applySnapshot() {
            var snapshot = NSDiffableDataSourceSnapshot<Int, Entry>()
            snapshot.appendSections([0, 1])
            snapshot.appendItems(parent.folders.map { .folder($0.id) }, toSection: 0)
            snapshot.appendItems(parent.raindrops.map { .bookmark($0.id) }, toSection: 1)
            if snapshot.itemIdentifiers != dataSource.snapshot().itemIdentifiers {
                dataSource.apply(snapshot, animatingDifferences: false)
            }
        }

        /// Headings show counts, and the folders heading's button depends on the width.
        private func refreshHeaders() {
            guard let collection else { return }
            for path in collection.indexPathsForVisibleSupplementaryElements(ofKind: NSCollectionView.elementKindSectionHeader) {
                if let header = collection.supplementaryView(forElementKind: NSCollectionView.elementKindSectionHeader,
                                                             at: path) as? SectionHeaderView {
                    configure(header, section: path.section)
                }
            }
        }

        /// Headings only when a page has folders: on its own, a grid of bookmarks needs none.
        private var showsHeaders: Bool { !parent.folders.isEmpty }

        private func configure(_ header: SectionHeaderView, section: Int) {
            guard section == 0 else {
                header.show(SectionHeader(title: "Bookmarks", count: parent.raindrops.count), collapse: nil)
                return
            }
            // The button only when there's more than a row to show or hide.
            let width = collection?.bounds.width ?? 0
            let overflows = parent.folders.count > GridMetrics.columns(across: width, minimum: GridMetrics.folderWidth)
            header.show(SectionHeader(title: "Collections", count: parent.folders.count),
                        collapse: overflows ? !showsAllFolders : nil)
        }

        fileprivate func update(_ parent: GridCollectionView) {
            let changed = content.isEmpty || self.parent.raindrops != parent.raindrops || self.parent.folders != parent.folders
            self.parent = parent
            guard let collection else { return }
            if let layout = collection.collectionViewLayout as? GridLayout, layout.cardSpacing != parent.cardSpacing {
                layout.cardSpacing = parent.cardSpacing
                layout.invalidateLayout()
            }
            if changed {
                content = Dictionary(uniqueKeysWithValues:
                    parent.folders.map { (Entry.folder($0.id), TileContent.folder($0)) }
                    + parent.raindrops.map { (Entry.bookmark($0.id), TileContent.bookmark($0)) }
                )
                measureTilesIfNeeded()
                applySnapshot()
                for path in collection.indexPathsForVisibleItems() {
                    if let entry = dataSource.itemIdentifier(for: path), let content = content[entry],
                       let item = collection.item(at: path) as? CollectionItem {
                        item.configure(content, store: parent.store, actions: actions(for: entry))
                    }
                }
                refreshHeaders()
            }
            let nativeSelection = Set(collection.selectionIndexPaths.compactMap { path -> Raindrop.ID? in
                if case .bookmark(let id) = dataSource.itemIdentifier(for: path) { return id }
                return nil
            })
            if nativeSelection != parent.selection {
                collection.selectionIndexPaths = Set(parent.selection.compactMap { dataSource.indexPath(for: .bookmark($0)) })
            }
        }

        /// Every tile of a kind is the same height, so one is measured, once, and used for all.
        /// A card is measured with every line it could have reserved. Changing what decides the
        /// height (`RaindropCard`'s line limits and cover) needs a relaunch.
        private func measureTilesIfNeeded() {
            if bookmarkHeight == 0, let raindrop = parent.raindrops.first {
                let view = NSHostingView(rootView: RaindropCard(raindrop: raindrop, isSelected: false, reservesSpace: true)
                    .frame(width: GridMetrics.minCardWidth))
                bookmarkHeight = ceil(view.fittingSize.height)
            }
            if folderHeight == 0, let folder = parent.folders.first {
                let view = NSHostingView(rootView: FolderTile(collection: folder, isSelected: false)
                    .frame(width: GridMetrics.folderWidth).environment(parent.store))
                folderHeight = ceil(view.fittingSize.height)
            }
        }

        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> NSSize {
            let width = collectionView.bounds.width
            var size = tileSize(section: indexPath.section, width: width)
            if indexPath.section == 0 {
                // Folder rows carry their own spacing (see `minimumLineSpacingForSectionAt`), so
                // a hidden folder's zero-height row takes no space at all.
                size.height = isHiddenFolder(indexPath.item, width: width) ? 0 : size.height + GridMetrics.rowSpacing
            }
            return size
        }

        /// Cards fill the row: as many columns as fit at the minimum width, then widened, unless
        /// they keep the minimum and `GridLayout` places them. Folders keep their width (see
        /// `insetForSectionAt`).
        private func tileSize(section: Int, width: CGFloat) -> NSSize {
            guard section == 1 else { return NSSize(width: GridMetrics.folderWidth, height: folderHeight) }
            guard parent.cardSpacing == .stretch else { return NSSize(width: GridMetrics.minCardWidth, height: bookmarkHeight) }
            let available = max(1, width - 2 * GridMetrics.inset)
            let spacing = GridMetrics.columnSpacing
            let columns = CGFloat(GridMetrics.columns(across: width, minimum: GridMetrics.minCardWidth))
            return NSSize(width: floor((available - (columns - 1) * spacing) / columns), height: bookmarkHeight)
        }

        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                            insetForSectionAt section: Int) -> NSEdgeInsets {
            guard collectionView.numberOfItems(inSection: section) > 0 else { return NSEdgeInsets() }
            let inset = GridMetrics.inset
            // Under a heading, the heading is the space above the section. Folder rows already
            // end in a row's spacing, so their section needs that much less below.
            let bottom = section == 0 ? max(0, inset - GridMetrics.rowSpacing) : inset
            return NSEdgeInsets(top: showsHeaders ? 4 : inset, left: inset, bottom: bottom,
                                right: section == 0 ? folderRightInset(width: collectionView.bounds.width) : inset)
        }

        /// Folders keep their width and their place from the left, like icons on a desktop. The
        /// space a row doesn't use goes to this margin; otherwise the layout spreads it between
        /// the tiles, and every folder drifts on each frame of a sidebar or inspector animation.
        private func folderRightInset(width: CGFloat) -> CGFloat {
            let columns = CGFloat(GridMetrics.columns(across: width, minimum: GridMetrics.folderWidth))
            let used = columns * GridMetrics.folderWidth + (columns - 1) * GridMetrics.columnSpacing
            return max(GridMetrics.inset, width - GridMetrics.inset - used)
        }

        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                            referenceSizeForHeaderInSection section: Int) -> NSSize {
            guard showsHeaders, collectionView.numberOfItems(inSection: section) > 0 else { return .zero }
            return NSSize(width: collectionView.bounds.width, height: GridMetrics.headerHeight)
        }

        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                            minimumInteritemSpacingForSectionAt section: Int) -> CGFloat { GridMetrics.columnSpacing }

        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                            minimumLineSpacingForSectionAt section: Int) -> CGFloat {
            section == 0 ? 0 : GridMetrics.rowSpacing
        }

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

        // MARK: Prefetching

        /// The memory cache holds only a couple of screens of covers, so the ones about to scroll
        /// into view are read ahead (from disk, usually) and show on their first frame.
        func collectionView(_ collectionView: NSCollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            ImagePipeline.shared.prefetch(coverURLs(at: indexPaths))
        }

        func collectionView(_ collectionView: NSCollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            ImagePipeline.shared.cancelPrefetch(coverURLs(at: indexPaths))
        }

        private func coverURLs(at paths: [IndexPath]) -> [URL] {
            paths.compactMap { path in
                guard let entry = dataSource.itemIdentifier(for: path), case .bookmark(let raindrop) = content[entry] else { return nil }
                return raindrop.coverURL
            }
        }

        private func publishSelection() {
            guard let collection else { return }
            let ids = Set(collection.selectionIndexPaths.compactMap { path -> Raindrop.ID? in
                if case .bookmark(let id) = dataSource.itemIdentifier(for: path) { return id }
                return nil
            })
            if parent.selection != ids { parent.selection = ids }
        }

        /// What VoiceOver can do with a tile. The hosted card can't be clicked (the collection
        /// takes the mouse), so without these, pressing it with VoiceOver did nothing.
        private func actions(for entry: Entry) -> TileActions {
            TileActions(
                select: { [weak self] in self?.select(entry) },
                open: { [weak self] in self?.open(entry) }
            )
        }

        /// Selects just this tile, as a click would.
        private func select(_ entry: Entry) {
            guard let collection, let path = dataSource.indexPath(for: entry) else { return }
            collection.selectionIndexPaths = [path]
            collectionView(collection, didSelectItemsAt: [path])
        }

        private func open(_ entry: Entry) {
            switch entry {
            case .folder(let id): parent.openFolder(id)
            case .bookmark(let id):
                if let url = parent.store.raindrop(id: id)?.url { parent.open(url) }
            }
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

private struct TileActions {
    let select: () -> Void
    let open: () -> Void
}

private struct CollectionTile: View {
    @Environment(LibraryStore.self) private var store
    let content: TileContent
    let isSelected: Bool
    let actions: TileActions

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
        // Pressing a tile with VoiceOver selects it, like a click.
        .accessibilityAction { actions.select() }
        .accessibilityAction(named: "Open") { actions.open() }
    }
}

private final class CollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("RaindropTile")
    private var content: TileContent?
    private var store: LibraryStore?
    private var actions: TileActions?
    private let hostingView = TileHostingView(rootView: AnyView(EmptyView()))

    override var isSelected: Bool {
        didSet { if oldValue != isSelected { render() } }
    }

    override func loadView() {
        hostingView.sizingOptions = []
        // The native item must remain hittable when its SwiftUI content passes mouse events through.
        let container = NSView()
        // A folder hidden by a collapsed section has no height, and must draw nothing.
        container.clipsToBounds = true
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        view = container
    }

    func configure(_ content: TileContent, store: LibraryStore, actions: TileActions) {
        // Actions for the same content do the same thing, so a change of content is what needs a render.
        self.actions = actions
        guard self.content != content || self.store !== store else { return }
        self.content = content
        self.store = store
        render()
    }

    private func render() {
        guard let content, let store, let actions else { return }
        hostingView.rootView = AnyView(CollectionTile(content: content, isSelected: isSelected, actions: actions)
            .environment(store).id(content.id))
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        content = nil
        store = nil
        actions = nil
        hostingView.rootView = AnyView(EmptyView())
    }
}

/// A section's heading, in the style of Finder's groups: its name, then how many it holds.
private struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(count, format: .number)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, GridMetrics.inset)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A section heading, with a Show All / Show Less button for the folders.
private final class SectionHeaderView: NSView, NSCollectionViewElement {
    static let identifier = NSUserInterfaceItemIdentifier("SectionHeader")
    private let hostingView = TileHostingView(rootView: AnyView(EmptyView()))
    let collapseButton = NSButton(title: "", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        hostingView.sizingOptions = []
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)

        // A plain accent-colored text button, like Finder's "Show More" in a group heading.
        collapseButton.isBordered = false
        collapseButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collapseButton)
        NSLayoutConstraint.activate([
            collapseButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -GridMetrics.inset),
            collapseButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `collapse` is whether the section is collapsed, or nil for no button.
    func show(_ header: SectionHeader, collapse: Bool?) {
        hostingView.rootView = AnyView(header)
        collapseButton.isHidden = collapse == nil
        collapseButton.attributedTitle = NSAttributedString(
            string: collapse == true ? "Show All" : "Show Less",
            attributes: [.foregroundColor: NSColor.controlAccentColor, .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
        )
    }
}

/// The flow layout, with fixed-width cards placed by column per `cardSpacing`. Left to itself, a
/// flow layout justifies each row on its own, so a short last row spreads out of the columns above.
private final class GridLayout: NSCollectionViewFlowLayout {
    var cardSpacing: CardSpacing = .stretch

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        super.layoutAttributesForElements(in: rect).map(placed)
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        super.layoutAttributesForItem(at: indexPath).map(placed)
    }

    private func placed(_ attributes: NSCollectionViewLayoutAttributes) -> NSCollectionViewLayoutAttributes {
        guard cardSpacing != .stretch, attributes.representedElementCategory == .item,
              let path = attributes.indexPath, path.section == 1, let collectionView else { return attributes }
        let width = collectionView.bounds.width
        let columns = GridMetrics.columns(across: width, minimum: GridMetrics.minCardWidth)
        let (lead, gap) = cardSpacing.placement(columns: columns, width: GridMetrics.minCardWidth,
                                                spacing: GridMetrics.columnSpacing,
                                                available: max(1, width - 2 * GridMetrics.inset))
        // A copy: the flow layout caches the attributes it returns.
        let copy = attributes.copy() as! NSCollectionViewLayoutAttributes
        copy.frame.origin.x = GridMetrics.inset + lead + CGFloat(path.item % columns) * (GridMetrics.minCardWidth + gap)
        return copy
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
    /// After the layout changes for a new width.
    var reflowed: (() -> Void)?
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
        reflowed?()

        if let (path, oldFrame) = anchor, let newFrame = layoutAttributesForItem(at: path)?.frame {
            let clip = scrollView.contentView
            // The content insets (the toolbar on top) extend how far the content can scroll.
            let minimum = -clip.contentInsets.top
            let maximum = max(minimum, (collectionViewLayout?.collectionViewContentSize.height ?? frame.height)
                - clip.bounds.height + clip.contentInsets.bottom)
            let y = min(maximum, max(minimum, newFrame.minY - (oldFrame.minY - viewport.minY)))
            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
            scrollView.reflectScrolledClipView(clip)
        }
    }
}
