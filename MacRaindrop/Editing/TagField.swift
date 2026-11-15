import SwiftUI

/// A raindrop's tags as removable chips, followed by a field for typing a new one.
///
/// Suggestions aren't part of it; screens that offer them show them nearby. The text being
/// typed is a binding so the screen can add it on save. The screen sets the text field style
/// and any background.
struct TagField: View {
    @Binding var tags: [String]
    @Binding var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "number")
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Button {
                        tags.removeAll { $0 == tag }
                    } label: {
                        Label(tag, systemImage: "xmark")
                            .labelStyle(TrailingIconLabelStyle())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Remove #\(tag)")
                }
                TextField("Add tag", text: $text)
                    .frame(minWidth: 80)
                    .onSubmit {
                        tags.addTag(text)
                        text = ""
                    }
            }
        }
    }
}

extension [String] {
    /// Adds a typed tag, dropping spaces and any leading `#`. Ignores blanks and duplicates.
    mutating func addTag(_ typed: String) {
        let tag = typed.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if !tag.isEmpty, !contains(tag) { append(tag) }
    }
}

/// Puts a label's icon after its title, for the removable tag chips.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.imageScale(.small).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    @Previewable @State var tags = ["design", "swiftui", "to-read"]
    @Previewable @State var text = ""
    TagField(tags: $tags, text: $text)
        .textFieldStyle(.plain)
        .padding()
        .frame(width: 320)
}
