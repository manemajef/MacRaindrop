import SwiftUI

/// The selected raindrop as a grouped form, like Reminders' details, with its fields in the
/// Raindrop apps' order: title and description, note, collection and tags, link and favorite,
/// then highlights and information.
///
/// Always editable, with standard controls and no edit mode. A text field saves when it's
/// committed (Return, or leaving it); menus, tags and toggles save as soon as they change.
/// Each change can be undone with ⌘Z. `InspectorEdits` shows what's on its way to the server
/// until the server confirms it.
///
/// Give it `.id(raindrop.id)`, so another bookmark starts with fresh fields.
struct InspectorView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(ActionPrompts.self) private var prompts
    @Environment(\.undoManager) private var undoManager
    let raindrop: Raindrop

    @FocusState private var focus: InspectorFieldID?

    private var edits: InspectorEdits { .edits(for: raindrop.id) }
    /// What's on screen: the server's copy with any unsaved edits on top.
    private var shown: Raindrop { edits.displayed(raindrop) }
    private var isSaving: Bool { edits.isBusy || store.pendingIDs.contains(raindrop.id) }

    var body: some View {
        Form {
            Section {
                CommitTextField(
                    value: shown.title, prompt: "Title", axis: .vertical, field: .title, focus: $focus
                ) { title in
                    // A bookmark needs a title; clearing it puts the old one back.
                    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty { change(RaindropChanges(title: title)) }
                }
                .font(.title3.weight(.semibold))
                .lineLimit(1...6)
                .fullWidthField()

                CommitTextField(
                    value: shown.excerpt, prompt: "Description", axis: .vertical, field: .excerpt, focus: $focus
                ) { change(RaindropChanges(excerpt: $0)) }
                .foregroundStyle(.secondary)
                .lineLimit(1...10)
                .fullWidthField()
            } header: {
                if raindrop.coverURL != nil {
                    CoverImage(url: raindrop.coverURL, kind: raindrop.type, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 180)
                        .clipShape(.rect(cornerRadius: 8))
                        .padding(.bottom, 4)
                }
            }

            Section {
                CommitTextField(
                    value: shown.note, prompt: "Note", axis: .vertical, field: .note, focus: $focus
                ) { change(RaindropChanges(note: $0)) }
                .lineLimit(3...12)
                .fullWidthField()
            }

            Section {
                LabeledContent {
                    collectionMenu
                } label: {
                    Label("Collection", systemImage: "folder")
                }
                HStack(alignment: .firstTextBaseline) {
                    Label("Tags", systemImage: "number")
                    TagTokenField(tags: shown.tags, knownTags: store.tags.map(\.name)) {
                        change(RaindropChanges(tags: $0))
                    }
                }
            }

            Section {
                CommitTextField(
                    value: shown.link, prompt: "https://", field: .link, focus: $focus
                ) { link in
                    let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !link.isEmpty { change(RaindropChanges(link: link)) }
                } label: {
                    Label("URL", systemImage: "link")
                }
                .lineLimit(1)
                .truncationMode(.middle)

                Toggle(isOn: Binding {
                    shown.important
                } set: {
                    change(RaindropChanges(important: $0))
                }) {
                    Label("Favorite", systemImage: "heart")
                }
            }

            if !raindrop.highlights.isEmpty {
                Section("Highlights") {
                    ForEach(raindrop.highlights) { HighlightView(highlight: $0) }
                }
            }

            Section("Information") {
                information
            }
        }
        .formStyle(.grouped)
        // Read-only while offline; fields still show their values.
        .disabled(!store.canWrite)
        .safeAreaInset(edge: .bottom) {
            if isSaving { savingStatus }
        }
        .animation(.default, value: isSaving)
        .onChange(of: prompts.editRequest, initial: true) { takeEditRequest() }
    }

    // MARK: Parts

    /// The collection tree as a pop-up, moving the raindrop as soon as one is picked.
    private var collectionMenu: some View {
        Menu {
            CollectionMenuItems(isDisabled: { $0 == shown.collectionID }) { id in
                change(RaindropChanges(collectionID: id))
            }
        } label: {
            Text(store.collectionTitle(for: shown.collectionID))
        }
        .fixedSize()
    }

    @ViewBuilder
    private var information: some View {
        LabeledContent("Saved") { Text(raindrop.created, format: .timestamp) }
        LabeledContent("Updated") { Text(raindrop.lastUpdate, format: .timestamp) }
        LabeledContent("Type", value: raindrop.type.label)
        if let date = raindrop.reminder?.date {
            LabeledContent("Reminder") { Text(date, format: .timestamp) }
        }
        if let cache = raindrop.cache {
            LabeledContent("Permanent Copy", value: cache.size.map {
                "\(cache.status) · \($0.formatted(.byteCount(style: .file)))"
            } ?? cache.status)
        }
        if raindrop.broken {
            LabeledContent("Status") {
                Label("Link appears broken", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var savingStatus: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Saving…")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.bar)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Actions

    private func change(_ changes: RaindropChanges) {
        edits.change(changes, in: store, undoManager: undoManager)
    }

    /// Edit (⌘E) on this bookmark puts the cursor in its title.
    private func takeEditRequest() {
        guard prompts.editRequest == raindrop.id else { return }
        prompts.editRequest = nil
        // Wait for the inspector to be on screen, in case Edit just opened it.
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            focus = .title
        }
    }
}

private struct HighlightView: View {
    let highlight: Raindrop.Highlight

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(highlight.swiftUIColor)
                .frame(width: 3)
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
        .padding(.vertical, 2)
    }
}

#Preview("Inspector") {
    let store = LibraryStore.preview
    let raindrop = store.raindrops.first { !$0.highlights.isEmpty } ?? store.raindrops[0]
    InspectorView(raindrop: raindrop)
        .frame(width: 300, height: 700)
        .previewEnvironment(store)
        .environment(ActionPrompts())
}
