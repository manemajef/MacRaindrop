import SwiftUI

/// A site's icon, fetched from the site itself: its Apple touch icon, which is sharp at any
/// size, else its `favicon.ico`. Shows `fallbackSymbol` until one loads, or if neither does.
///
/// Only the bookmark's own site is asked, never a third-party favicon service, so browsing
/// the library doesn't tell anyone else which sites are in it. Icons go through
/// `ImagePipeline`, so they're cached like covers.
struct Favicon: View {
    let domain: String
    var fallbackSymbol = "globe"

    @State private var loaded: (domain: String, image: CGImage)?

    private var candidates: [URL] {
        guard !domain.isEmpty else { return [] }
        return ["apple-touch-icon.png", "favicon.ico"].compactMap { URL(string: "https://\(domain)/\($0)") }
    }

    private var image: CGImage? {
        if let loaded, loaded.domain == domain { return loaded.image }
        return candidates.lazy.compactMap(ImagePipeline.shared.cachedImage(for:)).first
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 3))
            } else {
                Image(systemName: fallbackSymbol)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: domain) {
            guard image == nil else { return }
            for url in candidates {
                if let image = await ImagePipeline.shared.image(for: url) {
                    loaded = (domain, image)
                    return
                }
            }
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        ForEach(["apple.com", "github.com", "reddit.com", "x.com", "no-such-site.invalid"], id: \.self) { domain in
            VStack {
                Favicon(domain: domain).frame(width: 32, height: 32)
                Text(domain).font(.caption)
            }
        }
    }
    .padding()
}
