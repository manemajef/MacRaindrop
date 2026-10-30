import AppKit

/// A borderless floating panel, like Spotlight's. It takes the keyboard without activating the
/// app, so the main window stays where it is and the app you were in keeps its place.
final class QuickSearchPanel: NSPanel {
    /// Called when the panel loses the keyboard, from a click elsewhere or another app.
    var onResignKey: () -> Void = {}

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        // On every Space and over full-screen apps, and never in ⌘` or the Window menu.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        // The window is larger than the glass, so its own shadow would outline the empty
        // rectangle around it. The glass draws its own shadow instead.
        hasShadow = false
        animationBehavior = .none
    }

    // Borderless windows can't become key unless they say so; the search field needs it.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey()
    }
}
