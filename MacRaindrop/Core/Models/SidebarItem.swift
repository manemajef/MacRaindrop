import Foundation

/// What the sidebar can point at.
enum SidebarItem: Hashable {
    case all
    case unsorted
    case important
    case trash
    case collection(RaindropCollection.ID)
    case tag(String)
}
