import SwiftUI

/// A raindrop's tags as a form row: `#`, the tags as chips with a remove button, a field for
/// adding one, and `+` at the end.
///
/// Typing offers the library's matching tags in the system's completion menu, ranked by
/// `TagMatcher`. Return or `+` adds what's typed, Delete in an empty field removes the last tag,
/// and `+` with nothing typed puts the cursor in the field. Every change goes to `commit` with
/// the whole list, so each is one write.
struct TagEditor: View {
    let tags: [String]
    /// Every known tag, most used first.
    let knownTags: [String]
    var prompt = "Add tag"
    let commit: ([String]) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var suggestions: [String] {
        TagMatcher(known: knownTags).matches(for: text, excluding: tags)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // The row's label, lined up with the icons of the rows around it.
            InspectorRowIcon(systemImage: "number")

            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    TagChip(tag: tag) { commit(tags.filter { $0 != tag }) }
                }
                // A prompt with the label hidden: in a form, a text field's title is drawn as a
                // label beside it rather than as its placeholder.
                TextField(text: $text, prompt: Text(prompt)) { Text(prompt) }
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    // `FlowLayout` places each item at its ideal width, which for a text field is
                    // wide enough to push it onto a line of its own.
                    .frame(minWidth: 80, idealWidth: 90)
                    .textInputSuggestions {
                        ForEach(suggestions, id: \.self) { tag in
                            Text(tag).textInputCompletion(tag)
                        }
                    }
                    .onSubmit(addTypedTag)
                    .onKeyPress(.delete) {
                        guard text.isEmpty, let last = tags.last else { return .ignored }
                        commit(tags.filter { $0 != last })
                        return .handled
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

//            Button("Add Tag", systemImage: "plus") {
//                if text.trimmingCharacters(in: .whitespaces).isEmpty {
//                    isFocused = true
//                } else {
//                    addTypedTag()
//                }
//            }
//            .labelStyle(.iconOnly)
//            .buttonStyle(.plain)
//            .font(.callout.weight(.semibold))
//            .foregroundStyle(.secondary)
//            .help("Add Tag")
        }
        .animation(.snappy, value: tags)
    }

    /// Adds the field's text as a tag, dropping spaces around it and any leading `#`.
    private func addTypedTag() {
        let tag = text.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        text = ""
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        commit(tags + [tag])
    }
}

/// One tag, tinted like the cards' tags, with a button to remove it.
private struct TagChip: View {
    let tag: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            Text(tag)
            Button("Remove", systemImage: "xmark", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .help("Remove #\(tag)")
        }
        .font(.callout)
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 2)
        .glassEffect(.regular.tint(.accentColor))
        .background(.tint.opacity(0.15), in: .capsule)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

#Preview {
    @Previewable @State var tags = ["design", "swiftui", "to-read"]
    Form {
        Section {
            TagEditor(tags: tags, knownTags: ["design", "development", "swift", "swiftui", "to-read", "reading"]) {
                tags = $0
            }
        }
    }
    .formStyle(.grouped)
    .frame(width: 300)
}
