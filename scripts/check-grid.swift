import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

@Observable
private final class GridState {
    var raindrops: [Raindrop]
    var selection: Set<Raindrop.ID> = []
    var folders: [RaindropCollection]
    var showsInspector = false
    init(raindrops: [Raindrop], folders: [RaindropCollection]) {
        self.raindrops = raindrops
        self.folders = folders
    }
}

private struct GridCheckView: View {
    @Bindable var state: GridState
    let store: LibraryStore
    let opened: (URL) -> Void
    var body: some View {
        HStack(spacing: 0) {
            RaindropCollectionView(raindrops: state.raindrops, folders: state.folders,
                selection: $state.selection, store: store, prompts: ActionPrompts(),
                openFolder: { _ in }, open: opened)
            if state.showsInspector {
                Color.secondary.opacity(0.1).frame(width: 300)
            }
        }
    }
}

@main
private struct GridCheck {
    static func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    }

    static func collection(in view: NSView) -> NSCollectionView? {
        if let collection = view as? NSCollectionView { return collection }
        return view.subviews.lazy.compactMap { collection(in: $0) }.first
    }

    static func main() throws {
        _ = NSApplication.shared
        let sampleURL = Bundle.main.url(forResource: "raindrops", withExtension: "json")!
        let sample = try JSONSerialization.jsonObject(with: Data(contentsOf: sampleURL)) as! [String: Any]
        let originals = sample["items"] as! [[String: Any]]
        let fixture = (0..<1_000).map { index in
            var item = originals[index % originals.count]
            item["_id"] = index + 1
            item["cover"] = "" // Isolate layout from network timing.
            item["removed"] = false
            item["collectionId"] = SystemCollectionID.unsorted
            return item
        }
        let raindrops = try JSONDecoder.raindrop.decode([Raindrop].self,
            from: JSONSerialization.data(withJSONObject: fixture))
        let store = LibraryStore.preview
        try store.apply(raindrops)
        let state = GridState(raindrops: raindrops, folders: Array(store.collections.prefix(4)))
        var opened: [URL] = []
        let host = NSHostingView(rootView: GridCheckView(state: state, store: store, opened: { opened.append($0) }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 700),
            styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        window.title = "MacRaindrop Grid Check"
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        settle()
        let grid = collection(in: host)!
        assert(grid.numberOfItems(inSection: 1) == 1_000)
        assert(grid.numberOfItems(inSection: 0) == state.folders.count)
        assert(grid.visibleItems().count < 100, "Collection should instantiate a small visible subset")
        let first = grid.layoutAttributesForItem(at: IndexPath(item: 0, section: 1))!.frame
        assert(first.width >= 180 && first.height > 200, "Hosted cards must have a usable measured size")
        let row = (0..<10).compactMap { grid.layoutAttributesForItem(at: IndexPath(item: $0, section: 1))?.frame }
            .filter { $0.minY == first.minY }
        assert(abs(row.last!.maxX - (grid.bounds.width - 16)) < CGFloat(row.count + 1), "Cards should fill each row")
        let firstItem = grid.item(at: IndexPath(item: 0, section: 1))!
        let hitPoint = grid.convert(NSPoint(x: first.midX, y: first.midY), to: grid.superview)
        let hit = grid.hitTest(hitPoint)
        assert(hit === firstItem.view || hit?.isDescendant(of: firstItem.view) == true,
               "A card click must hit its native item view, rather than fall through to the collection background")

        let selected = IndexPath(item: 501, section: 1)
        grid.scrollToItems(at: [selected], scrollPosition: .centeredVertically)
        settle()
        grid.selectionIndexPaths = [selected]
        grid.delegate?.collectionView?(grid, didSelectItemsAt: [selected])
        settle()
        assert(state.selection == [raindrops[selected.item].id], "Native selection must reach SwiftUI")
        let before = grid.layoutAttributesForItem(at: selected)!.frame.minY - grid.visibleRect.minY
        for width: CGFloat in [730, 1_100, 620, 1_000] {
            window.setContentSize(NSSize(width: width, height: 700))
            settle()
            let frame = grid.layoutAttributesForItem(at: selected)!.frame
            let after = frame.minY - grid.visibleRect.minY
            assert(abs(after - before) < 2, "Selected card moved during reflow: \(before) -> \(after), width \(width)")
            assert(grid.visibleItems().count < 100)
        }
        for shown in [true, false] {
            state.showsInspector = shown
            settle()
            let after = grid.layoutAttributesForItem(at: selected)!.frame.minY - grid.visibleRect.minY
            assert(abs(after - before) < 2, "Inspector changed the selected card's vertical position")
        }

        // Drive the native key handler, rather than recreating selection rules in SwiftUI.
        let arrow = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{F703}", charactersIgnoringModifiers: "\u{F703}",
            isARepeat: false, keyCode: 124)!
        grid.keyDown(with: arrow)
        settle()
        assert(state.selection == [raindrops[selected.item + 1].id], "Right arrow must advance native selection")
        for (keyCode, character, expected) in [
            (UInt16(124), "\u{F703}", Set([raindrops[502].id, raindrops[503].id])),
            (UInt16(123), "\u{F702}", Set([raindrops[502].id]))
        ] {
            let shifted = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: character, charactersIgnoringModifiers: character,
                isARepeat: false, keyCode: keyCode)!
            grid.keyDown(with: shifted)
            settle()
            assert(state.selection == expected, "Shift-arrow should extend and shrink the native selection")
        }

        state.selection = [raindrops[650].id]
        settle()
        assert(grid.selectionIndexPaths == [IndexPath(item: 650, section: 1)], "SwiftUI selection must reach AppKit")
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36)!
        grid.keyDown(with: event)
        assert(opened == [raindrops[650].url!], "Return must activate the selection")
        let writer = grid.delegate?.collectionView?(grid, pasteboardWriterForItemAt: IndexPath(item: 650, section: 1)) as! NSPasteboardItem
        let payload = writer.data(forType: NSPasteboard.PasteboardType(UTType.raindropBookmark.identifier))!
        let dragged = try JSONDecoder().decode(RaindropLink.self, from: payload)
        assert(dragged.id == raindrops[650].id)
        assert(writer.string(forType: .URL) == raindrops[650].url!.absoluteString)

        state.raindrops.reverse()
        settle()
        assert(grid.selectionIndexPaths == [IndexPath(item: 349, section: 1)], "Reordering must preserve bookmark identity")
        grid.selectAll(nil)
        settle()
        assert(state.selection.count == 1_000, "Select All must select bookmarks")
        assert(grid.selectionIndexPaths.allSatisfy { $0.section == 1 })
        if !state.folders.isEmpty {
            let folder = IndexPath(item: 0, section: 0)
            grid.selectionIndexPaths = [folder]
            grid.delegate?.collectionView?(grid, didSelectItemsAt: [folder])
            settle()
            assert(state.selection.isEmpty, "Folder and bookmark selections must stay separate")
            assert(grid.selectionIndexPaths == [folder])
        }
        let screenshot = ProcessInfo.processInfo.environment["GRID_CHECK_IMAGE"]
        if let screenshot, let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(filePath: screenshot))
        }
        window.orderOut(nil)
        print("PASS: 1,000 items; bounded visible views; filled rows; selection binding; resize and inspector anchoring; arrow keys; Return; drag payload; reorder; Select All; folder selection")
    }
}
