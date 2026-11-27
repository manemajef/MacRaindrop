import CoreTransferable
import UniformTypeIdentifiers

/// A dragged collection. It only means something inside the app.
nonisolated struct CollectionDrag: Codable, Transferable {
    let id: RaindropCollection.ID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .raindropCollection)
    }
}
