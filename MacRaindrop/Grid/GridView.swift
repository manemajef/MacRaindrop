import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The bookmarks as cards, collections first. Each row is as tall as its tallest card.
///
/// What SwiftUI doesn't provide for a grid, and this writes itself: click, ⌘-click and ⇧-click
/// selection, arrow keys, Return, Escape and Select All. There's no rubber-band selection.
/// Keyboard focus goes through a plain AppKit view (`GridKeyView`): SwiftUI's focus state
/// couldn't reliably take focus back from the sidebar.
struct GridView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(ActionPrompts.self) private var prompts
    @Environment(\.openURL) private var openURL
    let raindrops: [Raindrop]
    @Binding var selection: Set<Raindrop.ID>
    var collections: [RaindropCollection] = []
    /// Whether cards say which collection they're in. See `SidebarItem.showsCollectionLabel`.
    var showsCollectionLabel = true
    var openCollection: (RaindropCollection.ID) -> Void = { _ in }

    /// The selected collection. Collection selection is singular and never mixed with bookmarks.
    @State private var selectedCollection: RaindropCollection.ID?
    /// Where ⇧-click and ⇧-arrow extend the selection from.
    @State private var anchor: Raindrop.ID?
    /// The card the arrow keys move from.
    @State private var cursor: Raindrop.ID?
    @State private var position = ScrollPosition(idType: Raindrop.ID.self)
    @State private var width: CGFloat = 0
    /// The cards on screen, kept outside SwiftUI's state so scrolling doesn't redraw the grid.
    @State private var visible = VisibleCards()
    /// The AppKit view that takes keyboard focus for the grid.
    @State private var keys = GridKeys()

    private var columns: Int { GridMetrics.columns(across: width, minimum: GridMetrics.minCardWidth) }
    private var selected: [Raindrop] { raindrops.filter { selection.contains($0.id) } }
    /// What Quick Look shows: the selected pages in grid order, starting at the card the arrow keys are on.
    private var preview: QuickLookItems {
        let shown = selected.filter { $0.url != nil }
        let current = shown.firstIndex { $0.id == cursor } ?? 0
        return QuickLookItems(urls: shown.compactMap(\.url), current: current)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !collections.isEmpty {
                    CollectionSection(collections: collections, selection: $selectedCollection, open: openCollection) {
                        selection = []
                    }
                    SectionHeader(title: "Bookmarks", count: raindrops.count)
                        .frame(height: GridMetrics.headerHeight)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: GridMetrics.minCardWidth),
                                             spacing: GridMetrics.columnSpacing, alignment: .top)],
                          spacing: GridMetrics.rowSpacing) {
                    ForEach(raindrops) { raindrop in
                        card(raindrop)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, GridMetrics.inset)
                .padding(.top, collections.isEmpty ? GridMetrics.inset : 4)
                .padding(.bottom, GridMetrics.inset)
            }
            // Clicking between cards clears the selection, as in Finder.
            .background {
                Color.clear.contentShape(.rect).onTapGesture {
                    clearSelection()
                    keys.focus()
                }
            }
        }
        // Keeps the top card in place while the grid reflows for a new width.
        .scrollPosition($position, anchor: .top)
        .onScrollTargetVisibilityChange(idType: Raindrop.ID.self, threshold: 0.95) { visible.ids = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
            width = newWidth
            keepSelectionInView()
        }
        .background {
            GridKeyResponder(keys: keys, actions: GridKeyActions(
                move: move,
                open: openSelection,
                preview: { preview },
                delete: { prompts.delete(selected, in: store) },
                clear: clearSelection,
                selectAll: {
                    selectedCollection = nil
                    selection = Set(raindrops.map(\.id))
                },
                copy: { selected.compactMap(\.url) }
            ))
        }
        .raindropDragContainer(selection: selection)
        // An open Quick Look panel follows the selection, as in Finder.
        .onChange(of: selection) { keys.view?.reloadPreview() }
        .onChange(of: raindrops) { keys.view?.reloadPreview() }
        .onDisappear { keys.view?.closePreview() }
    }

    private func card(_ raindrop: Raindrop) -> some View {
        RaindropCard(raindrop: raindrop, isSelected: selection.contains(raindrop.id),
                     isPending: store.pendingIDs.contains(raindrop.id),
                     collectionTitle: showsCollectionLabel ? store.collectionTitle(for: raindrop.collectionID) : nil)
            // Shorter cards stretch to their row's height.
            .frame(maxHeight: .infinity, alignment: .top)
            .onTapGesture { click(raindrop.id) }
            .draggable(containerItemID: raindrop.id)
            .contextMenu {
                let ids = selection.contains(raindrop.id) ? selection : [raindrop.id]
                RaindropActions(raindrops: ids.compactMap(store.raindrop(id:)))
            }
            .accessibilityAction {
                keys.focus()
                select(raindrop.id)
            }
            .accessibilityAction(named: "Open") { open(raindrop.id) }
    }

    // MARK: Selection

    private func click(_ id: Raindrop.ID) {
        keys.focus()
        let event = NSApp.currentEvent
        let flags = event?.modifierFlags ?? []
        if event?.clickCount == 2 {
            open(id)
        } else if flags.contains(.command) {
            selectedCollection = nil
            selection.formSymmetricDifference([id])
            anchor = id
            cursor = id
        } else if flags.contains(.shift) {
            extend(to: id)
        } else {
            select(id)
        }
    }

    private func select(_ id: Raindrop.ID) {
        selectedCollection = nil
        selection = [id]
        anchor = id
        cursor = id
    }

    /// Selects from the anchor to `id`, replacing the selection, as Finder does.
    private func extend(to id: Raindrop.ID) {
        guard let anchor, let from = raindrops.firstIndex(where: { $0.id == anchor }),
              let to = raindrops.firstIndex(where: { $0.id == id }) else { return select(id) }
        selectedCollection = nil
        selection = Set(raindrops[min(from, to)...max(from, to)].map(\.id))
        cursor = id
    }

    /// After a reflow (a new width, or the inspector opening), keeps a selected card that was on
    /// screen in view, Otherwise the top card stays put.
    private func keepSelectionInView() {
        let shown = visible.ids.filter(selection.contains)
        guard let id = shown.first(where: { $0 == cursor }) ?? shown.first else { return }
        position.scrollTo(id: id)
    }

    private func clearSelection() {
        selection = []
        selectedCollection = nil
    }

    private func move(_ direction: MoveCommandDirection, extending: Bool) {
        guard !raindrops.isEmpty else { return }
        let current = cursor.flatMap { id in raindrops.firstIndex { $0.id == id } }
        let next: Int
        if let current {
            switch direction {
            case .left: next = current - 1
            case .right: next = current + 1
            case .up: next = current - columns
            case .down: next = current + columns
            @unknown default: return
            }
        } else {
            next = 0
        }
        let id = raindrops[min(max(next, 0), raindrops.count - 1)].id
        if extending { extend(to: id) } else { select(id) }
        // Only as far as it takes to show the card, like a list.
        guard !visible.ids.contains(id) else { return }
        let below = current.map { next > $0 } ?? true
        withAnimation { position.scrollTo(id: id, anchor: below ? .bottom : .top) }
    }

    // MARK: Opening

    private func open(_ id: Raindrop.ID) {
        if let url = store.raindrop(id: id)?.url { openURL(url) }
    }

    private func openSelection() {
        if let selectedCollection { return openCollection(selectedCollection) }
        for raindrop in selected { if let url = raindrop.url { openURL(url) } }
    }
}

/// The IDs of the cards on screen. A class, so updating it as the grid scrolls doesn't
/// invalidate the view.
private final class VisibleCards {
    var ids: [Raindrop.ID] = []
}

#Preview {
    @Previewable @State var store = LibraryStore.preview
    @Previewable @State var selection: Set<Raindrop.ID> = []
    GridView(raindrops: store.raindrops(in: .all), selection: $selection)
        .frame(width: 800, height: 600)
        .previewEnvironment(store)
}

#Preview("With Collections") {
    @Previewable @State var store = LibraryStore.preview
    @Previewable @State var selection: Set<Raindrop.ID> = []
    // The collection with subcollections holding the most bookmarks, as cards mode shows it:
    // collections first, then bookmarks.
    let parent = store.collections
        .filter { !store.subcollections(of: $0.id).isEmpty }
        .max { store.count(for: .collection($0.id)) < store.count(for: .collection($1.id)) }!
    GridView(
        raindrops: store.raindrops(in: .collection(parent.id)),
        selection: $selection,
        collections: store.subcollections(of: parent.id)
    )
    .frame(width: 800, height: 600)
    .previewEnvironment(store)
}
