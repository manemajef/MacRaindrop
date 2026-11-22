import AppKit
import SwiftUI

/// A raindrop's tags in a native token field, like Mail's address fields: type to get
/// completions from the library's tags, Return or a comma turns the text into a tag, and
/// Delete removes the selected ones.
///
/// Calls `commit` with the whole list when a tag is added, and when editing ends with tags
/// removed, so each change is one write. Grows taller as tags wrap onto more lines.
struct TagTokenField: NSViewRepresentable {
    let tags: [String]
    /// Every known tag, most used first, for completions.
    let knownTags: [String]
    var prompt = "Add tags"
    let commit: ([String]) -> Void

    func makeNSView(context: Context) -> NSTokenField {
        let field = NSTokenField()
        field.delegate = context.coordinator
        field.tokenStyle = .rounded
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.placeholderString = prompt
        field.completionDelay = 0
        // Return also ends a token. Spaces don't, since tags may contain them.
        field.tokenizingCharacterSet = CharacterSet(charactersIn: ",")
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.lineBreakMode = .byWordWrapping
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.objectValue = tags
        return field
    }

    func updateNSView(_ field: NSTokenField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = prompt
        // Leave what's being typed alone; the server's copy shows once editing ends.
        if field.currentEditor() == nil, Coordinator.tokens(in: field) != tags {
            field.objectValue = tags
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: NSTokenField, context: Context) -> CGSize? {
        let width = proposal.width ?? 200
        let bounds = NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)
        let height = field.cell?.cellSize(forBounds: bounds).height ?? 22
        return CGSize(width: width, height: max(ceil(height), 20))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTokenFieldDelegate {
        var parent: TagTokenField

        init(parent: TagTokenField) {
            self.parent = parent
        }

        static func tokens(in field: NSTokenField) -> [String] {
            var seen = Set<String>()
            return ((field.objectValue as? [Any]) ?? [])
                .compactMap { $0 as? String }
                .map(Self.normalized)
                .filter { !$0.isEmpty && seen.insert($0).inserted }
        }

        /// Drops surrounding spaces and any leading `#`.
        nonisolated static func normalized(_ typed: String) -> String {
            typed.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        }

        private func commit(_ field: NSTokenField) {
            let tokens = Self.tokens(in: field)
            if tokens != parent.tags { parent.commit(tokens) }
        }

        // MARK: NSTokenFieldDelegate

        /// Known tags containing what's typed, those starting with it first, leaving out
        /// tags the raindrop already has.
        func tokenField(
            _ tokenField: NSTokenField,
            completionsForSubstring substring: String,
            indexOfToken tokenIndex: Int,
            indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?
        ) -> [Any]? {
            let typed = Self.normalized(substring)
            guard !typed.isEmpty else { return [] }
            let existing = Set(Self.tokens(in: tokenField))
            let matches = parent.knownTags.filter {
                !existing.contains($0) && $0.localizedStandardContains(typed)
            }
            let prefixed = matches.filter { $0.lowercased().hasPrefix(typed.lowercased()) }
            let others = matches.filter { !$0.lowercased().hasPrefix(typed.lowercased()) }
            selectedIndex?.pointee = -1
            return Array((prefixed + others).prefix(12))
        }

        func tokenField(_ tokenField: NSTokenField, shouldAdd tokens: [Any], at index: Int) -> [Any] {
            let added = tokens.compactMap { $0 as? String }.map(Self.normalized).filter { !$0.isEmpty }
            // The field updates its value after this returns.
            DispatchQueue.main.async { [weak self, weak tokenField] in
                guard let self, let tokenField else { return }
                commit(tokenField)
                tokenField.invalidateIntrinsicContentSize()
            }
            return added
        }

        func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String? {
            representedObject as? String
        }

        func controlTextDidChange(_ notification: Notification) {
            (notification.object as? NSTokenField)?.invalidateIntrinsicContentSize()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if let field = notification.object as? NSTokenField { commit(field) }
        }
    }
}

#Preview {
    @Previewable @State var tags = ["design", "swiftui", "to read"]
    TagTokenField(tags: tags, knownTags: ["design", "development", "swift", "swiftui"]) {
        tags = $0
    }
    .padding()
    .frame(width: 260)
}
