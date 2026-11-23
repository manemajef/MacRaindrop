import SwiftUI

/// The inspector's text fields, for keyboard focus.
enum InspectorFieldID: Hashable {
    case title, excerpt, note, link
}

/// A standard text field that keeps what's typed to itself until Return or leaving the field,
/// then hands it to `commit` if it changed. Escape puts the saved value back.
///
/// The label is the field's label, as for any `TextField`; a grouped form shows it beside the
/// field, and `.labelsHidden()` leaves just the prompt.
///
/// `displayedValue` shows a shorter form while the field isn't being edited, such as a URL
/// without its scheme; clicking in shows the real value.
struct CommitTextField<Label: View>: View {
    let value: String
    var prompt: String
    var axis: Axis = .horizontal
    let field: InspectorFieldID
    var focus: FocusState<InspectorFieldID?>.Binding
    var displayedValue: (String) -> String = { $0 }
    let commit: (String) -> Void
    @ViewBuilder var label: () -> Label

    @State private var text = ""
    /// Whether `text` holds the real value being edited, rather than the displayed form.
    @State private var isEditing = false

    private var isFocused: Bool { focus.wrappedValue == field }

    var body: some View {
        TextField(text: $text, prompt: Text(prompt), axis: axis, label: label)
            .focused(focus, equals: field)
            .onAppear { text = displayedValue(value) }
            // Saved, here or elsewhere: show it, unless it's being typed in.
            .onChange(of: value) { if !isEditing { text = displayedValue(value) } }
            .onChange(of: isFocused) { _, isFocused in
                if isFocused {
                    isEditing = true
                    text = value
                } else {
                    commitIfChanged()
                    isEditing = false
                    text = displayedValue(value)
                }
            }
            .onSubmit(commitIfChanged)
            .onExitCommand {
                text = value
                focus.wrappedValue = nil
            }
            // Selecting another bookmark removes the field without it losing focus first.
            .onDisappear(perform: commitIfChanged)
    }

    /// Only while editing: otherwise `text` may be the displayed form, which isn't an edit.
    private func commitIfChanged() {
        if isEditing, text != value { commit(text) }
    }
}

extension String {
    /// The URL as an address bar shows it: no `https://` or `http://`, and no trailing slash.
    var withoutScheme: String {
        var url = self
        for scheme in ["https://", "http://"] where url.lowercased().hasPrefix(scheme) {
            url.removeFirst(scheme.count)
        }
        if url.hasSuffix("/") { url.removeLast() }
        return url
    }
}

extension CommitTextField where Label == EmptyView {
    /// A field with only a prompt, for a form row of its own.
    init(
        value: String, prompt: String, axis: Axis = .horizontal,
        field: InspectorFieldID, focus: FocusState<InspectorFieldID?>.Binding,
        displayedValue: @escaping (String) -> String = { $0 },
        commit: @escaping (String) -> Void
    ) {
        self.init(
            value: value, prompt: prompt, axis: axis, field: field, focus: focus,
            displayedValue: displayedValue, commit: commit
        ) {
            EmptyView()
        }
    }
}

extension View {
    /// Lays a label-less field out like Reminders' title and notes: the full row, text leading.
    /// A grouped form otherwise treats it as a row's value and right-aligns it.
    func fullWidthField() -> some View {
        labelsHidden()
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A form row's icon: gray, in a fixed-width column so the icons of every row line up,
/// whatever each symbol's width.
struct InspectorRowIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .foregroundStyle(.secondary)
            .frame(width: 20)
            .accessibilityHidden(true)
    }
}
