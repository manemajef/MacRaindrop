import AppKit
import CoreTransferable
import SwiftUI

/// Bookmarks as a grid of cards that select like Finder icons: click, ⌘-click, ⇧-click,
/// rubber-band, arrow keys, ⌘A and Esc. Double-click or Return opens the selection in the browser.
struct RaindropGridView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.openURL) private var openURL
    let raindrops: [Raindrop]
    @Binding var selection: Set<Raindrop.ID>

    /// Where ⇧-click and ⇧-arrow ranges start, and where plain arrow keys move from.
    @State private var anchor: Raindrop.ID?
    @State private var viewport: CGSize = .zero
    @State private var cardFrames: [Raindrop.ID: CGRect] = [:]
    @State private var rubberBand: RubberBand?
    @FocusState private var isFocused: Bool

    private static let minCardWidth: CGFloat = 220
    private static let spacing: CGFloat = 16
    private static let padding: CGFloat = 20
    private static let coordinateSpace = "RaindropGrid"

    private var columnCount: Int {
        let available = viewport.width - 2 * Self.padding + Self.spacing
        return max(1, Int(available / (Self.minCardWidth + Self.spacing)))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                grid
                    .padding(Self.padding)
                    // Fill the viewport, so clicks and drags below the last row reach the background.
                    .frame(maxWidth: .infinity, minHeight: viewport.height, alignment: .topLeading)
                    .background { background }
                    .overlay(alignment: .topLeading) { rubberBandView }
                    .coordinateSpace(.named(Self.coordinateSpace))
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onMoveCommand { direction in
                guard let id = move(direction) else { return }
                withAnimation(.snappy) { proxy.scrollTo(id) }
            }
            .onKeyPress(.return) {
                open(selection)
                return .handled
            }
            .onKeyPress(characters: ["a"], phases: .down) { press in
                guard press.modifiers == .command else { return .ignored }
                selection = Set(raindrops.map(\.id))
                return .handled
            }
            .onExitCommand { selection = [] }
        }
        .raindropDragContainer(selection: selection)
        .onAppear { isFocused = true }
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing, alignment: .top), count: columnCount),
            alignment: .leading,
            spacing: Self.spacing
        ) {
            ForEach(raindrops) { raindrop in
                RaindropCard(raindrop: raindrop, isSelected: selection.contains(raindrop.id))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.coordinateSpace)) } action: {
                        cardFrames[raindrop.id] = $0
                    }
                    .onDisappear { cardFrames[raindrop.id] = nil }
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
        }
    }

    // MARK: Mouse selection

    private func click(_ id: Raindrop.ID) {
        isFocused = true
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
                            let hits = cardFrames.filter { $0.value.intersects(rubberBand.rect) }.keys
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

/// A card in the style of Raindrop's iOS grid: cover, title, excerpt, tags, then source and date.
struct RaindropCard: View {
    let raindrop: Raindrop
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay { CoverImage(url: raindrop.coverURL, kind: raindrop.type) }
                .clipShape(.rect(cornerRadius: 8))
                .padding(6)

            VStack(alignment: .leading, spacing: 5) {
                Text(raindrop.title)
                    .font(.headline)
                    .lineLimit(2)

                if !raindrop.excerpt.isEmpty {
                    Text(raindrop.excerpt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                if !raindrop.tags.isEmpty {
                    TagList(tags: raindrop.tags)
                        .fixedSize()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()
                }

                footer
                    .padding(.top, 2)
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: isSelected ? 3 : 1)
        }
        .contentShape(.rect(cornerRadius: 12))
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

/// What a dragged raindrop becomes outside the app: its URL.
nonisolated struct RaindropLink: Identifiable, Transferable {
    let id: Raindrop.ID
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.url)
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
}
