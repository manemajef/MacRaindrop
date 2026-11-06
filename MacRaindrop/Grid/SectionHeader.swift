import SwiftUI

/// A section's heading, in the style of Finder's groups: its name, then how many it holds.
struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(count, format: .number)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, GridMetrics.inset)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Section Header") {
    VStack(spacing: 0) {
        SectionHeader(title: "Collections", count: 3)
            .frame(height: 44)
        SectionHeader(title: "Bookmarks", count: 1_204)
            .frame(height: 44)
    }
    .frame(width: 600)
}
