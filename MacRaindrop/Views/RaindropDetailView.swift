import SwiftUI

struct RaindropDetailView: View {
    @Environment(LibraryStore.self) private var store
    let raindrop: Raindrop

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if raindrop.coverURL != nil {
                    CoverImage(url: raindrop.coverURL, kind: raindrop.type, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 320)
                        .clipShape(.rect(cornerRadius: 10))
                }

                header

                if !raindrop.excerpt.isEmpty {
                    Text(raindrop.excerpt)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if !raindrop.note.isEmpty {
                    section("Note") {
                        Text(raindrop.note).textSelection(.enabled)
                    }
                }

                if !raindrop.tags.isEmpty {
                    section("Tags") { TagList(tags: raindrop.tags) }
                }

                if !raindrop.highlights.isEmpty {
                    section("Highlights") {
                        ForEach(raindrop.highlights) { HighlightView(highlight: $0) }
                    }
                }

                section("Info") { metadata }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(raindrop.title)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.toggleImportant(raindrop.id)
                } label: {
                    Label("Favorite", systemImage: raindrop.important ? "heart.fill" : "heart")
                }
                if let url = raindrop.url {
                    ShareLink(item: url)
                    Link(destination: url) {
                        Label("Open in Browser", systemImage: "safari")
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(raindrop.title)
                .font(.title2.bold())
                .textSelection(.enabled)
            if let url = raindrop.url {
                Link(destination: url) {
                    Label(raindrop.domain, systemImage: raindrop.type.systemImage)
                }
                .font(.callout)
                .help(raindrop.link)
            }
        }
    }

    private var metadata: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            infoRow("Collection", value: collectionName)
            infoRow("Type", value: raindrop.type.label)
            infoRow("Created", value: raindrop.created.formatted(date: .abbreviated, time: .shortened))
            infoRow("Updated", value: raindrop.lastUpdate.formatted(date: .abbreviated, time: .shortened))
            if let date = raindrop.reminder?.date {
                infoRow("Reminder", value: date.formatted(date: .abbreviated, time: .shortened))
            }
            if let cache = raindrop.cache {
                infoRow("Permanent copy", value: cache.size.map {
                    "\(cache.status) · \($0.formatted(.byteCount(style: .file)))"
                } ?? cache.status)
            }
            if raindrop.broken {
                infoRow("Status", value: "Link appears broken")
            }
        }
        .font(.callout)
    }

    private var collectionName: String {
        switch raindrop.collectionID {
        case SystemCollectionID.unsorted: "Unsorted"
        case SystemCollectionID.trash: "Trash"
        case let id: store.collection(id: id)?.title ?? "Unknown"
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
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

#Preview {
    let store = LibraryStore.preview
    NavigationStack {
        RaindropDetailView(raindrop: store.raindrops.first { !$0.highlights.isEmpty } ?? store.raindrops[0])
    }
    .environment(store)
}
