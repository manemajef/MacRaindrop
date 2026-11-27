import SwiftUI

/// The collection a bookmark is in, as a `Label` with the sidebar's icon for it: a folder,
/// or a tray for Unsorted. Shown on cards and rows where bookmarks from several collections mix.
struct CollectionLabel: View {
    let title: String
    let raindrop: Raindrop

    var body: some View {
        Label(title, systemImage: SidebarItem(home: raindrop).systemImage)
            .lineLimit(1)
            .truncationMode(.tail)
            .help("In \(title)")
    }
}
