import SwiftUI

/// A raindrop's tags as small capsules, in one line.
struct TagList: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                Text("\(tag)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: .capsule)
//                    .glassEffect()
//                    .foregroundStyle(.tint)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("Tag List") {
    VStack(alignment: .leading, spacing: 12) {
//        TagList(tags: ["swift"])
        TagList(tags: ["design", "swiftui", "to-read", "macos"])
    }
    .padding()
}
