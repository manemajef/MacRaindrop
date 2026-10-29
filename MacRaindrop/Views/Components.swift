import SwiftUI

/// A raindrop's cover image, falling back to a type icon while loading or when there is none.
///
/// Covers come from `ImagePipeline`. One already in memory shows on the first frame, with no
/// placeholder in between, so cards scrolled back into view or rebuilt by a resize don't flash.
struct CoverImage: View {
    let url: URL?
    let kind: Raindrop.Kind
    var contentMode: ContentMode = .fill

    /// The last cover loaded, with its URL, so a stale one never shows after `url` changes.
    @State private var loaded: (url: URL, image: CGImage)?

    private var image: CGImage? {
        guard let url else { return nil }
        if let loaded, loaded.url == url { return loaded.image }
        return ImagePipeline.shared.cachedImage(for: url)
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: url) {
            // Holding the image here too keeps it on screen if the memory cache evicts it.
            guard let url, loaded?.url != url else { return }
            if let image = await ImagePipeline.shared.image(for: url) {
                loaded = (url, image)
            }
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: kind.systemImage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
    }
}

struct TagList: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: .capsule)
                    .foregroundStyle(.tint)
            }
        }
    }
}

extension Raindrop.Kind {
    var label: String {
        switch self {
        case .link: "Link"
        case .article: "Article"
        case .image: "Image"
        case .video: "Video"
        case .document: "Document"
        case .audio: "Audio"
        }
    }

    var systemImage: String {
        switch self {
        case .link: "link"
        case .article: "doc.text"
        case .image: "photo"
        case .video: "play.rectangle"
        case .document: "doc.richtext"
        case .audio: "waveform"
        }
    }
}

extension Raindrop.Highlight {
    /// Maps Raindrop's named highlight colors onto SwiftUI colors.
    var swiftUIColor: Color {
        switch color {
        case "blue": .blue
        case "brown": .brown
        case "cyan": .cyan
        case "gray": .gray
        case "green": .green
        case "indigo": .indigo
        case "orange": .orange
        case "pink": .pink
        case "purple": .purple
        case "red": .red
        case "teal": .teal
        default: .yellow
        }
    }
}
