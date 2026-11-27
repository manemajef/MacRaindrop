import Foundation

/// Which raindrops a place in the library shows: where to look, then what to keep.
///
/// The one place the rules live. The list on screen, the sidebar badges and (later) smart lists
/// all ask `matches(_:in:)`, so a badge can't disagree with the list it counts.
///
/// The Trash and collections are scopes, not predicates: a raindrop is in exactly one of them.
/// Everything else (Favorites, a tag, a kind, a search) is a predicate over the whole library,
/// and can be narrowed to a collection by changing the scope.
nonisolated struct LibraryQuery: Hashable, Codable, Sendable {
    var scope: Scope
    var predicate: Predicate = .any

    enum Scope: Hashable, Codable, Sendable {
        /// Everything except the Trash.
        case library
        case trash
        /// One collection's own raindrops, not its subcollections'. Unsorted is a collection
        /// here too, `SystemCollectionID.unsorted`.
        case collection(RaindropCollection.ID)

        func contains(_ raindrop: Raindrop) -> Bool {
            switch self {
            case .trash: raindrop.isInTrash
            case _ where raindrop.isInTrash: false
            case .library: true
            case .collection(let id): raindrop.collectionID == id
            }
        }
    }

    indirect enum Predicate: Hashable, Codable, Sendable {
        case any
        case favorite
        case tag(String)
        case kind(Raindrop.Kind)
        case hasHighlights
        case broken
        case untagged
        /// Uploaded to Raindrop rather than saved from the web.
        case file
        /// A later copy of a bookmark already saved. See `Context.duplicateIDs`.
        case duplicate
        /// The search field: title, excerpt, note, domain or a tag contains the text.
        case search(String)
        case all([Predicate])
        case anyOf([Predicate])
        case not(Predicate)

        func matches(_ raindrop: Raindrop, in context: Context) -> Bool {
            switch self {
            case .any: true
            case .favorite: raindrop.important
            case .tag(let tag): raindrop.tags.contains(tag)
            case .kind(let kind): raindrop.type == kind
            case .hasHighlights: !raindrop.highlights.isEmpty
            case .broken: raindrop.broken
            case .untagged: raindrop.tags.isEmpty
            case .file: raindrop.file != nil
            case .duplicate: context.duplicateIDs.contains(raindrop.id)
            case .search(let text):
                [raindrop.title, raindrop.excerpt, raindrop.note, raindrop.domain]
                    .contains { $0.localizedStandardContains(text) }
                    || raindrop.tags.contains { $0.localizedStandardContains(text) }
            case .all(let predicates): predicates.allSatisfy { $0.matches(raindrop, in: context) }
            case .anyOf(let predicates): predicates.contains { $0.matches(raindrop, in: context) }
            case .not(let predicate): !predicate.matches(raindrop, in: context)
            }
        }
    }

    /// What some predicates need to know about the rest of the library. Worked out once per
    /// change to the library, not once per raindrop asked about.
    struct Context: Sendable {
        /// Bookmarks outside the Trash whose link was already saved in an earlier bookmark.
        /// As in Raindrop, only the later copies count, not the first one saved.
        var duplicateIDs: Set<Raindrop.ID> = []

        init(raindrops: [Raindrop]) {
            let saved = raindrops.filter { !$0.isInTrash && $0.file == nil }
            for copies in Dictionary(grouping: saved, by: { Self.comparableLink($0.link) }).values where copies.count > 1 {
                let first = copies.min { ($0.created, $0.id) < ($1.created, $1.id) }!
                duplicateIDs.formUnion(copies.lazy.map(\.id).filter { $0 != first.id })
            }
        }

        /// The link as Raindrop compares it for duplicates: without the scheme, `www.`, trailing
        /// slashes, tracking parameters or the fragment.
        static func comparableLink(_ link: String) -> String {
            guard var components = URLComponents(string: link), let host = components.host else { return link }
            components.scheme = nil
            components.fragment = nil
            components.host = host.lowercased().hasPrefix("www.") ? String(host.lowercased().dropFirst(4)) : host.lowercased()
            while components.path.count > 1, components.path.hasSuffix("/") { components.path.removeLast() }
            if components.path == "/" { components.path = "" }
            let kept = components.queryItems?.filter { !isTracking($0.name) }
            components.queryItems = kept?.isEmpty == false ? kept : nil
            return components.string ?? link
        }

        private static func isTracking(_ parameter: String) -> Bool {
            let name = parameter.lowercased()
            return name.hasPrefix("utm_") || trackingParameters.contains(name)
        }

        private static let trackingParameters: Set<String> = [
            "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid",
            "mc_cid", "mc_eid", "igshid", "_ga", "_gl", "ref_src",
        ]
    }

    func matches(_ raindrop: Raindrop, in context: Context) -> Bool {
        scope.contains(raindrop) && predicate.matches(raindrop, in: context)
    }

    /// This query narrowed to raindrops matching the search field's `text`. Blank text changes nothing.
    func searching(_ text: String) -> LibraryQuery {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return self }
        var query = self
        query.predicate = predicate == .any ? .search(text) : .all([predicate, .search(text)])
        return query
    }
}
