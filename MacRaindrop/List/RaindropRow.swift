import SwiftUI

/// A bookmark in the list: cover, title, excerpt, then source, date and tags.
struct RaindropRow: View {
    let raindrop: Raindrop
    /// A write to this raindrop is waiting for the server.
    var isPending = false
    /// The collection the raindrop is in, shown in place of the date. Nil where every row is in
    /// the same collection, so it would say nothing.
    var collectionTitle: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverImage(url: raindrop.coverURL, kind: raindrop.type)
                .frame(width: 72, height: 54)
                .clipShape(.rect(cornerRadius: 6))
                .overlay {
                    if isPending {
                        ProgressView()
                            .controlSize(.small)
                            .padding(6)
                            .background(.regularMaterial, in: .circle)
                    }
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(raindrop.title)
                        .font(.headline)
                        .lineLimit(2)
                    if raindrop.important {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                            .imageScale(.small)
                            .accessibilityLabel("Favorite")
                    }
                }

                if !raindrop.excerpt.isEmpty {
                    Text(raindrop.excerpt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Label(raindrop.type.label, systemImage: raindrop.type.systemImage)
                        .labelStyle(.iconOnly)
                    Text(raindrop.domain)
                    Text("·")
                    if let collectionTitle {
                        CollectionLabel(title: collectionTitle, raindrop: raindrop)
                    } else {
                        Text(raindrop.created, format: .relativeNamed)
                    }
                    if raindrop.broken {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Broken link")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)

                if !raindrop.tags.isEmpty {
                    TagList(tags: raindrop.tags)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview("Row States") {
    let raindrop = LibraryStore.preview.raindrops(in: .all).first { !$0.tags.isEmpty && !$0.excerpt.isEmpty }!
    // The same bookmark plain, then with each flag and state a row can show.
    var bare = raindrop
    bare.excerpt = ""
    bare.tags = []
    bare.cover = ""
    var favorite = raindrop
    favorite.important = true
    var broken = raindrop
    broken.broken = true
    return List {
        RaindropRow(raindrop: raindrop)
        RaindropRow(raindrop: bare)
        RaindropRow(raindrop: favorite)
        RaindropRow(raindrop: broken)
        RaindropRow(raindrop: raindrop, collectionTitle: "Reading")
        RaindropRow(raindrop: raindrop, isPending: true)
    }
    .frame(width: 380, height: 560)
}
