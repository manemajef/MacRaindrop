import CoreTransferable
import UniformTypeIdentifiers

// What gets dragged. Inside the app, drops read the IDs; anywhere else, a bookmark becomes
// its link. The two types are declared in Config/Info.plist.

nonisolated extension UTType {
    static let raindropBookmark = UTType(exportedAs: "app.macraindrop.bookmark")
    static let raindropCollection = UTType(exportedAs: "app.macraindrop.collection")
}

/// A dragged raindrop.
nonisolated struct RaindropLink: Identifiable, Codable, Transferable {
    let id: Raindrop.ID
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .raindropBookmark)
        ProxyRepresentation(exporting: \.url)
    }
}

/// A dragged collection. It only means something inside the app.
nonisolated struct CollectionDrag: Codable, Transferable {
    let id: RaindropCollection.ID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .raindropCollection)
    }
}
