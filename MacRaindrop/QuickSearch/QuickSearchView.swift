import SwiftUI

/// The Quick Search panel's content: a large search field over a list of results, on glass.
///
/// The window around it never resizes. The glass is pinned to the top and its height is
/// animated here, so the list grows and shrinks smoothly while the field stays still.
struct QuickSearchView: View {
    let model: QuickSearchModel
    @FocusState private var isFieldFocused: Bool

    static let width: CGFloat = 680
    static let cornerRadius: CGFloat = 24
    static let listPadding: CGFloat = 8
    private static let fieldHeight: CGFloat = 56
    private static let visibleRows = 8
    private static let headerHeight: CGFloat = 26

    /// The tallest the glass gets: the field over a full page of results with its header.
    static let maxHeight = fieldHeight + 1 + listHeight(rows: visibleRows, header: true)

    private static func listHeight(rows: Int, header: Bool) -> CGFloat {
        CGFloat(rows) * QuickSearchRow.height + (header ? headerHeight : 0) + listPadding * 2
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            field(text: $model.query)
            if !model.results.isEmpty {
                Divider()
                results
            } else if showsMessage {
                Divider()
                Text(model.store == nil ? "Connect a Raindrop account to search" : "No Results")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: QuickSearchRow.height)
            }
        }
        .frame(width: Self.width)
        // Only the height animates, not the rows' contents.
        .animation(.smooth(duration: 0.18)) { content in
            content.frame(height: contentHeight, alignment: .top)
        }
        .clipShape(.rect(cornerRadius: Self.cornerRadius))
        .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
        .padding(QuickSearchController.shadowInset)
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: model.presentation, initial: true) { isFieldFocused = true }
        .onChange(of: model.store?.revision) { model.search() }
    }

    private var showsMessage: Bool {
        model.store == nil || (!model.query.isEmpty && !model.isSearching)
    }

    private var showsHeader: Bool { model.query.isEmpty }

    private var contentHeight: CGFloat {
        if !model.results.isEmpty {
            return Self.fieldHeight + 1 + Self.listHeight(rows: min(model.results.count, Self.visibleRows), header: showsHeader)
        }
        return Self.fieldHeight + (showsMessage ? 1 + QuickSearchRow.height : 0)
    }

    private func field(text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            TextField("Search Bookmarks", text: text)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($isFieldFocused)
        }
        .padding(.horizontal, 18)
        .frame(height: Self.fieldHeight)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if showsHeader {
                        Text("Recently Added")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .frame(height: Self.headerHeight, alignment: .bottomLeading)
                    }
                    ForEach(model.results) { raindrop in
                        QuickSearchRow(
                            raindrop: raindrop,
                            collection: model.collectionPath(for: raindrop),
                            query: model.query,
                            isSelected: raindrop.id == model.selectedRaindrop?.id
                        )
                        .id(raindrop.id)
                        .onHover { if $0 { model.hover(raindrop.id) } }
                        .onTapGesture { model.open(raindrop.id) }
                    }
                }
                .padding(Self.listPadding)
            }
            .scrollIndicators(.never)
            // Only the keyboard scrolls: scrolling to a hovered row would slide another under the pointer.
            .onChange(of: model.keyboardMoves) {
                if let id = model.selectedID { proxy.scrollTo(id) }
            }
            .onChange(of: model.query) {
                if let first = model.results.first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
    }
}
