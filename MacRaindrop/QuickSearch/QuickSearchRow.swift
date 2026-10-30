import SwiftUI

/// One result: the bookmark's kind, its title with the typed words in bold, and where it's from.
struct QuickSearchRow: View {
    let raindrop: Raindrop
    let collection: String?
    let query: String
    let isSelected: Bool

    static let height: CGFloat = 44

    var body: some View {
        HStack(spacing: 10) {
            QuickSearchThumbnail(raindrop: raindrop)
            VStack(alignment: .leading, spacing: 2) {
                Text(highlightedTitle)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isSelected {
                Text("↩ Open   ⌘↩ Show in Library")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .background {
            if isSelected {
                // Concentric with the panel: its radius less the list's inset.
                RoundedRectangle(cornerRadius: QuickSearchView.cornerRadius - QuickSearchView.listPadding)
                    .fill(.primary.opacity(0.1))
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var title: String {
        raindrop.title.isEmpty ? raindrop.link : raindrop.title
    }

    /// domain · collection · #tags
    private var subtitle: String {
        var parts = [raindrop.domain]
        if let collection { parts.append(collection) }
        if !raindrop.tags.isEmpty { parts.append(raindrop.tags.map { "#\($0)" }.joined(separator: " ")) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Each typed word bolded where it appears in the title, ignoring case and accents.
    private var highlightedTitle: AttributedString {
        var attributed = AttributedString(title)
        let words = query.split(whereSeparator: \.isWhitespace).filter { !$0.hasPrefix("#") }
        for word in words {
            var searchStart = attributed.startIndex
            while searchStart < attributed.endIndex,
                  let range = attributed[searchStart...].range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) {
                attributed[range].inlinePresentationIntent = .stronglyEmphasized
                searchStart = range.upperBound
            }
        }
        return attributed
    }
}

/// The bookmark's cover, small and rounded, or its kind's symbol until (or unless) there is one.
///
/// Uses the grid's thumbnail cache, so covers already seen in the grid show at once.
private struct QuickSearchThumbnail: View {
    let raindrop: Raindrop
    @State private var loaded: CGImage?

    static let size: CGFloat = 32

    var body: some View {
        let image = loaded ?? raindrop.coverURL.flatMap(ImagePipeline.shared.cachedImage(for:))
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: raindrop.type.systemImage)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .background(.quaternary.opacity(image == nil ? 0.5 : 0))
        .clipShape(.rect(cornerRadius: 7))
        .task(id: raindrop.coverURL) {
            guard let url = raindrop.coverURL, ImagePipeline.shared.cachedImage(for: url) == nil else { return }
            loaded = await ImagePipeline.shared.image(for: url)
        }
    }
}
