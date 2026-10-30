import SwiftUI

/// A card in the style of Raindrop's iOS grid: cover, title, excerpt, tags, then source and date.
struct RaindropCard: View {
    let raindrop: Raindrop
    let isSelected: Bool
    /// A write to this raindrop is waiting for the server.
    var isPending = false
    /// Takes the height of the longest title, excerpt and tags, whatever this one has. The grid
    /// measures one card this way and gives every card that height.
    var reservesSpace = false
    static let coverHeight: CGFloat = 150
    /// The lines the card is measured with. Shown, the title takes up to `titleLines` (or the
    /// excerpt's lines too, when there's no excerpt), and the excerpt fills what's left.
    static let titleLines = 3
    static let excerptLines = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: Self.coverHeight)
                .overlay { CoverImage(url: raindrop.coverURL, kind: raindrop.type) }
                // Only trims the filled image to its frame; the card's shape rounds the top corners.
                .clipped()

            // The title gets its lines first, the tags and footer keep theirs, and the excerpt
            // shows as much as fits in between, so every card is full whatever its text.
            VStack(alignment: .leading, spacing: 5) {
                Text(raindrop.title)
                    .font(.headline)
                    .lineLimit(raindrop.excerpt.isEmpty && !reservesSpace ? Self.titleLines + Self.excerptLines : Self.titleLines,
                               reservesSpace: reservesSpace)
                    .layoutPriority(1)

                if reservesSpace {
                    // An empty string reserves nothing, so a space stands in for a missing excerpt.
                    excerpt(raindrop.excerpt.isEmpty ? " " : raindrop.excerpt)
                        .lineLimit(Self.excerptLines, reservesSpace: true)
                } else if !raindrop.excerpt.isEmpty {
                    excerpt(raindrop.excerpt)
                        .frame(minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                }

                if reservesSpace || !raindrop.tags.isEmpty {
                    // A tag's height, with or without tags.
                    Text(verbatim: "#")
//                        .font(.caption)
                        .padding(.vertical, 2)
                        .hidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .leading) {
                            TagList(tags: raindrop.tags)
                                .fixedSize()
                        }
                        .clipped()
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Without an excerpt to fill it, the space goes here. With one, a spacer would
                // take half of it.
                if raindrop.excerpt.isEmpty || reservesSpace {
                    Spacer(minLength: 0)
                }

                footer
                    .padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.background.secondary)
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12).strokeBorder(.tint, lineWidth: 3)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isPending {
                ProgressView()
                    .controlSize(.small)
                    .padding(6)
                    .background(.regularMaterial, in: .circle)
                    .padding(8)
            }
        }
        .contentShape(.rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func excerpt(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: raindrop.type.systemImage)
                .accessibilityLabel(raindrop.type.label)
            Text(raindrop.domain)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if raindrop.broken {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Broken link")
            }
            if raindrop.important {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                    .accessibilityLabel("Favorite")
            }
            Text(raindrop.created, format: .dateTime.day().month(.abbreviated))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

#Preview("Variants") {
    let all = LibraryStore.preview.raindrops(in: .all)
    // One of each kind the sample data has, then the selected and pending states.
    let tagged = all.first { !$0.tags.isEmpty } ?? all[0]
    let noExcerpt = all.first { $0.excerpt.isEmpty } ?? all[1]
    let favorite = all.first { $0.important } ?? all[2]
    Grid(horizontalSpacing: GridMetrics.columnSpacing, verticalSpacing: GridMetrics.rowSpacing) {
        GridRow {
            RaindropCard(raindrop: tagged, isSelected: false)
            RaindropCard(raindrop: noExcerpt, isSelected: false)
            RaindropCard(raindrop: favorite, isSelected: false)
        }
        GridRow {
            RaindropCard(raindrop: all[3], isSelected: true)
            RaindropCard(raindrop: all[4], isSelected: false, isPending: true)
            RaindropCard(raindrop: all[5], isSelected: false)
        }
    }
    .frame(width: 3 * 200 + 2 * GridMetrics.columnSpacing)
    .padding(GridMetrics.inset)
}

#Preview("Narrowest and Widest") {
    let raindrop = LibraryStore.preview.raindrops(in: .all).first { !$0.tags.isEmpty }!
    // Cards stretch from the minimum up to just short of the width where another column fits.
    // With two columns that's (3 × minimum + spacing) / 2.
    let widest = (3 * GridMetrics.minCardWidth + GridMetrics.columnSpacing) / 2
    HStack(alignment: .top, spacing: GridMetrics.columnSpacing) {
        RaindropCard(raindrop: raindrop, isSelected: false)
            .frame(width: GridMetrics.minCardWidth)
        RaindropCard(raindrop: raindrop, isSelected: false)
            .frame(width: widest)
    }
    .padding(GridMetrics.inset)
}
