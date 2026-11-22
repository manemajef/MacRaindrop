import SwiftUI

/// A raindrop's cover image, falling back to a type icon while loading or when there is none.
///
/// Covers come from `ImagePipeline`. One already in memory shows on the first frame, with no
/// placeholder in between, so cards scrolled back into view or rebuilt by a resize don't flash.
struct CoverImage: View {
    let url: URL?
    let kind: Raindrop.Kind
    var contentMode: ContentMode = .fill
    /// Set to take the full width offered, as tall as the image's shape needs up to this
    /// height, and crop beyond it, rather than leave bars at the sides.
    var fillsWidthUpTo: CGFloat? = nil

    /// The last cover loaded, with its URL, so a stale one never shows after `url` changes.
    @State private var loaded: (url: URL, image: CGImage)?

    private var image: CGImage? {
        guard let url else { return nil }
        if let loaded, loaded.url == url { return loaded.image }
        return ImagePipeline.shared.cachedImage(for: url)
    }

    var body: some View {
        Group {
            if let maxHeight = fillsWidthUpTo {
                // Until the image loads, a 16:9 placeholder.
                let aspectRatio = image.map { CGFloat($0.width) / CGFloat(max($0.height, 1)) } ?? 16 / 9
                WidthFillingLayout(aspectRatio: aspectRatio, maxHeight: maxHeight) {
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        placeholder
                    }
                }
                .clipped()
            } else if let image {
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

/// The full width offered, by `width / aspectRatio` high up to `maxHeight`, for one subview.
private struct WidthFillingLayout: Layout {
    let aspectRatio: CGFloat
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        return CGSize(width: width, height: min(width / aspectRatio, maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: ProposedViewSize(bounds.size))
        }
    }
}

#Preview("Cover Placeholders") {
    // No cover: each kind's symbol, as shown while a cover loads or when there is none.
    HStack(spacing: 12) {
        ForEach(Raindrop.Kind.allCases, id: \.self) { kind in
            VStack {
                CoverImage(url: nil, kind: kind)
                    .frame(width: 96, height: 72)
                    .clipShape(.rect(cornerRadius: 6))
                Text(kind.label)
                    .font(.caption)
            }
        }
    }
    .padding()
}
