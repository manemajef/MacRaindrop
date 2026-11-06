import CoreGraphics

/// The grid's layout, in points. Each row is as tall as its tallest card.
enum GridMetrics {
    /// Space between the grid and the edges of its column.
    static let inset: CGFloat = 16
    /// Gap between tiles side by side.
    static let columnSpacing: CGFloat = 16
    /// Gap between rows.
    static let rowSpacing: CGFloat = 16
    /// The narrowest a bookmark card gets. Below it, the grid drops a column and cards widen
    /// to fill the row, up to the width at which another column fits.
    static let minCardWidth: CGFloat = 180
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
