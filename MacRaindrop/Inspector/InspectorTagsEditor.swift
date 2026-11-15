import SwiftUI

/// The inspector's tags, editable in place: each chip removed or tag added is saved right away.
///
/// The store takes one write per raindrop at a time and drops any sent while one is
/// pending. So a change made during a save waits here, in `unsavedTags`, and goes out as
/// soon as that save finishes. The field keeps focus and nothing typed is lost. A spinner
/// shows while any tag change hasn't reached the server.
///
/// Give it `.id(raindrop.id)` so a different bookmark starts with a clean slate.
struct InspectorTagsEditor: View {
    @Environment(LibraryStore.self) private var store
    let raindrop: Raindrop

    /// The tags the user wants, while they differ from what the server has confirmed.
    @State private var unsavedTags: [String]?
    @State private var newTag = ""
    @State private var isSaving = false

    private var canModify: Bool { store.canModify([raindrop.id]) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Tags")
                    .font(.headline)
                if unsavedTags != nil {
                    ProgressView()
                        .controlSize(.small)
                        .help("Saving tags…")
                }
            }
            TagField(tags: tags, text: $newTag)
                .textFieldStyle(.plain)
                .disabled(!store.canWrite)
        }
        .onChange(of: canModify) { _, canModify in
            if canModify { saveUnsavedTags() }
        }
    }

    private var tags: Binding<[String]> {
        Binding {
            unsavedTags ?? raindrop.tags
        } set: { tags in
            unsavedTags = tags
            saveUnsavedTags()
        }
    }

    /// Sends the wanted tags unless a save is already running here, or another write to this
    /// raindrop is (then `onChange(of: canModify)` calls back once it finishes).
    private func saveUnsavedTags() {
        guard !isSaving, let tags = unsavedTags, canModify else { return }
        isSaving = true
        Task {
            await store.attempt("Couldn’t Update Tags") {
                try await store.edit(raindrop.id, with: RaindropChanges(tags: tags))
            }
            isSaving = false
            // Saved, or failed and the store is showing why: either way the server's copy is
            // the truth now. If more changes came in meanwhile, they go out next.
            if unsavedTags == tags { unsavedTags = nil } else { saveUnsavedTags() }
        }
    }
}

#Preview {
    let store = LibraryStore.preview
    InspectorTagsEditor(raindrop: store.raindrops.first { !$0.tags.isEmpty } ?? store.raindrops[0])
        .padding()
        .frame(width: 320)
        .previewEnvironment(store)
}
