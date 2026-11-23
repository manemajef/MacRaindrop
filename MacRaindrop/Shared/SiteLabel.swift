import SwiftUI

/// The site a bookmark points to: its favicon and domain, as a `Label`.
///
/// Being a `Label`, it follows the screen's label style (`.iconOnly`, `.titleOnly`), font and
/// foreground style, so the same view fits a card's footer, a row or a glass pill.
struct SiteLabel: View {
    let domain: String
    /// Shown while the favicon loads, or when the site has none.
    var fallbackSymbol = "globe"
    var iconSize: CGFloat = 16

    var body: some View {
        Label {
            Text(domain)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Favicon(domain: domain, fallbackSymbol: fallbackSymbol)
                .frame(width: iconSize, height: iconSize)
        }
    }
}

extension SiteLabel {
    /// The raindrop's domain, falling back to its type's symbol.
    init(_ raindrop: Raindrop, iconSize: CGFloat = 16) {
        self.init(domain: raindrop.domain, fallbackSymbol: raindrop.type.systemImage, iconSize: iconSize)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 10) {
        SiteLabel(domain: "youtube.com")
        SiteLabel(domain: "reddit.com").font(.callout).foregroundStyle(.secondary)
        SiteLabel(domain: "x.com", iconSize: 12).font(.caption)
    }
    .padding()
}
