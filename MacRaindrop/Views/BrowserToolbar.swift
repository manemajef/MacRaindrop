import SwiftUI

// The window's toolbar, as groups that `ContentView` puts together. Items stay put and are
// disabled when they don't apply, rather than appearing and disappearing.
//
// Adjacent `ToolbarItem`s share one glass capsule; `ContentView` puts a `ToolbarSpacer`
// between the groups that should stand apart.

/// Back and Forward, at the leading edge like Finder.
struct HistoryToolbar: ToolbarContent {
    let browser: BrowserModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation){
            ControlGroup("Navigation") {
                Button("Back", systemImage: "chevron.left", action: browser.goBack)
                    .disabled(!browser.canGoBack)
                Button("Forward", systemImage: "chevron.right", action: browser.goForward)
                    .disabled(!browser.canGoForward)
            }
            .controlGroupStyle(.navigation)
        }
    }
}

/// List or cards, and the sort order.
struct ViewOptionsToolbar: ToolbarContent {
    @Binding var mode: CollectionMode
    @Binding var sort: RaindropSort

    var body: some ToolbarContent {
        ToolbarItem {
            Picker("View", selection: $mode) {
                ForEach(CollectionMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("Show bookmarks as cards or as a list")
        }

        ToolbarItem {
            Menu("Sort", systemImage: "arrow.up.arrow.down") {
                Picker("Sort", selection: $sort) {
                    ForEach(RaindropSort.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            }
        }
    }
}

/// Edit for the selected bookmark and the inspector toggle, which share a capsule.
struct EditAndInspectorToolbar: ToolbarContent {
    @Environment(LibraryStore.self) private var store
    @Environment(ActionPrompts.self) private var prompts
    let selection: [Raindrop]
    @Binding var isInspectorPresented: Bool

    var body: some ToolbarContent {
        ToolbarItem {
            Button("Edit", systemImage: "pencil") {
                prompts.editing = selection.first
            }
            .disabled(selection.count != 1 || !store.canModify(selection.map(\.id)))
            .help(store.isOnline ? "Edit the selected bookmark" : "You're offline")
        }
        ToolbarItem {
            Toggle(isOn: $isInspectorPresented) {
                Label("Inspector", systemImage: "info")
            }
            .help(isInspectorPresented ? "Hide Inspector" : "Show Inspector")
        }
    }
}
