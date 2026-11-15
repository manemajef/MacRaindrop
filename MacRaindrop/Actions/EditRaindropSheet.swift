import SwiftUI

/// Edits one raindrop, laid out like the iOS app's edit sheet: title and description beside
/// the cover, a note, the collection, tags with suggestions, then the link and favorite.
///
/// Opens with the cached copy and fetches the server's in the background. `RaindropDraft`
/// does the saving: only the fields that changed, after checking for changes made elsewhere.
struct EditRaindropSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RaindropDraft

    init(raindrop: Raindrop) {
        _draft = State(initialValue: RaindropDraft(raindrop: raindrop))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 14) {
                    group { summary }
                    group {
                        CollectionPicker(selection: $draft.value.collectionID)
                            .menuStyle(.button)
                            .buttonStyle(.plain)
                    }
                    tagsSection
                    group { linkAndFavorite }
                    if let errorMessage = draft.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .textFieldStyle(.plain)
                .padding(16)
            }
        }
        // As tall as the content needs; the note's line limit keeps that bounded.
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .disabled(draft.isSaving)
        .glassEffect(in: .containerRelative)
        .task { await draft.loadLatest(from: store) }
        .alert("Changed on Another Device", isPresented: $draft.showsConflict) {
            Button("Save Anyway") { save(checkingForConflicts: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This bookmark was changed elsewhere after you opened it. Saving replaces only the fields you edited here.")
        }
    }

    // MARK: Sections

    private var header: some View {
        ZStack {
            Text("Edit \(draft.value.type.label.lowercased())")
                .font(.headline)
            HStack {
                Button("Cancel",  role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Spacer()
                Button {
                    save(checkingForConflicts: true)
                } label: {
                    if draft.isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("s")
                .disabled(!draft.canSave(in: store))
            }
        }
        .padding(12)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Title", text: $draft.value.title, axis: .vertical)
                        .font(.title3.bold())
                        .lineLimit(1...3)
                    TextField("Description", text: $draft.value.excerpt, axis: .vertical)
                        .foregroundStyle(.secondary)
                        .lineLimit(1...4)
                }
                CoverImage(url: draft.value.coverURL, kind: draft.value.type)
                    .frame(width: 72, height: 72)
                    .clipShape(.rect(cornerRadius: 8))
            }
            Divider()
            TextField("Note", text: $draft.value.note, axis: .vertical)
                .lineLimit(3...8)
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            group {
                TagField(tags: $draft.value.tags, text: $draft.pendingTag)
            }
            if !suggestions.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(suggestions, id: \.self) { tag in
                        Button("+ \(tag)") { draft.value.tags.append(tag) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var linkAndFavorite: some View {
        VStack(spacing: 10) {
            LinkField(link: $draft.value.link)
            Divider()
            HStack(spacing: 8) {
                Image(systemName: draft.value.important ? "heart.fill" : "heart")
                    .foregroundStyle(draft.value.important ? AnyShapeStyle(.pink) : AnyShapeStyle(.secondary))
                Text("Favorite")
                Spacer()
                Toggle("Favorite", isOn: $draft.value.important)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }

    private func group(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }

    // MARK: Data

    /// The most used tags that this raindrop doesn't have yet.
    private var suggestions: [String] {
        store.tags.map(\.name).filter { !draft.value.tags.contains($0) }.prefix(8).map(\.self)
    }

    private func save(checkingForConflicts: Bool) {
        Task {
            if await draft.save(to: store, checkingForConflicts: checkingForConflicts) {
                dismiss()
            }
        }
    }
}

#Preview {
    let store = LibraryStore.preview
    // A bookmark with tags and a cover, so every section has something in it.
    EditRaindropSheet(raindrop: store.raindrops.first { !$0.tags.isEmpty && $0.coverURL != nil } ?? store.raindrops[0])
        .previewEnvironment(store)
}
