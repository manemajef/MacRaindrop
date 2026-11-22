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
    /// Whether the URL row shows the full URL in a field, rather than the site's domain.
    @State private var isEditingLink = false

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
                    // A concrete color: the field editor ignores hierarchical styles like
                    // `.secondary`, so the text turned primary while and after editing.
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1...10)
                    .fullWidthField()
            }
//                } header: {
//                    if raindrop.coverURL != nil {
//                        CoverImage(url: raindrop.coverURL, kind: raindrop.type, contentMode: .fit)
//                            .frame(maxWidth: .infinity, maxHeight: 180)
//                            .clipShape(.rect(cornerRadius: 8))
//                            .padding(.bottom, 4)
//                    }
//                }
//



            Section {
                HStack(alignment: .firstTextBaseline) {
                    Label("Tags", systemImage: "number")
                    TagTokenField(tags: shown.tags, knownTags: store.tags.map(\.name)) {
                        change(RaindropChanges(tags: $0))
                    }
                }
            }

            Section {
                linkRow
            }
            Section("Notes") {
                CommitTextField(
                    value: shown.note, prompt: "Note", axis: .vertical, field: .note, focus: $focus
                ) { change(RaindropChanges(note: $0)) }
                    .lineLimit(3...12)
                    .fullWidthField()
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
        // The cover stays put while the form scrolls under it, softened at its edge.
        .safeAreaBar(edge: .top, spacing: 0) {
            headerBar
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaInset(edge: .bottom) {
            if isSaving { savingStatus }
        }
        .animation(.default, value: isSaving)
        .onChange(of: prompts.editRequest, initial: true) { takeEditRequest() }
    }

    // MARK: Parts

    /// The cover, or a short tinted bar for a bookmark without one, with glass controls
    /// floating on its bottom edge: the collection and the favorite heart.
    private var headerBar: some View {
        Group {
            if raindrop.coverURL != nil {
                coverWithBlur
            } else {
                coverlessBackground
            }
        }
        .overlay(alignment: .bottom) {
            GlassEffectContainer {
                HStack(alignment: .center) {
                    floatingCollectionMenu
                    Spacer(minLength: 8)
                    floatingFavoriteButton
                }
            }
            .padding(10)
        }
    }

    /// A progressive blur and a light shade along the bottom, as Music does under its
    /// controls, so the pills sit on something calm over a busy cover.
    private var coverWithBlur: some View {
        cover
            .overlay {
                cover
                    .blur(radius: 16, opaque: true)
                    .mask {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0.5),
                            .init(color: .black, location: 0.85),
                        ], startPoint: .top, endPoint: .bottom)
                    }
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 80)
                    .allowsHitTesting(false)
            }
    }

    /// The site's icon, enlarged and blurred into a glow of its colors, so a bookmark without a
    /// cover still gets a header for the controls.
    private var coverlessBackground: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Favicon(domain: raindrop.domain, fallbackSymbol: raindrop.type.systemImage)
                    .frame(width: 160, height: 160)
                    .blur(radius: 40)
                    .opacity(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .clipped()
            .accessibilityHidden(true)
    }

    private var cover: some View {
        CoverImage(url: raindrop.coverURL, kind: raindrop.type, fillsWidthUpTo: Self.coverMaxHeight)
    }

    private static let coverMaxHeight: CGFloat = 240

    /// The site's favicon and domain. A click swaps in a field with the full URL to edit, which
    /// goes back to the domain once it's committed or left.
    @ViewBuilder
    private var linkRow: some View {
        if isEditingLink {
            CommitTextField(
                value: shown.link, prompt: "https://", field: .link, focus: $focus
            ) { link in
                let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
                if !link.isEmpty { change(RaindropChanges(link: link)) }
            } label: {
                Label("URL", systemImage: "link")
            }
            .lineLimit(1)
            .onSubmit { isEditingLink = false }
            .onChange(of: focus) { _, focus in
                if focus != .link { isEditingLink = false }
            }
        } else {
            Button {
                isEditingLink = true
                // The field appears on the next update; focus it once it's there.
                Task {
                    try? await Task.sleep(for: .milliseconds(30))
                    focus = .link
                }
            } label: {
                LabeledContent {
                    HStack(spacing: 6) {
                        Favicon(domain: shown.domain, fallbackSymbol: raindrop.type.systemImage)
                            .frame(width: 16, height: 16)
                        Text(shown.domain.isEmpty ? shown.link : shown.domain)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } label: {
                    Label("URL", systemImage: "link")
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(shown.link)
            .accessibilityHint("Edit the URL")
        }
    }

    private var favoriteBinding: Binding<Bool> {
        Binding { shown.important } set: { change(RaindropChanges(important: $0)) }
    }

    /// A heart over the cover, like Apple Music's, to favorite without scrolling to the toggle.
    private var floatingFavoriteButton: some View {
        Button {
            favoriteBinding.wrappedValue.toggle()
        } label: {
            Image(systemName: shown.important ? "heart.fill" : "heart")
                .foregroundStyle(shown.important ? AnyShapeStyle(.pink) : AnyShapeStyle(.primary))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 28)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .help(shown.important ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityLabel(shown.important ? "Remove from Favorites" : "Add to Favorites")
        .disabled(!store.canWrite)
    }

    /// The collection as a glass pill, with the collection tree in its menu. Moves the raindrop
    /// as soon as one is picked.
    private var floatingCollectionMenu: some View {
        Menu {
            CollectionMenuItems(isDisabled: { $0 == shown.collectionID }) { id in
                change(RaindropChanges(collectionID: id))
            }
        } label: {
            HStack(spacing: 6) {
                Label(store.collectionTitle(for: shown.collectionID), systemImage: collectionSymbol)
                    .lineLimit(1)
                // The plain button style hides the menu's own indicator.
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
                .padding(.horizontal, 12)
                .frame(height: 24)
                .contentShape(.capsule)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        // A menu ignores the glass button style and draws nearly clear, so the glass is explicit.
        .glassEffect(.regular.interactive(), in: .capsule)
        .fixedSize()
        .help("Move to Another Collection")
        .disabled(!store.canWrite)
    }

    private var collectionSymbol: String {
        shown.collectionID == SystemCollectionID.unsorted ? "tray" : "folder"
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
