import AppKit
import SwiftUI

extension View {
    /// Loads the library, then keeps it current: when the app comes forward, when the network
    /// comes back, and every few minutes while the app is active. There's no Sync button;
    /// the Debug menu has a manual one.
    func syncsAutomatically() -> some View {
        modifier(AutomaticSync())
    }
}

private struct AutomaticSync: ViewModifier {
    @Environment(LibraryStore.self) private var store

    func body(content: Content) -> some View {
        content
            .task {
                if store.phase == .idle { await store.load() }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5 * 60))
                    if NSApp.isActive { await store.syncIfStale() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { await store.syncIfStale() }
            }
            .onChange(of: store.isOnline) { _, isOnline in
                if isOnline { Task { await store.syncIfStale(olderThan: .zero) } }
            }
    }
}
