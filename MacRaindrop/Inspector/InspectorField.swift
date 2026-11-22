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
struct CommitTextField<Label: View>: View {
    let value: String
    var prompt: String
    var axis: Axis = .horizontal
    let field: InspectorFieldID
    var focus: FocusState<InspectorFieldID?>.Binding
    let commit: (String) -> Void
    @ViewBuilder var label: () -> Label

    @State private var text = ""

    private var isFocused: Bool { focus.wrappedValue == field }

    var body: some View {
        TextField(text: $text, prompt: Text(prompt), axis: axis, label: label)
            .focused(focus, equals: field)
            .onAppear { text = value }
            // Saved, here or elsewhere: show it, unless it's being typed in.
            .onChange(of: value) { if !isFocused { text = value } }
            .onChange(of: isFocused) { _, isFocused in
                if !isFocused { commitIfChanged() }
            }
            .onSubmit(commitIfChanged)
            .onExitCommand {
                text = value
                focus.wrappedValue = nil
            }
            // Selecting another bookmark removes the field without it losing focus first.
            .onDisappear(perform: commitIfChanged)
    }

    private func commitIfChanged() {
        if text != value { commit(text) }
    }
}

extension CommitTextField where Label == EmptyView {
    /// A field with only a prompt, for a form row of its own.
    init(
        value: String, prompt: String, axis: Axis = .horizontal,
        field: InspectorFieldID, focus: FocusState<InspectorFieldID?>.Binding,
        commit: @escaping (String) -> Void
    ) {
        self.init(value: value, prompt: prompt, axis: axis, field: field, focus: focus, commit: commit) {
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
