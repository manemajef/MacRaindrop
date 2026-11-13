import AppKit
import QuickLookUI
import SwiftUI

/// What the grid's keys do.
struct GridKeyActions {
    var move: (MoveCommandDirection, _ extending: Bool) -> Void
    var open: () -> Void
    var preview: () -> QuickLookItems
    var delete: () -> Void
    var clear: () -> Void
    var selectAll: () -> Void
    var copy: () -> [URL]
}

/// The pages Quick Look shows, and which of them it starts on.
struct QuickLookItems {
    var urls: [URL] = []
    var current = 0
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
        case 49 where !event.isARepeat: togglePreview()
        case 49: break
        case 51, 117: actions.delete()
        // Escape closes Quick Look first, as in Finder.
        case 53: if isPreviewing { closePreview() } else { actions.clear() }
        default: super.keyDown(with: event)
        }
    }

    override func selectAll(_ sender: Any?) { actions?.selectAll() }

    // MARK: Quick Look

    /// The system Quick Look panel, previewing the selected bookmarks' web pages. Quick Look
    /// renders the pages itself and adds the "Open with" button for the default browser.
    /// It finds this view through the responder chain, since the grid has the keyboard.
    private var items: [URL] = []

    private var isPreviewing: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
            && QLPreviewPanel.shared().dataSource === self
    }

    private func togglePreview() {
        if isPreviewing { return closePreview() }
        guard let preview = actions?.preview(), !preview.urls.isEmpty else { return }
        items = preview.urls
        let panel = QLPreviewPanel.shared()!
        // Without taking the keyboard: Quick Look's web view would keep the arrow keys, and
        // they should move through the grid, with the preview following.
        panel.orderFront(nil)
        panel.currentPreviewItemIndex = preview.current
    }

    func closePreview() {
        guard isPreviewing else { return }
        QLPreviewPanel.shared().orderOut(nil)
    }

    /// Shows the new selection in an open panel, or closes it when nothing with a page is selected.
    func reloadPreview() {
        guard isPreviewing, let preview = actions?.preview() else { return }
        guard !preview.urls.isEmpty else { return closePreview() }
        let panel = QLPreviewPanel.shared()!
        if preview.urls != items {
            items = preview.urls
            panel.reloadData()
        }
        if panel.currentPreviewItemIndex != preview.current {
            panel.currentPreviewItemIndex = preview.current
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    @objc func copy(_ sender: Any?) {
        guard let urls = actions?.copy(), !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
    }
}

extension GridKeyView: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { items.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        items[index] as NSURL
    }

    /// Keys pressed while the panel has the keyboard go to the grid, so the arrows move the
    /// selection and Space and Escape close the panel.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        keyDown(with: event)
        return true
    }
}
