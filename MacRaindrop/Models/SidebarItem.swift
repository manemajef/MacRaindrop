import Foundation

/// What the sidebar can point at.
///
/// Only an identity, for selection and Back/Forward. What each item shows, and how, is
/// described below rather than worked out by each view that switches on it.
enum SidebarItem: Hashable {
    case all
    case unsorted
    case important
    case trash
    case collection(RaindropCollection.ID)
    case tag(String)
    /// One of the sidebar's Filters, as in Raindrop's web and iOS apps. Raindrop lists Favorites
    /// among them; here it stays at the top, as favorites are in Mac sidebars.
    case filter(Filter)

    /// The Filters section's rows, in Raindrop's order.
    enum Filter: Hashable, CaseIterable {
        case highlights, articles, videos, images, documents, audio, files, broken, duplicates

        var predicate: LibraryQuery.Predicate {
            switch self {
            case .highlights: .hasHighlights
            case .articles: .kind(.article)
            case .videos: .kind(.video)
            case .images: .kind(.image)
            case .documents: .kind(.document)
            case .audio: .kind(.audio)
            case .files: .file
            case .broken: .broken
            case .duplicates: .duplicate
            }
        }

        var title: String {
            switch self {
            case .highlights: "Highlights"
            case .articles: "Articles"
            case .videos: "Video"
            case .images: "Images"
            case .documents: "Documents"
            case .audio: "Audio"
            case .files: "Files"
            case .broken: "Broken Links"
            case .duplicates: "Duplicates"
            }
        }

        var systemImage: String {
            switch self {
            case .highlights: "quote.bubble"
            case .articles: "doc.text"
            case .videos: "play"
            case .images: "photo"
            case .documents: "doc"
            case .audio: "waveform"
            case .files: "arrow.up.doc"
            case .broken: "exclamationmark.square"
            case .duplicates: "square.stack.3d.up"
            }
        }
    }

    /// The raindrops this item shows.
    var query: LibraryQuery {
        switch self {
        case .all: LibraryQuery(scope: .library)
        case .unsorted: LibraryQuery(scope: .collection(SystemCollectionID.unsorted))
        case .important: LibraryQuery(scope: .library, predicate: .favorite)
        case .trash: LibraryQuery(scope: .trash)
        case .collection(let id): LibraryQuery(scope: .collection(id))
        case .tag(let tag): LibraryQuery(scope: .library, predicate: .tag(tag))
        case .filter(let filter): LibraryQuery(scope: .library, predicate: filter.predicate)
        }
    }

    var systemImage: String {
        switch self {
        case .all: "tray.full"
        case .unsorted: "tray"
        case .important: "heart"
        case .trash: "trash"
        case .collection: "folder"
        case .tag: "number"
        case .filter(let filter): filter.systemImage
        }
    }

    /// Whether a raindrop shown here should say which collection it's in. Not when every one
    /// shown is in the same collection, or in the Trash, where the collection is gone.
    var showsCollectionLabel: Bool {
        switch query.scope {
        case .library: true
        case .collection, .trash: false
        }
    }

    /// Where a raindrop lives: the item that shows it without any filter.
    init(home raindrop: Raindrop) {
        self = switch raindrop.collectionID {
        case _ where raindrop.isInTrash: .trash
        case SystemCollectionID.unsorted: .unsorted
        case let id: .collection(id)
        }
    }
}
