import SwiftUI

/// A link icon followed by a field for the raindrop's URL. The screen sets the text field
/// style and any background.
struct LinkField: View {
    @Binding var link: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
            TextField("Link", text: $link)
        }
    }
}

#Preview {
    @Previewable @State var link = "https://raindrop.io"
    LinkField(link: $link)
        .textFieldStyle(.plain)
        .padding()
        .frame(width: 320)
}
