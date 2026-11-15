import Foundation

/// How a collection's bookmarks are ordered.
enum RaindropSort: String, CaseIterable, Identifiable {
    case newest, oldest, title, domain

    var id: Self { self }

    var label: String {
        switch self {
        case .newest: "Newest First"
        case .oldest: "Oldest First"
        case .title: "Title"
        case .domain: "Domain"
        }
    }

    func areInIncreasingOrder(_ a: Raindrop, _ b: Raindrop) -> Bool {
        switch self {
        case .newest: a.created > b.created
        case .oldest: a.created < b.created
        case .title: a.title.localizedStandardCompare(b.title) == .orderedAscending
        case .domain: a.domain.localizedStandardCompare(b.domain) == .orderedAscending
        }
    }
}
