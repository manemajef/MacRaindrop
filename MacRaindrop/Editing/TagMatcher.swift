import Foundation

/// Finds the known tags that match what's being typed, best first.
///
/// A tag matches when it starts with the text, has a word starting with it ("read" finds
/// "to-read"), contains it, or has its letters in order ("sui" finds "swiftui"). Ties keep the
/// order of `known`, which is most used first. Case and accents don't matter.
nonisolated struct TagMatcher: Sendable {
    /// Every known tag, most used first.
    let known: [String]

    func matches(for query: String, excluding taken: some Collection<String> = [String](), limit: Int = 8) -> [String] {
        let query = Self.folded(query.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")))
        guard !query.isEmpty else { return [] }
        let taken = Set(taken)
        return known.enumerated()
            .filter { !taken.contains($0.element) }
            .compactMap { index, tag in Self.rank(of: query, in: Self.folded(tag)).map { (rank: $0, index: index, tag: tag) } }
            .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
            .prefix(limit)
            .map(\.tag)
    }

    /// Lower is better; nil when `tag` doesn't match at all.
    static func rank(of query: String, in tag: String) -> Int? {
        if tag == query { return 0 }
        if tag.hasPrefix(query) { return 1 }
        let words = tag.split(whereSeparator: { " -_/.".contains($0) })
        if words.contains(where: { $0.hasPrefix(query) }) { return 2 }
        if tag.contains(query) { return 3 }
        if isSubsequence(query, of: tag) { return 4 }
        return nil
    }

    private static func isSubsequence(_ query: String, of tag: String) -> Bool {
        var remaining = query[...]
        for character in tag where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
