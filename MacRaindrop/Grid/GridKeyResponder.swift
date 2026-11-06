import AppKit
import SwiftUI

/// What the grid's keys do.
struct GridKeyActions {
    var move: (MoveCommandDirection, _ extending: Bool) -> Void
    var open: () -> Void
    var delete: () -> Void
    var clear: () -> Void
    var selectAll: () -> Void
    var copy: () -> [URL]
}

/// Holds the grid's key view, so a click in the grid can make it first responder.
final class GridKeys {
    weak var view: GridKeyView?

    /// Deferred: SwiftUI settles the first responder for a click after its tap handler runs.
    func focus() {
        DispatchQueue.main.async { [weak self] in
            guard let view = self?.view, let window = view.window, window.firstResponder !== view else { return }
            window.makeFirstResponder(view)
        }
    }
}

struct GridKeyResponder: NSViewRepresentable {
    let keys: GridKeys
    let actions: GridKeyActions

    func makeNSView(context: Context) -> GridKeyView {
        let view = GridKeyView()
        keys.view = view
        return view
    }

    func updateNSView(_ view: GridKeyView, context: Context) {
        view.actions = actions
        keys.view = view
    }
}

/// Takes keyboard focus for the grid and handles its keys. It never takes the mouse; the SwiftUI views above it do.
final class GridKeyView: NSView {
    var actions: GridKeyActions?

    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// A new grid appears for every location. Taking focus each time would pull it from the
    /// sidebar on every click there, so only when nothing has it.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window, window.firstResponder == nil || window.firstResponder === window {
            window.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard let actions else { return super.keyDown(with: event) }
        let extending = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 123: actions.move(.left, extending)
        case 124: actions.move(.right, extending)
        case 125: actions.move(.down, extending)
        case 126: actions.move(.up, extending)
        case 36, 76: actions.open()
        case 51, 117: actions.delete()
        case 53: actions.clear()
        default: super.keyDown(with: event)
        }
    }

    override func selectAll(_ sender: Any?) { actions?.selectAll() }

    @objc func copy(_ sender: Any?) {
        guard let urls = actions?.copy(), !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
    }
}
