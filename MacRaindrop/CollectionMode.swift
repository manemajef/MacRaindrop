import Foundation

/// How a collection's bookmarks are shown.
enum CollectionMode: String, CaseIterable, Identifiable {
    /// Sidebar and a grid of cards; double-clicking a card opens it in the browser.
    case cards
    
    /// Sidebar, bookmark list, and the selected page in a web view.
    case list

    var id: Self { self }

    var label: String {
        switch self {
        case .cards: "Cards"
        case .list: "List"
        }
    }

    var systemImage: String {
        switch self {
        case .cards: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}
