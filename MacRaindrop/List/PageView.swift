import SwiftUI
import WebKit

/// Shows the bookmarked page itself. Its details live in the window's inspector.
struct PageView: View {
    let raindrop: Raindrop

    var body: some View {
        if let url = raindrop.url {
            RaindropWebView(url: url)
        } else {
            ContentUnavailableView("No Web Address", systemImage: "link.badge.plus", description: Text("This bookmark has no page to show."))
        }
    }
}

private struct RaindropWebView: View {
    let url: URL
    @State private var page = WebPage()

    var body: some View {
        WebView(page)
            .overlay(alignment: .top) {
                if page.isLoading {
                    ProgressView(value: page.estimatedProgress)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }
            }
            .onChange(of: url, initial: true) {
                page.load(URLRequest(url: url))
            }
    }
}

#Preview("No Web Address") {
    var raindrop = LibraryStore.preview.raindrops[0]
    raindrop.link = ""
    return PageView(raindrop: raindrop)
        .frame(width: 600, height: 400)
}
