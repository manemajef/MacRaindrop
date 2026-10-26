import SwiftUI

/// A raindrop's cover image, falling back to a type icon while loading or when there is none.
struct CoverImage: View {
    let url: URL?
    let kind: Raindrop.Kind
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: contentMode)
            } else {
                placeholder
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
