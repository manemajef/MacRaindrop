import SwiftUI

extension View {
    /// What a library window does besides showing the library: hands the menu bar its selection
    /// and history, presents the actions' prompts, keeps the library synced, and answers
    /// requests from elsewhere in the app (Quick Search's reveal, a bookmark's Edit).
    func libraryWindowBehaviors(navigation: NavigationModel, prompts: ActionPrompts, showInspector: Binding<Bool>) -> some View {
        modifier(LibraryWindowBehaviors(navigation: navigation, prompts: prompts, showInspector: showInspector))
    }
}

/// Its own modifier, so the window's layout doesn't redraw when the window becomes active or
/// inactive, or when a request comes in.
private struct LibraryWindowBehaviors: ViewModifier {
    @Environment(LibraryStore.self) private var store
    @Environment(AppSession.self) private var session
    @Environment(\.appearsActive) private var appearsActive
    let navigation: NavigationModel
    let prompts: ActionPrompts
    @Binding var showInspector: Bool

    private var selectedRaindrops: [Raindrop] {
        navigation.selection.compactMap(store.raindrop(id:))
    }

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.bookmarkContext, BookmarkContext(raindrops: selectedRaindrops, prompts: prompts))
            .focusedSceneValue(\.navigation, navigation)
            .presentsPrompts(prompts)
            .syncsAutomatically()
            .environment(prompts)
            // Quick Search needs the session, which the app's scene owns, so the first window
            // hands it over. Later windows find it set up already.
            .task { QuickSearchController.install(session: session) }
            .onChange(of: session.revealRequest) { takeRevealRequest() }
            .onChange(of: appearsActive) { takeRevealRequest() }
            // A location deep in the collection tree opens its parents, so its row is visible.
            .onChange(of: navigation.location, initial: true) {
                navigation.revealLocation(in: store)
            }
            // Editing happens in the inspector, so Edit selects the bookmark and shows it.
            .onChange(of: prompts.editRequest) { _, id in
                guard let id else { return }
                navigation.selection = [id]
                showInspector = true
            }
    }

    /// Shows the bookmark Quick Search asked for, if this is the window in front.
    private func takeRevealRequest() {
        guard appearsActive, let id = session.revealRequest else { return }
        session.revealRequest = nil
        guard let raindrop = store.raindrop(id: id) else { return }
        navigation.reveal(raindrop)
    }
}
