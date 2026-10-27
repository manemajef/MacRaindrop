import SwiftUI

/// Edits one raindrop, laid out like the iOS app's edit sheet: title and description beside
/// the cover, a note, the collection, tags with suggestions, then the link and favorite.
///
/// Opens with the cached copy and fetches the server's in the background. Save sends only the
/// fields that changed, and first checks whether the bookmark changed elsewhere meanwhile.
struct EditRaindropSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The version the form started from; edits are measured against it.
    @State private var original: Raindrop
    @State private var draft: Raindrop
    @State private var newTag = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showsConflict = false

    init(raindrop: Raindrop) {
        _original = State(initialValue: raindrop)
        _draft = State(initialValue: raindrop)
    }

    private var changes: RaindropChanges {
        var changes = RaindropChanges()
        if draft.title != original.title { changes.title = draft.title }
        if draft.excerpt != original.excerpt { changes.excerpt = draft.excerpt }
        if draft.note != original.note { changes.note = draft.note }
        if draft.link != original.link { changes.link = draft.link }
        if draft.tags != original.tags { changes.tags = draft.tags }
        if draft.important != original.important { changes.important = draft.important }
        if draft.collectionID != original.collectionID { changes.collectionID = draft.collectionID }
        return changes
    }

    private var hasChanges: Bool { changes != RaindropChanges() }

    private var canSave: Bool {
        hasChanges && !isSaving && !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
            && store.canModify([draft.id])
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 14) {
                    group { summary }
                    group { collectionRow }
                    tagsSection
                    group { linkAndFavorite }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
        }
        // As tall as the content needs; the note's line limit keeps that bounded.
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .disabled(isSaving)
        .glassEffect(in: .containerRelative)
        .task { await loadLatest() }
        .alert("Changed on Another Device", isPresented: $showsConflict) {
            Button("Save Anyway") { save(checkingForConflicts: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This bookmark was changed elsewhere after you opened it. Saving replaces only the fields you edited here.")
        }
    }

    // MARK: Sections

    private var header: some View {
        ZStack {
            Text("Edit \(draft.type.label.lowercased())")
                .font(.headline)
            HStack {
                Button("Cancel",  role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Spacer()
                Button {
                    save(checkingForConflicts: true)
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("s")
                .disabled(!canSave)
            }
        }
        .padding(12)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Title", text: $draft.title, axis: .vertical)
                        .font(.title3.bold())
                        .lineLimit(1...3)
                    TextField("Description", text: $draft.excerpt, axis: .vertical)
                        .foregroundStyle(.secondary)
                        .lineLimit(1...4)
                }
                CoverImage(url: draft.coverURL, kind: draft.type)
                    .frame(width: 72, height: 72)
                    .clipShape(.rect(cornerRadius: 8))
            }
            Divider()
            TextField("Note", text: $draft.note, axis: .vertical)
                .lineLimit(3...8)
        }
        .textFieldStyle(.plain)
    }

    private var collectionRow: some View {
        Menu {
            CollectionMenuItems(isDisabled: { $0 == draft.collectionID }, choose: { draft.collectionID = $0 })
        } label: {
            HStack {
                Label(collectionTitle, systemImage: draft.collectionID == SystemCollectionID.unsorted ? "tray" : "folder")
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            group {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "number")
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(draft.tags, id: \.self) { tag in
                            Button {
                                draft.tags.removeAll { $0 == tag }
                            } label: {
                                Label(tag, systemImage: "xmark")
                                    .labelStyle(TrailingIconLabelStyle())
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Remove #\(tag)")
                        }
                        TextField("Add tag", text: $newTag)
                            .textFieldStyle(.plain)
                            .frame(minWidth: 80)
                            .onSubmit(addNewTag)
                    }
                }
            }
            if !suggestions.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(suggestions, id: \.self) { tag in
                        Button("+ \(tag)") { draft.tags.append(tag) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var linkAndFavorite: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                TextField("Link", text: $draft.link)
                    .textFieldStyle(.plain)
            }
            Divider()
            HStack(spacing: 8) {
                Image(systemName: draft.important ? "heart.fill" : "heart")
                    .foregroundStyle(draft.important ? AnyShapeStyle(.pink) : AnyShapeStyle(.secondary))
                Text("Favorite")
                Spacer()
                Toggle("Favorite", isOn: $draft.important)
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

    private var collectionTitle: String {
        draft.collectionID == SystemCollectionID.unsorted
            ? "Unsorted"
            : store.collection(id: draft.collectionID)?.title ?? "Collection"
    }

    /// The most used tags that this raindrop doesn't have yet.
    private var suggestions: [String] {
        store.tags.map(\.name).filter { !draft.tags.contains($0) }.prefix(8).map(\.self)
    }

    private func addNewTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if !tag.isEmpty, !draft.tags.contains(tag) { draft.tags.append(tag) }
        newTag = ""
    }

    /// Picks up the server's copy if nothing has been edited yet. Otherwise the edits stay,
    /// and Save notices the difference.
    private func loadLatest() async {
        guard let latest = try? await store.refresh(original.id), !hasChanges else { return }
        original = latest
        draft = latest
    }

    private func save(checkingForConflicts: Bool) {
        addNewTag()
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                if checkingForConflicts {
                    let latest = try await store.refresh(original.id)
                    if latest.lastUpdate != original.lastUpdate {
                        showsConflict = true
                        return
                    }
                }
                try await store.edit(original.id, with: changes)
                dismiss()
            } catch {
                // Stay open with every edit intact.
                errorMessage = error.localizedDescription
            }
        }
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

/// Lays children out left to right, wrapping onto new lines, like inline text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

#Preview {
    let store = LibraryStore.preview
    // A bookmark with tags and a cover, so every section has something in it.
    EditRaindropSheet(raindrop: store.raindrops.first { !$0.tags.isEmpty && $0.coverURL != nil } ?? store.raindrops[0])
        .environment(store)
}
