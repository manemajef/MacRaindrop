import SwiftUI

/// The window's toolbar, the same in both modes: ‹ › | view, sort | inspector. Items stay
/// put and are disabled when they don't apply, rather than appearing and disappearing.
///
/// Adjacent `ToolbarItem`s share one glass capsule, so a `ToolbarSpacer` sets apart the groups
/// that should stand apart.
struct ContentToolbar: ToolbarContent {
    let navigation: NavigationModel
    @Binding var mode: ViewMode
    @Binding var sort: RaindropSort
    @Binding var isInspectorPresented: Bool

    var body: some ToolbarContent {
        HistoryToolbar(navigation: navigation)
        ViewOptionsToolbar(mode: $mode, sort: $sort)
        ToolbarSpacer(.fixed)
        InspectorToolbar(isInspectorPresented: $isInspectorPresented)
    }
}

/// Back and Forward, at the leading edge like Finder.
private struct HistoryToolbar: ToolbarContent {
    let navigation: NavigationModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation){
            ControlGroup("Navigation") {
                Button("Back", systemImage: "chevron.left", action: navigation.goBack)
                    .disabled(!navigation.canGoBack)
                Button("Forward", systemImage: "chevron.right", action: navigation.goForward)
                    .disabled(!navigation.canGoForward)
            }
            .controlGroupStyle(.navigation)
        }
    }
}

/// List or cards, and the sort order.
private struct ViewOptionsToolbar: ToolbarContent {
    @Binding var mode: ViewMode
    @Binding var sort: RaindropSort

    var body: some ToolbarContent {
        ToolbarItem {
            Picker("View", selection: $mode) {
                ForEach(ViewMode.allCases) { mode in
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

/// The inspector toggle. Bookmarks are edited in the inspector, so this is also how to edit.
private struct InspectorToolbar: ToolbarContent {
    @Binding var isInspectorPresented: Bool

    var body: some ToolbarContent {
        ToolbarItem {
            Toggle(isOn: $isInspectorPresented) {
                Label("Inspector", systemImage: "info")
            }
            .help(isInspectorPresented ? "Hide Inspector" : "Show Inspector")
        }
    }
}
