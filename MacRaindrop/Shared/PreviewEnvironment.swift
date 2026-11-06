import SwiftUI

extension View {
    /// What most previews need: a library (the bundled sample data, unless the preview made its
    /// own to pick raindrops from) and a window's prompts.
    func previewEnvironment(_ store: LibraryStore = .preview) -> some View {
        environment(store).environment(ActionPrompts())
    }
}
