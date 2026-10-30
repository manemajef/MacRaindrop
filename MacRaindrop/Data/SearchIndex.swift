import Foundation

/// A ranked search over every bookmark's text, for Quick Search.
///
/// Each bookmark's fields are folded once (lowercased, accents removed) and kept as UTF-8 bytes,
/// so a keystroke is a plain byte scan: a few milliseconds for thousands of bookmarks. Every
/// query word must match some field. A word scores by where it matched (the start of a field
/// beats the start of a word, which beats the middle of a word, which beats a fuzzy match) times
/// the field's weight, so a title match always outranks one buried in an excerpt.
///
/// Searching is two steps, finding candidates and then scoring them. Today every bookmark is a
/// candidate; a much larger library could swap in a word index for the first step alone.
nonisolated struct SearchIndex: Sendable {
    enum Field: Int, CaseIterable, Sendable {
        case title, tags, domain, url, collection, note, excerpt, highlights

        var weight: Double {
            switch self {
            case .title: 1.0
            case .tags: 0.9
            case .domain: 0.75
            case .url: 0.6
            case .collection: 0.6
            case .note: 0.5
            case .excerpt: 0.4
            case .highlights: 0.3
            }
        }

        /// Long prose matches almost any fragment, so there only the start of a word counts.
        var matchesInsideWords: Bool {
            switch self {
            case .note, .excerpt, .highlights: false
            default: true
            }
        }

        /// Fuzzy matching ("rct" → react) only where the text is short and typed from memory.
        var matchesFuzzily: Bool { self == .title || self == .domain }
    }

    struct Match: Sendable, Equatable {
        let id: Raindrop.ID
        let score: Double
    }

    private struct Entry: Sendable {
        let id: Raindrop.ID
        /// Indexed by `Field.rawValue`. Tags are joined with spaces, so each tag starts a word.
        let fields: [[UInt8]]
        /// Each tag on its own, for exact tag matches and `#tag` queries.
        let tags: [[UInt8]]
        let created: Date
        let inTrash: Bool
    }

    private let entries: [Entry]

    var count: Int { entries.count }

    /// `collectionPaths` names each collection as it reads in the sidebar, like "Work › Design".
    init(raindrops: [Raindrop], collectionPaths: [RaindropCollection.ID: String]) {
        entries = raindrops.map { raindrop in
            let tags = raindrop.tags.map(Self.fold)
            var fields = [[UInt8]](repeating: [], count: Field.allCases.count)
            fields[Field.title.rawValue] = Self.fold(raindrop.title)
            fields[Field.tags.rawValue] = Array(tags.joined(separator: [UInt8(ascii: " ")]))
            fields[Field.domain.rawValue] = Self.fold(raindrop.domain)
            fields[Field.url.rawValue] = Self.fold(Self.trimmingScheme(raindrop.link))
            fields[Field.collection.rawValue] = Self.fold(collectionPaths[raindrop.collectionID] ?? "")
            fields[Field.note.rawValue] = Self.fold(raindrop.note)
            fields[Field.excerpt.rawValue] = Self.fold(raindrop.excerpt)
            fields[Field.highlights.rawValue] = Self.fold(raindrop.highlights.map { "\($0.text) \($0.note)" }.joined(separator: " "))
            return Entry(id: raindrop.id, fields: fields, tags: tags, created: raindrop.created, inTrash: raindrop.isInTrash)
        }
    }

    /// The best matches, best first. An empty query gives the newest bookmarks outside the trash.
    func search(_ query: String, limit: Int = 50) -> [Match] {
        let terms = Self.terms(in: query)
        guard !terms.isEmpty else {
            return entries
                .filter { !$0.inTrash }
                .sorted { $0.created > $1.created }
                .prefix(limit)
                .map { Match(id: $0.id, score: 0) }
        }

        var scored: [(match: Match, created: Date)] = []
        for entry in entries {
            guard var score = Self.score(entry, terms) else { continue }
            if entry.inTrash { score *= 0.5 }
            scored.append((Match(id: entry.id, score: score), entry.created))
        }
        scored.sort { $0.match.score != $1.match.score ? $0.match.score > $1.match.score : $0.created > $1.created }
        return scored.prefix(limit).map(\.match)
    }

    // MARK: Scoring

    private struct Term {
        let bytes: [UInt8]
        /// Written as `#tag`: matches tags only.
        let tagOnly: Bool
    }

    private static func terms(in query: String) -> [Term] {
        query.split(whereSeparator: \.isWhitespace).compactMap { word in
            let tagOnly = word.hasPrefix("#")
            let bytes = fold(String(tagOnly ? word.dropFirst() : word))
            return bytes.isEmpty ? nil : Term(bytes: bytes, tagOnly: tagOnly)
        }
    }

    /// The sum of each term's best field score, or nil when any term matches nothing.
    private static func score(_ entry: Entry, _ terms: [Term]) -> Double? {
        var total = 0.0
        for term in terms {
            var best = 0.0
            if term.tagOnly {
                best = entry.tags.lazy.map { tagQuality(term.bytes, $0) }.max() ?? 0
            } else {
                for field in Field.allCases {
                    // No field can beat the title's best, so skip the rest once it's matched in full.
                    guard best < field.weight * 1.2 else { break }
                    let quality = field == .tags
                        ? entry.tags.lazy.map { tagQuality(term.bytes, $0) }.max() ?? 0
                        : quality(of: term.bytes, in: entry.fields[field.rawValue], field: field)
                    best = max(best, field.weight * quality)
                }
            }
            guard best > 0 else { return nil }
            total += best
        }
        return total
    }

    /// How well `term` matches `text`, from 0 (not at all) to 1.2 (the whole field).
    static func quality(of term: [UInt8], in text: [UInt8], field: Field) -> Double {
        guard !text.isEmpty, term.count <= text.count else { return 0 }
        if text == term { return 1.2 }

        var insideWord = false
        var start = 0
        while let found = firstIndex(of: term, in: text, from: start) {
            if found == 0 { return 1.0 }
            if isWordStart(text, found) { return 0.8 }
            insideWord = true
            start = found + 1
        }
        if insideWord, field.matchesInsideWords { return 0.4 }
        if field.matchesFuzzily, term.count >= 2 { return fuzzyQuality(of: term, in: text) }
        return 0
    }

    private static func tagQuality(_ term: [UInt8], _ tag: [UInt8]) -> Double {
        if tag == term { return 1.2 }
        if tag.starts(with: term) { return 1.0 }
        return 0
    }

    /// The term's letters in order, starting at a word, scored by how tightly they cluster.
    /// "gh" in "github" scores higher than "gb" in "github", and both well below a real prefix.
    private static func fuzzyQuality(of term: [UInt8], in text: [UInt8]) -> Double {
        var best = 0.0
        for start in text.indices where text[start] == term[0] && isWordStart(text, start) {
            var position = start + 1
            var matched = 1
            while matched < term.count, position < text.count {
                if text[position] == term[matched] { matched += 1 }
                position += 1
            }
            guard matched == term.count else { break }
            // Letters scattered across a long title are a coincidence, not a match.
            let span = position - start
            guard span <= term.count * 2 + 1 else { continue }
            best = max(best, 0.3 * Double(term.count) / Double(span))
        }
        return best
    }

    private static func firstIndex(of term: [UInt8], in text: [UInt8], from start: Int) -> Int? {
        let first = term[0]
        var index = start
        let last = text.count - term.count
        while index <= last {
            if text[index] == first {
                var offset = 1
                while offset < term.count, text[index + offset] == term[offset] { offset += 1 }
                if offset == term.count { return index }
            }
            index += 1
        }
        return nil
    }

    /// Whether a word starts at `index`: the byte before it isn't a letter or a digit. Bytes of
    /// non-ASCII characters count as letters, so "café" is one word.
    private static func isWordStart(_ text: [UInt8], _ index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = text[index - 1]
        return !(previous >= 0x80 || (previous >= 0x30 && previous <= 0x39) || (previous >= 0x61 && previous <= 0x7A))
    }

    // MARK: Folding

    /// Lowercased, without accents, as UTF-8.
    static func fold(_ text: String) -> [UInt8] {
        Array(text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).utf8)
    }

    private static func trimmingScheme(_ link: String) -> String {
        var link = Substring(link)
        for prefix in ["https://", "http://"] where link.hasPrefix(prefix) {
            link = link.dropFirst(prefix.count)
        }
        if link.hasPrefix("www.") { link = link.dropFirst(4) }
        return String(link)
    }
}
