import SwiftUI

// How a raindrop's kind and highlights look on screen.

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
