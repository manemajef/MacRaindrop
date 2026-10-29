import AppKit
import CoreTransferable
import SwiftUI

/// Bookmarks as a grid of cards that select like Finder icons: click, ⌘-click, ⇧-click,
/// rubber-band, arrow keys, ⌘A and Esc. Double-click or Return opens the selection in the browser.
///
/// Subcollections come first, as folder tiles. A click selects one, and a double-click or
/// Return opens it.
struct RaindropGridView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(ActionPrompts.self) private var prompts
    @Environment(\.openURL) private var openURL
    let raindrops: [Raindrop]
    @Binding var selection: Set<Raindrop.ID>
    var folders: [RaindropCollection] = []
    var openFolder: (RaindropCollection.ID) -> Void = { _ in }

    private var selected: [Raindrop] { raindrops.filter { selection.contains($0.id) } }

    /// A selected folder tile. Folders and bookmarks are never selected together.
    @State private var selectedFolder: RaindropCollection.ID?

    /// Where ⇧-click and ⇧-arrow ranges start, and where plain arrow keys move from.
    @State private var anchor: Raindrop.ID?
    /// Changes only when a column is gained or lost, not on every frame of a resize.
    @State private var columnCount = 1
    @State private var viewportHeight: CGFloat = 0
    @State private var isScrolledToTop = true
    @State private var cardFrames = CardFrames()
    @State private var rubberBand: RubberBand?
    @FocusState private var isFocused: Bool

    private static let minCardWidth: CGFloat = 180
    private static let spacing: CGFloat = 8
    private static let padding: CGFloat = 16
    private static let coordinateSpace = "RaindropGrid"

    private static func columnCount(forWidth width: CGFloat) -> Int {
        let available = width - 2 * padding + spacing
        return max(1, Int(available / (minCardWidth + spacing)))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                grid
                    .padding(Self.padding)
                    // Fill the viewport, so clicks and drags below the last row reach the background.
                    .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .topLeading)
                    .background { background }
                    .overlay(alignment: .topLeading) { rubberBandView }
                    .coordinateSpace(.named(Self.coordinateSpace))
            }
            .onGeometryChange(for: Int.self) { Self.columnCount(forWidth: $0.size.width) } action: { columnCount = $0 }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top < 1 } action: {
                isScrolledToTop = $1
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, top in
                cardFrames.scrolled(to: top)
            }
            .onScrollPhaseChange { _, phase in cardFrames.scrollPhase = phase }
            // Reflowing moves every card. Bring the one that was at the top back there,
            // rather than leaving the scroll offset where it was and the content shifted under it.
            .onChange(of: columnCount) {
                // At the top, stay there, above the folder tiles.
                guard !isScrolledToTop, let id = cardFrames.topCard else { return }
                // Without the animation of whatever resized the grid: an animated scroll isn't
                // idle, so `CardFrames` would take a card from mid-reflow as the new top.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { proxy.scrollTo(id, anchor: .top) }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onMoveCommand { direction in
                guard let id = move(direction) else { return }
                withAnimation(.snappy) { proxy.scrollTo(id) }
            }
            .onKeyPress(.return) {
                if let selectedFolder {
                    openFolder(selectedFolder)
                } else {
                    open(selection)
                }
                return .handled
            }
            .onKeyPress(characters: ["a"], phases: .down) { press in
                guard press.modifiers == .command else { return .ignored }
                selection = Set(raindrops.map(\.id))
                return .handled
            }
            .onExitCommand {
                selection = []
                selectedFolder = nil
            }
            .onDeleteCommand { prompts.delete(selected, in: store) }
            .copyable(selected.compactMap(\.url))
        }
        .raindropDragContainer(selection: selection)
        .onAppear { isFocused = true }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: Self.spacing * 2) {
            if !folders.isEmpty {
                folderTiles
            }
            cards
        }
    }

    private var folderTiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: Self.spacing)], spacing: Self.spacing) {
            ForEach(folders) { folder in
                FolderTile(collection: folder, isSelected: selectedFolder == folder.id)
                    .draggable(CollectionDrag(id: folder.id))
                    .dropTarget(for: .collection(folder.id))
                    .gesture(TapGesture(count: 2).onEnded { openFolder(folder.id) })
                    .simultaneousGesture(TapGesture().onEnded {
                        isFocused = true
                        selectedFolder = folder.id
                        selection = []
                    })
                    .contextMenu {
                        Button("Open", systemImage: "folder") { openFolder(folder.id) }
                    }
            }
        }
    }

    /// Each card is identified by its raindrop, so a change in column count moves cards
    /// rather than rebuilding them.
    private var cards: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing, alignment: .top), count: columnCount),
            spacing: Self.spacing
        ) {
            ForEach(raindrops) { raindrop in
                card(raindrop)
            }
        }
    }

    private func card(_ raindrop: Raindrop) -> some View {
        RaindropCard(
            raindrop: raindrop,
            isSelected: selection.contains(raindrop.id),
            isPending: store.pendingIDs.contains(raindrop.id)
        )
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.coordinateSpace)) } action: {
                cardFrames.frames[raindrop.id] = $0
            }
            .onDisappear { cardFrames.frames[raindrop.id] = nil }
            .gesture(TapGesture(count: 2).onEnded { open([raindrop.id]) })
            .simultaneousGesture(TapGesture().onEnded { click(raindrop.id) })
            .draggable(containerItemID: raindrop.id)
            .contextMenu {
                // Like Finder: right-clicking a selected card acts on the whole selection.
                let targets = selection.contains(raindrop.id) ? selection : [raindrop.id]
                RaindropActions(raindrops: raindrops.filter { targets.contains($0.id) })
            }
            .id(raindrop.id)
    }

    // MARK: Mouse selection

    private func click(_ id: Raindrop.ID) {
        isFocused = true
        selectedFolder = nil
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            selection.formSymmetricDifference([id])
            anchor = id
        } else if modifiers.contains(.shift), let anchor {
            selection.formUnion(ids(from: anchor, to: id))
        } else {
            selection = [id]
            anchor = id
        }
    }

    /// Empty space: a click clears the selection, a drag draws a rubber band.
    private var background: some View {
        Color.clear
            .contentShape(.rect)
            .onTapGesture {
                isFocused = true
                selection = []
                selectedFolder = nil
            }
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.coordinateSpace))
                    .onChanged { drag in
                        if rubberBand == nil {
                            isFocused = true
                            // ⌘ or ⇧ adds to the existing selection instead of replacing it.
                            let extending = !NSEvent.modifierFlags.isDisjoint(with: [.command, .shift])
                            rubberBand = RubberBand(origin: drag.startLocation, initialSelection: extending ? selection : [])
                        }
                        rubberBand?.current = drag.location
                        if let rubberBand {
                            let hits = cardFrames.frames.filter { $0.value.intersects(rubberBand.rect) }.keys
                            selection = rubberBand.initialSelection.union(hits)
                        }
                    }
                    .onEnded { _ in rubberBand = nil }
            )
    }

    @ViewBuilder
    private var rubberBandView: some View {
        if let rect = rubberBand?.rect {
            Rectangle()
                .fill(Color.accentColor.opacity(0.15))
                .strokeBorder(Color.accentColor.opacity(0.6))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        }
    }

    // MARK: Keyboard selection

    /// Moves (or with ⇧, extends) the selection one card or one row. Returns the card to reveal.
    private func move(_ direction: MoveCommandDirection) -> Raindrop.ID? {
        guard !raindrops.isEmpty else { return nil }
        let ids = raindrops.map(\.id)
        let current = anchor.flatMap(ids.firstIndex(of:))
        let target: Int
        if let current {
            let step = switch direction {
            case .left: -1
            case .right: 1
            case .up: -columnCount
            case .down: columnCount
            @unknown default: 0
            }
            target = min(max(current + step, 0), ids.count - 1)
        } else {
            target = 0
        }

        if NSEvent.modifierFlags.contains(.shift) {
            selection.formUnion(self.ids(from: anchor ?? ids[target], to: ids[target]))
        } else {
            selection = [ids[target]]
        }
        anchor = ids[target]
        return ids[target]
    }

    // MARK: Helpers

    private func ids(from start: Raindrop.ID, to end: Raindrop.ID) -> [Raindrop.ID] {
        let ids = raindrops.map(\.id)
        guard let a = ids.firstIndex(of: start), let b = ids.firstIndex(of: end) else { return [end] }
        return Array(ids[min(a, b)...max(a, b)])
    }

    private func open(_ ids: some Collection<Raindrop.ID>) {
        for url in raindrops.filter({ ids.contains($0.id) }).compactMap(\.url) {
            openURL(url)
        }
    }
}

