import SwiftUI

/// A menu for choosing a raindrop's collection: Unsorted, then the collection tree.
///
/// It draws only its label. The screen sets the menu and button styles and any
/// background, so the same picker fits a sheet's rounded box or an inspector row.
struct CollectionPicker<Label: View>: View {
    @Binding var selection: RaindropCollection.ID
    @ViewBuilder var label: (RaindropCollection.ID) -> Label

    var body: some View {
        Menu {
            CollectionMenuItems(isDisabled: { $0 == selection }, choose: { selection = $0 })
        } label: {
            label(selection)
        }
    }
}

extension CollectionPicker where Label == CollectionPickerLabel {
    /// The standard label: the collection's icon and name, with up-down chevrons at the end.
    init(selection: Binding<RaindropCollection.ID>) {
        self.init(selection: selection) { CollectionPickerLabel(collectionID: $0) }
    }
}

/// The collection's icon and name across the full width, with up-down chevrons at the end.
struct CollectionPickerLabel: View {
    @Environment(LibraryStore.self) private var store
    let collectionID: RaindropCollection.ID

    var body: some View {
        HStack {
            Label(
                store.collectionTitle(for: collectionID),
                systemImage: collectionID == SystemCollectionID.unsorted ? "tray" : "folder"
            )
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
    }
}

#Preview {
    @Previewable @State var selection = SystemCollectionID.unsorted
    CollectionPicker(selection: $selection)
        .menuStyle(.button)
        .buttonStyle(.plain)
        .padding()
        .frame(width: 320)
        .previewEnvironment(LibraryStore.preview)
}
