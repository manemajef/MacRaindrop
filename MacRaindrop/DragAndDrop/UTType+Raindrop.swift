import UniformTypeIdentifiers

// What gets dragged. Inside the app, drops read the IDs; anywhere else, a bookmark becomes
// its link. The two types are declared in Config/Info.plist.

nonisolated extension UTType {
    static let raindropBookmark = UTType(exportedAs: "app.macraindrop.bookmark")
    static let raindropCollection = UTType(exportedAs: "app.macraindrop.collection")
}
