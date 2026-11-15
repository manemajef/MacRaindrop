import SwiftUI

/// The raindrop's metadata: cover, excerpt, note, tags, highlights and info.
struct InspectorView: View {
    @Environment(LibraryStore.self) private var store
    let raindrop: Raindrop
    /// The edit in progress on the title, description, note and link, or nil when not editing.
    @State private var draft: RaindropDraft?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if raindrop.coverURL != nil {
                    CoverImage(url: raindrop.coverURL, kind: raindrop.type, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(.rect(cornerRadius: 8))
                }
                
                if let draft {
                    InspectorTextEditor(draft: draft) { self.draft = nil }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        header

                        if !raindrop.excerpt.isEmpty {
                            Text(raindrop.excerpt)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                
                if let url = raindrop.url {
                    HStack {
                        Link(destination: url) {
                            Label(raindrop.domain, systemImage: raindrop.type.systemImage)
                        }
                        .font(.callout)
                        .help(raindrop.link)
                        Spacer()
                        favoriteButton
                    }
                }

                // While editing, the note is in the edit form above.
                if draft == nil, !raindrop.note.isEmpty {
                    section("Notes") {
                        Text(raindrop.note).textSelection(.enabled)
                    }
                }

                InspectorTagsEditor(raindrop: raindrop)
                    .id(raindrop.id)

                if !raindrop.highlights.isEmpty {
                    section("Highlights") {
                        ForEach(raindrop.highlights) { HighlightView(highlight: $0) }
                    }
                }

                section("Info") { infoSection }
                    
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Edits that weren't saved are dropped when another bookmark is selected.
        .onChange(of: raindrop.id) { draft = nil }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(raindrop.title)
                .font(.title3.bold())
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button("Edit", systemImage: "pencil") {
                draft = RaindropDraft(raindrop: raindrop)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Edit title, description, note and link")
            .disabled(!store.canModify([raindrop.id]))
        }
    }
    
    private var favoriteButton: some View {
        Button {
            Task {
                await store.attempt("", {
                    try await store.setImportant([raindrop.id], !raindrop.important)
                })
            }
            
        } label : {
            Image(systemName: raindrop.important ? "heart.fill" : "heart")
                .foregroundStyle(raindrop.important ? AnyShapeStyle(.pink) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .disabled(!store.canModify([raindrop.id]))
        .contentTransition(.symbolEffect(.replace))
    }
    
    /// Moves the raindrop as soon as a collection is picked, like the favorite button. The row
    /// keeps showing the current collection, with a spinner, until the server confirms.
    private var collectionPicker: some View {
        let selection = Binding {
            raindrop.collectionID
        } set: { id in
            let raindropID = raindrop.id
            Task {
                await store.attempt("Couldn’t Move Bookmark") {
                    try await store.move([raindropID], to: id)
                }
            }
        }
        return HStack(spacing: 6) {
            if store.pendingIDs.contains(raindrop.id) {
                ProgressView().controlSize(.small)
            }
            CollectionPicker(selection: selection) { id in
                Text(store.collectionTitle(for: id))
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.visible)
            .fixedSize()
            .disabled(!store.canModify([raindrop.id]))
        }
    }

    private var infoSection: some View {
        Form {
            Section {
                LabeledContent("Collection") { collectionPicker }
                LabeledContent("Type", value: raindrop.type.label)
                if let date = raindrop.reminder?.date {
                    LabeledContent("Reminder") { Text(date, format: .timestamp) }
                }
            }

            Section {
                LabeledContent("Created") { Text(raindrop.created, format: .timestamp) }
                LabeledContent("Updated") { Text(raindrop.lastUpdate, format: .timestamp) }
                if let cache = raindrop.cache {
                    LabeledContent("Permanent copy", value: cache.size.map {
                        "\(cache.status) · \($0.formatted(.byteCount(style: .file)))"
                    } ?? cache.status)
                }
                if raindrop.broken {
                    LabeledContent("Status", value: "Link appears broken")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }
}

private struct HighlightView: View {
    let highlight: Raindrop.Highlight

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(highlight.swiftUIColor)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(highlight.text)
                    .lineLimit(8)
                    .textSelection(.enabled)
                if !highlight.note.isEmpty {
                    Text(highlight.note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(highlight.swiftUIColor.opacity(0.08), in: .rect(cornerRadius: 8))
    }
}

#Preview("Info") {
    let store = LibraryStore.preview
    InspectorView(raindrop: store.raindrops.first { !$0.highlights.isEmpty } ?? store.raindrops[0])
        .frame(width: 320, height: 600)
        .previewEnvironment(store)
}
