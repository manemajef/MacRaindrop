import SwiftUI

/// A card in the style of Raindrop's iOS grid: cover, title, excerpt, tags, then source and date.
struct RaindropCard: View {
    let raindrop: Raindrop
    let isSelected: Bool
    /// A write to this raindrop is waiting for the server.
    var isPending = false

    // MARK: Height
    //
    // There's no height setting as such: every card is the same height, and the grid measures
    // one card at launch (`GridCollectionView`) and uses that for all of them. These decide it.

    /// About 16:10 at a typical card width. Fixed rather than a ratio of the width: then a
    /// card's height never changes as the grid resizes, and neither do the rows above the
    /// viewport. With a ratio, every row above grew or shrank on each frame of a sidebar
    /// animation, pushing the visible cards further the further down the grid was scrolled.
    static let coverHeight: CGFloat = 125
    /// Lines kept for the title and the excerpt, even when they're shorter or empty.
    static let titleLines = 2
    static let excerptLines = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: Self.coverHeight)
                .overlay { CoverImage(url: raindrop.coverURL, kind: raindrop.type) }
                // Only trims the filled image to its frame; the card's shape rounds the top corners.
                .clipped()

            VStack(alignment: .leading, spacing: 5) {
                // Every line is reserved even when empty, so all cards are the same height.
                // The grid then needs no measuring pass to line rows up, and a card keeps
                // its identity (and its loaded cover) when the column count changes.
                Text(raindrop.title)
                    .font(.headline)
                    .lineLimit(Self.titleLines, reservesSpace: true)

                // An empty string reserves nothing, so a space stands in for a missing excerpt.
                Text(raindrop.excerpt.isEmpty ? " " : raindrop.excerpt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(Self.excerptLines, reservesSpace: true)

                // A tag's height, with or without tags.
                Text(verbatim: "#")
                    .font(.caption)
                    .padding(.vertical, 2)
                    .hidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) {
                        TagList(tags: raindrop.tags)
                            .fixedSize()
                    }
                    .clipped()

                footer
                    .padding(.top, 2)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .top)
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
