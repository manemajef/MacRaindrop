import AppKit
import KeyboardShortcuts

/// The global shortcut that shows Quick Search, fixed at ⇧⌘L for now.
///
/// The only file that knows about the KeyboardShortcuts package, so it can be swapped out
/// (or gain a Settings recorder) without touching the panel.
enum QuickSearchHotKey {
    static func onPress(_ action: @escaping () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .quickSearch, action: action)
    }
}

private extension KeyboardShortcuts.Name {
    static let quickSearch = Self("quickSearch", default: .init(.l, modifiers: [.command, .shift]))
}
