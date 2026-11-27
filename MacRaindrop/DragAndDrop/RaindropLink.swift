import CoreTransferable
import UniformTypeIdentifiers

/// A dragged raindrop. Inside the app, drops read its ID; anywhere else, it becomes its link.
nonisolated struct RaindropLink: Identifiable, Codable, Transferable {
    let id: Raindrop.ID
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .raindropBookmark)
        ProxyRepresentation(exporting: \.url)
    }
}