/// Where each card on screen is, for rubber-band selection and for keeping the top card in
/// place through a reflow. A reference rather than state: every card writes to it on every
/// frame of a resize, and nothing on screen depends on it.
private final class CardFrames {
    var frames: [Raindrop.ID: CGRect] = [:]
    /// The card at the top of the viewport, as the user last left it.
    private(set) var topCard: Raindrop.ID?
    var scrollPhase: ScrollPhase = .idle

    /// Notes the top card after a scroll by the user (or a scroll animation they started).
    /// Offsets that move while idle come from a reflow or from restoring `topCard`, and would
    /// only make it drift to the start of its row.
    func scrolled(to top: CGFloat) {
        guard scrollPhase != .idle || topCard == nil else { return }
        topCard = frames
            .filter { $0.value.maxY > top }
            .min { ($0.value.minY, $0.value.minX) < ($1.value.minY, $1.value.minX) }?
            .key
    }
}

private struct RubberBand {
    var origin: CGPoint
    var current: CGPoint = .zero
    var initialSelection: Set<Raindrop.ID>

    var rect: CGRect {
        CGRect(
            x: min(origin.x, current.x),
            y: min(origin.y, current.y),
            width: abs(current.x - origin.x),
            height: abs(current.y - origin.y)
        )
    }
}

/// A subcollection at the top of the grid: its name, and what's inside.
private struct FolderTile: View {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(16 / 10, contentMode: .fit)
                // Height from the card's width alone, whatever height the grid proposes.
                .fixedSize(horizontal: false, vertical: true)
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
