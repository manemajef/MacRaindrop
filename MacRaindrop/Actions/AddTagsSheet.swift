import SwiftUI

/// Asks for tags to add to one or more raindrops, and waits for the server before closing.
struct AddTagsSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let request: TagRequest

    @State private var text = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Comma-separated, with any leading `#` dropped.
    private var tags: [String] {
        var seen = Set<String>()
        return text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private var suggestions: [String] {
        store.tags.map(\.name).filter { !tags.contains($0) }.prefix(12).map(\.self)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.ids.count == 1 ? "Add Tags" : "Add Tags to \(request.ids.count) Bookmarks")
                .font(.headline)

            TextField("Tags", text: $text, prompt: Text("design, swift, to read"))
                .textFieldStyle(.roundedBorder)
                .disabled(isSaving)
                .onSubmit(save)

            if !suggestions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { tag in
                            Button("#\(tag)") { text = (tags + [tag]).joined(separator: ", ") }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action: save) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Add")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tags.isEmpty || isSaving || !store.canModify(request.ids))
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func save() {
        guard !tags.isEmpty, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await store.addTags(tags, to: request.ids)
                dismiss()
            } catch {
                // Stay open with what was typed, so nothing is lost.
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

#Preview("Add Tags") {
    let store = LibraryStore.preview
    AddTagsSheet(request: TagRequest(ids: [store.raindrops[0].id]))
        .previewEnvironment(store)
}

#Preview("Add Tags to Several") {
    let store = LibraryStore.preview
    AddTagsSheet(request: TagRequest(ids: store.raindrops.prefix(3).map(\.id)))
        .previewEnvironment(store)
}
