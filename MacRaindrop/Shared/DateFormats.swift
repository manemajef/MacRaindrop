import Foundation

// The app's date formats, so every screen shows the same kind of date the same way.
// Use them with `Text(date, format: .timestamp)` or `date.formatted(.timestamp)`.

extension FormatStyle where Self == Date.FormatStyle {
    /// A full date and time, like "Nov 15, 2026 at 3:42 PM". For details such as created or updated.
    static var timestamp: Self { .init(date: .abbreviated, time: .shortened) }

    /// Day and month only, like "15 Nov". For compact places such as grid cards.
    static var shortDay: Self { .dateTime.day().month(.abbreviated) }
}

extension FormatStyle where Self == Date.RelativeFormatStyle {
    /// How long ago, in words, like "yesterday" or "3 hours ago".
    static var relativeNamed: Self { .relative(presentation: .named) }
}
