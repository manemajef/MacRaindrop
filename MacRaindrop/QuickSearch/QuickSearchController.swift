import AppKit
import SwiftUI

/// Owns the Quick Search panel: shows it on the hotkey, places it, routes its keys, and hides it.
///
/// The panel is a fixed size, as tall as the longest list, and never resizes. The glass inside
/// is top-aligned and SwiftUI animates its height, so results come and go smoothly instead of
/// the window jumping. The transparent area around it holds the glass's shadow.
final class QuickSearchController {
    private static var shared: QuickSearchController?

    /// Sets up the hotkey once, and builds the panel and search index ahead of the first press.
    static func install(session: AppSession) {
        guard shared == nil else { return }
        let controller = QuickSearchController(session: session)
        shared = controller
        QuickSearchHotKey.onPress { controller.toggle() }
        _ = controller.panel
        if let store = session.store {
            Task { _ = await store.searchIndex() }
        }
    }

    /// Room around the glass for its shadow.
    static let shadowInset: CGFloat = 40

    private let model: QuickSearchModel
    private lazy var panel = makePanel()
    private var keyMonitor: Any?
    private var hiddenAt: Date?
    /// The app that had the keyboard before the panel took it, to hand it back on Escape.
    private var previousApp: NSRunningApplication?

    private init(session: AppSession) {
        model = QuickSearchModel(session: session)
        model.dismiss = { [weak self] restoresFocus in self?.hide(restoringFocus: restoresFocus) }
    }

    func toggle() {
        if panel.isVisible, panel.isKeyWindow { hide(restoringFocus: true) } else { show() }
    }

    func show() {
        guard !panel.isVisible else {
            panel.makeKey()
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost == .current ? nil : frontmost
        // A query from a minute ago is stale; one from a few seconds ago is probably a retry.
        if let hiddenAt, Date.now.timeIntervalSince(hiddenAt) > 60 { model.query = "" }
        // Results are ready before the panel is on screen, so it opens already at its size.
        model.willPresent()
        panel.contentView?.layoutSubtreeIfNeeded()
        place()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        startRoutingKeys()
    }

    /// `restoringFocus` gives the keyboard back to the app that had it. Not after a click
    /// elsewhere (the click already chose where it goes) or an action that activates an app.
    func hide(restoringFocus: Bool) {
        guard panel.isVisible else { return }
        stopRoutingKeys()
        panel.orderOut(nil)
        hiddenAt = .now
        if restoringFocus, let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        }
        previousApp = nil
    }

    // MARK: Window

    private func makePanel() -> QuickSearchPanel {
        let panel = QuickSearchPanel()
        let hostingView = NSHostingView(rootView: QuickSearchView(model: model))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.setContentSize(NSSize(
            width: QuickSearchView.width + Self.shadowInset * 2,
            height: QuickSearchView.maxHeight + Self.shadowInset * 2
        ))
        panel.onResignKey = { [weak self] in self?.hide(restoringFocus: false) }
        return panel
    }

    /// Centred on the screen under the pointer, the glass's top a fifth of the way down, like Spotlight.
    private func place() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let top = visible.maxY - visible.height * 0.2 + Self.shadowInset
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: top - size.height))
    }

    // MARK: Keys

    /// Arrows, Return and Escape go to the results, not the search field, while the panel is key.
    private func startRoutingKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func stopRoutingKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        // Mid-composition (a Japanese or Chinese input method), these keys belong to the input method.
        if (panel.firstResponder as? NSTextView)?.hasMarkedText() == true { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch (event.keyCode, modifiers.contains(.control)) {
        case (53, _): model.cancel()                          // Escape
        case (125, _), (45, true): model.moveSelection(by: 1) // ↓, ⌃N
        case (126, _), (35, true): model.moveSelection(by: -1) // ↑, ⌃P
        case (36, _), (76, _):                                // Return, Enter
            if modifiers.contains(.command) { model.revealSelected() } else { model.openSelected() }
        default: return false
        }
        return true
    }
}
